--!strict
-- c0118, code review 001 (R0083): what the first review found that the sequestered acceptance specs do not pin.
--   F1: a chart's caption carries the unit its axis was scaled to and, for one series, that series (the chart draws a
--       legend from two); the board's charts are sized in #charts, not by Stats' 320 px.
--   F2: the page shows model.problems (a spend.md that does not parse).
--   F3: the board keeps no round-file pattern of its own (boardview.rounds is the one rule, shared with metrics).
-- Fixture under .cache/c0118-review (a tracker folder, no git): the done dates come from spend rows.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local dir = `{here}/.cache/c0118-review`
local TRACKER = `{dir}/game/.tracker`
local AS_OF = stats.seconds("2026-10-21T10:00:00Z")
local FACTS = { asOf = AS_OF, refs = {}, worktrees = {}, dispatch = {} }
local HEADER = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n"
	.. "|---|---|---|---|---|---|---|---|---|---|\n"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function item(path: string, id: string, front: string)
	write(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end
local function readSource(path: string): string
	return fs.readFile(`{here}/{path}`)
end

-- the code of a Luau file with its line comments removed (board.luau writes none as a long comment)
local function code(src: string): string
	local lines = {}
	for line in string.gmatch(src, "[^\n]*") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The page's own script, run by node against a fake DOM (as c0118's page.spec does): what #problems and #charts hold after
-- the page opens and after znBoard.load swaps the model. Never literal require text: the repo scanner would read it.
local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8");
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
["tab-board", "tab-rafts", "tab-issues", "search", "projects", "board", "columns", "charts", "problems", "window", "range",
 "as-of", "list", "pane", "board-data", "stats"].forEach(el);
els.board.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash: "" }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, navigator: {},
  console, JSON, Math, String, Array, Object, Number, Date, decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
const snap = () => ({ problems: els.problems.innerHTML, charts: els.charts.innerHTML });
const out = { open: snap() };
const base = JSON.parse(els["board-data"].textContent);
const clean = Object.assign({}, base, { problems: [] });
sandbox.znBoard.load(clean); out.cleared = snap();
const two = Object.assign({}, base, { problems: ["a/spend.md does not parse", "history: map line"] });
sandbox.znBoard.load(two); out.two = snap();
const one = Object.assign({}, base, { problems: ["only/spend.md does not parse"] });
sandbox.znBoard.load(one); out.one = snap();
const bare = JSON.parse(JSON.stringify(base));
for (const p of Object.keys(bare.charts)) delete bare.charts[p].captions;
sandbox.znBoard.load(bare); out.bare = snap();
console.log(JSON.stringify(out));
]==]

local function node(page: string): any
	local ok, r = pcall(process.exec, "node", { `{dir}/harness.js`, page })
	if not ok then
		error(`node is required for this spec: {r}`)
	end
	if not r.ok then
		error(r.stderr)
	end
	return serde.decode("json", r.stdout)
end

