import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
  id: app

  property color cBg: "#141414"
  property color cPanel: "#1e1e1e"
  property color cPanel2: "#2a2a2a"
  property color cLine: "#333333"
  property color cInk: "#cacccc"
  property color cDim: "#8a8a8d"
  property color cAccent: "#e68e0d"
  property string uiFont: "monospace"

  function hex(raw, key) {
    var m = raw.match(new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m"))
    return m ? m[1] : null
  }
  function loadTheme(raw) {
    function g(k, d) { return hex(raw, k) || d }
    cBg = g("background", cBg)
    cPanel = g("lighter_background", cBg)
    cPanel2 = g("selection", g("muted", cPanel))
    cLine = g("muted", g("selection", cLine))
    cInk = g("bright_foreground", g("foreground", cInk))
    cDim = g("light_foreground", g("dark_foreground", cDim))
    cAccent = g("accent", g("blue", cAccent))
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: app.loadTheme(text())
  }
  Process {
    command: ["omarchy", "font", "current"]
    running: true
    stdout: StdioCollector { id: fontOut; waitForEnd: true }
    onExited: { var f = (fontOut.text || "").trim(); if (f) app.uiFont = f }
  }

  property var apps: []
  property string filter: ""
  property int pick: 0
  Process {
    command: ["omaspaces", "apps", "--json"]
    running: true
    stdout: StdioCollector { id: appsOut; waitForEnd: true }
    onExited: { try { app.apps = JSON.parse(appsOut.text) } catch (e) { app.apps = [] } }
  }

  // Real work-area constraints in logical px, matching how `omaspaces apply` sizes tiles
  // (monitor logical size − reserved − 2·gaps_out; each tile inset by gaps_in).
  property real cW: 1516
  property real cH: 740
  property int cGi: 5
  property int cBs: 2
  property int minTile: 160
  property int sizeStep: 32
  property bool cReady: false
  function firstInt(s, d) { var m = String(s).match(/-?\d+/); return m ? parseInt(m[0]) : d }
  Process {
    command: ["bash", "-lc",
      "hyprctl monitors -j | jq -r '(([.[]|select(.focused)][0]) // .[0])|(.width,.height,.scale,.reserved[0],.reserved[1],.reserved[2],.reserved[3])'; " +
      "hyprctl getoption general:gaps_in -j | jq -r '.css // .int // 5'; " +
      "hyprctl getoption general:gaps_out -j | jq -r '.css // .int // 10'; " +
      "hyprctl getoption general:border_size -j | jq -r '.int // 2'"]
    running: true
    stdout: StdioCollector { id: consOut; waitForEnd: true }
    onExited: {
      var lines = (consOut.text || "").trim().split("\n")
      if (lines.length < 10) return
      var scale = parseFloat(lines[2]) || 1
      var lw = Math.round(app.firstInt(lines[0], 1920) / scale)
      var lh = Math.round(app.firstInt(lines[1], 1080) / scale)
      var rl = app.firstInt(lines[3], 0), rt = app.firstInt(lines[4], 0)
      var rr = app.firstInt(lines[5], 0), rb = app.firstInt(lines[6], 0)
      var gi = app.firstInt(lines[7], 5), go = app.firstInt(lines[8], 10)
      app.cGi = gi; app.cBs = app.firstInt(lines[9], 2)
      app.cW = Math.max(200, lw - rl - rr - 2 * go)
      app.cH = Math.max(200, lh - rt - rb - 2 * go)
      app.cReady = true
    }
  }

  function matches() {
    if (!filter) return apps
    var f = filter.toLowerCase()
    return apps.filter(function (a) { return a.name.toLowerCase().indexOf(f) >= 0 })
  }

  // Layout is a binary tree: a leaf holds {id, app}; a split holds {id, split, ratio, a, b}.
  property var tree: null
  property int rev: 0
  property string sel: ""
  property int uid: 1
  function nid() { return "n" + (uid++) }
  function leaf(a) { return { id: nid(), app: a || null } }
  function touch() { rev++ }
  function isLeaf(n) { return n && !n.split }

  function template(name) {
    if (name === "single") return leaf()
    if (name === "cols2") return { id: nid(), split: "v", ratio: 0.5, a: leaf(), b: leaf() }
    if (name === "cols3") return { id: nid(), split: "v", ratio: 0.34, a: leaf(),
                                   b: { id: nid(), split: "v", ratio: 0.5, a: leaf(), b: leaf() } }
    if (name === "main") return { id: nid(), split: "v", ratio: 0.6, a: leaf(),
                                  b: { id: nid(), split: "h", ratio: 0.5, a: leaf(), b: leaf() } }
    if (name === "grid") return { id: nid(), split: "h", ratio: 0.5,
                                  a: { id: nid(), split: "v", ratio: 0.5, a: leaf(), b: leaf() },
                                  b: { id: nid(), split: "v", ratio: 0.5, a: leaf(), b: leaf() } }
    return leaf()
  }
  function walk(n, x, y, w, h, leaves, divs) {
    if (!n) return
    if (isLeaf(n)) { if (leaves) leaves.push({ id: n.id, x: x, y: y, w: w, h: h, app: n.app }); return }
    if (n.split === "v") {
      var wa = w * n.ratio
      if (divs) divs.push({ id: n.id, vertical: true, px: x + wa, py: y, len: h, node: n })
      walk(n.a, x, y, wa, h, leaves, divs)
      walk(n.b, x + wa, y, w - wa, h, leaves, divs)
    } else {
      var ha = h * n.ratio
      if (divs) divs.push({ id: n.id, vertical: false, px: x, py: y + ha, len: w, node: n })
      walk(n.a, x, y, w, ha, leaves, divs)
      walk(n.b, x, y + ha, w, h - ha, leaves, divs)
    }
  }
  function leaves() { var l = []; walk(tree, 0, 0, 1, 1, l, null); return l }
  function dividers() { var l = [], d = []; walk(tree, 0, 0, 1, 1, l, d); return d }
  function node(id) { var hit = null; (function rec(n) { if (!n) return; if (n.id === id) hit = n; else if (!isLeaf(n)) { rec(n.a); rec(n.b) } })(tree); return hit }
  function parent(id) { var hit = null; (function rec(n, p) { if (!n) return; if (n.id === id) hit = p; else if (!isLeaf(n)) { rec(n.a, n); rec(n.b, n) } })(tree, null); return hit }
  function rect(id) {
    var out = null
    ;(function rec(n, x, y, w, h) {
      if (!n) return
      if (n.id === id) { out = { x: x, y: y, w: w, h: h }; return }
      if (isLeaf(n)) return
      if (n.split === "v") { var wa = w * n.ratio; rec(n.a, x, y, wa, h); rec(n.b, x + wa, y, w - wa, h) }
      else { var ha = h * n.ratio; rec(n.a, x, y, w, ha); rec(n.b, x, y + ha, w, h - ha) }
    })(tree, 0, 0, 1, 1)
    return out
  }
  // Constraint-aware helpers: fraction → real tile pixels, min-size clamping, per-tile resize.
  function pxW(fw) { return Math.max(1, Math.round(fw * cW - cGi)) }
  function pxH(fh) { return Math.max(1, Math.round(fh * cH - cGi)) }
  function clampR(vertical, boxExtentFrac, r) {
    var extentPx = boxExtentFrac * (vertical ? cW : cH)
    var minR = (minTile + cGi) / extentPx
    if (!(minR < 0.5)) minR = 0.5
    return Math.max(minR, Math.min(1 - minR, r))
  }
  function pathTo(id) {
    var out = null
    ;(function rec(n, acc) {
      if (!n || out) return
      if (n.id === id) { out = acc; return }
      if (isLeaf(n)) return
      rec(n.a, acc.concat([{ node: n, side: "a" }]))
      rec(n.b, acc.concat([{ node: n, side: "b" }]))
    })(tree, [])
    return out || []
  }
  function canResize(axis) {
    var want = axis === "w" ? "v" : "h", path = pathTo(sel)
    for (var i = 0; i < path.length; i++) if (path[i].node.split === want) return true
    return false
  }
  function resizeSel(axis, deltaPx) {
    if (!sel || !tree) return
    var want = axis === "w" ? "v" : "h", path = pathTo(sel), anc = null
    for (var i = path.length - 1; i >= 0; i--) if (path[i].node.split === want) { anc = path[i]; break }
    if (!anc) return
    var box = rect(anc.node.id); if (!box) return
    var extentFrac = want === "v" ? box.w : box.h
    var dR = deltaPx / (extentFrac * (want === "v" ? cW : cH))
    anc.node.ratio = clampR(want === "v", extentFrac, anc.node.ratio + (anc.side === "a" ? dR : -dR))
    touch()
  }
  function selRect() { return sel ? rect(sel) : null }
  function firstLeaf(n) { return isLeaf(n) ? n.id : firstLeaf(n.a) }
  function setTree(t) { tree = t; sel = firstLeaf(t); touch() }

  function split(dir) {
    var n = node(sel)
    if (!isLeaf(n)) return
    var kept = { id: nid(), app: n.app }
    n.split = dir; n.ratio = 0.5; n.a = kept; n.b = leaf()
    delete n.app
    sel = kept.id
    touch()
  }
  function remove() {
    var p = parent(sel)
    if (!p) return
    var sib = p.a.id === sel ? p.b : p.a
    for (var k in p) delete p[k]
    for (var k2 in sib) p[k2] = sib[k2]
    sel = p.id
    touch()
  }
  function guessClass(ex) { return (ex.split(" ")[0].split("/").pop() || "").toLowerCase() }
  function assign(a) {
    var n = node(sel)
    if (!isLeaf(n) || !a) return
    n.app = { label: a.name, exec: a.exec, match: a.wmclass ? "class:" + a.wmclass : "class:" + guessClass(a.exec) }
    touch()
  }
  function clear() { var n = node(sel); if (isLeaf(n)) { n.app = null; touch() } }
  function selApp() { var n = node(sel); return isLeaf(n) ? n.app : null }

  function moveSel(dir) {
    var here = rect(sel)
    if (!here) { sel = firstLeaf(tree); touch(); return }
    var cx = here.x + here.w / 2, cy = here.y + here.h / 2
    var best = "", score = 1e9, ls = leaves()
    for (var i = 0; i < ls.length; i++) {
      var L = ls[i]
      if (L.id === sel) continue
      var dx = (L.x + L.w / 2) - cx, dy = (L.y + L.h / 2) - cy
      var ok = dir === "left" ? dx < -0.01 : dir === "right" ? dx > 0.01 : dir === "up" ? dy < -0.01 : dy > 0.01
      if (!ok) continue
      var s = (dir === "left" || dir === "right") ? Math.abs(dx) + Math.abs(dy) * 3 : Math.abs(dy) + Math.abs(dx) * 3
      if (s < score) { score = s; best = L.id }
    }
    if (best) { sel = best; touch() }
  }

  function round4(v) { return Math.round(v * 10000) / 10000 }
  function tiles() {
    var out = [], ls = leaves()
    for (var i = 0; i < ls.length; i++) {
      var L = ls[i]
      if (!L.app || !L.app.exec) continue
      out.push({ exec: L.app.exec, match: L.app.match || "class:" + guessClass(L.app.exec),
                 region: [round4(L.x), round4(L.y), round4(L.w), round4(L.h)] })
    }
    return out
  }
  function save(name, apply, close) {
    if (!name || tiles().length === 0) return
    var json = JSON.stringify({ name: name, tiles: tiles(), tree: tree })
    var sh = 'printf %s "$1" | omaspaces import "$2" -'
    if (apply) sh += ' && omaspaces apply "$2"'
    Quickshell.execDetached(["bash", "-lc", sh, "save", json, name])
    if (close) Qt.quit()
  }

  // Capture the workspace you arranged by hand into a reusable preset (exact regions).
  property string status: ""
  Timer { id: statusClear; interval: 2600; onTriggered: app.status = "" }
  Timer { id: listRefresh; interval: 600; onTriggered: listProc.running = true }
  function captureCurrent(name) {
    if (!name) { nameField.forceActiveFocus(); app.status = "Name it, then Capture"; statusClear.restart(); return }
    Quickshell.execDetached(["omaspaces", "save", name])
    app.status = "Captured current windows as '" + name + "'"
    statusClear.restart(); listRefresh.restart()
  }

  property var layoutNames: []
  property bool showLoad: false
  Process {
    id: listProc
    command: ["omaspaces", "list", "--json"]
    running: true
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: { try { app.layoutNames = JSON.parse(listOut.text) } catch (e) { app.layoutNames = [] } }
  }
  Process {
    id: showProc
    stdout: StdioCollector { id: showOut; waitForEnd: true }
    onExited: { try { app.openLoaded(JSON.parse(showOut.text)) } catch (e) {} }
  }
  function reid(n) {
    if (!n) return leaf()
    if (isLeaf(n)) return { id: nid(), app: n.app ? { label: n.app.label, exec: n.app.exec, match: n.app.match } : null }
    return { id: nid(), split: n.split, ratio: n.ratio, a: reid(n.a), b: reid(n.b) }
  }
  function fromTiles(ts) {
    if (!ts || !ts.length) return template("single")
    var ns = ts.map(function (t) { return leaf({ label: t.exec.split(" ")[0], exec: t.exec, match: t.match }) })
    var acc = ns[0]
    for (var i = 1; i < ns.length; i++) acc = { id: nid(), split: "v", ratio: 1 / (i + 1), a: acc, b: ns[i] }
    return acc
  }
  function openLoaded(d) { tree = (d && d.tree) ? reid(d.tree) : fromTiles(d ? d.tiles : []); sel = firstLeaf(tree); touch() }
  function loadName(name) { showProc.command = ["omaspaces", "show", name]; showProc.running = true; showLoad = false; nameField.text = name }

  Component.onCompleted: setTree(template("main"))

  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omaspaces-builder"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5); MouseArea { anchors.fill: parent; onClicked: Qt.quit() } }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Escape) { if (app.showLoad) app.showLoad = false; else Qt.quit(); return }
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Return) { app.save(nameField.text.trim(), true, true); return }
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_S) { app.save(nameField.text.trim(), false, false); return }
        switch (e.key) {
        case Qt.Key_Left: app.moveSel("left"); break
        case Qt.Key_Right: app.moveSel("right"); break
        case Qt.Key_Up: app.moveSel("up"); break
        case Qt.Key_Down: app.moveSel("down"); break
        case Qt.Key_V: app.split("v"); break
        case Qt.Key_H: app.split("h"); break
        case Qt.Key_X: case Qt.Key_Delete: app.remove(); break
        case Qt.Key_1: app.setTree(app.template("single")); break
        case Qt.Key_2: app.setTree(app.template("cols2")); break
        case Qt.Key_3: app.setTree(app.template("cols3")); break
        case Qt.Key_4: app.setTree(app.template("main")); break
        case Qt.Key_5: app.setTree(app.template("grid")); break
        case Qt.Key_A: case Qt.Key_Slash: app.pick = 0; search.forceActiveFocus(); break
        case Qt.Key_N: nameField.forceActiveFocus(); break
        case Qt.Key_C: app.captureCurrent(nameField.text.trim()); break
        case Qt.Key_L: app.showLoad = !app.showLoad; if (app.showLoad) listProc.running = true; break
        default: return
        }
        e.accepted = true
      }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1200)
        height: Math.min(parent.height - 80, 800)
        radius: 14
        color: app.cBg
        border.color: app.cLine
        border.width: 1
        MouseArea { anchors.fill: parent; onClicked: app.showLoad = false }

        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: 58
          Text { text: "Workspace Builder"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 17; font.bold: true; anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter } }
          Text { text: "arrows select · v/h split · a app · c capture current · Ctrl+Enter apply · Esc"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 12; anchors { left: parent.left; leftMargin: 210; verticalCenter: parent.verticalCenter } }
          Rectangle {
            id: loadBtn
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            width: loadTxt.width + 24; height: 32; radius: 8
            color: loadMa.containsMouse || app.showLoad ? app.cPanel2 : app.cPanel
            border.color: app.cLine; border.width: 1
            Text { id: loadTxt; anchors.centerIn: parent; text: "Load ▾"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13 }
            MouseArea { id: loadMa; anchors.fill: parent; hoverEnabled: true; onClicked: { app.showLoad = !app.showLoad; if (app.showLoad) listProc.running = true } }
          }
        }
        Rectangle { height: 1; color: app.cLine; anchors { top: header.bottom; left: parent.left; right: parent.right } }

        Rectangle {
          id: side
          anchors { top: header.bottom; right: parent.right; bottom: parent.bottom }
          width: 330
          color: app.cPanel
          Text { id: sideTitle; text: app.sel ? "TILE" : "SELECT A TILE"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 11; font.letterSpacing: 1; anchors { top: parent.top; left: parent.left; leftMargin: 18; topMargin: 16 } }
          Rectangle {
            id: searchBox
            visible: app.sel !== ""
            anchors { top: sideTitle.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16; topMargin: 10 }
            height: 34; radius: 8; color: app.cPanel2
            border.color: search.activeFocus ? app.cAccent : app.cLine; border.width: 1
            TextInput {
              id: search
              anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
              verticalAlignment: TextInput.AlignVCenter
              color: app.cInk; font.family: app.uiFont; font.pixelSize: 13; clip: true
              onTextChanged: { app.filter = text; app.pick = 0 }
              Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Down) { app.pick = Math.min(app.pick + 1, app.matches().length - 1); e.accepted = true }
                else if (e.key === Qt.Key_Up) { app.pick = Math.max(app.pick - 1, 0); e.accepted = true }
                else if (e.key === Qt.Key_Return) { app.assign(app.matches()[app.pick]); keys.forceActiveFocus(); e.accepted = true }
                else if (e.key === Qt.Key_Escape) { keys.forceActiveFocus(); e.accepted = true }
              }
              Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: search.text === ""; text: "search apps…"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 13 }
            }
          }
          ListView {
            id: appList
            visible: app.sel !== ""
            anchors { top: searchBox.bottom; left: parent.left; right: parent.right; topMargin: 8; leftMargin: 10; rightMargin: 10 }
            height: 300
            clip: true
            currentIndex: app.pick
            model: (app.filter, app.apps, app.matches())
            delegate: Rectangle {
              width: appList.width; height: 32; radius: 6
              color: (index === app.pick && search.activeFocus) || rowMa.containsMouse ? app.cPanel2 : "transparent"
              Text { text: modelData.name; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 20; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
              MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.assign(modelData) }
            }
          }
          Column {
            visible: app.sel !== ""
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 16 }
            spacing: 8
            Text { width: parent.width; text: app.selApp() ? "In this tile: " + app.selApp().label : "No app yet"; color: app.selApp() ? app.cInk : app.cDim; font.family: app.uiFont; font.pixelSize: 12; elide: Text.ElideRight }
            Rectangle {
              visible: app.selApp() !== null
              width: parent.width; height: 30; radius: 7; color: app.cPanel2; border.color: app.cLine; border.width: 1
              Text { anchors.centerIn: parent; text: "Clear tile"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 12 }
              MouseArea { anchors.fill: parent; onClicked: app.clear() }
            }
          }
        }

        Flow {
          id: templates
          anchors { top: header.bottom; left: parent.left; right: side.left; topMargin: 14; leftMargin: 18; rightMargin: 18 }
          spacing: 8
          Repeater {
            model: [["single", "Single"], ["cols2", "2 Columns"], ["cols3", "3 Columns"], ["main", "Main + Stack"], ["grid", "Grid 2×2"]]
            delegate: Rectangle {
              height: 30; radius: 7; width: tl.width + 22
              color: tlMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1
              Text { id: tl; anchors.centerIn: parent; text: modelData[1]; color: app.cInk; font.family: app.uiFont; font.pixelSize: 12 }
              MouseArea { id: tlMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.setTree(app.template(modelData[0])) }
            }
          }
        }
        Row {
          id: tileTools
          anchors { top: templates.bottom; left: parent.left; leftMargin: 18; topMargin: 8 }
          spacing: 8
          Repeater {
            model: [["v", "Split ▏▏"], ["h", "Split ▁▔"], ["rm", "Remove"]]
            delegate: Rectangle {
              height: 28; radius: 7; width: tt.width + 20
              color: ttMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1
              opacity: app.sel ? 1 : 0.4
              Text { id: tt; anchors.centerIn: parent; text: modelData[1]; color: app.cInk; font.family: app.uiFont; font.pixelSize: 12 }
              MouseArea { id: ttMa; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[0] === "rm" ? app.remove() : app.split(modelData[0]) }
            }
          }
          Item { width: 6; height: 1 }
          Row {
            spacing: 5; visible: !!app.sel && app.cReady
            anchors.verticalCenter: parent.verticalCenter
            Text { text: "W"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 26; height: 28; radius: 7; color: wmMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1; opacity: app.canResize("w") ? 1 : 0.35
              Text { anchors.centerIn: parent; text: "−"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 15 }
              MouseArea { id: wmMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.resizeSel("w", -app.sizeStep) } }
            Text { width: 54; horizontalAlignment: Text.AlignHCenter; text: (app.rev, app.sel && app.selRect()) ? app.pxW(app.selRect().w) + "px" : "—"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 26; height: 28; radius: 7; color: wpMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1; opacity: app.canResize("w") ? 1 : 0.35
              Text { anchors.centerIn: parent; text: "+"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 14 }
              MouseArea { id: wpMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.resizeSel("w", app.sizeStep) } }
            Item { width: 8; height: 1 }
            Text { text: "H"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 26; height: 28; radius: 7; color: hmMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1; opacity: app.canResize("h") ? 1 : 0.35
              Text { anchors.centerIn: parent; text: "−"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 15 }
              MouseArea { id: hmMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.resizeSel("h", -app.sizeStep) } }
            Text { width: 54; horizontalAlignment: Text.AlignHCenter; text: (app.rev, app.sel && app.selRect()) ? app.pxH(app.selRect().h) + "px" : "—"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 26; height: 28; radius: 7; color: hpMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1; opacity: app.canResize("h") ? 1 : 0.35
              Text { anchors.centerIn: parent; text: "+"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 14 }
              MouseArea { id: hpMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.resizeSel("h", app.sizeStep) } }
          }
        }

        Rectangle {
          id: canvasWrap
          anchors { top: tileTools.bottom; left: parent.left; right: side.left; bottom: footer.top; margins: 18 }
          color: app.cPanel; radius: 10; border.color: app.cLine; border.width: 1
          Item {
            id: canvas
            anchors.centerIn: parent
            property real aspect: app.cReady ? app.cW / app.cH : 16 / 9
            width: Math.min(parent.width - 24, (parent.height - 24) * aspect)
            height: width / aspect

            Repeater {
              model: (app.rev, app.tree ? app.leaves() : [])
              delegate: Rectangle {
                property var d: modelData
                x: d.x * canvas.width + 3; y: d.y * canvas.height + 3
                width: d.w * canvas.width - 6; height: d.h * canvas.height - 6
                radius: 7
                color: d.id === app.sel ? Qt.rgba(app.cAccent.r, app.cAccent.g, app.cAccent.b, 0.16) : app.cPanel2
                border.color: d.id === app.sel ? app.cAccent : app.cLine
                border.width: d.id === app.sel ? 2 : 1
                Column {
                  anchors.centerIn: parent; spacing: 4
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: d.app ? d.app.label : "empty"; color: d.app ? app.cInk : app.cDim; font.family: app.uiFont; font.pixelSize: 13; font.bold: !!d.app; font.italic: !d.app }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: (app.rev, app.cReady) ? app.pxW(d.w) + " × " + app.pxH(d.h) + " px" : Math.round(d.w * 100) + "% × " + Math.round(d.h * 100) + "%"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 11 }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(d.w * 100) + "% × " + Math.round(d.h * 100) + "%"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 10 }
                }
                MouseArea { anchors.fill: parent; onClicked: { app.sel = d.id; app.touch() } }
              }
            }
            Repeater {
              model: (app.rev, app.tree ? app.dividers() : [])
              delegate: Item {
                property var dv: modelData
                x: dv.vertical ? dv.px * canvas.width - 7 : dv.px * canvas.width
                y: dv.vertical ? dv.py * canvas.height : dv.py * canvas.height - 7
                width: dv.vertical ? 14 : dv.len * canvas.width
                height: dv.vertical ? dv.len * canvas.height : 14
                Rectangle { anchors.centerIn: parent; width: dv.vertical ? 3 : parent.width * 0.85; height: dv.vertical ? parent.height * 0.85 : 3; radius: 2; color: dMa.containsMouse || dMa.pressed ? app.cAccent : app.cLine }
                MouseArea {
                  id: dMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: dv.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
                  onPositionChanged: function (m) {
                    if (!pressed) return
                    var p = mapToItem(canvas, m.x, m.y)
                    var box = app.rect(dv.node.id)
                    if (!box) return
                    var r = dv.vertical ? (p.x / canvas.width - box.x) / box.w : (p.y / canvas.height - box.y) / box.h
                    dv.node.ratio = app.clampR(dv.vertical, dv.vertical ? box.w : box.h, r)
                    app.touch()
                  }
                }
              }
            }
          }
        }

        Rectangle {
          id: footer
          anchors { left: parent.left; right: side.left; bottom: parent.bottom }
          height: 62; color: "transparent"
          Rectangle { height: 1; color: app.cLine; anchors { top: parent.top; left: parent.left; right: parent.right } }
          Rectangle {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            width: 230; height: 34; radius: 8; color: app.cPanel2
            border.color: nameField.activeFocus ? app.cAccent : app.cLine; border.width: 1
            TextInput {
              id: nameField
              anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
              verticalAlignment: TextInput.AlignVCenter
              color: app.cInk; font.family: app.uiFont; font.pixelSize: 13; clip: true
              Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Return) { app.save(text.trim(), true, true); e.accepted = true }
                else if (e.key === Qt.Key_Escape) { keys.forceActiveFocus(); e.accepted = true }
              }
              Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: nameField.text === ""; text: "workspace name"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 13 }
            }
          }
          Text {
            anchors { left: parent.left; leftMargin: 258; verticalCenter: parent.verticalCenter }
            width: 320; elide: Text.ElideRight
            text: app.status; color: app.cAccent; font.family: app.uiFont; font.pixelSize: 12; visible: app.status !== ""
          }
          Row {
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle {
              width: capTxt.width + 24; height: 34; radius: 8; color: capMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1
              Text { id: capTxt; anchors.centerIn: parent; text: "Capture current"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13 }
              MouseArea { id: capMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.captureCurrent(nameField.text.trim()) }
            }
            Rectangle {
              width: saveTxt.width + 24; height: 34; radius: 8; color: saveMa.containsMouse ? app.cPanel2 : app.cPanel; border.color: app.cLine; border.width: 1
              Text { id: saveTxt; anchors.centerIn: parent; text: "Save"; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13 }
              MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.save(nameField.text.trim(), false, false) }
            }
            Rectangle {
              width: applyTxt.width + 24; height: 34; radius: 8; color: app.cAccent
              Text { id: applyTxt; anchors.centerIn: parent; text: "Save & Apply"; color: "#0b0b0b"; font.family: app.uiFont; font.pixelSize: 13; font.bold: true }
              MouseArea { anchors.fill: parent; onClicked: app.save(nameField.text.trim(), true, true) }
            }
          }
        }

        Rectangle {
          visible: app.showLoad
          z: 100
          anchors { top: header.bottom; right: parent.right; topMargin: 4; rightMargin: 20 }
          width: 240; height: Math.min(340, 16 + Math.max(1, app.layoutNames.length) * 34)
          color: app.cPanel; border.color: app.cLine; border.width: 1; radius: 10
          ListView {
            anchors.fill: parent; anchors.margins: 6; clip: true
            model: app.layoutNames
            delegate: Rectangle {
              width: ListView.view.width; height: 32; radius: 6; color: liMa.containsMouse ? app.cPanel2 : "transparent"
              Text { text: modelData; color: app.cInk; font.family: app.uiFont; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 20; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
              MouseArea { id: liMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.loadName(modelData) }
            }
          }
          Text { visible: app.layoutNames.length === 0; anchors.centerIn: parent; text: "no saved layouts"; color: app.cDim; font.family: app.uiFont; font.pixelSize: 12 }
        }
      }
    }
  }
}
