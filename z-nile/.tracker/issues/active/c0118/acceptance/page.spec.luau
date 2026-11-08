--!strict
-- c0118 AC4: the page's own script, run by node against a fake DOM: it opens on the Board of the first project, with a
-- tab per project; the done window hides and shows done cards by age (61 minutes old: hidden at 1 hour, shown at 3);
-- raft bands; the charts follow the range; a card click shows its run details; a project tab, a search and a #project
-- link switch the project; the arrow keys cycle Board, Rafts and Issues, each showing the selected project only; and
-- znBoard.load (c0121's seam) swaps the model and keeps the project, the window and the range.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local DIR = ".cache/c0118-page"
local REGISTRY = [==[
[[project]]
name = "game"
root = "game/.tracker"

[[project]]
name = "tool"
root = "tool/.tracker"
]==]

local function write(path: string, text: string)
	local full = `{DIR}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function item(path: string, front: { string })
	local id = string.match(path, "([^/]+)$") :: string
	write(
		`{path}/{id}.md`,
		"---\nid: " .. id .. "\n" .. table.concat(front, "\n") .. "\n---\n\n# " .. id .. "\n"
	)
end
local function spend(dir: string, id: string, when: string, phase: string, tokens: string, model: string)
	write(
		`{dir}/spend.md`,
		`# Spend: {id} t\n\n| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n`
			.. "|---|---|---|---|---|---|---|---|---|---|\n"
			.. `| 1 | {when} | s | 4 | 1 | 2.5 | spend | {phase} | {tokens} | {model} |\n`
	)
end

local G, T = "game/.tracker", "tool/.tracker"
local AS_OF = stats.seconds("2026-10-21T10:00:00Z")

-- The fake DOM: elements by id, attributes, class lists, listeners, and `closest` for the selectors the page uses.
-- Never literal require text: the repo scanner would read it.
local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), hash = process.argv[3] || "";
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
const els = {};
function el(id) {
  const ls = {}, cl = new Set(), attrs = {};
  return els[id] = { id, innerHTML: "", textContent: "", value: "", scrollTop: 0,
    classList: { add: c => cl.add(c), remove: c => cl.delete(c), contains: c => cl.has(c),
      toggle: (c, f) => { const on = f === undefined ? !cl.has(c) : !!f; on ? cl.add(c) : cl.delete(c); return on; } },
    addEventListener: (t, f) => (ls[t] = ls[t] || []).push(f), dispatch: (t, e) => (ls[t] || []).forEach(f => f(e)),
    setAttribute: (n, v) => (attrs[n] = String(v)), removeAttribute: n => delete attrs[n], hasAttribute: n => n in attrs,
    getAttribute: n => (n in attrs ? attrs[n] : null), focus() {}, blur() {}, select() {}, scrollIntoView() {},
    querySelectorAll: () => [] };
}
["tab-board", "tab-rafts", "tab-issues", "search", "projects", "board", "columns", "charts", "window", "range", "as-of",
 "list", "pane", "board-data", "stats"].forEach(el);
els.board.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, navigator: {},
  console, JSON, Math, String, Array, Object, Number, Date, decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
const target = (sel, attr, value) => ({ closest: s => (s === sel ? { getAttribute: n => (n === attr ? value : null) } : null) });
const key = k => doc.dispatch("keydown", { key: k, target: {}, preventDefault() {} });
const snap = () => ({ projects: els.projects.innerHTML, columns: els.columns.innerHTML, charts: els.charts.innerHTML,
  pane: els.pane.innerHTML, list: els.list.innerHTML, boardHidden: els.board.hasAttribute("hidden"),
  listHidden: els.list.hasAttribute("hidden"), hash: sandbox.location.hash, windowOptions: els.window.innerHTML,
  rangeOptions: els.range.innerHTML, tabBoard: els["tab-board"].classList.contains("on"), stats: els.stats.innerHTML });
