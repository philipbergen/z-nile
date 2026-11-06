// Runs Model.js (a QML `.pragma library` script) under node.
//   node --test ~/.config/omarchy/plugins/znile.board/tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const names = [...source.matchAll(/^function (\w+)/gm)].map(m => m[1])
const M = new Function(`${source}\nreturn { STAGES, ${names.join(", ")} }`)()

const raw = {
  repo: "/r",
  projects: { f0002: "pickman", c0001: "z-nile", d0003: "pickman", R0001: "z-nile" },
  projectOrder: ["pickman", "z-nile"],
  issues: [
    { id: "f0002", type: "feature", title: "Two", stage: "new", dependsOn: ["c0001"], body: "# f0002: Two\n\n## Problem\nline" },
    { id: "c0001", type: "chore", title: "One", stage: "active", raft: "R0001" },
    { id: "d0003", type: "defect", title: "<img src=\"https://x.invalid/t\">", stage: "new" },
    { id: "bogus", type: "feature", title: "dropped", stage: "new" },
  ],
  rafts: [{ id: "R0001", type: "chore", label: "chore", title: "Raft", stage: "active", issues: ["c0001"] }],
}

test("normalize drops bad ids and computes issue blockers", () => {
  const m = M.normalize(raw)
  assert.deepEqual(m.issues.map(i => i.id), ["f0002", "c0001", "d0003"])
  assert.deepEqual(m.byId.f0002.blockedBy, ["c0001"])
  assert.deepEqual(m.projects, ["pickman", "z-nile"])
  assert.equal(m.byId.R0001.project, "z-nile")
})

test("titles keep markup-shaped text verbatim (rendered as PlainText)", () => {
  const m = M.normalize(raw)
  assert.equal(m.byId.d0003.title, "<img src=\"https://x.invalid/t\">")
})

test("columns sort by lower number first and honor a dragged order", () => {
  const m = M.normalize(raw)
  let cols = M.columns(m.issues, {}, [], false)
  assert.deepEqual(cols.map(c => c.stage), ["new", "preparing", "prepared", "active"])
  assert.deepEqual(cols[0].items.map(i => i.id), ["f0002", "d0003"])
  const order = M.reorder(["f0002", "d0003"], "d0003", "f0002")
  assert.deepEqual(order, ["d0003", "f0002"])
  cols = M.columns(m.issues, {}, order, false)
  assert.deepEqual(cols[0].items.map(i => i.id), ["d0003", "f0002"])
})

test("reorder to the end and no-ops", () => {
  assert.deepEqual(M.reorder(["a", "b", "c"], "a", ""), ["b", "c", "a"])
  assert.deepEqual(M.reorder(["a", "b"], "a", "a"), ["a", "b"])
  assert.deepEqual(M.reorder(["a", "b"], "z", "a"), ["a", "b"])
})

test("filters by project, type and words", () => {
  const m = M.normalize(raw)
  assert.equal(M.stageCounts(m.issues, { projects: ["pickman"] }).total, 2)
  assert.equal(M.stageCounts(m.issues, { types: ["chore"] }).total, 1)
  assert.equal(M.stageCounts(m.issues, { query: "two" }).total, 1)
})

test("preview drops the heading; prompt and rank argv stay single elements", () => {
  const m = M.normalize(raw)
  assert.equal(M.preview(m.byId.f0002.body, 4), "## Problem\nline")
  assert.match(M.divePrompt(m.byId.f0002), /^Walk me through znile ticket f0002 \(Two\)/)
  assert.deepEqual(M.rankArgv("./zn rank {id} --before {beforeId}", "f0002", "c0001; rm -rf /"),
    ["./zn", "rank", "f0002", "--before", "c0001; rm -rf /"])
  assert.deepEqual(M.rankArgv("", "a", "b"), [])
})

test("safeMarkdown neutralizes HTML and images outside code only", () => {
  const md = M.safeMarkdown([
    "# f0001: T",
    "Text <img src=\"https://x.invalid/a\"> and ![pic](https://x.invalid/b) and `<b>code</b>`",
    "```",
    "<script>kept()</script>",
    "```",
    "after <b>",
  ].join("\n"))
  assert.equal(md, [
    "Text &lt;img src=\"https://x.invalid/a\"> and \\![pic](https://x.invalid/b) and `<b>code</b>`",
    "```",
    "<script>kept()</script>",
    "```",
    "after &lt;b>",
  ].join("\n"))
})

