--!strict
-- c0107 AC4: search opens the issue itself, a raft pane still lists what it waits for, Stats stays
-- out of the nav, and the tracker skill describes the new board.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local ROOT = ".cache/c0107-keep"

-- c0120 override: the spec runs from its home (z-nile/), but the board names its template and the vendored
-- marked from the checkout's top (where ./zn runs), so both are read there
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
if string.sub(board.TEMPLATE_PATH, 1, 1) ~= "/" then
	board.TEMPLATE_PATH = `{TOP}/{board.TEMPLATE_PATH}`
end
local MARKED = `{TOP}/{board.MARKED_PATH}`

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function write(path: string, front: { string }, body: string)
	fs.writeDir(`{ROOT}/{dirname(path)}`)
	fs.writeFile(`{ROOT}/{path}`, "---\n" .. table.concat(front, "\n") .. "\n---\n\n" .. body)
end

local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8");
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
function el(id) {
  const ls = {}, cl = new Set();
  return {
    id, innerHTML: "", textContent: "", value: "", scrollTop: 0,
    classList: {
      add: c => cl.add(c), remove: c => cl.delete(c), contains: c => cl.has(c),
      toggle: (c, f) => { const on = f === undefined ? !cl.has(c) : !!f; on ? cl.add(c) : cl.delete(c); return on; },
    },
    addEventListener: (t, f) => (ls[t] = ls[t] || []).push(f),
    dispatch: (t, ev) => (ls[t] || []).forEach(f => f(ev)),
    focus() {}, blur() {}, select() {}, scrollIntoView() {},
    getAttribute: () => null, setAttribute() {}, closest: () => null,
  };
}
const ids = ["tab-rafts", "tab-issues", "search", "list", "pane", "board-data"];
const els = {};
ids.forEach(i => (els[i] = el(i)));
const at = {};
ids.forEach(i => (at[i] = html.indexOf('id="' + i + '"')));
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
let loadingAt = -1;
const sandbox = {
  document: {
    getElementById: i => (els[i] && (loadingAt < 0 || (at[i] >= 0 && at[i] < loadingAt)) ? els[i] : null),
    querySelector: () => null, addEventListener: doc.addEventListener, body: doc, activeElement: doc,
  },
  location: { hash: "" },
  history: { replaceState: (a, b, h) => (sandbox.location.hash = h) },
  navigator: { clipboard: { writeText: () => ({ then: ok => ok() }) } },
  console, JSON, Math, String, Array, Object, decodeURIComponent, encodeURIComponent,
};
sandbox.window = sandbox; sandbox.self = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) { loadingAt = s.index; vm.runInContext(s[2], sandbox); }
loadingAt = -1;
doc.dispatch("DOMContentLoaded", { target: doc, preventDefault() {} });
const out = { pane: els.pane.innerHTML };
els.search.value = "f9100";
els.search.dispatch("keydown", { key: "Enter", target: els.search });
out.afterSearch = els.pane.innerHTML;
out.list = els.list.innerHTML;
els.search.value = "c9102";
els.search.dispatch("keydown", { key: "Enter", target: els.search });
out.loose = els.pane.innerHTML;
console.log(JSON.stringify(out));
]==]

return t.spec("c0107 board keep", function(it)
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	write("rafts/R9100/R9100.md", {
		"id: R9100",
		"type: feature",
		"title: ReadyRaft",
		"issues: [f9100]",
		"design: ready",
		"status: prepared-a-b-c",
	}, "# R9100: ReadyRaft\n")
	write("issues/f9100/f9100.md", {
		"id: f9100",
		"type: feature",
		"title: ReadyFeature",
		"raft: R9100",
		"depends_on: [c9102]",
		"design: ready",
	}, "# f9100: ReadyFeature\n\nThe feature body sentence stays visible.\n")
	write("issues/c9102/c9102.md", {
		"id: c9102",
		"type: feature",
		"title: LooseFeature",
		"raft:",
		"depends_on: []",
		"design: draft",
	}, "# c9102: LooseFeature\n\nThe loose body sentence stays visible.\n")

	local page = `{ROOT}/page.html`
	local html = board.render(board.collect(ROOT) :: any, fs.readFile(MARKED))
	fs.writeFile(page, html)
	fs.writeFile(`{ROOT}/harness.js`, HARNESS)

	it("keeps Stats out of the nav", function()
		local nav = string.match(html, "<nav>.-</nav>") or ""
		t.expect((string.find(nav, "stats", 1, true))).toBe(nil)
		t.expect(string.find(html, 'id="stats-toggle"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, 'id="stats"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(nav, 'id="tab-rafts"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(nav, 'id="tab-issues"', 1, true) ~= nil).toBe(true)
	end)

	it("the tracker skill's board row names Rafts, Issues and mix, and still names the artifact", function()
		-- c0120 override: the skill is read from the checkout's top
		local row = ""
		for line in string.gmatch(fs.readFile(`{TOP}/.claude/skills/tracker/SKILL.md`), "[^\n]+") do
			if string.sub(line, 1, 10) == "| board | " then
				row = line
			end
		end
		t.expect(row ~= "").toBe(true)
		t.expect(string.find(row, "Views Rafts and Issues", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "not a third view", 1, true) ~= nil).toBe(true)
		t.expect((string.find(row, "not a fourth tab", 1, true))).toBe(nil)
		t.expect(string.find(row, "mix", 1, true) ~= nil).toBe(true)
		t.expect((string.find(row, "Tabs Active / Waiting / Done", 1, true))).toBe(nil)
		for _, token in { "board.yml", "tracker-board", "gh run download", "rm -rf .cache/board-ci" } do
			t.expect(string.find(row, token, 1, true) ~= nil).toBe(true)
		end
	end)

	it("a raft pane still says what it waits for, and search opens the issue", function()
		local run = process.exec("node", { `{ROOT}/harness.js`, page })
		if not run.ok then
			error(run.stderr)
		end
		local shown = serde.decode("json", run.stdout)
		t.expect(string.find(shown.pane, "Waiting for", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.pane, "c9102", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.afterSearch, '<h2><span class="id">f9100</span>', 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(shown.afterSearch, "Depends on", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.afterSearch, "The feature body sentence stays visible.", 1, true) ~= nil)
			.toBe(true)
		t.expect((string.find(shown.afterSearch, '<h2><span class="id">R9100</span>', 1, true))).toBe(nil)
		t.expect(string.find(shown.afterSearch, 'data-id="R9100"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.list, 'data-id="f9100"', 1, true) ~= nil).toBe(true)
		t.expect((string.find(shown.list, 'data-id="R9100"', 1, true))).toBe(nil)
		t.expect(string.find(shown.loose, "Dependents", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.loose, "R9100", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.loose, "The loose body sentence stays visible.", 1, true) ~= nil)
			.toBe(true)
		fs.removeDir(ROOT)
	end)
end)
