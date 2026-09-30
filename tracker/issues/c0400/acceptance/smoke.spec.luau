--!strict
-- c0400 AC6: the page's own scripts run. node executes the generated page's inline scripts against a
-- small fake DOM (the DOM subset the design allows; elements after the script do not exist yet while
-- it loads) and drives it: initial tab (with and without active rafts), every key, tab switching,
-- search with highlighting, unknown ids, and #id links on load.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local fixture = {} :: any

fixture.FILES = {
	{
		path = "rafts/done/R0010/R0010.md",
		front = { "id: R0010", "type: chore", "title: Alpha", "design: ready" },
		body = "# R0010: Alpha\n",
	},
	{
		path = "rafts/active/R0020/R0020.md",
		front = { "id: R0020", "type: feature", "title: Beta", "design: ready" },
		body = "# R0020: Beta\n",
	},
	{
		path = "rafts/R0030/R0030.md",
		front = { "id: R0030", "type: feature", "title: Gamma", "design: ready" },
		body = "# R0030: Gamma\n\n| a | b |\n|---|---|\n| 1 | 2 |\n",
	},
	{
		path = "rafts/R0050/R0050.md",
		front = { "id: R0050", "type: chore", "title: Epsilon", "design: reviewed" },
		body = "# R0050: Epsilon\n",
	},
	{
		path = "issues/done/c0010/c0010.md",
		front = { "id: c0010", "type: chore", "title: First", "raft: R0010", "depends_on: []" },
		body = "# c0010: First\n",
	},
	{
		path = "issues/active/f0020/f0020.md",
		front = { "id: f0020", "type: feature", "title: Second", "raft: R0020", "depends_on: [c0010]" },
		body = "# f0020: Second\n",
	},
	{
		path = "issues/f0030/f0030.md",
		front = { "id: f0030", "type: feature", "title: Third", "raft: R0030", "depends_on: [f0020]" },
		body = "# f0030: Third\n",
	},
	{
		path = "issues/f0031/f0031.md",
		front = { "id: f0031", "type: feature", "title: Third B", "raft: R0030", "depends_on: []" },
		body = "# f0031: Third B\n",
	},
	{
		path = "issues/c0050/c0050.md",
		front = { "id: c0050", "type: chore", "title: Fifth", "raft: R0050", "depends_on: []" },
		body = "# c0050: Fifth\n",
	},
	{
		path = "issues/f0060/f0060.md",
		front = { "id: f0060", "type: feature", "title: Loose", "raft: ", "depends_on: []" },
		body = "# f0060: Loose\n",
	},
}

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

function fixture.write(root: string, skip: string?)
	if fs.isDir(root) then
		fs.removeDir(root)
	end
	for _, f in fixture.FILES do
		if skip and string.find(f.path, skip, 1, true) then
			continue
		end
		local path = `{root}/{f.path}`
		fs.writeDir(dirname(path))
		fs.writeFile(path, "---\n" .. table.concat(f.front, "\n") .. "\n---\n\n" .. f.body)
	end
end