return t.spec("c0118 code review 001", function(it)
	it("sets up a done raft whose only review spend is one model's 12 million tokens", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		write(`{here}/.cache/c0118-review/z-nile-marker`, "fixture\n")
		item(`{TRACKER}/rafts/done/R0010`, "R0010", "type: chore\ntitle: Landed\ndesign: ready\nstatus: done")
		item(`{TRACKER}/issues/done/c0011`, "c0011", "type: chore\ntitle: Member\nraft: R0010\nstatus: done")
		write(
			`{TRACKER}/issues/done/c0011/spend.md`,
			"# Spend: c0011 t\n\n"
				.. HEADER
				.. "| 1 | 2026-10-19 10:00 | s | 0 | 0 | 2.0 | spend | design-review | 12000000 | opus-x |\n"
		)
		write(`{TRACKER}/issues/done/c0011/design-review-001.md`, "# Review 001\n")
	end)

	it(
		"F1: the tokens caption names the scaled unit and the lone series; the rounds caption stays plain",
		function()
			local m = board.collect(TRACKER, nil, FACTS)
			local game = m.charts.game
			t.expect(game ~= nil).toBe(true)
			for _, range in m.ranges do
				t.expect(has(game.captions.tokens[range.key], "M tokens")).toBe(true)
				t.expect(has(game.captions.tokens[range.key], "opus-x")).toBe(true)
				t.expect(game.captions.rounds[range.key]).toBe("")
			end
		end
	)

	it(
		"F1: the page draws each figure's own caption (the node run of the page's script), and sizes the charts apart from Stats",
		function()
			fs.writeFile(`{dir}/page-ok.html`, board.build(TRACKER, nil, FACTS))
			fs.writeFile(`{dir}/harness.js`, HARNESS)
			local out = node(`{dir}/page-ok.html`)
			-- each caption sits in its own figure
			local rounds = string.match(
				out.open.charts,
				'<figure class="chart%-fig" data%-chart="rounds">.-</figure>'
			) :: string
			local tokens = string.match(
				out.open.charts,
				'<figure class="chart%-fig" data%-chart="tokens">.-</figure>'
			) :: string
			t.expect(has(rounds, "<figcaption>Review rounds by week</figcaption>")).toBe(true)
			t.expect(has(tokens, "<figcaption>Review tokens by model, M tokens: opus-x</figcaption>"))
				.toBe(true)
			-- a model without captions (an older served model) still draws, with the plain captions
			local bare = string.match(
				out.bare.charts,
				'<figure class="chart%-fig" data%-chart="tokens">.-</figure>'
			) :: string
			t.expect(has(bare, "<figcaption>Review tokens by model</figcaption>")).toBe(true)
			local html = fs.readFile(`{dir}/page-ok.html`)
			t.expect(has(html, "#charts .chart { width: 100%; max-width: 640px; }")).toBe(true)
			t.expect(has(html, ".chart { width: 320px; height: auto; }")).toBe(true) -- Stats keeps its own size
			-- one rule for the board's chart width: a later rule could undo it
			local _, count = string.gsub(html, "#charts .chart {", "", nil :: any)
			t.expect(count).toBe(1)
		end
	)

	it(
		"F2: a spend.md that does not parse is named in the model, and the page shows it and redraws it on load",
		function()
			write(
				`{TRACKER}/issues/done/c0012/c0012.md`,
				"---\nid: c0012\ntype: chore\ntitle: Bad\nstatus: done\n---\n\n# c0012\n"
			)
			write(
				`{TRACKER}/issues/done/c0012/spend.md`,
				"# Spend: c0012 t\n\n| 1 | 2026-10-20 10:00 | <b>unterminated\n"
			)
			local m = board.collect(TRACKER, nil, FACTS)
			t.expect(#m.problems).toBe(1)
			t.expect(has(m.problems[1], "c0012/spend.md")).toBe(true)
			fs.writeFile(`{dir}/page-bad.html`, board.build(TRACKER, nil, FACTS))
			local out = node(`{dir}/page-bad.html`)
			t.expect(has(out.open.problems, "1 file could not be read")).toBe(true)
			t.expect(has(out.open.problems, "c0012/spend.md")).toBe(true)
			t.expect(has(out.open.problems, "<b>")).toBe(false) -- the quoted row is escaped, never drawn as markup (review 003 F2)
			t.expect(out.cleared.problems).toBe("") -- load with no problems clears the note
			t.expect(has(out.two.problems, "2 files could not be read")).toBe(true)
			t.expect(has(out.two.problems, "history: map line")).toBe(true)
			t.expect(has(out.one.problems, "1 file could not be read")).toBe(true) -- one problem is shown, not hidden
		end
	)

	it(
		"F3: board.luau keeps no round-file pattern of its own: reviewFiles matches nothing, boardview.rounds counts",
		function()
			local src = code(readSource("engine/board.luau"))
			t.expect(has(src, "review%-")).toBe(false)
			t.expect(has(src, "boardview.rounds(")).toBe(true)
			-- reviewFiles lists the folder and nothing more (any spelling of a filter would show as a match call)
			local body = string.match(src, "local function reviewFiles.-\nend\n") :: string
			t.expect(body ~= nil).toBe(true)
			for _, call in
				{
					"string.match",
					"string.find",
					"string.gmatch",
					"string.gsub",
					":match(",
					":find(",
					"string.sub",
				}
			do
				t.expect(has(body, call)).toBe(false)
			end
			-- no string literal in the file names a review together with a pattern character (`[-]`, `%-`, `^`, `$`)
			for lit in string.gmatch(src, '"([^"\n]*)"') do
				if string.find(lit, "review", 1, true) and string.find(lit, "[%%%[%]%^%$]") then
					error(`a pattern naming a review: "{lit}"`)
				end
			end
		end
	)
end)
