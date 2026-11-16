// c0257 acceptance: rules of Model.js that the app's own tests/model.test.mjs does not pin (found by prep's mutation
// check: a reorder that lands one place late and a path that climbs out of the repository both survived it).
// Run by model.spec.luau with C0257_APP set to the znile.board folder. Model.js is a QML `.pragma library` script, so it is
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

test("RULE additive keys: keys the app does not read (rank, heartbeat, minutes) change nothing it shows", () => {
  const plain = M.normalize(base())
  const raw = base()
  raw.issues[0].heartbeat = "lost"
  raw.issues[0].minutes = 35
  raw.issues[1].rank = 3
  raw.rafts[0].heartbeat = "parked"
  raw.futureTopLevelKey = { anything: [1, 2, 3] }
  const extra = M.normalize(raw)
  const shape = m => JSON.stringify([m.issues.map(i => [i.id, i.stage, i.blockedBy, i.after, i.title]), m.rafts.map(r => [r.id, r.stage, r.issues]), m.projects])
  assert.equal(shape(extra), shape(plain))
  assert.deepEqual(M.columns(extra.issues, {}, {}, true).map(c => c.items.map(i => i.id)), M.columns(plain.issues, {}, {}, true).map(c => c.items.map(i => i.id)))
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
