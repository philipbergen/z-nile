import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// Loads the znile board through fetch.sh and keeps it fresh: on a timer, and
// whenever the main checkout's `main` or a fetch moves. Holds the session's
// dragged order and runs the two actions (reprioritize, dive in).
Item {
  id: root

  property var shell: null

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME")

  // ---- settings (settings.json beside this file, hot-reloaded)
  property var settings: ({})
  readonly property string repoPath: {
    var p = String(settings.repoPath || "~/code/pickman")
    return p.indexOf("~/") === 0 ? home + p.slice(1) : p
  }
  readonly property int refreshIntervalSec: Math.max(15, Number(settings.refreshIntervalSec) || 120)
  readonly property string rankCommand: String(settings.rankCommand || "")

  // ---- state
  property var model: Model.normalize({})
  property bool loading: false
  property string error: ""
  property bool _again: false
  // stage key -> ids, the order dragged this session
  property var orders: ({})
  property string notice: ""
  property int noticeSerial: 0

  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < model.issues.length; i++) if (model.issues[i].stage === "active") n++
    return n
  }
  readonly property int openCount: {
    var n = 0
    for (var i = 0; i < model.issues.length; i++) if (model.issues[i].stage !== "done") n++
    return n
  }

  // ---- theme palette: the theme's named colours, for type and stage hues
  property var palette: ({})
  function hue(name, fallback) {
    var v = palette[name]
    return v ? v : fallback
  }

  function refresh() {
    if (fetchProcess.running) { _again = true; return }
    loading = true
    fetchProcess.command = [pluginDir + "/fetch.sh", repoPath]
    fetchProcess.running = true
    if (!agentsProcess.running) agentsProcess.running = true
    if (!prsProcess.running) { prsProcess.command = [pluginDir + "/prs.sh", repoPath]; prsProcess.running = true }
  }

  function say(text) {
    notice = String(text)
    noticeSerial++
  }

  function orderFor(key) { return orders[key] || [] }

  // `ids` is the column as shown; `id` dropped before `beforeId` ("" = end).
  function reprioritize(key, ids, id, beforeId) {
    var next = ({})
    for (var k in orders) next[k] = orders[k]
    next[key] = Model.reorder(ids, id, beforeId)
    orders = next
    var argv = Model.rankArgv(rankCommand, id, beforeId)
    if (argv.length === 0) {
      say(id + " moved for this session only: znile has no priority yet")
      return
    }
    if (rankProcess.running) { say("still saving the last move; try again"); return }
    rankProcess.command = argv
    rankProcess.running = true
  }

  // ---- AI CLIs: the installed ones, and the one dive-ins open in
  property var agents: []
  property string omarchyAgent: ""
  property string chosenAgent: ""
  readonly property string agent: Model.pickAgent(agents, chosenAgent, omarchyAgent)
  readonly property string agentName: {
    var a = Model.agentById(agent)
    return a ? a.name : ""
  }

  function chooseAgent(id) {
    if (!Model.agentById(id)) return
    chosenAgent = id
    agentChoiceFile.setText(id + "\n")
  }

  // Opens a new terminal (Hyprland tiles it beside the board) with the agent
  // running interactively in the repo, seeded with the dive-in prompt.
  function dive(item, agentId) {
    if (!item) return
    launch(agentId || agent, Model.divePrompt(item), "opening " + item.id)
  }

  // A new terminal with the AI capturing a new ticket in `project`.
  function newTicket(project, agentId, about) {
    launch(agentId || agent, Model.ticketPrompt(project, about), "new " + project + " ticket")
  }

  function launch(id, prompt, what) {
    var a = Model.agentById(id)
    if (!a) { say("no AI CLI installed: set one up with omarchy agent"); return }
    // Each value is its own argv element; nothing is parsed by a shell.
    Quickshell.execDetached(Model.diveArgv(id, repoPath, prompt))
    if (a.clipboard) {
      Quickshell.execDetached(["wl-copy", "--", prompt])
      say(a.name + " can't take a starting prompt: it's on the clipboard, paste it in")
    } else {
      say(what + " in " + a.name)
    }
  }

  // Open pull requests, from gh; none when gh can't answer.
  property var prs: []
  Process {
    id: prsProcess
    stdout: StdioCollector { id: prsOut; waitForEnd: true }
    onExited: {
      try { root.prs = JSON.parse(prsOut.text) || [] } catch (e) { root.prs = [] }
      root.model = Object.assign({}, Model.attachPrs(root.model, root.prs))
    }
  }

  Process {
    id: agentsProcess
    command: [root.pluginDir + "/agents.sh"]
    running: true
    stdout: StdioCollector { id: agentsOut; waitForEnd: true }
    onExited: {
      var text = String(agentsOut.text || "")
      var m = /^default (\S+)$/m.exec(text)
      root.omarchyAgent = m ? m[1] : ""
      root.agents = Model.installedAgents(text.replace(/^default .*$/m, ""))
    }
  }

  // The last agent chosen, kept across restarts (outside the plugin folder,
  // whose changes reload the plugin).
  FileView {
    id: agentChoiceFile
    path: root.home + "/.local/state/znile-board/agent"
    printErrors: false
    onLoaded: root.chosenAgent = String(text()).trim()
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) {
        try {
          root.model = Model.attachPrs(Model.normalize(JSON.parse(fetchOut.text)), root.prs)
          root.error = ""
        } catch (e) {
          root.error = "could not read the board: " + e
        }
      } else {
        var lines = String(fetchErr.text || "").trim().split("\n")
        root.error = (lines[lines.length - 1] || ("fetch.sh exited " + exitCode)).slice(0, 300)
      }
      if (root._again) { root._again = false; root.refresh() }
    }
  }

  Process {
    id: rankProcess
    workingDirectory: root.repoPath
    stderr: StdioCollector { id: rankErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) { root.say("priority saved"); root.refresh() }
      else root.say("priority not saved: " + String(rankErr.text || "").trim().split("\n").pop().slice(0, 200))
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // A sync, land or fetch moves one of these; wait for git to settle.
  Timer { id: settle; interval: 1500; onTriggered: root.refresh() }
  FileView {
    path: root.repoPath + "/.git/refs/heads/main"
    watchChanges: true
    printErrors: false
    onFileChanged: settle.restart()
  }
  FileView {
    path: root.repoPath + "/.git/FETCH_HEAD"
    watchChanges: true
    printErrors: false
    onFileChanged: settle.restart()
  }

  FileView {
    id: settingsFile
    path: root.pluginDir + "/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.settings = JSON.parse(text()) || {} } catch (e) { root.settings = {} }
      root.refresh()
    }
    onLoadFailed: { root.settings = {}; root.refresh() }
  }

  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = /^\s*([a-z_0-9]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/.exec(lines[i])
        if (m) out[m[1]] = m[2]
      }
      root.palette = out
    }
  }
}
