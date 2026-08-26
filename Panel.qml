import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Where's My Rivian: the car in the bar, and a map behind it.
//
// The bar shows the Rivian mark. The panel shows where the car is, which way
// it is pointing, how full it is and how far that gets you.
//
// This is the easier half of the equivalent Tesla widget, and for one reason:
// reading a Rivian never touches the car. The vehicle pushes telemetry to
// Rivian's cloud on its own schedule and `vehicleState` reads that cloud, so
// there is no call here that can hold a car awake and no battery to protect.
// Every field arrives with its own timestamp, which is why the panel talks
// about when the cloud last heard rather than pretending it just asked.
//
// What that costs instead is honesty about staleness: a car parked in a
// basement has not moved, but nor has anything about it been heard, and those
// two look identical from here. `lastSync` is the field that tells them
// apart, and it is why it has a line of its own.
//
// Glyphs are \u escapes rather than literal characters, so the source survives
// editors and patches that mangle private-use codepoints.
Panel {
  id: root

  moduleName: "kayleg.rivian"
  ipcTarget: "kayleg.rivian"

  // The script that does the talking sits next to this file, so the plugin
  // runs from wherever it was installed without putting anything on $PATH.
  readonly property string script:
    Qt.resolvedUrl("bin/rivian").toString().replace(/^file:\/\//, "")

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // The bar exposes a foreground and a font, not an accent; the accent is a
  // theme-level colour, so it is read straight off Color.
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Omarchy's palette has a foreground, an accent, an urgent and a muted, and
  // no green. This is the one place a literal colour is right: a live
  // indicator is green everywhere, in every theme, and one that drifted to
  // whatever the accent happened to be would stop reading as "it is up" and
  // start reading as decoration. It marks the panel's status dot and the bar
  // mark while the car is moving, and nothing else.
  readonly property color liveGreen: "#4caf50"

  // And red while it is charging, for the same reason the live mark is a
  // literal green: "it is filling up" should read the same in every theme
  // rather than turning into whatever the accent is today. Material's red 500
  // to the green's 500, so the two sit at the same weight. The error state
  // keeps Color.urgent — a fault and a charge are both red, and the word
  // beside the dot is what tells them apart, the same way it already
  // distinguishes driving from parked.
  readonly property color chargeRed: "#f44336"

  // What the panel accents itself with: the charge colour while it is
  // charging, the theme's accent the rest of the time.
  readonly property color liveAccent: charging ? chargeRed : accent

  // ----------------------------------------------------------------- settings

  readonly property string vin: setting("vin", "")
  readonly property int panelWidth: setting("panelWidth", 380)
  readonly property int mapZoom: setting("mapZoom", 16)
  readonly property string mapStyle: setting("mapStyle", "Auto")
  readonly property int statePollMinutes: setting("statePollMinutes", 5)
  // Rivian reports metric on the wire whatever the car's own screen says, and
  // does not report which the screen shows, so there is nothing to follow and
  // this has to be asked. Auto reads the locale.
  readonly property string units: setting("units", "Auto")
  readonly property bool showAddress: setting("showAddress", true)
  readonly property string mapsUrl: setting("mapsUrl",
    "https://www.google.com/maps/search/?api=1&query={lat},{lon}")

  // Whether the theme in force is a light one, judged off the panel
  // background's luminance rather than off a theme name: a theme can be
  // called anything, but a background either reflects light or it does not.
  // The coefficients are the usual perceptual weights: green carries most of
  // what the eye reads as brightness.
  readonly property bool lightTheme: {
    var bg = Color.background
    return (0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b) > 0.5
  }

  // The grey canvas basemaps are quiet enough to read a marker off and come in a
  // matched pair, which is the whole reason they are the default over OSM's
  // own: a dark map dropped into a light theme is a hole in the panel, and a
  // light one in a dark theme is a torch in the face. Auto follows the theme
  // so neither happens; the explicit choices are for anyone who wants the map
  // to disagree on purpose.
  readonly property string effectiveMapStyle:
    mapStyle === "Auto" ? (lightTheme ? "Light" : "Dark") : mapStyle

  // Esri's grey canvas basemaps rather than CARTO's, which is not a style
  // preference. CARTO began requiring an API key for basemaps.cartocdn.com and
  // signals it in the worst possible way: HTTP 200, a valid PNG, with "API KEY
  // REQUIRED" drawn across the image. Nothing downstream can tell that from a
  // map, so it cached like one and the panel showed a wall of nag tiles.
  //
  // Esri's Canvas Dark/Light Gray Base fill the same role — deliberately quiet,
  // so a marker on top is the loudest thing — and need no key. Note the path is
  // {z}/{y}/{x}, y before x, which is Esri's order rather than a typo.
  readonly property string tileUrl: {
    var esri = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/"
    if (effectiveMapStyle === "Light") return esri + "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"
    if (effectiveMapStyle === "OpenStreetMap") return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    return esri + "World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
  }

  // Whether what is about to be drawn is a pale map. Anything painted on top
  // of it, the attribution and the ring around the marker, has to contrast with
  // the tiles rather than with the panel, and those two can disagree: a dark
  // theme with the map forced to Light is exactly where white-on-white went
  // missing. OpenStreetMap's standard style counts as light too.
  readonly property bool lightMap: effectiveMapStyle !== "Dark"

  // Qt decides for itself whether a string is markup, and a Text or tooltip in
  // that mode fetches `<img src="http://...">` for real, from inside the shell
  // process. The address comes from Nominatim and the error text from Rivian, so
  // neither is ours to vouch for. The panel's own Text elements are pinned to
  // PlainText; the bar tooltip belongs to the shell and is not ours to set, so
  // anything heading that way has its angle brackets taken off first — without
  // a `<` there is nothing for Qt to mistake for a tag.
  function plain(s) {
    return String(s === undefined || s === null ? "" : s).replace(/[<>]/g, "")
  }

  function cmd(args) {
    var base = [root.script,
                "--units", root.units === "Miles" ? "miles"
                         : root.units === "Kilometres" ? "km" : "auto",
                "--tile-url", root.tileUrl]
    if (root.vin !== "") base = base.concat(["--vin", root.vin])
    return base.concat(args)
  }

  // -------------------------------------------------------------------- state

  // What the free poll last said: "online", "asleep", "offline", or "" before
  // the first answer.
  property string carState: ""
  // The last full reading, from `rivian car`. Null until one lands.
  property var reading: null
  // The tile plan for the position in `reading`.
  property var mapPlan: null
  // The position in `reading`, as a street and a town. Kept in parts, because
  // the house number is worth having when the car is parked and noise when it
  // is moving.
  property string placeStreet: ""
  property string placeNumber: ""
  property string placeTown: ""

  // At speed the nearest address changes every second, so the number is
  // dropped and only the road is named: "De Hees, Kronenberg" holds still
  // while "De Hees 39" flickers through the whole street.
  readonly property string place: {
    if (placeStreet === "" && placeTown === "") return ""
    var head = placeStreet
    if (!driving && placeNumber !== "" && head !== "") head += " " + placeNumber
    return [head, placeTown].filter(function(part) { return part !== "" }).join(", ")
  }
  property string errorText: ""
  // The sentence behind the error, when the script has one. Kept apart so the
  // status word in the header can stay two words long while the line at the
  // bottom explains itself.
  property string errorHint: ""

  readonly property bool hasReading: reading !== null && reading.ok === true
  readonly property bool driving: hasReading && reading.driving === true
  readonly property bool charging: hasReading && reading.charging_now === true
  readonly property bool plugged: hasReading && reading.plugged === true
  // "Asleep" here means the car's own power state, which is worth showing but
  // is not a reason to avoid asking: nothing this widget does can wake it.
  readonly property bool asleep: carState === "asleep"

  // Not "free to ask" — everything is free to ask — but "worth asking again",
  // which is a different question with the same two answers.
  readonly property bool changing: driving || charging

  readonly property real lat: hasReading && reading.lat !== null ? reading.lat : 0
  readonly property real lon: hasReading && reading.lon !== null ? reading.lon : 0
  readonly property bool hasPosition: hasReading && reading.lat !== null && reading.lon !== null

  // Ticks so the "seen 4 minutes ago" line ages on screen instead of freezing
  // at whatever it said when the panel opened.
  property double now: Date.now()

  Timer {
    interval: 15000
    running: root.opened || root.driving
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  // ------------------------------------------------------------------ the car

  // What the bar shows. It runs on a timer all day and it never touches the
  // car: Rivian answers it from its own copy of the car's telemetry. `state`
  // and `car` share one cached reading in the script, so this poll and an
  // opened panel cost one call between them rather than one each.
  Process {
    id: stateProc
    command: root.cmd(["state"])
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          return
        }
        // Read before the ok check, because `car` can succeed at showing you
        // the last known position and still have something to report about
        // why it is the last known one.
        root.errorText = data.error || ""
        root.errorHint = data.hint || ""
        root.noteNeedsLogin(data)
        if (data.ok !== true) return

        var was = root.carState
        root.carState = data.state

        // A car that has just woken is a car somebody is using, which is
        // exactly when where-is-it stops being a rhetorical question.
        if (was !== "online" && data.state === "online") root.refresh(false)
        // The bar's own summary comes from the same reading, so a panel that
        // has never been opened still has something to show when it is.
        if (root.reading === null && data.battery !== null) root.refresh(false)
      }
    }
  }

  Timer {
    interval: Math.max(1, root.statePollMinutes) * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stateProc.running) stateProc.running = true
  }

  // The full reading. `force` is the refresh button skipping the script's
  // reuse window; everything else is content with a reading a few seconds old.
  Process {
    id: carProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          return
        }
        root.errorText = data.error || ""
        root.errorHint = data.hint || ""
        root.noteNeedsLogin(data)
        if (data.ok !== true) return
        root.reading = data
      }
    }
  }

  function refresh(force) {
    if (carProc.running) return
    carProc.command = root.cmd(force ? ["car", "--force"] : ["car"])
    carProc.running = true
  }

  // Only while something is actually moving. A parked car is polled by the
  // bar's own timer and nothing more: not to protect it, but because the
  // answer does not change and a redraw that says the same thing is noise.
  Timer {
    interval: root.driving ? 15000 : 60000
    running: root.changing
    repeat: true
    onTriggered: root.refresh(false)
  }


  // ------------------------------------------------------------------ the map

  Process {
    id: mapProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok === true) root.mapPlan = data
        } catch (e) {
        }
      }
    }
  }

  // Tiles are fetched over the network, so this waits for the position and the
  // panel geometry to settle rather than firing on every pixel of a resize.
  Timer {
    id: mapDebounce
    interval: 250
    onTriggered: {
      if (!root.hasPosition || mapProc.running) return
      var w = Math.round(mapArea.width)
      var h = Math.round(mapArea.height)
      if (w <= 0 || h <= 0) return
      mapProc.command = root.cmd(["map", String(root.lat), String(root.lon),
                                  String(root.mapZoom), String(w), String(h)])
      mapProc.running = true
    }
  }

  function planMap() {
    if (root.opened && root.hasPosition) mapDebounce.restart()
  }

  onMapZoomChanged: planMap()

  // One handler, because QML takes one per signal: opening the panel is both
  // a reason to ask the car and a reason to lay out the map.
  onOpenedChanged: {
    planMap()
    if (!opened) return
    // Opening the panel is a person asking, so it is worth one reading,
    // still subject to the script's throttle, so opening it twice in a
    // minute costs one call, not two.
    refresh(false)
    if (!stateProc.running) stateProc.running = true
  }

  // The position moving is a reason to redraw the map and to look the new
  // spot up by name. Both are debounced, so a drive is not a thousand
  // requests.
  onLatChanged: { planMap(); placeDebounce.restart() }
  onLonChanged: { planMap(); placeDebounce.restart() }

  Process {
    id: placeProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var ok = data.ok === true
          root.placeStreet = ok ? (data.street || "") : ""
          root.placeNumber = ok ? (data.number || "") : ""
          root.placeTown = ok ? (data.town || "") : ""
        } catch (e) {
          root.placeStreet = ""
          root.placeNumber = ""
          root.placeTown = ""
        }
      }
    }
  }

  Timer {
    id: placeDebounce
    interval: 400
    onTriggered: {
      if (!root.showAddress || !root.hasPosition || placeProc.running) return
      placeProc.command = root.cmd(["place", String(root.lat), String(root.lon)])
      placeProc.running = true
    }
  }

  onHasPositionChanged: if (hasPosition) placeDebounce.restart()

  // ------------------------------------------------------------------ actions

  // There is no wake button here, and its absence is the point. Rivian's app
  // API has no wake call to make: the car is not what answers, so there is
  // nothing to rouse. A sleeping Rivian reports its last known everything just
  // as readily as an awake one.

  Process { id: browserProc }

  function openInMaps() {
    if (!hasPosition) return
    var url = mapsUrl.replace(/\{lat\}/g, String(lat)).replace(/\{lon\}/g, String(lon))
    browserProc.command = ["xdg-open", url]
    browserProc.running = true
    root.close()
  }

  // ------------------------------------------------------------- signing in

  // Rivian has no OAuth flow and no token you can go and generate, so signing
  // in means handing over the account's own email and password. That is worth
  // doing as few times as possible and in as few places as possible, which is
  // the argument for doing it here rather than in a terminal: one place, and
  // one that can tell you what went wrong.
  //
  // Neither secret is ever an argument. `bin/rivian login --stdin` reads them
  // off stdin, because everything on a command line appears in
  // /proc/<pid>/cmdline, which any process on the machine can read. The same
  // goes for the code. The password lives in a QML string for as long as it
  // takes to write it down the pipe and is cleared in the same handler.
  //
  // "" when there is nothing to do, "credentials" for the email and password,
  // "code" once Rivian has sent a one-time code.
  property string signInStage: ""
  property string signInError: ""
  property string emailText: ""
  property string passwordText: ""
  property string codeText: ""

  readonly property bool signingIn: signInStage !== ""
  readonly property bool signInBusy: loginProc.running || otpProc.running
  // The script says whether signing in is the fix, rather than the panel
  // guessing it from the wording of an error.
  property bool needsLogin: false

  // Raise the form on the first answer that says the session is no good, and
  // not again while it is already up: a poll landing mid-typing must not wipe
  // the box under the cursor.
  function noteNeedsLogin(data) {
    var needs = data && data.needs_login === true
    needsLogin = needs
    if (needs && !signingIn && !signInBusy) beginSignIn()
    // A session that came good again elsewhere — `rivian login` in a terminal
    // — closes the form rather than leaving it stranded over a working car.
    if (!needs && signingIn && !signInBusy) cancelSignIn()
  }

  function beginSignIn() {
    // The stage is only set when `pending` answers, so a second poll arriving
    // before it does would start a second one. Once is enough.
    if (pendingProc.running) return
    signInError = ""
    passwordText = ""
    codeText = ""
    // A sign-in interrupted half way — panel closed after the code was sent —
    // comes back to the code box rather than asking for the password again.
    pendingProc.running = true
  }

  function cancelSignIn() {
    signInStage = ""
    signInError = ""
    emailText = ""
    passwordText = ""
    codeText = ""
  }

  // Back to the email box, and the stashed OTP token goes with it. Separate
  // from logout: there is no session yet at this point, so there is nothing
  // to sign out of.
  function restartSignIn() {
    if (signInBusy) return
    if (!cancelProc.running) cancelProc.running = true
    signInStage = "credentials"
    signInError = ""
    codeText = ""
    passwordText = ""
  }

  Process { id: cancelProc; command: root.cmd(["cancel"]) }

  // Focus is handled by the fields themselves, as they become visible — the
  // shell's own idiom for this, and the one that also covers a panel reopened
  // onto a form that was already up.

  function submitCredentials() {
    if (signInBusy || emailText === "" || passwordText === "") return
    signInError = ""
    loginProc.email = emailText
    loginProc.password = passwordText
    passwordText = ""
    loginProc.command = root.cmd(["login", "--stdin"])
    loginProc.running = true
  }

  function submitCode() {
    if (signInBusy || codeText === "") return
    signInError = ""
    otpProc.code = codeText
    codeText = ""
    otpProc.command = root.cmd(["otp", "--stdin"])
    otpProc.running = true
  }

  // Signed in: drop everything the form was holding and go and get a reading.
  // Named for what it does, not for a state. An earlier `signedIn()` collided
  // with a leftover `property bool signedIn` from the Tesla port: the property
  // won, so calling it threw and the panel sat on the code box after a
  // sign-in that had already succeeded.
  function completeSignIn() {
    cancelSignIn()
    needsLogin = false
    if (!stateProc.running) stateProc.running = true
    root.refresh(true)
  }

  Process {
    id: pendingProc
    command: root.cmd(["pending"])
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { data = null }
        root.signInStage = (data && data.pending === true) ? "code" : "credentials"
      }
    }
  }

  Process {
    id: loginProc
    property string email: ""
    property string password: ""
    stdinEnabled: true
    onStarted: {
      write(email + "\n" + password + "\n")
      // Cleared the instant it is spent, so a panel left open is not a panel
      // holding a password.
      password = ""
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          root.signInError = "the sign-in helper said something unreadable"
          return
        }
        if (data.ok !== true) {
          root.signInError = data.error || "sign-in failed"
          return
        }
        if (data.mfa === true) {
          root.signInStage = "code"
          root.signInError = ""
        } else if (data.signedIn === true) {
          root.completeSignIn()
        }
      }
    }
  }

  Process {
    id: otpProc
    property string code: ""
    stdinEnabled: true
    onStarted: {
      write(code + "\n")
      code = ""
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          root.signInError = "the sign-in helper said something unreadable"
          return
        }
        if (data.ok !== true) {
          // A wrong code is worth staying on this step for. Rivian's own
          // wording is better than anything this panel could invent.
          root.signInError = data.error || "the code was not accepted"
          // A code can also fail because it already worked and the sign-in it
          // belonged to is finished — the failure then is "nothing is waiting
          // for a code", and the right answer is not to show it. Ask what the
          // session actually is; if it is good, the form closes on its own.
          if (!stateProc.running) stateProc.running = true
          return
        }
        if (data.signedIn === true) root.completeSignIn()
      }
    }
  }

  // ------------------------------------------------------------------ wording

  // There is no compass anywhere in words. Which way the car is pointing is
  // worth a glance and not a sentence, so the marker on the map carries it and
  // nothing repeats it underneath.

  function agoOf(seconds) {
    var s = Math.max(0, Math.round(seconds))
    if (s < 45) return "just now"
    if (s < 90) return "a minute ago"
    if (s < 3600) return Math.round(s / 60) + " minutes ago"
    if (s < 7200) return "an hour ago"
    if (s < 86400) return Math.round(s / 3600) + " hours ago"
    if (s < 172800) return "yesterday"
    return Math.round(s / 86400) + " days ago"
  }

  readonly property real readingAge: hasReading ? Math.max(0, now / 1000 - reading.at) : 0
  // Old enough that the map should stop looking authoritative. An hour is
  // about when "it is probably still there" turns into "it was there".
  readonly property bool stale: readingAge > 3600

  readonly property string carName: {
    if (!hasReading) return "Rivian"
    // Rivian's own app makes you name the car and most people do, so unlike
    // Tesla this is usually the answer rather than the fallback.
    if (reading.name && reading.name !== "Rivian") return reading.name
    var model = String(reading.model || "")
    if (model === "") return "Rivian"
    return reading.year ? String(reading.year) + " " + model : model
  }

  readonly property string stateWord: {
    if (errorText !== "") return errorText
    if (driving) return "driving"
    if (charging) return "charging"
    if (carState === "") return "checking"
    return carState
  }

  // The one-line answer to the question in the plugin's name.
  readonly property string summary: {
    if (!hasReading) return errorText !== "" ? errorText : "No reading yet"
    // Rivian does not report charger power, so a charge is described by when
    // it finishes instead — which is the more useful of the two anyway, and
    // the number you would have worked out from the kilowatts regardless.
    var doing = driving
      ? (reading.speed === null ? "Driving" : "Driving " + reading.speed + " " + reading.speed_unit)
      : charging
        ? (reading.minutes_to_full
            ? "Charging, full " + Qt.formatTime(
                new Date(Date.now() + reading.minutes_to_full * 60000), clockFormat)
            : "Charging")
        : plugged ? "Plugged in" : "Parked"
    // Everything on this panel came out of one reading, so how old that
    // reading is belongs on the line that is already about when.
    return doing + " · fetched " + agoOf(readingAge)
  }

  // Doors, boot and windows, as one sentence, and only when there is one to
  // make. Nearly always empty, which is exactly what earns it a place: a line
  // that is usually absent gets read on the day it appears.
  readonly property string openText: {
    if (!hasReading || !reading.open || reading.open.length === 0) return ""
    var items = reading.open
    var list = items.length === 1
      ? items[0]
      : items.slice(0, -1).join(", ") + " and " + items[items.length - 1]
    return list.charAt(0).toUpperCase() + list.slice(1)
      + (items.length === 1 ? " is open" : " are open")
  }

  // Rivian's app API does not expose the active route, so there is no
  // destination or arrival time to show and this widget does not invent one.
  // What it can say about the future is when a charge finishes, which is the
  // line below and the one people actually watch.
  readonly property bool navigating: false

  // The locale's own short time, with the seconds taken out of the pattern
  // rather than out of the string: some locales put them in ShortFormat and
  // some do not, and an arrival is not a number you read to the second. Taking
  // them from the pattern leaves everything else the locale asked for, the
  // twelve-hour clock and its AM included.
  readonly property string clockFormat:
    Qt.locale().timeFormat(Locale.ShortFormat).replace(/[.:]?\bs+\b/g, "")

  // "Home at 19:48 · 2.6 km". The clock time rather than "in six
  // minutes", because arriving is something you meet the car at, and a time is
  // what you compare against the one on your own wrist.
  // "Full at 19:48 · 80%". The clock time rather than "in 47 minutes", because
  // a charge is something you come back for, and a time is what you compare
  // against the one on your own wrist.
  readonly property string etaText: {
    if (!charging || !hasReading || !reading.minutes_to_full) return ""
    var parts = ["Full at " + Qt.formatTime(
      new Date(Date.now() + reading.minutes_to_full * 60000), clockFormat)]
    if (reading.charge_limit) parts.push(reading.charge_limit + "%")
    return parts.join(" · ")
  }

  readonly property string barSpeed:
    driving && reading.speed !== null ? reading.speed + " " + reading.speed_unit : ""

  // --------------------------------------------------------------------- bar

  // The bar is the mark and nothing else. An earlier version slid the speed in
  // beside it while the car was moving, which made the bar shuffle every time
  // a car pulled away. A lot of movement in the corner of your eye to say
  // something the panel says better. The colour carries it instead.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar

    iconComponent: Component {
      RivianMark {
        iconSize: Style.bar.iconFont
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }
    }

    // Three states and no more: green while the car is moving, plain the rest
    // of the time, faded when the widget cannot vouch for what it is showing.
    // The mark is monochrome otherwise on purpose, because a bar full of
    // coloured glyphs is a bar you stop reading.
    active: root.driving
    // Green rather than the shell's urgent red, which is what WidgetButton
    // reaches for by default. A car being driven is the ordinary use of a car,
    // not an alarm, and this is the same green as the panel's live dot so the
    // two agree about what it means.
    activeColor: root.liveGreen
    // Deliberately not dimmed for a sleeping car, though the Tesla widget this
    // came from does exactly that. There it means something: a sleeping Tesla
    // cannot be read without waking it, so the fade is telling you the panel
    // is showing you the past. A sleeping Rivian is read exactly as well as an
    // awake one, so the same fade would say nothing — and since a Rivian is
    // asleep most of the time, it would say nothing almost permanently, at 45%
    // opacity, which is just a hard-to-see icon.
    //
    // What is left is the case the fade was always for: the widget cannot
    // vouch for what it is showing. Rivian unreachable, or a reading old
    // enough that the car may well have moved since.
    dimmed: root.errorText !== "" || root.stale
    tooltipText: {
      if (root.errorText !== "") return root.plain("Dude, where's my car? " + root.errorText)
      if (!root.hasReading) return "Dude, where's my car?"
      if (root.driving) return root.plain(root.summary)
      if (root.place !== "") return root.plain("Parked at " + root.place)
      return root.plain(root.summary)
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.openInMaps()
        return
      }
      root.toggle()
    }
  }

  // ------------------------------------------------------------------- panel

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)
    // Primes keyboard focus when the panel maps, which is what makes a text
    // field in here usable at all.
    focusTarget: keyCatcher

    // Wraps the content so Esc closes the panel. While the sign-in form is up
    // it stands down entirely: PanelKeyCatcher takes keys before its children,
    // so without `blocked` every letter typed into the email box would be read
    // as a navigation shortcut instead of as text.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.signingIn
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.fill: parent
        // Generous on purpose. This panel is read in glances rather than
        // scanned, and every section in it answers a different question, so
        // they want visible daylight between them rather than a tidy list.
        spacing: Style.space(12)

        // ------------------------------------------------------------- header

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, badge.height)

          // The plugin is called Rivian everywhere it is listed, because that
          // is what you look for when you go hunting for it. The joke is here,
          // at the top of the panel, where it is the actual question being asked.
          PanelSectionHeader {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "DUDE, WHERE'S MY CAR?"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: badge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            // No model name here. The panel is about one specific car and
            // naming it on every glance is noise; the bar's tooltip says which
            // one on the rare occasion that is the question.
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              // Green for reachable, whatever it is doing: driving and
              // charging are both online, and the word beside the dot already
              // says which. The dot answers one question only: is the car
              // there to be asked.
              color: root.errorText !== "" ? Color.urgent
                   : root.asleep ? Color.muted
                   : root.carState === "" ? root.foreground
                   : root.charging ? root.chargeRed
                   : root.liveGreen
              opacity: root.asleep ? 0.7 : 1
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.stateWord
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.foreground
              opacity: 0.7
            }
          }
        }

        // ----------------------------------------------------------- sign in

        // Shown instead of the car when there is no usable session, which is
        // the only time this panel has nothing true to say about a car. It
        // replaces the view rather than sitting above it, because a map of
        // where the car was last week over a form asking who you are is two
        // answers to different questions stacked on one another.
        Column {
          width: parent.width
          visible: root.signingIn
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.signInStage === "code"
              ? "Rivian has sent a one-time code to your phone or email."
              : "Rivian has no way to hand out an API token, so this signs in with the account's own email and password. They go to rivian.com and are not stored \u2014 only the session it hands back is kept."
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.foreground
            opacity: 0.75
          }

          TextField {
            id: emailField
            width: parent.width
            visible: root.signInStage === "credentials"
            enabled: !root.signInBusy
            placeholderText: "Email"
            text: root.emailText
            foreground: root.foreground
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
            onTextChanged: if (text !== root.emailText) root.emailText = text
            onAccepted: passwordField.forceActiveFocus()
            Keys.onEscapePressed: root.cancelSignIn()
            onVisibleChanged: if (visible && root.emailText === "") Qt.callLater(forceActiveFocus)
            Component.onCompleted: if (visible && root.emailText === "") Qt.callLater(forceActiveFocus)
          }

          TextField {
            id: passwordField
            width: parent.width
            visible: root.signInStage === "credentials"
            enabled: !root.signInBusy
            placeholderText: "Password"
            // The shell's own field masks on this flag; nothing here has to
            // reimplement an echo mode.
            password: true
            text: root.passwordText
            foreground: root.foreground
            onTextChanged: if (text !== root.passwordText) root.passwordText = text
            onAccepted: root.submitCredentials()
            Keys.onEscapePressed: root.cancelSignIn()
            // An email already filled in means the password is what is missing.
            onVisibleChanged: if (visible && root.emailText !== "") Qt.callLater(forceActiveFocus)
          }

          TextField {
            id: codeField
            width: parent.width
            visible: root.signInStage === "code"
            enabled: !root.signInBusy
            placeholderText: "Code"
            text: root.codeText
            foreground: root.foreground
            inputMethodHints: Qt.ImhDigitsOnly
            onTextChanged: if (text !== root.codeText) root.codeText = text
            onAccepted: root.submitCode()
            Keys.onEscapePressed: root.restartSignIn()
            onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
            Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            readonly property int buttonWidth:
              Math.floor((width - Style.space(6)) / 2)

            Button {
              width: parent.buttonWidth
              text: root.signInBusy ? "Signing in\u2026"
                  : root.signInStage === "code" ? "Verify" : "Sign in"
              enabled: !root.signInBusy && (root.signInStage === "code"
                ? root.codeText !== ""
                : root.emailText !== "" && root.passwordText !== "")
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.signInStage === "code" ? root.submitCode()
                                                     : root.submitCredentials()
            }

            Button {
              // On the code step this abandons the half-finished sign-in and
              // goes back to the email box, which is the only way out of a
              // code that never arrives.
              width: parent.buttonWidth
              text: root.signInStage === "code" ? "Start over" : "Cancel"
              enabled: !root.signInBusy
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.signInStage === "code") {
                  root.restartSignIn()
                } else {
                  root.cancelSignIn()
                  root.close()
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.signInError !== ""
            // Rivian's own wording, not a translation of it: "Invalid code" is
            // both shorter and more trustworthy than anything invented here.
            text: root.plain(root.signInError)
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Color.urgent
          }
        }

        // ---------------------------------------------------------------- map

        Rectangle {
          visible: !root.signingIn
          id: mapArea
          width: parent.width
          // Three to two rather than sixteen to nine. A map is read outwards
          // from the middle, so at a narrow width the wide aspect spends the
          // panel on horizon and leaves you two streets of context; the squarer
          // one shows the block the car is parked on.
          height: Math.round(width * 2 / 3)
          radius: Style.space(6)
          color: Qt.rgba(0, 0, 0, 0.35)
          clip: true

          MapView {
            anchors.fill: parent
            plan: root.mapPlan
            lightMap: root.lightMap
            heading: root.hasReading && root.reading.heading !== null ? root.reading.heading : 0
            driving: root.driving
            stale: root.stale
            foreground: root.foreground
            accent: root.liveAccent
            fontFamily: root.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: !root.hasPosition
            text: root.errorText !== "" ? root.errorText
                : root.hasReading ? "The car is not sharing its location"
                : "Waiting for the car"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.foreground
            opacity: 0.6
          }

          // The map is the link. Where the car is and wanting to go there are
          // the same thought, so there is nothing to aim at but what you are
          // already looking at.
          MouseArea {
            anchors.fill: parent
            enabled: root.hasPosition
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openInMaps()
          }

          // No speed badge here any more. It said what the line under the map
          // already says and what the status word above it already implies, and
          // it did so on top of the one thing in the panel worth looking at.
        }

        // -------------------------------------------------------------- where

        Column {
          visible: !root.signingIn
          width: parent.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.place !== ""
            text: root.place
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
          }

          // Above the summary rather than below it: the summary ends in how old
          // the reading is, which is the last thing on the panel worth reading
          // and so belongs last.
          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.etaText !== ""
            text: root.etaText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.liveAccent
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.summary
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.foreground
            opacity: 0.65
          }
        }

        PanelSeparator { width: parent.width; visible: !root.signingIn }

        // -------------------------------------------------------------- stats

        // Battery and range at the two ends of one line, with the bar spanning
        // both underneath. Three columns of figures was the first arrangement
        // and it only worked while the panel was wide: narrow it and each column
        // is too tight to hold a big number and its unit without them colliding.
        // Two figures and a full-width bar survives being made small, and reads
        // better wide as well.
        // The three read as one thing, so they are spaced as one thing. Left to
        // the panel's own rhythm the figures floated a long way above their own
        // bar and the block came apart.
        Column {
          visible: !root.signingIn
          width: parent.width
          spacing: Style.space(4)

          // The bar first and the numbers under it. They used to sit above at
          // display size, which made the battery the loudest thing on a panel
          // whose subject is where the car is. The bar already carries the
          // reading at a glance; the figures are there to be precise, not to
          // shout.
          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1,
                (root.hasReading && root.reading.battery !== null ? root.reading.battery : 0) / 100))
              height: parent.height
              radius: parent.radius
              color: root.charging ? root.chargeRed : root.foreground
              opacity: root.charging ? 1 : 0.8

              Behavior on width {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
              }
            }

            // The charge limit is a notch rather than a third number on the
            // line below: what you read off a bar is how far the fill is from
            // the line, and the line only needs naming once.
            Rectangle {
              visible: root.hasReading && root.reading.charge_limit !== null
              x: parent.width * Math.max(0, Math.min(1,
                (root.hasReading && root.reading.charge_limit !== null ? root.reading.charge_limit : 100) / 100))
                - width / 2
              width: Math.max(1, Style.space(2))
              height: parent.height
              color: root.foreground
              opacity: 0.5
            }
          }

          // Charge on the left, what it is heading for in the middle, range on
          // the right. The three ends of the same sentence, under the bar that
          // draws it.
          Item {
            width: parent.width
            height: batteryLabel.implicitHeight

            Text {
              textFormat: Text.PlainText
              id: batteryLabel
              anchors.left: parent.left
              text: root.hasReading && root.reading.battery !== null
                ? root.reading.battery + "%" : "\u2014"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: root.foreground
            }

            // Nothing in the middle. The charge limit lived here, centred
            // between two aligned figures, which made it read as a third
            // unrelated item and shifted about as the numbers changed width.
            // The notch on the bar shows it, and the details grid names it.

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: root.hasReading && root.reading.range !== null
                ? Math.round(root.reading.range) + " " + root.reading.range_unit : "\u2014"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: root.foreground
            }
          }
        }

        PanelSeparator { width: parent.width; visible: !root.signingIn }

        // ------------------------------------------------------------ details

        // The things you look up rather than watch. Two columns of label-over-
        // value, because a label beside its value needs a leader line to stay
        // readable at this width and a label above it needs nothing at all.
        Grid {
          id: detailGrid
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(10)

          // Ordered by what you came for. Locked is what you check when you
          // cannot find the car; software is trivia. Left as eight cells of
          // equal weight in no particular order, nothing stood out because
          // everything looked equally worth reading. Pairs are kept together
          // across each row so the two halves explain each other.
          // A null here is "the cloud has not heard", which is not the same as
          // "no", and showing an em dash for it rather than "no" is the whole
          // reason the script bothers to tell them apart.
          Detail {
            label: "locked"
            value: !root.hasReading || root.reading.locked === null ? "\u2014"
                 : root.reading.locked ? "yes" : "no"
          }

          Detail {
            // Rivian's answer to Sentry Mode, and it is called Gear Guard on the
            // car's own screen, so it is called that here.
            label: "gear guard"
            value: !root.hasReading || root.reading.gear_guard === null ? "\u2014"
                 : root.reading.gear_guard ? "armed" : "off"
          }

          Detail {
            label: "odometer"
            value: root.hasReading && root.reading.odometer !== null
              ? Number(root.reading.odometer).toLocaleString(Qt.locale(), "f", 0)
                + " " + root.reading.range_unit
              : "\u2014"
          }

          Detail {
            label: "tyres"
            // Rivian reports a verdict per corner rather than a pressure, so
            // there is no number to show and no spread to read off. "OK" or the
            // count that disagrees is the whole of what it knows.
            value: {
              if (!root.hasReading || !root.reading.tyres) return "\u2014"
              var t = root.reading.tyres
              if (t.known === 0) return "\u2014"
              return t.low === 0 ? "OK" : t.low + " low"
            }
          }

          Detail {
            label: "inside"
            value: root.hasReading && root.reading.inside_temp !== null
              ? root.reading.inside_temp + " " + root.reading.temp_unit : "\u2014"
          }

          // Rivian reports no outside temperature, so the cell that would have
          // held it holds the thing this API has and Tesla's does not: when the
          // car last spoke to the cloud. On a reading that is answering for a
          // car in a basement, this is the only field that says so.
          Detail {
            label: "last heard"
            value: {
              if (!root.hasReading || !root.reading.last_sync) return "\u2014"
              var t = Date.parse(root.reading.last_sync)
              return isNaN(t) ? "\u2014" : root.agoOf((root.now - t) / 1000)
            }
          }

          Detail {
            label: "charge limit"
            value: root.hasReading && root.reading.charge_limit !== null
              ? root.reading.charge_limit + "%" : "\u2014"
          }

          Detail {
            label: "plugged in"
            value: !root.hasReading ? "\u2014" : root.reading.plugged ? "yes" : "no"
          }

          Detail {
            label: "drive mode"
            value: root.hasReading && root.reading.drive_mode
              ? String(root.reading.drive_mode).replace(/_/g, " ") : "\u2014"
          }

          Detail {
            label: "software"
            // An update waiting is worth the arrow; which version it is is not,
            // and would not fit anyway.
            value: {
              if (!root.hasReading || !root.reading.software) return "\u2014"
              var v = String(root.reading.software)
              return root.reading.software_available
                  && root.reading.software_available !== root.reading.software
                ? v + " \u2191" : v
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: !root.signingIn && root.openText !== ""
          text: root.openText
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          color: Color.urgent
        }

        PanelSeparator { width: parent.width; visible: !root.signingIn }

        // ------------------------------------------------------------ actions

        Row {
          visible: !root.signingIn
          id: actions
          width: parent.width
          spacing: Style.space(6)

          // Split evenly rather than sized to their labels: at this width three
          // buttons hugging their text leave a ragged gap on the right, and a
          // row of equal buttons is easier to hit besides.
          readonly property int count: 2
          readonly property int buttonWidth:
            Math.floor((width - Style.space(6) * (count - 1)) / count)

          Button {
            width: actions.buttonWidth
            text: "Open in maps"
            enabled: root.hasPosition
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openInMaps()
          }

          Button {
            // The cost goes in the tooltip rather than the label, and in as few
            // words as it takes: a tooltip long enough to be a sentence is one
            // nobody finishes. "Keeps awake" rather than "wakes" because that is
            // what happens: the button is disabled while the car is asleep, and
            // the call behind it could not wake one if it were not.
            // No cost to warn about in the tooltip, and no reason to disable it
            // on a sleeping car: the cloud answers either way.
            width: actions.buttonWidth
            text: carProc.running ? "Asking\u2026" : "Refresh"
            tooltipText: "Asks Rivian, not the car"
            enabled: !carProc.running
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.refresh(true)
          }

        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          // Signing in has its own form now, so this is left with the errors
          // no form can fix: a gateway that is down, a reading that would not
          // parse. The hint is preferred when there is one because it says
          // what to do, and the raw error only when there is not.
          visible: !root.signingIn && root.errorText !== "" && !root.needsLogin
          text: root.errorHint !== "" ? root.errorHint : root.plain(root.errorText)
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.foreground
          opacity: 0.6
        }
      }
    }
  }

  // One looked-up fact: what it is, small and quiet, with the answer under it.
  component Detail: Column {
    property string label: ""
    property string value: ""

    width: Math.floor((detailGrid.width - Style.space(8)) / 2)
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: label
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: root.foreground
      opacity: 0.5
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: value
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      color: root.foreground
    }
  }

  // Lets the panel be exercised without driving anywhere:
  //
  //   omarchy-shell kayleg.rivian.test drive 87 243
  //   omarchy-shell kayleg.rivian.test charge 47
  //   omarchy-shell kayleg.rivian.test park
  //   omarchy-shell kayleg.rivian.test sleep
  //   omarchy-shell kayleg.rivian.test live
  //
  // Synthetic input does not reach this shell, so a test hook is the only way
  // to see what a moving car looks like without one.
  IpcHandler {
    target: "kayleg.rivian.test"

    function drive(speed: int, heading: int): string {
      if (!root.hasReading) return "no reading to base a drive on yet"
      var next = JSON.parse(JSON.stringify(root.reading))
      next.driving = true
      next.shift = "drive"
      next.speed = speed
      next.heading = heading
      next.at = Math.round(Date.now() / 1000)
      root.carState = "online"
      root.reading = next
      return "driving " + speed + " " + next.speed_unit + " heading " + heading
    }

    // A charge on top of whatever the panel is showing. This is the branch
    // with a clock in it, so it is the one worth being able to summon.
    function charge(minutes: int): string {
      if (!root.hasReading) return "no reading to charge from yet"
      var next = JSON.parse(JSON.stringify(root.reading))
      next.driving = false
      next.shift = "park"
      next.speed = null
      next.charging_now = true
      next.plugged = true
      next.charging = "charging_active"
      next.minutes_to_full = minutes
      next.at = Math.round(Date.now() / 1000)
      root.carState = "online"
      root.reading = next
      return "charging, full in " + minutes + " minutes"
    }

    function park(): string {
      if (!root.hasReading) return "no reading to park yet"
      var next = JSON.parse(JSON.stringify(root.reading))
      next.driving = false
      next.shift = "park"
      next.speed = null
      next.charging_now = false
      next.minutes_to_full = null
      next.at = Math.round(Date.now() / 1000)
      root.carState = "online"
      root.reading = next
      return "parked"
    }

    function sleep(): string {
      root.carState = "asleep"
      return "asleep"
    }

    // Open and close the panel without a mouse. Mainly so a screenshot of it
    // can be taken from a script — with a fixture in place, that produces a
    // picture of a car that does not exist, which is the only kind that
    // belongs in a public listing.
    function open(): string {
      if (!root.opened) root.toggle()
      return "opened"
    }

    function close(): string {
      if (root.opened) root.close()
      return "closed"
    }

    // Back to whatever the car actually says, so a test never leaves the panel
    // lying about a real car.
    function live(): string {
      if (!stateProc.running) stateProc.running = true
      root.refresh(true)
      return "refreshing"
    }
  }
}
