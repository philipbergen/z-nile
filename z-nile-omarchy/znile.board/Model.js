.pragma library

// Pure helpers for the znile board. Everything here takes plain data and
// returns plain data, so tests/model.test.mjs can run it under node.

var STAGES = ["new", "preparing", "prepared", "active", "done"]
var TYPES = ["feature", "defect", "chore"]
var ID_RE = /^[fdcR][0-9]{4}$/

var MAX_TITLE = 200
var MAX_BODY = 6000

function clip(value, max) {
  var s = value === undefined || value === null ? "" : String(value)
  return s.length > max ? s.slice(0, max - 1) + "…" : s
}

function idList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var id = String(value[i])
    if (ID_RE.test(id)) out.push(id)
  }
  return out
}

function idNumber(id) {
  var n = parseInt(String(id).slice(1), 10)
  return isFinite(n) ? n : 1e9
}

function stageIndex(stage) {
  var i = STAGES.indexOf(String(stage))
  return i < 0 ? 0 : i
}

function cleanItem(raw, kind, project) {
  if (!raw || !ID_RE.test(String(raw.id))) return null
  var stage = STAGES.indexOf(String(raw.stage)) >= 0 ? String(raw.stage) : "new"
  var label = String(raw.label || raw.type || "")
  return {
    id: String(raw.id),
    kind: kind,
    num: idNumber(raw.id),
    project: project || "",
    type: TYPES.indexOf(String(raw.type)) >= 0 ? String(raw.type) : "",
    label: label === "mix" || TYPES.indexOf(label) >= 0 ? label : "",
    title: clip(raw.title, MAX_TITLE),
    stage: stage,
    stageIndex: stageIndex(stage),
    status: clip(raw.status, 40),
    design: clip(raw.design, 40),
    raft: raw.raft && ID_RE.test(String(raw.raft)) ? String(raw.raft) : "",
    issues: idList(raw.issues),
    dependsOn: idList(raw.dependsOn),
    dependents: idList(raw.dependents),
    blockedBy: idList(raw.blockedBy),
    after: [],
    blockedMembers: [],
    path: "",
    url: "",
    prs: [],
    emergent: raw.emergent === true,
    command: raw.command ? clip(raw.command, 80) : "",
    body: clip(raw.body, MAX_BODY)
  }
}

// Turns `./zn board` JSON (plus fetch.sh's `projects` map and `repo`) into the
// model the window draws. Issues get their own blockedBy: the engine only
// computes it for rafts.
function normalize(raw) {
  raw = raw || {}
  var projectOf = raw.projects && typeof raw.projects === "object" ? raw.projects : {}
  var issues = [], rafts = [], byId = {}
  var src = Array.isArray(raw.issues) ? raw.issues : []
  for (var i = 0; i < src.length; i++) {
    var it = cleanItem(src[i], "issue", projectOf[src[i] && src[i].id])
    if (it) { issues.push(it); byId[it.id] = it }
  }
  src = Array.isArray(raw.rafts) ? raw.rafts : []
  for (var j = 0; j < src.length; j++) {
    var r = cleanItem(src[j], "raft", projectOf[src[j] && src[j].id])
    if (r) { rafts.push(r); byId[r.id] = r }
  }
  // znile blocks whole rafts: a raft can't start while any ticket in it
  // depends on unfinished work outside it. A dependency between two tickets
  // of the same raft only orders them. So a ticket is `blockedBy` its
  // unfinished dependencies outside its raft, and `after` the ones inside.
  var membersOf = {}
  for (var q = 0; q < rafts.length; q++) membersOf[rafts[q].id] = rafts[q].issues
  for (var k = 0; k < issues.length; k++) {
    var issue = issues[k]
    var siblings = issue.raft && membersOf[issue.raft] ? membersOf[issue.raft] : []
    var open = issue.dependsOn.filter(function(dep) {
      return byId[dep] !== undefined && byId[dep].stage !== "done"
    })
    issue.blockedBy = open.filter(function(dep) { return siblings.indexOf(dep) < 0 })
    issue.after = open.filter(function(dep) { return siblings.indexOf(dep) >= 0 })
  }
  // Which of a raft's tickets block it, and on what.
  for (var b = 0; b < rafts.length; b++) {
    rafts[b].blockedMembers = []
    for (var c = 0; c < rafts[b].issues.length; c++) {
      var mem = byId[rafts[b].issues[c]]
      if (mem && mem.kind === "issue" && mem.blockedBy.length > 0)
        rafts[b].blockedMembers.push({ id: mem.id, by: mem.blockedBy })
    }
  }
  var paths = raw.paths && typeof raw.paths === "object" ? raw.paths : {}
  var webBase = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/blob\/main\/$/.test(String(raw.webBase || "")) ? String(raw.webBase) : ""
  var everything = issues.concat(rafts)
  for (var w = 0; w < everything.length; w++) {
    var x = everything[w]
    var path = String(paths[x.id] || "")
    x.path = /^[\w.\/-]+\.md$/.test(path) && path.indexOf("..") < 0 ? path : ""
    x.url = webBase && x.path ? webBase + x.path : ""
  }
  // A raft takes its members' project when the map has none for it.
  for (var m = 0; m < rafts.length; m++) {
    if (rafts[m].project !== "") continue
    for (var n = 0; n < rafts[m].issues.length; n++) {
      var member = byId[rafts[m].issues[n]]
      if (member && member.project) { rafts[m].project = member.project; break }
    }
  }
  var projects = []
  var all = issues.concat(rafts)
  for (var p = 0; p < all.length; p++)
    if (all[p].project && projects.indexOf(all[p].project) < 0) projects.push(all[p].project)
  if (Array.isArray(raw.projectOrder)) {
    projects.sort(function(a, b) {
      var ia = raw.projectOrder.indexOf(a), ib = raw.projectOrder.indexOf(b)
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
    })
  }
  return {
    issues: issues,
    rafts: rafts,
    byId: byId,
    projects: projects,
    stats: raw.stats || null,
    repo: String(raw.repo || ""),
    fetchedAt: String(raw.fetchedAt || "")
  }
}

