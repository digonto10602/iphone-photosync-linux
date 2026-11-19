import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// iPhone Transfers — bar icon with a progress ring; click opens a see-through panel with
// the PhotoSync transfer status. Data comes from `iphone-transfers --json` (one JSON line
// per second), which watches ~/iphone_backup.
Panel {
  id: root
  moduleName: "digimonk.iphone-transfers"
  ipcTarget: "iphone-transfers"
  manageIpc: true

  readonly property string home: Quickshell.env("HOME")
  readonly property string bin: home + "/.local/bin/iphone-transfers"
  readonly property string backupDir: home + "/iphone_backup"

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real panelAlpha: Math.max(0.3, Math.min(1, Number(setting("panelOpacity", 72)) / 100))

  property var st: ({ live: false, peers: [], speed: 0, speeds: [], total: 0, done: 0, doneBytes: 0,
                      fraction: -1, eta: -1, sessionEnd: 0, active: [], stalled: [], recent: [] })
  property bool feedOk: false
  property real spin: 0

  readonly property bool transferring: st.active.length > 0
  readonly property var lead: st.active.length > 0 ? st.active[0] : null
  // Overall fraction when the total is known, else the leading file's own progress, else -1.
  readonly property real ringValue: st.fraction >= 0 ? st.fraction
                                  : (lead && lead.expected > 0 ? Math.min(1, lead.size / lead.expected) : -1)
  readonly property bool allDone: st.total > 0 && st.done >= st.total

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function statusLine() {
    if (!feedOk) return strings.t("status.feedDown")
    if (transferring) {
      var proto = st.peers.length > 0 ? st.peers[0].split(" ").slice(1).join(" ") : ""
      return proto ? strings.t("status.receiving").arg(proto) : strings.t("status.arriving")
    }
    if (st.peers.length > 0) return strings.t("status.connected")
    if (st.sessionEnd > 0) {
      var t = new Date(st.sessionEnd * 1000).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
      return strings.t("status.lastTransfer").arg(t)
    }
    return strings.t("status.idle")
  }

  function pct(v) { return Commons.I18n.formatNumber(Math.floor(Math.max(0, Math.min(1, v)) * 100), 0) + "%" }

  function setTotal(n) {
    n = Math.floor(Number(n))
    if (!isFinite(n) || n < 0) n = 0
    if (n > 1000000) n = 1000000
    Quickshell.execDetached([root.bin, "--set-total", String(n)])
    var copy = Object.assign({}, st); copy.total = n; st = copy      // show it at once
  }

  function openFolder() { Quickshell.execDetached(["uwsm-app", "--", "nautilus", root.backupDir]) }
  function openTerminal() {
    Quickshell.execDetached(["omarchy", "launch", "or", "focus", "tui", "--app-id=org.omarchy.iphone-transfers", "iphone-transfers"])
  }

  // KeyboardPanel paints its card in the theme's popup colour at full strength; make this
  // panel's card see-through (same colour, panelOpacity alpha).
  function tintCard() {
    // The content is loaded inside the card (a BorderSurface): walk up from it.
    var c = panel.loadedContent
    for (var depth = 0; c && depth < 8; depth++, c = c.parent) {
      if (c.borderSpec !== undefined && c.padding !== undefined && c.radius !== undefined && c.color !== undefined) {
        c.color = Qt.binding(function() {
          var b = Commons.Color.popups.background
          return Qt.rgba(b.r, b.g, b.b, root.panelAlpha)
        })
        return
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    Qt.callLater(function() {
      root.tintCard()
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    })
  }

  // Constant-speed spinner while bytes arrive but no percentage is known.
  NumberAnimation on spin {
    from: 0; to: 1; duration: 1400; loops: Animation.Infinite
    running: root.transferring && root.ringValue < 0 && Style.duration(1400) > 0
  }

  // ── data feed ──────────────────────────────────────────────────────────────
  Process {
    id: feed
    command: [root.bin, "--json"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var d = Model.parse(line)
        if (d) { root.st = d; root.feedOk = true }
      }
    }
    onExited: function(exitCode) { root.feedOk = false; restartFeed.restart() }
  }
  Timer { id: restartFeed; interval: 3000; onTriggered: feed.running = true }

  // ── bar icon ───────────────────────────────────────────────────────────────
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Ring {
          anchors.centerIn: parent
          width: button.iconSize + Style.space(4); height: width
          value: root.ringValue
          spin: root.spin
          spinning: root.transferring
          ringColor: root.accent
          lineFrac: 0.11
          visible: root.transferring || root.st.peers.length > 0
        }
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "󰄜"
          font.family: root.fontFamily
          font.pixelSize: (root.transferring || root.st.peers.length > 0) ? button.iconSize * 0.62 : button.iconSize * 0.85
          color: root.transferring ? root.accent : (root.st.peers.length > 0 ? root.barForeground : Qt.darker(root.barForeground, 1.4))
        }
      }
    }
    onPressed: function(code) {
      if (code === Qt.RightButton) root.openTerminal()
      else if (code === Qt.MiddleButton) root.openFolder()
      else root.toggle()
    }
  }

  // ── panel ──────────────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))
    onLoadedContentChanged: Qt.callLater(root.tintCard)

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // No single-key shortcuts: the panel can pop up on its own when a transfer starts,
      // and keys typed for another window must not trigger anything here.

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // soft accent glow behind the header
        Rectangle {
          width: parent.width; height: Style.space(150); radius: Style.cornerRadius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
            GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.0) }
          }
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(14)

          // hero: big ring + title, status and speed
          RowLayout {
            width: parent.width
            spacing: Style.space(16)

            Item {
              implicitWidth: Style.space(100); implicitHeight: implicitWidth
              Ring {
                anchors.fill: parent
                value: root.ringValue
                spin: root.spin
                spinning: root.transferring
                ringColor: root.accent
                lineFrac: 0.075
              }
              Column {
                anchors.centerIn: parent
                spacing: 0
                PlainText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.ringValue >= 0 ? root.pct(root.ringValue) : "󰄜"
                  font.pixelSize: Style.font.display
                  font.bold: true
                  color: root.ringValue >= 0 ? root.fg : root.accent
                }
                PlainText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.st.total > 0 || root.transferring
                  text: root.st.total > 0 ? strings.t("stat.files").toLowerCase() : root.lead ? root.lead.name.substring(0, 10) : ""
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              PlainText {
                Layout.fillWidth: true
                text: strings.t("title")
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              PlainText {
                Layout.fillWidth: true
                text: root.allDone ? strings.t("done.all") : root.statusLine()
                font.pixelSize: Style.font.bodySmall
                color: root.allDone ? root.accent : root.dim
                elide: Text.ElideRight
              }
              PlainText {
                Layout.topMargin: Style.space(4)
                text: Model.human(root.st.speed) + "/s"
                font.pixelSize: Style.font.displayLarge
                font.bold: true
                color: root.st.speed > 0 ? root.accent : root.dim
              }
              PlainText {
                visible: root.st.peers.length > 0
                Layout.fillWidth: true
                text: "● " + root.st.peers.join("  ·  ")
                font.pixelSize: Style.font.caption
                color: root.accent
                elide: Text.ElideRight
              }
            }
          }

          // speed history
          Canvas {
            id: spark
            width: parent.width
            height: Style.space(48)
            property var values: root.st.speeds
            property color lineColor: root.accent
            onValuesChanged: requestPaint()
            onLineColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var v = values || []
              ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
              ctx.lineWidth = 1
              ctx.beginPath(); ctx.moveTo(0, height - 0.5); ctx.lineTo(width, height - 0.5); ctx.stroke()
              if (v.length < 2) return
              var max = 1
              for (var i = 0; i < v.length; i++) max = Math.max(max, v[i])
              var n = 60, step = width / (n - 1), off = n - v.length
              function px(i) { return (i + off) * step }
              function py(val) { return height - 2 - (val / max) * (height - 6) }
              var g = ctx.createLinearGradient(0, 0, 0, height)
              g.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.38))
              g.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0))
              ctx.beginPath()
              ctx.moveTo(px(0), height)
              for (var j = 0; j < v.length; j++) ctx.lineTo(px(j), py(v[j]))
              ctx.lineTo(px(v.length - 1), height)
              ctx.closePath()
              ctx.fillStyle = g
              ctx.fill()
              ctx.beginPath()
              for (var k = 0; k < v.length; k++) { if (k === 0) ctx.moveTo(px(k), py(v[k])); else ctx.lineTo(px(k), py(v[k])) }
              ctx.strokeStyle = lineColor
              ctx.lineWidth = 2
              ctx.lineJoin = "round"
              ctx.stroke()
            }
          }

          // stat chips
          Row {
            width: parent.width
            spacing: Style.space(8)
            readonly property real chipW: (width - spacing * 2) / 3
            StatChip {
              width: parent.chipW
              label: strings.t("stat.files")
              value: root.st.total > 0 ? root.st.done + " / " + root.st.total : String(root.st.done)
            }
            StatChip { width: parent.chipW; label: strings.t("stat.received"); value: Model.human(root.st.doneBytes) }
            StatChip {
              width: parent.chipW
              label: strings.t("stat.timeLeft")
              value: root.st.total > 0 ? (root.allDone ? "✓" : Model.duration(root.st.eta)) : "—"
              highlight: root.st.total > 0 && !root.allDone
            }
          }

          // how many files are being sent
          Rectangle {
            width: parent.width
            implicitHeight: totalRow.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.st.total > 0 ? 0.25 : 0.6)

            RowLayout {
              id: totalRow
              anchors.left: parent.left; anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlainText { Layout.fillWidth: true; text: strings.t("total.label"); font.pixelSize: Style.font.body }
                PlainText {
                  Layout.fillWidth: true
                  visible: root.st.total === 0
                  text: strings.t("total.hint")
                  font.pixelSize: Style.font.caption
                  color: root.dim
                  wrapMode: Text.WordWrap
                }
              }
              StepButton { glyph: "−"; onClicked: root.setTotal(Math.max(0, root.st.total - 1)) }
              Rectangle {
                implicitWidth: Style.space(64); implicitHeight: Style.space(28)
                radius: Style.cornerRadius
                color: Qt.rgba(0, 0, 0, 0.25)
                border.width: totalInput.activeFocus ? 2 : 1
                border.color: totalInput.activeFocus ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
                TextInput {
                  id: totalInput
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  horizontalAlignment: TextInput.AlignHCenter
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  color: root.fg
                  selectionColor: root.accent
                  validator: IntValidator { bottom: 0; top: 1000000 }
                  inputMethodHints: Qt.ImhDigitsOnly
                  Component.onCompleted: text = root.st.total > 0 ? String(root.st.total) : ""
                  onAccepted: { root.setTotal(parseInt(text || "0", 10)); focus = false; panel.loadedContent.forceActiveFocus() }
                  Keys.onEscapePressed: { focus = false; panel.loadedContent.forceActiveFocus() }
                  onActiveFocusChanged: if (!activeFocus) text = root.st.total > 0 ? String(root.st.total) : ""
                  PlainText {
                    anchors.centerIn: parent
                    visible: totalInput.text === "" && !totalInput.activeFocus
                    text: strings.t("total.unknown")
                    font.pixelSize: Style.font.bodySmall
                    color: root.accent
                  }
                }
                Connections {
                  target: root
                  function onStChanged() { if (!totalInput.activeFocus) totalInput.text = root.st.total > 0 ? String(root.st.total) : "" }
                }
              }
              StepButton {
                glyph: "+"
                onClicked: root.setTotal(root.st.total > 0 ? root.st.total + 1 : Math.max(1, root.st.done + root.st.active.length))
              }
            }
          }

          // files arriving now
          SectionTitle { text: strings.t("section.now") + (root.st.active.length > 0 ? "  " + root.st.active.length : "") }
          PlainText {
            visible: root.st.active.length === 0
            width: parent.width
            text: strings.t("nothing")
            font.pixelSize: Style.font.bodySmall
            color: root.dim
          }
          Repeater {
            model: root.st.active
            FileProgress { required property var modelData; width: column.width; file: modelData }
          }

          // stalled partial files
          SectionTitle { visible: root.st.stalled.length > 0; text: strings.t("section.stalled"); color: root.urgent }
          Repeater {
            model: root.st.stalled
            RowLayout {
              required property var modelData
              width: column.width
              spacing: Style.space(8)
              PlainText { text: "󰀦"; color: root.urgent; font.pixelSize: Style.font.body }
              PlainText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideMiddle; font.pixelSize: Style.font.bodySmall }
              PlainText {
                text: strings.t("stalled.meta")
                        .arg(modelData.expected > 0 ? root.pct(modelData.size / modelData.expected) : Model.human(modelData.size))
                        .arg(Model.duration(modelData.idle))
                font.pixelSize: Style.font.caption
                color: root.urgent
              }
            }
          }

          // finished in this transfer
          SectionTitle { visible: root.st.recent.length > 0; text: strings.t("section.recent") }
          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.st.recent
              RowLayout {
                required property var modelData
                width: column.width
                spacing: Style.space(8)
                PlainText { text: ""; color: root.accent; font.pixelSize: Style.font.bodySmall }
                PlainText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideMiddle; font.pixelSize: Style.font.bodySmall }
                PlainText { text: modelData.folder.replace(/^videos\/|^images\//, ""); color: root.dim; font.pixelSize: Style.font.caption }
                PlainText { text: Model.human(modelData.size); color: root.dim; font.pixelSize: Style.font.caption }
              }
            }
          }

          // actions
          Row {
            width: parent.width
            spacing: Style.space(8)
            PillButton { width: (parent.width - parent.spacing) / 2; glyph: ""; label: strings.t("button.folder"); onClicked: root.openFolder() }
            PillButton { width: (parent.width - parent.spacing) / 2; glyph: ""; label: strings.t("button.terminal"); onClicked: root.openTerminal() }
          }
        }
      }
    }
  }

  // ── building blocks ────────────────────────────────────────────────────────
  component PlainText: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    color: root.fg
  }

  component SectionTitle: PlainText {
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    font.capitalization: Font.AllUppercase
    color: root.dim
  }

  component Ring: Canvas {
    id: ring
    property real value: -1
    property real spin: 0
    property bool spinning: false
    property color ringColor: root.accent
    property real lineFrac: 0.08
    onValueChanged: requestPaint()
    onSpinChanged: if (spinning && value < 0) requestPaint()
    onSpinningChanged: requestPaint()
    onRingColorChanged: requestPaint()
    onVisibleChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var lw = Math.max(1.5, Math.min(width, height) * lineFrac)
      var r = Math.min(width, height) / 2 - lw / 2 - 0.5
      var cx = width / 2, cy = height / 2
      ctx.lineCap = "round"
      ctx.lineWidth = lw
      ctx.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.18)
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
      ctx.strokeStyle = ringColor
      ctx.beginPath()
      if (value >= 0) {
        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.015, Math.min(1, value)))
      } else if (spinning) {
        var a = spin * 2 * Math.PI - Math.PI / 2
        ctx.arc(cx, cy, r, a, a + Math.PI * 0.55)
      } else {
        return
      }
      ctx.stroke()
    }
  }

  component StatChip: Rectangle {
    property string label: ""
    property string value: ""
    property bool highlight: false
    implicitHeight: chipCol.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
    border.width: 1
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, highlight ? 0.55 : 0.18)
    Column {
      id: chipCol
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      spacing: Style.space(2)
      PlainText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: label; font.pixelSize: Style.font.caption; color: root.dim }
      PlainText {
        width: parent.width; horizontalAlignment: Text.AlignHCenter
        text: value; font.pixelSize: Style.font.title; font.bold: true
        color: highlight ? root.accent : root.fg
        elide: Text.ElideRight
      }
    }
  }

  component FileProgress: Column {
    property var file: null
    readonly property real frac: file && file.expected > 0 ? Math.min(1, file.size / file.expected) : -1
    spacing: Style.space(4)
    RowLayout {
      width: parent.width
      spacing: Style.space(8)
      PlainText { Layout.fillWidth: true; text: file ? file.name : ""; elide: Text.ElideMiddle; font.pixelSize: Style.font.body }
      PlainText { text: frac >= 0 ? root.pct(frac) : ""; color: root.accent; font.pixelSize: Style.font.bodySmall; font.bold: true }
    }
    Rectangle {
      id: track
      width: parent.width; height: Style.space(5); radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
      Rectangle {
        height: parent.height; radius: parent.radius
        width: frac >= 0 ? Math.max(height, parent.width * frac) : parent.width * 0.25
        x: frac >= 0 ? 0 : (parent.width - width) * (0.5 + 0.5 * Math.sin(root.spin * 2 * Math.PI))
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) }
          GradientStop { position: 1.0; color: root.accent }
        }
        Behavior on width { NumberAnimation { duration: Style.duration(250); easing.type: Easing.OutCubic } }
      }
    }
    PlainText {
      width: parent.width
      font.pixelSize: Style.font.caption
      color: root.dim
      elide: Text.ElideRight
      text: !file ? "" : file.expected > 0
            ? strings.t("file.meta").arg(Model.human(file.size)).arg(Model.human(file.expected)).arg(Model.human(file.speed)).arg(Model.duration(file.eta))
            : strings.t("file.metaUnknown").arg(Model.human(file.size)).arg(Model.human(file.speed))
    }
  }

  component StepButton: Rectangle {
    property string glyph: ""
    signal clicked()
    implicitWidth: Style.space(28); implicitHeight: Style.space(28)
    radius: width / 2
    color: stepMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
    PlainText { anchors.centerIn: parent; text: glyph; font.pixelSize: Style.font.heading; font.bold: true; color: root.accent }
    MouseArea { id: stepMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
  }

  component PillButton: Rectangle {
    property string glyph: ""
    property string label: ""
    signal clicked()
    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: pillMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
    border.width: 1
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, pillMouse.containsMouse ? 0.8 : 0.3)
    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)
      PlainText { text: glyph; color: root.accent; font.pixelSize: Style.font.body }
      PlainText { text: label; font.pixelSize: Style.font.bodySmall }
    }
    MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
  }
}
