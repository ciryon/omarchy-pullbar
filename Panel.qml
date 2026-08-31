import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget: number of pull requests waiting on your review, with a popup
// listing review requests, PRs assigned to you, and PRs you opened. Data comes
// from `gh search prs` via prs.sh; clicking a row opens it in the browser.
Panel {
  id: root
  moduleName: "io.github.ciryon.pullbar"
  ipcTarget: "io.github.ciryon.pullbar"
  manageIpc: false

  readonly property int refreshIntervalSec: Math.max(60, parseInt(String(setting("refreshIntervalSec", 300)), 10) || 300)
  readonly property int maxPerSection: Math.max(3, parseInt(String(setting("maxPerSection", 10)), 10) || 10)
  readonly property string helperPath: String(Qt.resolvedUrl("prs.sh")).replace("file://", "")

  property var entries: []
  property bool loading: false
  property string lastError: ""
  property int reviewCount: 0
  property int cursor: -1

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string barLabel: " " + reviewCount

  function refresh() {
    if (proc.running) return
    loading = true
    proc.command = ["bash", helperPath, String(maxPerSection)]
    proc.running = true
  }

  function apply(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (e) {
      lastError = "Could not read pull requests"
      return
    }
    var sections = [["Review requested", data.review], ["Assigned to me", data.assigned], ["Opened by me", data.authored]]
    var seen = ({})
    var list = []
    for (var s = 0; s < sections.length; s++) {
      var name = sections[s][0]
      var prs = Array.isArray(sections[s][1]) ? sections[s][1] : []
      for (var i = 0; i < prs.length; i++) {
        var pr = prs[i]
        if (!pr || !pr.url || seen[pr.url]) continue
        seen[pr.url] = true
        list.push({
          section: name,
          title: String(pr.title || ""),
          repo: pr.repository ? String(pr.repository.nameWithOwner || pr.repository.name || "") : "",
          number: Number(pr.number || 0),
          url: String(pr.url),
          draft: pr.isDraft === true
        })
      }
    }
    entries = list
    reviewCount = Array.isArray(data.review) ? data.review.length : 0
    lastError = ""
    if (cursor >= list.length) cursor = list.length - 1
  }

  function openEntry(entry) {
    if (!entry || !entry.url) return
    Qt.openUrlExternally(entry.url)
    close()
  }

  function moveCursor(dy) {
    if (entries.length === 0) return
    cursor = Math.max(0, Math.min(entries.length - 1, (cursor < 0 ? 0 : cursor + dy)))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursor = -1
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    running: false
    command: []
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) root.apply(out.text)
      else root.lastError = String(err.text || "").trim() || "gh search prs failed"
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function count(): string { return String(root.reviewCount) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    slotSize: Style.bar.statusSlot
    tooltipText: root.reviewCount === 1 ? "1 pull request awaits your review" : root.reviewCount + " pull requests await your review"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: if (root.cursor >= 0) root.openEntry(root.entries[root.cursor])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: flick
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
          width: flick.width
          spacing: Style.space(4)

          PanelHero {
            width: parent.width
            title: "Pull requests"
            meta: root.lastError !== "" ? root.lastError
                                        : (root.loading ? "Refreshing…" : root.entries.length + " open")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.entries.length === 0 && root.lastError === ""
            width: parent.width
            text: root.loading ? "Loading…" : "Nothing open"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            topPadding: Style.space(8)
          }

          Repeater {
            model: root.entries

            Column {
              width: column.width
              spacing: Style.space(2)

              PanelSectionHeader {
                visible: index === 0 || root.entries[index - 1].section !== modelData.section
                text: modelData.section
                foreground: root.foreground
                fontFamily: root.fontFamily
                topPadding: Style.space(10)
              }

              Rectangle {
                width: parent.width
                implicitHeight: rowText.implicitHeight + Style.space(12)
                radius: Style.space(6)
                color: root.cursor === index || rowHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"

                Column {
                  id: rowText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: modelData.title
                    color: modelData.draft ? root.dim : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: modelData.repo + " #" + modelData.number + (modelData.draft ? " · draft" : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                HoverHandler { id: rowHover; onHoveredChanged: if (hovered) root.cursor = index }

                TapHandler { onTapped: root.openEntry(modelData) }
              }
            }
          }
        }
      }
    }
  }
}
