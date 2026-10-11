import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ajhh.galaxybuds"
  ipcTarget: "galaxybuds"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", false) === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int lowBatteryPercent: 20
  readonly property color barIconColor: lowBattery ? urgent
    : buds.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool lowBattery: buds.connected && buds.lowestLevel !== Model.LEVEL_UNKNOWN
    && buds.lowestLevel <= lowBatteryPercent

  // Mode keys work in both paths: they pick a mode when the app publishes one, and toggle otherwise.
  readonly property var modeKeys: ({ "o": Model.MODE_OFF, "a": Model.MODE_AMBIENT, "n": Model.MODE_ANC })
  readonly property bool ambientSliderVisible: buds.supportsAmbientLevel && buds.noiseMode === Model.MODE_AMBIENT

  // Everything here is a toggle GalaxyBudsClient does not report back, so the rows are actions rather than switches.
  // The ANC and ambient toggles are only offered when the app cannot tell us the current mode.
  readonly property var actions: (buds.supportsModes ? [] : [
    { id: "anc", label: "Cancelación de ruido", caption: "Activar o desactivar ANC", key: "n" },
    { id: "ambient", label: "Sonido ambiente", caption: "Activar o desactivar el modo ambiente", key: "a" }
  ]).concat([
    { id: "conversation", label: "Detección de conversación", caption: "Baja el volumen cuando hablas", key: "c" },
    { id: "touch", label: "Bloquear controles táctiles", caption: "Activar o desactivar el bloqueo", key: "l" },
    { id: "find", label: "Buscar auriculares", caption: "Hace sonar los Buds", key: "f" }
  ])

  // Rebuilt whenever a section appears, so j and k never land on a hidden control.
  readonly property var cursorRows: {
    var rows = []
    if (!buds.connected) return rows
    if (buds.supportsModes) for (var i = 0; i < Model.MODES.length; i++) rows.push("mode:" + Model.MODES[i])
    if (ambientSliderVisible) rows.push("ambientLevel")
    for (var j = 0; j < actions.length; j++) rows.push(actions[j].id)
    return rows
  }
  readonly property string cursorRow: cursorRows.length === 0
    ? ""
    : cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) {
    return cursorActive && cursorRow === name
  }

  function moveCursor(dy) {
    cursorActive = true
    if (cursorRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
  }

  function nudgeCursor(dx) {
    if (cursorRow === "ambientLevel") buds.setAmbientLevel(buds.ambientLevel + dx)
  }

  function pickMode(mode) {
    if (buds.supportsModes) buds.setNoiseMode(mode)
    else if (mode === Model.MODE_ANC) buds.toggleAnc()
    else if (mode === Model.MODE_AMBIENT) buds.toggleAmbient()
  }

  function trigger(id) {
    if (id.indexOf("mode:") === 0) buds.setNoiseMode(id.substring(5))
    else if (id === "anc") buds.toggleAnc()
    else if (id === "ambient") buds.toggleAmbient()
    else if (id === "conversation") buds.toggleConversation()
    else if (id === "touch") buds.toggleTouchLock()
    else if (id === "find") buds.toggleFind()
  }

  visible: !hideWhenDisconnected || buds.connected
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    buds.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  BudsService {
    id: buds
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { buds.refresh(); return "ok" }
    function anc(): string { root.pickMode(Model.MODE_ANC); return "ok" }
    function ambient(): string { root.pickMode(Model.MODE_AMBIENT); return "ok" }
    function off(): string { root.pickMode(Model.MODE_OFF); return "ok" }
    function cycle(): string { buds.cycleNoiseMode(); return "ok" }
    function mode(): string { return buds.noiseMode }
    function ambientLevel(level: int): string { buds.setAmbientLevel(level - 1); return "ok" }
    function battery(): string { return Model.tooltip(buds) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: buds.connected ? Model.GLYPH_BUDS : Model.GLYPH_BUDS_OUTLINE
    foreground: root.barIconColor
    tooltipText: Model.tooltip(buds)
    onPressed: function (b) {
      if (b === Qt.RightButton) buds.cycleNoiseMode()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.nudgeCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.trigger(root.cursorRow)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") { buds.refresh(); return }
        if (root.modeKeys[key] !== undefined) { root.pickMode(root.modeKeys[key]); return }
        for (var i = 0; i < root.actions.length; i++)
          if (root.actions[i].key === key) root.trigger(root.actions[i].id)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: buds.displayName
            meta: buds.connected ? (buds.supportsModes ? Model.modeName(buds.noiseMode)
                : buds.firmware !== "" ? "Firmware " + buds.firmware : "Conectados")
              : buds.schemaUnsupported ? "Esquema no soportado"
              : buds.appRunning ? "No conectados"
              : buds.bridgeRunning ? "GalaxyBudsClient no está abierto"
              : "El puente no está en marcha"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: buds.connected ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: Model.GLYPH_BUDS
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: buds.actionStatus !== "" || buds.lastError !== ""
            width: parent.width
            text: buds.actionStatus !== "" ? buds.actionStatus : buds.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: buds.connected
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "BATERÍA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              BudRow { width: parent.width; label: "Izq"; level: buds.leftBud.level; meta: Model.wearText(buds.leftBud.wear) }
              BudRow { width: parent.width; label: "Der"; level: buds.rightBud.level; meta: Model.wearText(buds.rightBud.wear) }
              BudRow { width: parent.width; label: "Estuche"; level: buds.caseLevel; meta: "" }
            }
          }

          PanelSeparator {
            visible: buds.connected
            foreground: root.foreground
          }

          Column {
            visible: buds.supportsModes
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODO DE ESCUCHA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.MODES
                ModeRow {
                  required property var modelData
                  width: parent.width
                  mode: modelData
                }
              }
            }

            SliderRow {
              visible: root.ambientSliderVisible
              width: parent.width
            }
          }

          PanelSeparator {
            visible: buds.supportsModes
            foreground: root.foreground
          }

          Column {
            visible: buds.connected
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actions
              ActionRow {
                required property var modelData
                width: parent.width
                rowName: modelData.id
                label: modelData.id === "find" && buds.finding ? "Dejar de buscar" : modelData.label
                caption: modelData.caption
                key: modelData.key
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !buds.connected
            width: parent.width
            text: !buds.bridgeRunning
              ? "Inicia el servicio: systemctl --user start galaxybuds-bridge"
              : !buds.appRunning
                ? "Abre GalaxyBudsClient (se puede dejar minimizado en la bandeja)."
                : "Conecta tus Galaxy Buds para ver la batería y los controles."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component BudRow: Item {
    id: budRow
    property string label: ""
    property int level: Model.LEVEL_UNKNOWN
    property string meta: ""

    readonly property bool low: level !== Model.LEVEL_UNKNOWN && level <= root.lowBatteryPercent

    implicitHeight: budLayout.implicitHeight

    RowLayout {
      id: budLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: budRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Math.max(Style.space(44), implicitWidth + Style.space(10))
      }

      Rectangle {
        id: meterTrack
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)

        Rectangle {
          width: meterTrack.width * Model.levelFraction(budRow.level)
          height: parent.height
          radius: parent.radius
          color: budRow.low ? root.urgent : root.foreground
        }
      }

      Text {
        textFormat: Text.PlainText
        text: Model.levelText(budRow.level)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(38)
      }

      Text {
        textFormat: Text.PlainText
        text: budRow.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.preferredWidth: Style.space(78)
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string rowName: ""
    property string label: ""
    property string caption: ""
    property string key: ""

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX
    opacity: buds.busy ? 0.6 : 1.0

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(actionRow.rowName)
      onClicked: root.trigger(actionRow.rowName)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.caption
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        text: actionRow.key.toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ModeRow: CursorSurface {
    id: modeRow
    property string mode: ""

    readonly property string rowName: "mode:" + mode
    readonly property bool selected: buds.noiseMode === mode

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: modeLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(modeRow.rowName)
      onClicked: buds.setNoiseMode(modeRow.mode)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: modeLabel
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: Model.modeName(modeRow.mode)
        color: root.foreground
        opacity: modeRow.selected ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        text: Model.GLYPH_CHECK
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: modeRow.selected ? 1.0 : 0.0
      }
    }
  }

  component SliderRow: CursorSurface {
    id: sliderRow
    hasCursor: root.rowHasCursor("ambientLevel")
    foreground: root.foreground
    implicitHeight: sliderColumn.implicitHeight + Style.spacing.rowPaddingX

    HoverHandler { onHoveredChanged: if (hovered) root.focusRow("ambientLevel") }

    Column {
      id: sliderColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Nivel de ambiente"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          text: Model.ambientLevelText(buds.ambientLevel, buds.ambientMax)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: Math.max(1, buds.ambientMax)
        step: 1
        integer: true
        tickCount: buds.ambientMax + 1
        value: Math.max(0, buds.ambientLevel)
        onReleased: function (v) { buds.setAmbientLevel(v) }
      }
    }
  }
}