test("safeMarkdown: an unclosed fence keeps the rest as code", () => {
  assert.equal(M.safeMarkdown("a <i>\n~~~\n<i>"), "a &lt;i>\n~~~\n<i>")
})

test("agents: installed filter, pick order, dive argv", () => {
  const installed = M.installedAgents("claude\ngrok\nkimi\n")
  assert.deepEqual(installed.map(a => a.id), ["claude", "grok", "kimi"])
  assert.equal(M.pickAgent(installed, "grok", "kimi"), "grok")
  assert.equal(M.pickAgent(installed, "codex", "kimi"), "kimi")
  assert.equal(M.pickAgent(installed, "", "codex"), "claude")
  assert.equal(M.pickAgent([], "", "kimi"), "")
  const argv = M.diveArgv("claude", "/repo", "a \"b\"; c")
  assert.deepEqual(argv.slice(-4), ["-e", "claude", "--", "a \"b\"; c"])
  assert.ok(argv.includes("--dir=/repo"))
  assert.ok(!argv.some(x => /yolo|bypass|skip-permissions|auto/.test(x)))
  assert.deepEqual(M.diveArgv("kimi", "/r", "p").slice(-2), ["-e", "kimi"])
})

test("blocking: outside deps block, in-raft deps only order; rafts list blocked tickets", () => {
  const m = M.normalize({
    webBase: "https://github.com/o/r/blob/main/",
    paths: { c0002: "z/.tracker/issues/c0002/c0002.md", c0003: "../evil.md" },
    issues: [
      { id: "c0001", type: "chore", title: "outside", stage: "prepared", raft: "R0001" },
      { id: "c0002", type: "chore", title: "a", stage: "prepared", raft: "R0002", dependsOn: ["c0001", "c0003"] },
      { id: "c0003", type: "chore", title: "b", stage: "prepared", raft: "R0002" },
      { id: "c0004", type: "chore", title: "c", stage: "prepared", raft: "R0002" },
    ],
    rafts: [
      { id: "R0001", title: "x", stage: "prepared", issues: ["c0001"] },
      { id: "R0002", title: "y", stage: "prepared", issues: ["c0002", "c0003", "c0004"], blockedBy: ["R0001"] },
    ],
  })
  assert.deepEqual(m.byId.c0002.blockedBy, ["c0001"])
  assert.deepEqual(m.byId.c0002.after, ["c0003"])
  assert.deepEqual(m.byId.R0002.blockedMembers, [{ id: "c0002", by: ["c0001"] }])
  assert.equal(m.byId.c0002.url, "https://github.com/o/r/blob/main/z/.tracker/issues/c0002/c0002.md")
  assert.equal(m.byId.c0003.url, "")
  assert.equal(M.stageCounts(m.issues.concat(m.rafts), { blocked: true }).total, 2)
})

test("styled code spans: our own span, ticket text escaped for HTML and markdown", () => {
  const style = { color: "#e0af68", background: "#292e42" }
  const md = M.safeMarkdown("x `a<b>_*c` y <i>", style)
  assert.equal(md,
    'x <span style="color:#e0af68;background-color:#292e42;font-family:monospace;font-weight:600">&nbsp;a&lt;b&gt;\\_\\*c&nbsp;</span> y &lt;i>')
  // a bad colour never reaches the style attribute
  assert.equal(M.safeMarkdown("`q`", { color: "red\" onx=\"", background: "#000000" }), "`q`")
  // a quote inside code can't end the attribute: it's text between the tags
  assert.ok(!/style="[^"]*"[^>]*"/.test(M.safeMarkdown('`a"b`', style)))
})