-- The fake DOM: exactly the subset c0400's Design allows the page script to use.
local HARNESS = [==[
const load = m => module["req" + "uire"](m); // never literal require text: the repo scanner would read it
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), hash = process.argv[3] || "", mode = process.argv[4] || "walk";
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
function el(id) {
  const listeners = {}, classes = new Set();
  const e = {
    id, innerHTML: "", textContent: "", value: "", scrollTop: 0,
    classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c),
      toggle: (c, f) => { const on = f === undefined ? !classes.has(c) : !!f; on ? classes.add(c) : classes.delete(c); return on; } },
    addEventListener: (type, fn) => (listeners[type] = listeners[type] || []).push(fn),
    dispatch: (type, ev) => (listeners[type] || []).forEach(fn => fn(ev)),
    focus() { sandbox.document.activeElement = e; }, blur() { if (sandbox.document.activeElement === e) sandbox.document.activeElement = body; },
    select() {}, scrollIntoView() {}, getAttribute: () => null, closest: () => null,
  };
  return e;
}
const ids = ["tab-active", "tab-waiting", "tab-done", "search", "list", "pane", "board-data"];
const els = {}; ids.forEach(i => (els[i] = el(i)));
const at = {}; ids.forEach(i => (at[i] = html.indexOf('id="' + i + '"')));
const data = scripts.find(s => /id="board-data"/.test(s[1]));
if (!data) throw new Error("no board-data script");
els["board-data"].textContent = data[2];
const doc = el("document"), body = el("body");
let loadingAt = -1; // while a script loads, only elements before it exist (as in a browser)
const sandbox = {
  document: {
    getElementById: i => (els[i] && (loadingAt < 0 || (at[i] >= 0 && at[i] < loadingAt)) ? els[i] : null),
    querySelector: () => null, addEventListener: doc.addEventListener, body, activeElement: body,
  },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) },
  console, JSON, Math, String, Array, Object, decodeURIComponent, encodeURIComponent,
};
sandbox.window = sandbox; sandbox.self = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) { loadingAt = s.index; vm.runInContext(s[2], sandbox); }
loadingAt = -1;
doc.dispatch("DOMContentLoaded", { target: doc, preventDefault() {} });
function key(k, target) {
  const ev = { key: k, target: target || body, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
  if (target) target.dispatch("keydown", ev);
  doc.dispatch("keydown", ev);
  return ev.defaultPrevented;
}
function expect(cond, msg) { if (!cond) throw new Error(msg + "\n--- list:\n" + els.list.innerHTML.slice(0, 400) + "\n--- pane:\n" + els.pane.innerHTML.slice(0, 600)); }
function highlighted(id) { const m = els.pane.innerHTML.match(new RegExp('<details[^>]*id="i-' + id + '"[^>]*>')); return !!m && /highlight/.test(m[0]) && /\bopen\b/.test(m[0]); }
const list = () => els.list.innerHTML, pane = () => els.pane.innerHTML;
if (mode === "walk") {
  expect(/R0020/.test(list()) && !/R0050/.test(list()), "opens on the Active tab");
  expect(/Beta/.test(pane()), "shows the first Active raft");
  key("ArrowUp");
  expect(/Beta/.test(pane()), "ArrowUp stops at the first row");
  key("ArrowRight");
  expect(/R0050/.test(list()) && !/R0020/.test(list()), "ArrowRight moves to Waiting");
  expect(/Epsilon/.test(pane()), "switching tabs selects the first row");
  key("ArrowUp");
  expect(/Epsilon/.test(pane()), "ArrowUp on the first of several rows stays there (no wrap)");
  key("ArrowDown");
  expect(/f0060/.test(pane()) && /No raft/.test(pane()), "ArrowDown selects the No raft entry");
  key("ArrowDown");
  expect(/f0060/.test(pane()), "ArrowDown stops at the last row");
  key("ArrowUp");
  expect(/Epsilon/.test(pane()), "ArrowUp moves back");
  key("ArrowLeft");
  expect(/R0020/.test(list()), "ArrowLeft moves back to Active");
  key("ArrowLeft");
  expect(/R0010/.test(list()) && /Alpha/.test(pane()), "ArrowLeft cycles from Active to Done");
  expect(/Dependents/.test(pane()) && /<a class="jump" data-id="R0020"/.test(pane()), "the pane lists reverse dependencies as links");
  key("ArrowRight");
  expect(/R0020/.test(list()), "ArrowRight cycles from Done to Active");
  expect(key("/") === true, "/ calls preventDefault, so the / is not typed into the field");
  expect(sandbox.document.activeElement === els.search, "/ focuses the search field");
  key("ArrowDown", els.search);
  key("ArrowRight", els.search);
  expect(/R0020/.test(list()) && /Beta/.test(pane()), "arrow keys typed into the search field are ignored");
  key("Escape", els.search);
  expect(sandbox.document.activeElement !== els.search, "Esc leaves the search field");
  els.search.value = "F0031";
  key("Enter", els.search);
  expect(/Gamma/.test(pane()), "search finds the raft holding the issue, case-insensitively");
  expect(highlighted("f0031"), "the searched issue is highlighted and open");
  expect(/<table>/.test(pane()), "markdown is rendered with marked (a table)");
  expect(/R0050/.test(list()) && !/R0020/.test(list()), "a search hit switches the list to the entry's tab");
  expect(sandbox.location.hash === "#f0031", "a successful jump updates location.hash");
  expect(/Waiting for/.test(pane()) && /Depends on/.test(pane()), "the pane shows Waiting for and Depends on");
  expect(/<a class="jump" data-id="R0020"/.test(pane()), "dependencies are id links");
  els.pane.dispatch("click", { target: { closest: sel => (sel === "a.jump" ? { getAttribute: n => (n === "data-id" ? "R0020" : null) } : null) }, preventDefault() {} });
  expect(/Beta/.test(pane()) && /R0020/.test(list()) && sandbox.location.hash === "#R0020", "clicking an id link jumps to that item");
  els.search.value = "f0031";
  key("Enter", els.search);
  key("ArrowUp");
  expect(/f0060/.test(pane()) && /No raft/.test(pane()), "ArrowUp from an unlisted pane selects the last row");
  els.search.value = "f0031";
  key("Enter", els.search);
  expect(!els.search.classList.contains("miss"), "a hit does not mark the field");
  key("ArrowDown");
  expect(/Epsilon/.test(pane()), "ArrowDown from an unlisted pane selects the first row");
  els.search.value = "x9999";
  key("Enter", els.search);
  expect(els.search.classList.contains("miss"), "an unknown id marks the field");
  els.search.value = "r0050";
  key("Enter", els.search);
  expect(/Epsilon/.test(pane()) && !els.search.classList.contains("miss"), "a raft id shows that raft and clears the mark");
  els["tab-done"].dispatch("click", { target: els["tab-done"], preventDefault() {} });
  expect(/R0010/.test(list()), "clicking a tab switches to it");
} else if (mode === "quiet") {
  expect(/R0050/.test(list()) && !/Nothing here/.test(list()) && /Gamma/.test(pane()), "with nothing active, opens on Waiting");
  key("ArrowLeft");
  expect(/Nothing here/.test(list()), "an empty tab shows Nothing here");
  key("ArrowDown"); key("ArrowUp");
  key("ArrowRight");
  expect(/R0050/.test(list()), "keys on an empty tab are harmless");
} else {
  expect(/Fifth/.test(pane()) && highlighted("c0050"), "a #id in the URL opens that item");
}
console.log("SMOKE OK");
]==]