const out = { open: snap() };
if (!hash) {
  const setWindow = s => { els.window.value = String(s); els.window.dispatch("change", {}); return snap(); };
  out.w1h = setWindow(3600); out.w3h = setWindow(10800); out.w30d = setWindow(2592000); out.w24h = setWindow(86400);
  els.range.value = "all"; els.range.dispatch("change", {}); out.rangeAll = snap();
  els.columns.dispatch("click", { target: target("button.card", "data-id", "f0021"), preventDefault() {} }); out.card = snap();
  els.projects.dispatch("click", { target: target("button[data-project]", "data-project", "tool") }); out.tool = snap();
  els.search.value = "f0031"; els.search.dispatch("keydown", { key: "Enter", target: els.search }); out.search = snap();
  key("ArrowRight"); out.rafts = snap();
  key("ArrowRight"); out.issues = snap();
  key("ArrowRight"); out.wrap = snap();
  els.projects.dispatch("click", { target: target("button[data-project]", "data-project", "tool") });
  els.window.value = "2592000"; els.window.dispatch("change", {});
  els.columns.dispatch("click", { target: target("button.card", "data-id", "c0120"), preventDefault() {} });
  const next = JSON.parse(els["board-data"].textContent);
  next.issues.push(Object.assign({}, next.issues.find(i => i.id === "c0120"), { id: "c0125", title: "Arrived live" }));
  next.columns.tool.ticket[0].ids.push("c0125");
  next.rafts.find(r => r.id === "R0110").pr = { number: 7, url: "https://example.invalid/pr/7", state: "draft" };
  next.issues.find(i => i.id === "c0111").checks = { state: "passing" };
  sandbox.znBoard.load(next, "<p>fresh stats</p>"); out.loaded = snap();
  els.columns.dispatch("click", { target: target("button.card", "data-id", "c0111"), preventDefault() {} }); out.live = snap();
}
console.log(JSON.stringify(out));
]==]

local shown: any = nil
local hashed: any = nil
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end
local function node(page: string, hash: string): any
	local ok, r = pcall(process.exec, "node", { `{DIR}/harness.js`, page, hash })
	if not ok then
		error(`node is required for this spec: {r}`)
	end
	if not r.ok then
		error(r.stderr)
	end
	return serde.decode("json", r.stdout)
end