test("PRs attach by branch and title ids; tickets get their raft's PR", () => {
  const m = M.normalize({
    issues: [
      { id: "c0117", title: "a", stage: "active", raft: "R0052" },
      { id: "c0118", title: "b", stage: "prepared", raft: "R0083" },
      { id: "c0132", title: "c", stage: "preparing" },
    ],
    rafts: [{ id: "R0052", title: "r", stage: "active", issues: ["c0117"] },
            { id: "R0083", title: "s", stage: "prepared", issues: ["c0118"] }],
  })
  M.attachPrs(m, [
    { number: 125, title: "R0052: Models and dispatcher (c0117)", headRefName: "impl-c0117", isDraft: true, url: "https://github.com/o/r/pull/125" },
    { number: 122, title: "c0118: board (stacked on #125 R0052)", headRefName: "impl-c0118", isDraft: true, url: "https://github.com/o/r/pull/122" },
    { number: 175, title: "tracker: prep c0132 Sweeper", headRefName: "prep-sweeper", isDraft: false, url: "https://github.com/o/r/pull/175" },
    { number: 9, title: "R0052 evil", headRefName: "x", url: "javascript:alert(1)" },
  ])
  assert.deepEqual(m.byId.R0052.prs.map(p => p.number), [125])
  assert.deepEqual(m.byId.c0117.prs.map(p => p.number), [125])
  assert.deepEqual(m.byId.c0118.prs.map(p => p.number), [122])
  assert.deepEqual(m.byId.c0132.prs.map(p => p.number), [175])
  assert.equal(m.byId.c0132.prs[0].draft, false)
})

test("ticketPrompt names the project and the capture skill; bad project names drop out", () => {
  const a = M.ticketPrompt("snake", "  bug: tail clips walls ")
  assert.match(a, /in project snake \(--project snake\)/)
  assert.match(a, /z-nile\/skills\/z-ticket\/SKILL\.md/)
  assert.match(a, /It is about: bug: tail clips walls$/)
  assert.match(M.ticketPrompt("pickman", ""), /First ask me what the ticket is about\.$/)
  assert.doesNotMatch(M.ticketPrompt("x; rm -rf /", "y"), /rm -rf/)
})

test("cost: ticket spend, raft rollup or member sum, formatting", () => {
  const m = M.normalize({
    issues: [
      { id: "c0001", title: "a", stage: "done", raft: "R0001" },
      { id: "c0002", title: "b", stage: "prepared", raft: "R0002" },
      { id: "c0003", title: "c", stage: "prepared", raft: "R0002" },
    ],
    rafts: [
      { id: "R0001", title: "x", stage: "done", issues: ["c0001"] },
      { id: "R0002", title: "y", stage: "prepared", issues: ["c0002", "c0003"] },
    ],
    spend: {
      c0001: { minutes: 30, tokens: 0, phases: { build: { minutes: 30 } } },
      R0001: { minutes: 340.4, tokens: 430000, phases: { prep: { minutes: 90 }, "design-review": { minutes: 128, tokens: 430000 } } },
      c0002: { minutes: 120, tokens: 1177234, phases: { prep: { minutes: 120 }, "design-review": { minutes: 0, tokens: 1177234 } } },
      c0003: { minutes: 3, tokens: -5, phases: { capture: { minutes: 3 }, "<b>": { minutes: 9 } } },
    },
  })
  assert.equal(m.byId.R0001.cost.minutes, 340.4)                // own rollup wins
  assert.equal(m.byId.R0002.cost.minutes, 123)                  // backlog raft: sum of tickets
  assert.equal(m.byId.R0002.cost.tokens, 1177234)
  assert.equal(m.byId.c0003.cost.tokens, 0)                     // negative dropped
  assert.ok(!("<b>" in m.byId.c0003.cost.phases))               // odd phase names dropped
  assert.equal(M.costLine(m.byId.R0001.cost), "5.7 h · 430k tokens")
  assert.equal(M.costLine(m.byId.c0003.cost), "3 min")
  assert.equal(M.costLine(M.normalize({ issues: [{ id: "c0009", title: "z", stage: "new" }] }).byId.c0009.cost), "")
  assert.equal(M.fmtTokens(1177234), "1.2M")
  assert.equal(M.phaseLine(m.byId.R0002.cost), "capture 3 min · prep 2 h · design-review 0 min, 1.2M")
})
