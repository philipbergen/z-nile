// c0249: the Omarchy board app orders by the engine's rank and persists a drag through ./zn rank. Runs Model.js (a QML
// `.pragma library` script) under node, like the app's own tests; C0249_APP names the plugin folder (znile.board).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { join } from "node:path"

const app = process.env.C0249_APP
const source = readFileSync(join(app, "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const names = [...source.matchAll(/^function (\w+)/gm)].map(m => m[1])
const M = new Function(`${source}\nreturn { STAGES, ${names.join(", ")} }`)()
const settings = JSON.parse(readFileSync(join(app, "settings.json"), "utf8"))
const service = readFileSync(join(app, "Service.qml"), "utf8")

const issue = (id, over = {}) => ({ id, type: "chore", title: id, stage: "new", ...over })

test("the shipped rank command is ./zn rank with the dragged id and the id it was dropped before", () => {
  assert.equal(settings.rankCommand, "./zn rank {id} --before {beforeId}")
  assert.deepEqual(M.rankArgv(settings.rankCommand, "c0010", "c0020"), ["./zn", "rank", "c0010", "--before", "c0020"])
  // dropped last: the before id is empty, and stays one argument
  assert.deepEqual(M.rankArgv(settings.rankCommand, "c0010", ""), ["./zn", "rank", "c0010", "--before", ""])
  // never a shell: an id with shell syntax stays one argument
  assert.deepEqual(M.rankArgv(settings.rankCommand, "c0010", "c0020; rm -rf /").slice(3), ["--before", "c0020; rm -rf /"])
})

test("a column is in the engine's order: a set rank first, the lower first, then the ticket number", () => {
  const m = M.normalize({
    issues: [
      issue("c0100"),
      issue("f0200", { rank: 40, effectiveRank: 40 }),
      issue("d0150", { rank: 40, effectiveRank: 40 }),
      issue("c0300", { rank: 5, effectiveRank: 5 }),
      issue("c0050"),
    ],
  })
  assert.deepEqual(M.sortByPriority(m.issues, []).map(i => i.id), ["c0300", "d0150", "f0200", "c0050", "c0100"])
  // the columns the window draws use it
  const cols = M.columns(m.issues, {}, {}, false)
  assert.deepEqual(cols.find(c => c.stage === "new").items.map(i => i.id), ["c0300", "d0150", "f0200", "c0050", "c0100"])
})

test("a raft is placed by the rank the engine computed for it (its own, else its members' best)", () => {
  const m = M.normalize({
    rafts: [
      { id: "R0002", stage: "new", issues: [], rank: null, effectiveRank: 7 },
      { id: "R0001", stage: "new", issues: [], rank: null, effectiveRank: null },
      { id: "R0003", stage: "new", issues: [], rank: 90, effectiveRank: 90 },
    ],
  })
  assert.deepEqual(M.sortByPriority(m.rafts, []).map(r => r.id), ["R0002", "R0003", "R0001"])
})

test("anything but a whole number from 1 to 999999 is an unset rank", () => {
  for (const bad of [0, -1, 1.5, 1000000, "7", null, undefined, NaN, Infinity, {}, [3]]) {
    const m = M.normalize({ issues: [issue("c0001", { rank: bad, effectiveRank: bad })] })
    assert.equal(m.byId.c0001.rank, null, String(bad))
  }
  assert.equal(M.normalize({ issues: [issue("c0001", { rank: 999999 })] }).byId.c0001.rank, 999999)
  // the effective rank wins over the own one
  assert.equal(M.normalize({ issues: [issue("c0001", { rank: 9, effectiveRank: 4 })] }).byId.c0001.rank, 4)
  assert.equal(M.normalize({ issues: [issue("c0001", { rank: 9 })] }).byId.c0001.rank, 9)
})

test("the order dragged in this session shows a move at once, ahead of the rank", () => {
  const m = M.normalize({ issues: [issue("c0100", { rank: 10, effectiveRank: 10 }), issue("c0200", { rank: 20, effectiveRank: 20 })] })
  assert.deepEqual(M.sortByPriority(m.issues, ["c0200", "c0100"]).map(i => i.id), ["c0200", "c0100"])
  assert.deepEqual(M.sortByPriority(m.issues, ["c0200"]).map(i => i.id), ["c0200", "c0100"])
})

test("a saved move drops the session order, so the next refresh shows the engine's order", () => {
  // Service.qml: the rank process's success handler resets the dragged orders before it refreshes
  assert.match(service, /if \(exitCode === 0\) \{[^}]*root\.orders = \(\{\}\)[^}]*root\.say\([^}]*"priority saved[^}]*root\.refresh\(\)/)
  // a drop below the unset cards unsets the card: the command's last line says so and the notice repeats it
  assert.match(service, /stdout: StdioCollector \{ id: rankOut/)
  assert.match(service, /dropped below the unset items/)
  // and a failed or missing command keeps the dragged order and says so
  assert.match(service, /priority not saved: /)
  assert.match(service, /moved for this session only/)
})