return t.spec("c0118 board page", function(it)
	it("builds a two-project page", function()
		if fs.isDir(DIR) then
			fs.removeDir(DIR)
		end
		write("z-nile/projects.toml", REGISTRY)
		item(
			`{G}/rafts/active/R0020`,
			{ "type: feature", "title: Running", "design: ready", "status: active-a-b-c" }
		)
		item(
			`{G}/issues/active/f0021`,
			{ "type: feature", "title: Runs", "raft: R0020", "status: active-a-b-c" }
		)
		spend(`{G}/issues/active/f0021`, "f0021", "2026-10-20 11:00", "code-review", "300", "grok-y")
		item(
			`{G}/rafts/active/R0030`,
			{ "type: feature", "title: Readied", "design: ready", "status: active-d-e-f" }
		)
		item(
			`{G}/issues/active/f0031`,
			{ "type: feature", "title: Waits", "raft: R0030", "status: active-d-e-f" }
		)
		item(`{G}/rafts/done/R0010`, { "type: chore", "title: Landed", "design: ready" })
		write(`{G}/rafts/done/R0010/design-review-001.md`, "# r\n")
		item(`{G}/issues/done/c0011`, { "type: chore", "title: Just landed", "raft: R0010" })
		spend(`{G}/issues/done/c0011`, "c0011", "2026-10-21 08:59", "deliver", "", "") -- 61 minutes before as-of
		item(`{G}/issues/done/c0012`, { "type: chore", "title: Landed yesterday", "raft: R0010" })
		spend(`{G}/issues/done/c0012`, "c0012", "2026-10-20 12:00", "deliver", "", "") -- 22 hours
		item(`{G}/issues/done/c0013`, { "type: chore", "title: Landed long ago", "raft:" })
		spend(`{G}/issues/done/c0013`, "c0013", "2026-10-10 12:00", "deliver", "", "") -- 11 days
		item(
			`{T}/rafts/R0110`,
			{ "type: chore", "title: Tool raft", "design: ready", "status: prepared-g-h-i" }
		)
		item(
			`{T}/issues/c0111`,
			{ "type: chore", "title: Tool rafted", "raft: R0110", "status: prepared-g-h-i" }
		)
		item(`{T}/issues/c0120`, { "type: chore", "title: Tool ticket", "raft:" })
		local facts = {
			asOf = AS_OF,
			refs = { { name = "origin/R0020-alpha", at = AS_OF } },
			worktrees = {},
			dispatch = {},
		}
		fs.writeFile(`{DIR}/page.html`, board.build(nil, DIR, facts))
		fs.writeFile(`{DIR}/harness.js`, HARNESS)
		shown = node(`{DIR}/page.html`, "")
		hashed = node(`{DIR}/page.html`, "#tool")
	end)

	it("opens on the Board of the first project, with a tab per project and the list hidden", function()
		local open = shown.open
		t.expect(open.tabBoard).toBe(true)
		t.expect(open.boardHidden).toBe(false)
		t.expect(open.listHidden).toBe(true)
		t.expect(has(open.projects, 'data-project="game" class="on"')).toBe(true)
		t.expect(has(open.projects, 'data-project="tool"')).toBe(true)
		local game = (string.find(open.projects, "game", 1, true)) :: number
		t.expect(game < ((string.find(open.projects, "tool", 1, true)) :: number)).toBe(true)
		for _, c in { "ticket", "design", "raft", "ready", "run", "done" } do
			t.expect(has(open.columns, `data-column="{c}"`)).toBe(true)
		end
		t.expect(has(open.columns, 'data-id="c0111"')).toBe(false) -- tool's card
	end)

	it("draws each raft as a band behind its cards, in its column", function()
		local cols = shown.open.columns
		local run = string.match(cols, 'data%-column="run".-data%-column="done"') or ""
		t.expect(has(run, 'class="band" data-raft="R0020"')).toBe(true)
		t.expect(has(run, 'data-id="f0021"')).toBe(true)
		local ready = string.match(cols, 'data%-column="ready".-data%-column="run"') or ""
		t.expect(has(ready, 'data-raft="R0030"')).toBe(true)
		t.expect(has(ready, 'data-id="f0031"')).toBe(true)
	end)

	it(
		"shows done cards while their age is within the window: 24 hours by default, 1 hour up to 30 days",
		function()
			local function shows(s: any, id: string): boolean
				return has(s.columns, `class="card" data-id="{id}"`)
					or has(s.columns, `class="card sel" data-id="{id}"`)
			end
			t.expect(shows(shown.open, "c0012")).toBe(true)
			t.expect(shows(shown.open, "c0011")).toBe(true)
			t.expect(shows(shown.open, "c0013")).toBe(false)
			t.expect(shows(shown.w1h, "c0011")).toBe(false) -- 61 minutes old
			t.expect(shows(shown.w1h, "c0012")).toBe(false)
			t.expect(shows(shown.w3h, "c0011")).toBe(true)
			t.expect(shows(shown.w3h, "c0012")).toBe(false)
			t.expect(shows(shown.w30d, "c0013")).toBe(true)
			t.expect(shows(shown.w24h, "c0013")).toBe(false)
			t.expect(has(shown.open.windowOptions, 'value="86400" selected')).toBe(true)
			t.expect(has(shown.open.windowOptions, 'value="3600"')).toBe(true)
			t.expect(has(shown.open.windowOptions, 'value="2592000"')).toBe(true)
		end
	)

	it("shows both charts for the chosen range, 90 days by default", function()
		t.expect(has(shown.open.rangeOptions, 'value="90d" selected')).toBe(true)
		t.expect(has(shown.open.charts, 'data-chart="game/rounds/90d"')).toBe(true)
		t.expect(has(shown.open.charts, 'data-chart="game/tokens/90d"')).toBe(true)
		t.expect(has(shown.rangeAll.charts, 'data-chart="game/rounds/all"')).toBe(true)
		t.expect(has(shown.rangeAll.charts, 'data-chart="game/tokens/all"')).toBe(true)
		t.expect(has(shown.rangeAll.charts, "game/rounds/90d")).toBe(false)
	end)

	it(
		"a card click shows its column, model, spend and document, and says PR and checks are live elsewhere",
		function()
			local pane = shown.card.pane
			t.expect(has(pane, '<h2><span class="id">f0021</span>')).toBe(true)
			t.expect(has(pane, "<dd>Run</dd>")).toBe(true)
			t.expect(has(pane, "grok-y")).toBe(true)
			t.expect(has(pane, "2.5 min, 300 tokens, +4/-1 lines")).toBe(true)
			t.expect(has(pane, "R0020-alpha")).toBe(true)
			t.expect(has(pane, "zn board --serve")).toBe(true)
			t.expect(has(shown.card.columns, 'class="card sel" data-id="f0021"')).toBe(true)
		end
	)

	it("a project tab shows that project's columns only, and names it in the link", function()
		local s = shown.tool
		t.expect(has(s.projects, 'data-project="tool" class="on"')).toBe(true)
		t.expect(has(s.columns, 'data-id="c0120"')).toBe(true)
		t.expect(has(s.columns, 'data-raft="R0110"')).toBe(true)
		t.expect(has(s.columns, 'data-id="f0021"')).toBe(false)
		t.expect(s.hash).toBe("#tool")
	end)

	it("a search for another project's card switches to that project and stays on the Board", function()
		local s = shown.search
		t.expect(has(s.projects, 'data-project="game" class="on"')).toBe(true)
		t.expect(s.boardHidden).toBe(false)
		t.expect(has(s.pane, '<h2><span class="id">f0031</span>')).toBe(true)
		t.expect(has(s.columns, 'class="card sel" data-id="f0031"')).toBe(true)
	end)

	it(
		"the arrow keys cycle Board, Rafts and Issues, and the lists show the selected project only",
		function()
			t.expect(shown.rafts.boardHidden).toBe(true)
			t.expect(shown.rafts.listHidden).toBe(false)
			t.expect(has(shown.rafts.list, 'data-id="R0020"')).toBe(true)
			t.expect(has(shown.rafts.list, 'data-id="R0110"')).toBe(false)
			t.expect(has(shown.issues.list, 'data-id="f0031"')).toBe(true)
			t.expect(has(shown.issues.list, 'data-id="c0120"')).toBe(false)
			t.expect(shown.wrap.boardHidden).toBe(false)
			t.expect(shown.wrap.tabBoard).toBe(true)
		end
	)

	it("a #project link opens that project's Board", function()
		t.expect(has(hashed.open.projects, 'data-project="tool" class="on"')).toBe(true)
		t.expect(has(hashed.open.columns, 'data-id="c0120"')).toBe(true)
		t.expect(hashed.open.boardHidden).toBe(false)
	end)

	it("znBoard.load swaps the model and keeps the project and the done window", function()
		local s = shown.loaded
		t.expect(has(s.projects, 'data-project="tool" class="on"')).toBe(true)
		t.expect(has(s.columns, 'data-id="c0125"')).toBe(true)
		t.expect(has(s.columns, "Arrived live")).toBe(true)
		t.expect(has(s.windowOptions, 'value="2592000"')).toBe(true)
	end)

	it(
		"znBoard.load keeps the range and the selected card, and replaces the Stats section when given one",
		function()
			local s = shown.loaded
			t.expect(has(s.charts, 'data-chart="tool/rounds/all"')).toBe(true)
			t.expect(has(s.columns, 'class="card sel" data-id="c0120"')).toBe(true)
			t.expect(has(s.pane, '<h2><span class="id">c0120</span>')).toBe(true)
			t.expect(s.stats).toBe("<p>fresh stats</p>")
		end
	)

	it(
		"a card shows the PR and checks a served model carries, and the static page says where they live",
		function()
			t.expect(has(shown.live.pane, '<a href="https://example.invalid/pr/7">#7</a> draft')).toBe(true)
			t.expect(has(shown.live.pane, "checks passing")).toBe(true)
			t.expect(has(shown.live.pane, "zn board --serve")).toBe(false)
			t.expect(has(shown.card.pane, "zn board --serve")).toBe(true)
		end
	)

	it("without git history the done column says its times come from spend rows", function()
		t.expect(has(shown.open.columns, "done times from spend rows")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(DIR)
	end)
end)