local DIR = ".cache/c0400-smoke"

return t.spec("c0400 page smoke test (node)", function(it)
	fixture.write(`{DIR}/tracker`)
	fs.writeFile(
		`{DIR}/page.html`,
		board.render(board.collect(`{DIR}/tracker`), fs.readFile(board.MARKED_PATH))
	)
	fixture.write(`{DIR}/quiet`, "/active/")
	fs.writeFile(
		`{DIR}/quiet.html`,
		board.render(board.collect(`{DIR}/quiet`), fs.readFile(board.MARKED_PATH))
	)
	fs.writeFile(`{DIR}/harness.js`, HARNESS)

	local function node(args: { string }): any
		local ok, r = pcall(process.exec, "node", args)
		if not ok then
			error(
				"node is required for the c0400 smoke test (it is preinstalled on GitHub runners): "
					.. tostring(r)
			)
		end
		return r
	end

	it("drives the page: tabs, arrows, search, highlight, unknown ids", function()
		local r = node({ `{DIR}/harness.js`, `{DIR}/page.html`, "", "walk" })
		if not r.ok or not string.find(r.stdout, "SMOKE OK", 1, true) then
			error(r.stderr .. r.stdout)
		end
	end)

	it("with nothing active, opens on Waiting and copes with an empty tab", function()
		local r = node({ `{DIR}/harness.js`, `{DIR}/quiet.html`, "", "quiet" })
		if not r.ok or not string.find(r.stdout, "SMOKE OK", 1, true) then
			error(r.stderr .. r.stdout)
		end
	end)

	it("opens the item named by #id on load", function()
		local r = node({ `{DIR}/harness.js`, `{DIR}/page.html`, "#c0050", "hash" })
		if not r.ok or not string.find(r.stdout, "SMOKE OK", 1, true) then
			error(r.stderr .. r.stdout)
		end
	end)

	it("cleans up", function()
		fs.removeDir(DIR)
	end)
end)
