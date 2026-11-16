// c0257 acceptance: rules of Model.js that the app's own tests/model.test.mjs does not pin (found by prep's mutation
// check: a reorder that lands one place late and a path that climbs out of the repository both survived it).
// Run by rules.spec.luau with C0257_APP set to the znile.board folder. Model.js is a QML `.pragma library` script, so it is
// loaded the way the app's own test loads it.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { join } from "node:path"

const app = process.env.C0257_APP
if (!app) throw new Error("C0257_APP names the znile.board folder")
const source = readFileSync(join(app, "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const names = [...source.matchAll(/^function (\w+)/gm)].map(m => m[1])
const M = new Function(`${source}\nreturn { STAGES, ${names.join(", ")} }`)()

const base = () => ({
  repo: "/r",
  projects: { c0001: "z-nile", c0002: "z-nile", R0001: "z-nile" },
  projectOrder: ["z-nile"],
  paths: { c0001: "z-nile/.tracker/issues/c0001/c0001.md", c0002: "../../etc/c0002.md" },
  webBase: "https://github.com/o/r/blob/main/",
  issues: [
    { id: "c0001", type: "chore", title: "One", stage: "active", raft: "R0001" },
    { id: "c0002", type: "chore", title: "Two", stage: "wandering", dependsOn: ["c0001"] },
  ],
  rafts: [{ id: "R0001", type: "chore", label: "chore", title: "Raft", stage: "active", issues: ["c0001"] }],
})

test("RULE reorder: the moved id sits exactly before the target; no-ops return the same order", () => {
  assert.deepEqual(M.reorder(["a", "b", "c", "d"], "d", "b"), ["a", "d", "b", "c"])
  assert.deepEqual(M.reorder(["a", "b", "c", "d"], "a", "c"), ["b", "a", "c", "d"])
  assert.deepEqual(M.reorder(["a", "b", "c"], "b", "b"), ["a", "b", "c"])
  assert.deepEqual(M.reorder(["a", "b", "c"], "zz", "b"), ["a", "b", "c"])
  assert.deepEqual(M.reorder(["a", "b", "c"], "a", ""), ["b", "c", "a"])
})

test("RULE paths: a document path that climbs out of the repository is dropped, with its link", () => {
  const m = M.normalize(base())
  assert.equal(m.byId.c0001.path, "z-nile/.tracker/issues/c0001/c0001.md")
  assert.equal(m.byId.c0001.url, "https://github.com/o/r/blob/main/z-nile/.tracker/issues/c0001/c0001.md")
  assert.equal(m.byId.c0002.path, "")
  assert.equal(m.byId.c0002.url, "")
})

test("RULE webBase: only a github.com blob/main base makes links", () => {
  const raw = base()
  raw.webBase = "https://evil.invalid/blob/main/"
  const m = M.normalize(raw)
  assert.equal(m.byId.c0001.url, "")
})

test("RULE stage: an unknown stage lands in New, so a card is never lost", () => {
  const m = M.normalize(base())
  assert.equal(m.byId.c0002.stage, "new")
})

test("RULE unknown keys: keys the app does not read change nothing it shows", () => {
  const plain = M.normalize(base())
  const raw = base()
  raw.issues[0].someFutureKey = "x"
  raw.rafts[0].anotherFutureKey = { nested: [1, 2, 3] }
  raw.futureTopLevelKey = { anything: [1, 2, 3] }
  const extra = M.normalize(raw)
  const shape = m => JSON.stringify([m.issues.map(i => [i.id, i.stage, i.blockedBy, i.after, i.title]), m.rafts.map(r => [r.id, r.stage, r.issues]), m.projects])
  assert.equal(shape(extra), shape(plain))
})

// Today's behaviour: rank (c0249) and heartbeat marks (c0276, c0290) are not read. c0249 and c0290 each change this case
// when they make the app show them; they name this spec as an override (c0257 Design, Relation to the other boards).
test("RULE rank and heartbeat keys are ignored today (c0249 and c0290 override this case)", () => {
  const plain = M.normalize(base())
  const raw = base()
  raw.issues[0].heartbeat = "lost"
  raw.issues[0].minutes = 35
  raw.issues[1].rank = 3
  raw.rafts[0].heartbeat = "parked"
  const extra = M.normalize(raw)
  const ids = m => M.columns(m.issues, {}, {}, true).map(c => c.items.map(i => i.id))
  assert.deepEqual(ids(extra), ids(plain))
  assert.equal(JSON.stringify(extra.issues.map(i => i.title)), JSON.stringify(plain.issues.map(i => i.title)))
})

test("RULE clipping: a title is cut at 200 characters and a body at 6000", () => {
  const raw = base()
  raw.issues[0].title = "t".repeat(300)
  raw.issues[0].body = "b".repeat(9000)
  const m = M.normalize(raw)
  assert.equal(m.byId.c0001.title.length, 200)
  assert.ok(m.byId.c0001.body.length <= 6000 + 3)
})

test("RULE markdown: HTML and images outside code are neutralised, code stays verbatim", () => {
  const md = M.safeMarkdown("# c0001: T\n<script>x()</script> ![a](http://u.invalid/i.png) `<b>`\n```\n<i>\n```\n<img src=x>")
  assert.ok(!/<script|<img/.test(md.split("```")[0] + md.split("```")[2]), md)
  assert.ok(md.includes("&lt;script>"))
  assert.ok(md.includes("\\![a](http://u.invalid/i.png)"))
  assert.ok(md.includes("`<b>`"))
  assert.ok(md.includes("```\n<i>\n```"))
})

test("RULE agents: no agent starts with an auto-approve flag, and the prompt is one argument", () => {
  const prompt = "do it; rm -rf / \"x\" $(y)"
  for (const id of ["claude", "codex", "grok", "kimi", "opencode", "copilot", "agy", "cursor-agent", "qwen", "pi", "crush"]) {
    const argv = M.diveArgv(id, "/repo", prompt)
    assert.ok(argv.length > 0, id)
    assert.ok(!argv.some(x => /yolo|bypass|skip-permissions|dangerous|full-auto|auto-approve|--force|--approve/.test(x)), id + ": " + argv.join(" "))
    assert.ok(argv.filter(x => x.includes("rm -rf")).length <= 1, id)
    assert.ok(!(argv[0] === "sh" || argv[0] === "bash"), id)
  }
})

test("RULE pull requests: only github.com pull URLs attach", () => {
  const m = M.normalize(base())
  M.attachPrs(m, [
    { number: 7, title: "c0001 ok", headRefName: "c0001-x", isDraft: false, url: "https://github.com/o/r/pull/7" },
    { number: 8, title: "c0001 evil", headRefName: "c0001-y", isDraft: false, url: "https://evil.invalid/o/r/pull/8" },
    { number: 9, title: "c0001 js", headRefName: "c0001-z", isDraft: false, url: "javascript:alert(1)" },
  ])
  assert.deepEqual(m.byId.c0001.prs.map(p => p.number), [7])
})

test("RULE ids: an item whose id is not a ticket or raft id is dropped", () => {
  const raw = base()
  raw.issues.push({ id: "../etc", type: "chore", title: "x", stage: "new" }, { id: "c00011", type: "chore", title: "y", stage: "new" })
  assert.deepEqual(M.normalize(raw).issues.map(i => i.id), ["c0001", "c0002"])
})

test("RULE rank command: the template never becomes a shell invocation", () => {
  const argv = M.rankArgv("./zn rank {id} --before {beforeId}", "c0001", "c0002; rm -rf /")
  assert.equal(argv[0], "./zn")
  assert.ok(argv.includes("c0002;") || argv.some(x => x.includes("c0002")))
  assert.ok(!(argv[0] === "sh" || argv[0] === "bash"))
})

test("RULE session order: a dragged order wins over the number, ids it does not name follow by number", () => {
  const items = ["c0003", "c0001", "c0002", "c0010"].map(id => ({ id, num: Number(id.slice(1)) }))
  assert.deepEqual(M.sortByPriority(items, []).map(i => i.id), ["c0001", "c0002", "c0003", "c0010"])
  assert.deepEqual(M.sortByPriority(items, ["c0010", "c0002", "c0003"]).map(i => i.id), ["c0010", "c0002", "c0003", "c0001"])
  assert.deepEqual(M.sortByPriority(items, ["c0003", "c0001"]).map(i => i.id), ["c0003", "c0001", "c0002", "c0010"])
})

test("RULE rank command: empty template means no command (the move stays in the session)", () => {
  assert.deepEqual(M.rankArgv("", "c0001", "c0002"), [])
  assert.deepEqual(M.rankArgv("   ", "c0001", "c0002"), [])
  assert.deepEqual(M.rankArgv("./zn rank {id} --before {beforeId}", "c0001", "c0002"), ["./zn", "rank", "c0001", "--before", "c0002"])
})