// Priority until znile has its own: the lower ticket number first. `order` is
// the session's dragged order (a whole column's ids); ids in it keep that
// order, and ids it doesn't know follow them by number.
function sortByPriority(items, order) {
  var rank = {}
  if (Array.isArray(order)) for (var i = 0; i < order.length; i++) rank[order[i]] = i
  return items.slice().sort(function(a, b) {
    var ra = rank[a.id], rb = rank[b.id]
    if (ra !== undefined && rb !== undefined) return ra - rb
    if (ra !== undefined) return -1
    if (rb !== undefined) return 1
    return a.num - b.num || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
  })
}

// Moves `id` to sit just before `beforeId` in the visible `ids` list and
// returns the new list. A missing `beforeId` (or "") moves it to the end.
function reorder(ids, id, beforeId) {
  if (!Array.isArray(ids) || ids.indexOf(id) < 0 || id === beforeId) return ids ? ids.slice() : []
  var out = ids.filter(function(x) { return x !== id })
  var at = beforeId ? out.indexOf(beforeId) : -1
  if (at < 0) out.push(id)
  else out.splice(at, 0, id)
  return out
}

function matches(item, filters) {
  filters = filters || {}
  if (filters.projects && filters.projects.length > 0 && filters.projects.indexOf(item.project) < 0) return false
  if (filters.blocked && item.blockedBy.length === 0 && item.blockedMembers.length === 0) return false
  if (filters.types && filters.types.length > 0) {
    var t = item.type || item.label
    if (filters.types.indexOf(t) < 0 && !(t === "mix" && filters.types.length > 0)) return false
  }
  var q = String(filters.query || "").toLowerCase().trim()
  if (q !== "") {
    var hay = (item.id + " " + item.title + " " + item.raft + " " + item.project).toLowerCase()
    var words = q.split(/\s+/)
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
  }
  return true
}

// One column per stage, each sorted by priority. `orders` maps a stage to
// its dragged order (an array applies to every stage).
function columns(items, filters, orders, showDone) {
  var cols = []
  for (var s = 0; s < STAGES.length; s++) {
    if (STAGES[s] === "done" && !showDone) continue
    var stage = STAGES[s]
    var inStage = items.filter(function(it) { return it.stage === stage && matches(it, filters) })
    var order = Array.isArray(orders) ? orders : (orders && orders[stage]) || []
    var sorted = sortByPriority(inStage, order)
    if (stage === "done") sorted.reverse() // newest finished work first
    cols.push({ stage: stage, items: sorted })
  }
  return cols
}

function stageCounts(items, filters) {
  var counts = { new: 0, preparing: 0, prepared: 0, active: 0, done: 0, total: 0 }
  for (var i = 0; i < items.length; i++) {
    if (!matches(items[i], filters)) continue
    counts[items[i].stage] += 1
    counts.total += 1
  }
  return counts
}

function projectCounts(items) {
  var out = {}
  for (var i = 0; i < items.length; i++) {
    if (items[i].stage === "done") continue
    var p = items[i].project || "?"
    out[p] = (out[p] || 0) + 1
  }
  return out
}

