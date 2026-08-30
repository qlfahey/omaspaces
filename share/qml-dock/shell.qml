import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
  id: app

  property color cBg:     "#141414"
  property color cPanel:  "#1e1e1e"
  property color cPanel2: "#2a2a2a"
  property color cLine:   "#333333"
  property color cInk:    "#cacccc"
  property color cDim:    "#8a8a8d"
  property color cAccent: "#e68e0d"
  property string uiFont: "monospace"

  function hexOf(raw, key) {
    var m = raw.match(new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m"))
    return m ? m[1] : null
  }
  function parseColors(raw) {
    var g = function (k, d) { return hexOf(raw, k) || d }
    app.cBg     = g("background", app.cBg)
    app.cPanel  = g("lighter_background", app.cBg)
    app.cPanel2 = g("selection", g("muted", app.cPanel))
    app.cLine   = g("muted", g("selection", "#333333"))
    app.cInk    = g("bright_foreground", g("foreground", app.cInk))
    app.cDim    = g("light_foreground", g("dark_foreground", app.cDim))
    app.cAccent = g("accent", g("blue", app.cAccent))
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false; watchChanges: true
    onLoaded: app.parseColors(text()); onFileChanged: reload()
  }
  Process {
    command: ["omarchy", "font", "current"]; running: true
    stdout: StdioCollector { id: fontOut; waitForEnd: true }
    onExited: { var f = (fontOut.text || "").trim(); if (f) app.uiFont = f }
  }

  property var pins: []
  FileView {
    id: pinsFile
    path: Quickshell.env("HOME") + "/.local/share/omaspaces/dock.json"
    printErrors: false; watchChanges: true
    onLoaded: { try { app.pins = JSON.parse(text()).pins || [] } catch (e) { app.pins = [] } }
    onFileChanged: reload()
    onLoadFailed: app.pins = []
  }
  Process { command: ["omaspaces", "dock", "pins"]; running: true
    stdout: StdioCollector { id: pinsOut; waitForEnd: true }
    onExited: { try { app.pins = JSON.parse(pinsOut.text) } catch (e) {} }
  }

  property var layoutNames: []
  Process {
    id: listProc
    command: ["omaspaces", "list", "--json"]; running: true
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: { try { app.layoutNames = JSON.parse(listOut.text) } catch (e) { app.layoutNames = [] } }
  }
  Process {
    running: true
    command: ["bash", "-lc",
      "inotifywait -m -q -e close_write,create,delete,move " +
      Quickshell.env("HOME") + "/.config/omarchy/layouts 2>/dev/null"]
    stdout: SplitParser { onRead: function (l) { listProc.running = true } }
  }

  function entryById(id) {
    var v = DesktopEntries.applications.values, lid = String(id).toLowerCase()
    for (var i = 0; i < v.length; i++) {
      var e = v[i]
      if (String(e.id).toLowerCase() === lid) return e
    }
    return null
  }
  function iconFor(id) {
    var e = app.entryById(id)
    var name = e ? String(e.icon || "") : ""
    if (name.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (name.charAt(0) === "/") return "file://" + name
    return Quickshell.iconPath(name, true)
  }
  function nameFor(id) { var e = app.entryById(id); return e ? e.name : id }
  function runningToplevel(id) {
    var v = ToplevelManager.toplevels.values, lid = String(id).toLowerCase()
    for (var i = 0; i < v.length; i++) {
      var aid = String(v[i].appId || "").toLowerCase()
      if (aid === lid || (aid.length && lid.indexOf(aid) >= 0) || (aid.length && aid.indexOf(lid) >= 0)) return v[i]
    }
    return null
  }
  function activateOrLaunch(id) {
    var t = app.runningToplevel(id)
    if (t) t.activate()
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }
  function togglePin(id, pinned) {
    Quickshell.execDetached(["omaspaces", "dock", pinned ? "unpin" : "pin", id])
  }
  function dockItems() {
    var items = [], seen = {}
    for (var i = 0; i < app.pins.length; i++) { items.push({ id: app.pins[i], pinned: true }); seen[String(app.pins[i]).toLowerCase()] = true }
    var v = ToplevelManager.toplevels.values
    for (var j = 0; j < v.length; j++) {
      var aid = String(v[j].appId || "")
      if (!aid.length || seen[aid.toLowerCase()]) continue
      seen[aid.toLowerCase()] = true
      items.push({ id: aid, pinned: false })
    }
    return items
  }
  function applyLayout(n) { Quickshell.execDetached(["omaspaces", "apply", n]) }
  function removeLayout(n) { Quickshell.execDetached(["omaspaces", "rm", n]) }
  function buildNew() { Quickshell.execDetached(["omaspaces", "build"]) }
  function addPin() { Quickshell.execDetached(["omaspaces", "dock", "add"]) }
  function launchNew(id) { Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"]) }
  function workspaceById(id) {
    var v = Hyprland.workspaces.values
    for (var i = 0; i < v.length; i++) if (v[i].id === id) return v[i]
    return null
  }
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5], v = Hyprland.workspaces.values
    for (var i = 0; i < v.length; i++) { var id = v[i].id; if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id) }
    ids.sort(function (a, b) { return a - b }); return ids
  }
  function focusWorkspace(id) { Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "' + id + '" })']) }
  function cycleWorkspace(dir) { Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "' + (dir > 0 ? "e+1" : "e-1") + '" })']) }

  PanelWindow {
    id: win
    anchors.bottom: true
    color: "transparent"
    implicitWidth: pill.width
    implicitHeight: 78
    WlrLayershell.namespace: "omaspaces-dock"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
      id: pill
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      height: 64
      width: bar.implicitWidth + 28
      radius: 20
      color: Qt.rgba(app.cPanel.r, app.cPanel.g, app.cPanel.b, 0.9)
      border.color: Qt.rgba(app.cInk.r, app.cInk.g, app.cInk.b, 0.12)
      border.width: 1

      WheelHandler { onWheel: function (e) { app.cycleWorkspace(e.angleDelta.y < 0 ? 1 : -1) } }

      Row {
        id: bar
        anchors.centerIn: parent
        spacing: 6

        Repeater {
          model: app.workspaceIds()
          delegate: Rectangle {
            property int wid: modelData
            property var ws: app.workspaceById(wid)
            property bool wfocused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wid
            property bool woccupied: ws && ws.toplevels.values.length > 0
            width: 30; height: 34; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            color: wfocused ? app.cAccent : (wsm.containsMouse ? app.cPanel2 : "transparent")
            border.color: app.cLine; border.width: wfocused ? 0 : 1
            opacity: (woccupied || wfocused) ? 1 : 0.45
            Text { anchors.centerIn: parent; text: String(wid); color: wfocused ? "#0b0b0b" : app.cInk; font.family: app.uiFont; font.pixelSize: 13; font.bold: wfocused }
            MouseArea { id: wsm; anchors.fill: parent; hoverEnabled: true; onClicked: app.focusWorkspace(wid) }
          }
        }
        Rectangle { width: 1; height: 34; color: app.cLine; anchors.verticalCenter: parent.verticalCenter }

        Repeater {
          model: (app.pins, ToplevelManager.toplevels.values, app.dockItems())
          delegate: Item {
            id: appItem
            property var it: modelData
            property bool running: app.runningToplevel(it.id) !== null
            width: 52; height: 56
            anchors.verticalCenter: parent.verticalCenter

            Image {
              id: icon
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: dot.top; anchors.bottomMargin: 4
              width: 42; height: 42
              sourceSize.width: 84; sourceSize.height: 84
              source: app.iconFor(it.id)
              fillMode: Image.PreserveAspectFit
              smooth: true
              opacity: it.pinned ? 1.0 : 0.92
              scale: ama.containsMouse ? 1.28 : 1.0
              transformOrigin: Item.Bottom
              Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }
            Rectangle {
              id: dot
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom; anchors.bottomMargin: 2
              width: 4; height: 4; radius: 2
              color: appItem.running ? app.cAccent : "transparent"
            }
            MouseArea {
              id: ama
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function (m) {
                if (m.button === Qt.RightButton) app.togglePin(it.id, it.pinned)
                else if (m.modifiers & Qt.MetaModifier) app.launchNew(it.id)
                else app.activateOrLaunch(it.id)
              }
            }
            Rectangle {
              visible: ama.containsMouse
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.top; anchors.bottomMargin: 2
              width: tip.width + 14; height: tip.height + 8; radius: 6
              color: app.cPanel2; border.color: app.cLine; border.width: 1
              Text { id: tip; anchors.centerIn: parent; text: app.nameFor(it.id); color: app.cInk; font.family: app.uiFont; font.pixelSize: 11 }
            }
          }
        }

        Item {
          width: 40; height: 56; anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.centerIn: parent; width: 34; height: 34; radius: 9
            color: pam.containsMouse ? app.cPanel2 : "transparent"
            border.color: app.cLine; border.width: 1
            Text { anchors.centerIn: parent; text: "\uf067"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 12 }
            MouseArea { id: pam; anchors.fill: parent; hoverEnabled: true; onClicked: app.addPin() }
          }
        }

        Rectangle { width: 1; height: 34; color: app.cLine; anchors.verticalCenter: parent.verticalCenter }

        Repeater {
          model: app.layoutNames
          delegate: Rectangle {
            height: 34; radius: 10; width: lrow.width + 22
            anchors.verticalCenter: parent.verticalCenter
            color: lm.containsMouse ? app.cPanel2 : "transparent"
            border.color: app.cLine; border.width: 1
            Row {
              id: lrow; anchors.centerIn: parent; spacing: 6
              Text { text: "\uf0db"; color: app.cAccent; font.family: app.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
              Text { text: modelData; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true; onClicked: app.applyLayout(modelData) }
            Rectangle {
              visible: lm.containsMouse
              anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 2 }
              width: 15; height: 15; radius: 8
              color: app.cPanel2; border.color: app.cLine; border.width: 1
              Text { anchors.centerIn: parent; text: "×"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 11 }
              MouseArea { anchors.fill: parent; onClicked: app.removeLayout(modelData) }
            }
          }
        }

        Item {
          width: 40; height: 56; anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.centerIn: parent; width: 34; height: 34; radius: 9
            color: bm.containsMouse ? app.cAccent : app.cPanel2
            Text { anchors.centerIn: parent; text: "+"; color: bm.containsMouse ? "#0b0b0b" : app.cInk; font.family: app.uiFont; font.pixelSize: 18 }
            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: app.buildNew() }
          }
        }

      }
    }
  }
}
