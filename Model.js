// No QML imports on purpose, so every function here runs in a plain JS harness.

// Highest schema_version this panel knows how to read.
var SUPPORTED_SCHEMA = 1

// Level the bridge reports when a bud or the case has not been heard from.
var LEVEL_UNKNOWN = -1

// nf-md-check U+F012C.
// nf-md-earbuds U+F184F and nf-md-earbuds_outline U+F1850.
var GLYPH_BUDS = "\uDB86\uDC4F"
var GLYPH_BUDS_OUTLINE = "\uDB86\uDC50"

var GLYPH_CHECK = "\uDB80\uDD2C"

var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137

// GalaxyBudsClient's Event names, accepted by its Application.ExecuteAction.
var ACTION_ANC = "AncToggle"
var ACTION_AMBIENT = "AmbientToggle"
var ACTION_CONVERSATION = "ToggleConversationDetect"
var ACTION_TOUCH_LOCK = "LockTouchpadToggle"
var ACTION_FIND_START = "StartFind"
var ACTION_FIND_STOP = "StopFind"

// GalaxyBudsClient's NoiseControlModes names, accepted by Device.SetNoiseControlMode.
var MODE_OFF = "Off"
var MODE_AMBIENT = "AmbientSound"
var MODE_ANC = "NoiseReduction"
var MODES = [MODE_OFF, MODE_AMBIENT, MODE_ANC]

function defaultBud() {
  return { level: LEVEL_UNKNOWN, wear: "Disconnected" }
}

// Full shape on every path, so the panel never reads undefined off a parse failure.
function defaultStatus() {
  return {
    ok: false,
    lastError: "",
    schemaTooNew: false,
    appRunning: false,
    connected: false,
    name: "",
    model: "",
    firmware: "",
    left: defaultBud(),
    right: defaultBud(),
    caseLevel: LEVEL_UNKNOWN,
    noiseMode: "",
    ambientLevel: LEVEL_UNKNOWN,
    ambientMax: LEVEL_UNKNOWN
  }
}

function intOr(value, fallback) {
  var n = parseInt(value, 10)
  return isFinite(n) ? n : fallback
}

// The whole of $XDG_STATE_HOME/galaxybuds/status.json, one line, written by bin/galaxybuds-bridge:
// {"address":"AA:BB:...","app_running":true,"battery":{"case":60,"left":82,"right":15},
//  "connected":true,"firmware":"R640XXU0AYF1","model":"Buds4Pro","name":"Buds4 Pro",
//  "schema_version":1,"wear":{"left":"Wearing","right":"Case"}}
function parseStatus(raw) {
  var status = defaultStatus()
  var text = String(raw || "").trim()
  if (text === "") {
    status.lastError = "El archivo de estado está vacío"
    return status
  }

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    status.lastError = "No se pudo leer el archivo de estado"
    return status
  }
  if (!parsed || typeof parsed !== "object" || parsed.schema_version === undefined) {
    status.lastError = "El archivo de estado no trae schema_version"
    return status
  }
  if (intOr(parsed.schema_version, 0) > SUPPORTED_SCHEMA) {
    status.schemaTooNew = true
    status.lastError = "El puente usa el esquema " + parsed.schema_version + ", este panel lee " + SUPPORTED_SCHEMA
    return status
  }

  status.ok = true
  status.appRunning = parsed.app_running === true
  status.connected = status.appRunning && parsed.connected === true
  if (!status.connected) return status

  var battery = parsed.battery || {}
  var wear = parsed.wear || {}
  status.name = String(parsed.name || "")
  status.model = String(parsed.model || "")
  status.firmware = String(parsed.firmware || "")
  status.left = budFrom(battery.left, wear.left)
  status.right = budFrom(battery.right, wear.right)
  // The case reports 0 while no bud is inside it to relay its level.
  var budInCase = isInCase(status.left.wear) || isInCase(status.right.wear)
  var caseLevel = levelOr(battery["case"])
  status.caseLevel = caseLevel === 0 && !budInCase ? LEVEL_UNKNOWN : caseLevel
  var mode = String(parsed.noise_mode || "")
  status.noiseMode = MODES.indexOf(mode) >= 0 ? mode : ""
  var ambient = parsed.ambient || {}
  status.ambientMax = intOr(ambient.max, LEVEL_UNKNOWN)
  status.ambientLevel = status.ambientMax < 0 ? LEVEL_UNKNOWN : intOr(ambient.level, LEVEL_UNKNOWN)
  return status
}

function budFrom(level, wear) {
  var w = String(wear || "Disconnected")
  // A bud the case cannot reach reports 0, which is not the same as empty.
  return { level: w === "Disconnected" ? LEVEL_UNKNOWN : levelOr(level), wear: w }
}

function isInCase(wear) {
  return wear === "Case" || wear === "ClosedCase" || wear === "Charging"
}

function modeName(mode) {
  if (mode === MODE_OFF) return "Desactivado"
  if (mode === MODE_AMBIENT) return "Sonido ambiente"
  if (mode === MODE_ANC) return "Cancelación de ruido"
  return "Desconocido"
}

function nextMode(mode) {
  var at = MODES.indexOf(mode)
  return MODES[(at + 1) % MODES.length]
}

// The firmware counts from 0; Samsung's own app labels the steps from 1.
function ambientLevelText(level, max) {
  if (level === LEVEL_UNKNOWN || max < 0) return "--"
  return "Nivel " + (level + 1) + " de " + (max + 1)
}

function levelOr(value) {
  var n = intOr(value, LEVEL_UNKNOWN)
  return n < 0 || n > 100 ? LEVEL_UNKNOWN : n
}

// "Buds4Pro" -> "Galaxy Buds4 Pro"
function modelName(model) {
  var m = String(model || "")
  if (m === "" || m === "NULL") return ""
  return "Galaxy " + m.replace(/Pro$/, " Pro").replace(/Fe$/, " FE").replace(/Live$/, " Live").replace(/Plus$/, "+")
}

function wearText(wear) {
  if (wear === "Wearing") return "En el oído"
  if (wear === "Idle") return "Fuera"
  if (wear === "Case") return "En estuche"
  if (wear === "ClosedCase") return "Estuche cerrado"
  if (wear === "Charging") return "Cargando"
  // A bud asleep in a closed case drops off the link, so this is the usual reading for it.
  if (wear === "Disconnected") return "Sin conexión"
  return ""
}

function levelText(level) {
  return level === LEVEL_UNKNOWN ? "--" : String(level) + "%"
}

// 0 to 1 for the meter; an unknown level draws an empty track rather than a full one.
function levelFraction(level) {
  if (level === LEVEL_UNKNOWN) return 0
  return Math.max(0, Math.min(100, level)) / 100
}

// Lowest known bud level, which is what runs out first.
function lowestBud(left, right) {
  var known = [left.level, right.level].filter(function (l) { return l !== LEVEL_UNKNOWN })
  return known.length === 0 ? LEVEL_UNKNOWN : Math.min.apply(null, known)
}

function tooltip(status) {
  if (!status.connected) return "Galaxy Buds"
  return (status.noiseMode !== "" ? modeName(status.noiseMode) + "\n" : "")
    + "Izq " + levelText(status.leftBud.level)
    + " · Der " + levelText(status.rightBud.level)
    + " · Estuche " + levelText(status.caseLevel)
}

function elideError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > MAX_ERROR_CHARS ? value.substring(0, ELIDED_ERROR_CHARS) + "…" : value
}