// Daily opened/closed for the sparkline, oldest first.
function activity(stats) {
  var days = stats && stats.views && Array.isArray(stats.views.month) ? stats.views.month : []
  var out = []
  for (var i = 0; i < days.length; i++) {
    var d = days[i] || {}
    out.push({
      label: clip(d.bucket && d.bucket.label, 20),
      opened: Number(d.opened && d.opened.all) || 0,
      closed: Number(d.closed && d.closed.all) || 0
    })
  }
  return out
}

function weekSummary(stats) {
  var w = stats && stats.periods && stats.periods.week ? stats.periods.week : null
  if (!w) return null
  return {
    opened: Number(w.opened && w.opened.all) || 0,
    closed: Number(w.closed && w.closed.all) || 0,
    hours: Math.round((Number(w.minutes && w.minutes.all) || 0) / 60)
  }
}

// The body without its `# id: title` heading, trimmed to a few lines.
function preview(body, maxLines) {
  var lines = String(body || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length && out.length < (maxLines || 8); i++) {
    var line = lines[i]
    if (i === 0 && /^#\s/.test(line)) continue
    if (out.length === 0 && line.trim() === "") continue
    out.push(line)
  }
  return out.join("\n").trim()
}

function divePrompt(item) {
  var what = item.kind === "raft" ? "raft" : "ticket"
  return "Walk me through znile " + what + " " + item.id + " (" + item.title + "): "
    + "where it is in the pipeline, its design, what blocks it, its raft, dependencies and spend. "
    + "Discussion only: don't change anything."
}

// `{id}` and `{beforeId}` in the user's rank command become separate argv
// elements' text; nothing goes through a shell.
function rankArgv(template, id, beforeId) {
  var parts = String(template || "").trim().split(/\s+/).filter(function(p) { return p !== "" })
  if (parts.length === 0) return []
  return parts.map(function(p) {
    return p.split("{id}").join(id).split("{beforeId}").join(beforeId || "")
  })
}

// Markdown for the detail pane, made safe for Text.MarkdownText: Qt's
// importer passes raw HTML through and loads images, so outside code every
// `<` becomes `&lt;` (shown as `<`, never parsed as a tag) and every image
// `![` becomes a plain link `\![`. Code fences and code spans stay verbatim:
// markdown never reads HTML there.
function safeMarkdown(body, style) {
  var lines = preview(body, 100000).split("\n")
  var out = [], fence = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var m = /^\s{0,3}(`{3,}|~{3,})/.exec(line)
    if (fence !== "") {
      out.push(line)
      if (m && m[1].charAt(0) === fence.charAt(0) && m[1].length >= fence.length) fence = ""
      continue
    }
    if (m) { fence = m[1]; out.push(line); continue }
    out.push(safeInline(line, style))
  }
  return out.join("\n")
}

var HEX = /^#[0-9a-fA-F]{6}$/

// Outside code: `<` -> `&lt;`, `![` -> `\![`. A code span stays as markdown
// code, or, given `style` ({ color, background } as #rrggbb), becomes a
// tinted monospace span the board generates itself; its text is escaped for
// both HTML and markdown, so nothing from the ticket turns into markup.
function safeInline(line, style) {
  var styled = style && HEX.test(style.color) && HEX.test(style.background)
  var parts = String(line).split(/(`+[^`]*?`+)/)
  for (var i = 0; i < parts.length; i++) {
    var code = /^(`+)([^`]*?)(`+)$/.exec(parts[i])
    if (code && code[1].length === code[3].length) {
      if (styled) parts[i] = codeSpan(code[2], style)
      continue
    }
    parts[i] = parts[i].replace(/</g, "&lt;").replace(/!\[/g, "\\![")
  }
  return parts.join("")
}

function codeSpan(text, style) {
  var t = String(text)
  if (/^ .* $/.test(t) && t.trim() !== "") t = t.slice(1, -1)
  t = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/([\\`*_\[\]{}()#+\-.!|~])/g, "\\$1")
    .replace(/ /g, "&nbsp;")
  return "<span style=\"color:" + style.color + ";background-color:" + style.background
    + ";font-family:monospace;font-weight:600\">&nbsp;" + t + "&nbsp;</span>"
}

// AI CLIs the board can open a ticket in. `argv` seeds an interactive session
// with the prompt; agents with no way to do that open plain and the prompt
// goes to the clipboard. The dive-in is a discussion, so every agent starts
// in its normal ask-before-acting mode (no yolo / bypass flags).
var AGENTS = [
  { id: "claude", name: "Claude", argv: function(p) { return ["claude", "--", p] } },
  { id: "codex", name: "Codex", argv: function(p) { return ["codex", "--", p] } },
  { id: "grok", name: "Grok", argv: function(p) { return ["grok", "--", p] } },
  { id: "kimi", name: "Kimi", argv: function(p) { return ["kimi"] }, clipboard: true },
  { id: "opencode", name: "OpenCode", argv: function(p) { return ["opencode", "--prompt", p] } },
  { id: "copilot", name: "Copilot", argv: function(p) { return ["copilot", "--interactive", p] } },
  { id: "agy", name: "Antigravity", argv: function(p) { return ["agy", "--prompt-interactive", p] } },
  { id: "cursor-agent", name: "Cursor", argv: function(p) { return ["cursor-agent", "agent", "--", p] } },
  { id: "qwen", name: "Qwen", argv: function(p) { return ["qwen", "--prompt-interactive=" + p] } },
  { id: "pi", name: "Pi", argv: function(p) { return ["pi", p] } },
  { id: "crush", name: "Crush", argv: function(p) { return ["crush"] }, clipboard: true }
]

function agentById(id) {
  for (var i = 0; i < AGENTS.length; i++) if (AGENTS[i].id === id) return AGENTS[i]
  return null
}

// The installed agents, in AGENTS order, from the ids agents.sh printed.
function installedAgents(text) {
  var ids = String(text || "").split(/\s+/)
  return AGENTS.filter(function(a) { return ids.indexOf(a.id) >= 0 })
}

// The agent to use: the chosen one if installed, else Omarchy's default if
// installed, else the first installed.
function pickAgent(installed, chosen, omarchyDefault) {
  var ids = installed.map(function(a) { return a.id })
  if (ids.indexOf(chosen) >= 0) return chosen
  if (ids.indexOf(omarchyDefault) >= 0) return omarchyDefault
  return ids.length > 0 ? ids[0] : ""
}

// The terminal command for a dive-in: one argv, nothing parsed by a shell.
function diveArgv(agentId, repo, prompt) {
  var agent = agentById(agentId)
  if (!agent) return []
  return ["uwsm-app", "--", "xdg-terminal-exec", "--app-id=org.omarchy.agent", "--dir=" + repo, "-e"]
    .concat(agent.argv(prompt))
}

// Open pull requests per ticket and raft. A PR belongs to every id in its
// branch name and title ("R0081-reuse…", "tracker: prep c0132 …",
// "R0052: Models and dispatcher (c0117)"), but not to one after "stacked on".
// A ticket also shows its raft's PRs.
var PR_URL = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/[0-9]+$/

function prIds(pr) {
  var text = String(pr.headRefName || "") + " " + String(pr.title || "").replace(/stacked on.*$/i, "")
  var out = [], re = /(?:^|[^A-Za-z0-9])([fdcR][0-9]{4})(?![0-9])/g, m
  while ((m = re.exec(text)) !== null) if (out.indexOf(m[1]) < 0) out.push(m[1])
  return out
}

function attachPrs(model, prs) {
  var own = {}
  var list = Array.isArray(prs) ? prs : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i] || {}
    if (!PR_URL.test(String(p.url)) || !(Number(p.number) > 0)) continue
    var pr = { number: Number(p.number), url: String(p.url), draft: p.isDraft === true,
      title: clip(p.title, 160), branch: clip(p.headRefName, 120) }
    var ids = prIds(p)
    for (var j = 0; j < ids.length; j++) (own[ids[j]] = own[ids[j]] || []).push(pr)
  }
  var all = model.issues.concat(model.rafts)
  for (var k = 0; k < all.length; k++) {
    var it = all[k], seen = {}, out = []
    var mine = (own[it.id] || []).concat(it.raft ? (own[it.raft] || []) : [])
    for (var n = 0; n < mine.length; n++) {
      if (seen[mine[n].number]) continue
      seen[mine[n].number] = true
      out.push(mine[n])
    }
    it.prs = out.sort(function(a, b) { return a.number - b.number })
  }
  return model
}

// The prompt that starts an AI CLI on capturing a new ticket. It names the
// project and the repo's own capture skill, so any agent follows the same
// rules; the user's words, when given, are the ticket's starting point.
function ticketPrompt(project, about) {
  var p = /^[a-z0-9][a-z0-9-]{0,40}$/.test(String(project)) ? String(project) : ""
  var text = clip(String(about || "").trim(), 2000)
  var head = "Capture a new z-nile ticket" + (p ? " in project " + p + " (--project " + p + ")" : "")
    + ", following z-nile/skills/z-ticket/SKILL.md step by step (it starts in a capture worktree)."
  return text !== ""
    ? head + " It is about: " + text
    : head + " First ask me what the ticket is about."
}
