import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool bridgeRunning: false
  property bool appRunning: false
  property bool connected: false
  property bool schemaUnsupported: false
  property string name: ""
  property string model: ""
  property string firmware: ""
  property var leftBud: Model.defaultBud()
  property var rightBud: Model.defaultBud()
  property int caseLevel: Model.LEVEL_UNKNOWN
  property string noiseMode: ""
  property int ambientLevel: Model.LEVEL_UNKNOWN
  property int ambientMax: Model.LEVEL_UNKNOWN
  property string lastError: ""
  property string actionStatus: ""
  property bool finding: false

  readonly property bool busy: commandProcess.running
  // The bridge publishes here on change, so there is nothing to poll.
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/galaxybuds/status.json"
  readonly property string displayName: Model.modelName(model) || name || "Galaxy Buds"
  readonly property int lowestLevel: Model.lowestBud(leftBud, rightBud)
  // An unpatched GalaxyBudsClient publishes no mode, so the panel falls back to its toggles.
  readonly property bool supportsModes: connected && noiseMode !== ""
  readonly property bool supportsAmbientLevel: connected && ambientMax > 0

  // How long an optimistic value is held before the bridge's own state wins.
  readonly property int settleHoldMs: 4000

  // Held over incoming reads until the Buds agree, so a write in flight cannot snap the control back.
  property string _pendingField: ""
  property var _pendingValue: null

  // Single slot: a call sent while another is in flight replaces the queued one, which is what slider drags produce.
  property var _queued: null

  function refresh() {
    stateFile.reload()
  }

  function applyLine(raw) {
    var status = Model.parseStatus(raw)
    // A line we cannot read still proves the bridge is running and writing.
    bridgeRunning = true
    schemaUnsupported = status.schemaTooNew
    lastError = status.lastError
    appRunning = status.appRunning
    connected = status.connected
    name = status.name
    model = status.model
    firmware = status.firmware
    leftBud = status.left
    rightBud = status.right
    caseLevel = status.caseLevel
    ambientMax = status.ambientMax
    noiseMode = _settle("noiseMode", status.noiseMode)
    ambientLevel = _settle("ambientLevel", status.ambientLevel)
    if (!connected) finding = false
  }

  // The bridge removes the file when it stops, so an absent file is a stopped bridge.
  function stateGone() {
    bridgeRunning = false
    appRunning = false
    connected = false
    finding = false
    lastError = ""
  }

  function _settle(field, reported) {
    if (_pendingField !== field) return reported
    if (reported === _pendingValue) {
      _clearPending()
      return reported
    }
    return _pendingValue
  }

  function _clearPending() {
    _pendingField = ""
    _pendingValue = null
    settleTimer.stop()
  }

  function _command(path, method, arg) {
    // gdbus parses arguments as GVariant text, so a bare word must be quoted to
    // stay a string. Only plain identifiers and whole numbers get through: a
    // quote or bracket would let a value rewrite the call.
    var text = typeof arg === "number" ? (Number.isInteger(arg) ? String(arg) : "")
      : (/^[A-Za-z0-9_]+$/.test(String(arg)) ? "'" + arg + "'" : "")
    if (text === "") return null
    return [
      "gdbus", "call", "--session",
      "--dest", "me.timschneeberger.GalaxyBudsClient",
      "--object-path", path,
      "--method", method,
      text
    ]
  }

  function _send(command, field, optimistic) {
    if (!connected || command === null) return
    if (field !== "") {
      _pendingField = field
      _pendingValue = optimistic
      root[field] = optimistic
      settleTimer.restart()
    }
    if (commandProcess.running) {
      _queued = command
      return
    }
    commandProcess.command = command
    commandProcess.running = true
  }

  function run(action) {
    _send(_command("/me/timschneeberger/galaxybudsclient",
      "me.timschneeberger.GalaxyBudsClient.Application.ExecuteAction", action), "", null)
  }

  function setNoiseMode(mode) {
    if (!supportsModes || Model.MODES.indexOf(mode) < 0) return
    _send(_command("/me/timschneeberger/galaxybudsclient/device",
      "me.timschneeberger.GalaxyBudsClient.Device.SetNoiseControlMode", mode), "noiseMode", mode)
  }

  function cycleNoiseMode() {
    if (supportsModes) setNoiseMode(Model.nextMode(noiseMode))
    else toggleAnc()
  }

  function setAmbientLevel(level) {
    if (!supportsAmbientLevel) return
    var clamped = Math.max(0, Math.min(ambientMax, Math.round(level)))
    if (clamped === ambientLevel) return
    _send(_command("/me/timschneeberger/galaxybudsclient/device",
      "me.timschneeberger.GalaxyBudsClient.Device.SetAmbientSoundVolume", clamped), "ambientLevel", clamped)
  }

  function toggleAnc() { run(Model.ACTION_ANC) }
  function toggleAmbient() { run(Model.ACTION_AMBIENT) }
  function toggleConversation() { run(Model.ACTION_CONVERSATION) }
  function toggleTouchLock() { run(Model.ACTION_TOUCH_LOCK) }

  function toggleFind() {
    if (!connected) return
    finding = !finding
    run(finding ? Model.ACTION_FIND_START : Model.ACTION_FIND_STOP)
  }

  function flash(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  Timer {
    // Bounds the optimistic hold, and re-reads because a call that changed nothing writes no new line.
    id: settleTimer
    interval: root.settleHoldMs
    repeat: false
    onTriggered: { root._clearPending(); root.refresh() }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    // text() is stale inside the change signal, so both paths go through reload.
    onFileChanged: reload()
    onLoaded: root.applyLine(text())
    onLoadFailed: root.stateGone()
  }

  Process {
    id: commandProcess
    running: false
    command: []
    stderr: StdioCollector { id: commandErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.finding = false
        root._queued = null
        // Clearing the hold also stops the timer that would have re-read, so do it here.
        root._clearPending()
        root.refresh()
        root.flash(Model.elideError(commandErr.text || "GalaxyBudsClient rechazó la acción"))
        return
      }
      if (root._queued) {
        var next = root._queued
        root._queued = null
        commandProcess.command = next
        commandProcess.running = true
      }
    }
  }
}
