--!strict
-- c0276: board.withVerdicts, the pure function that puts each claim's verdict on its card and puts lost work first
-- inside each bucket and band; and the page's own script, run by node against a fake DOM, which draws the mark. No
-- remote, no clock: the verdicts are given. Fixture under .cache/c0276-verdicts.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local DIR = ".cache/c0276-verdicts"

-- A model with the keys withVerdicts reads: two rafts, five issues, one project with one column of two bands.
local function item(id: string, extra: { [string]: any }?): any
	local base: { [string]: any } = {
		id = id,
		kind = if string.sub(id, 1, 1) == "R" then "raft" else "issue",
		type = "chore",
		label = "chore",
		title = `title {id}`,
		state = "backlog",
		design = "draft",
		status = "preparing",
		stage = "preparing",
		project = "game",
		column = "design",
		body = "",
		dependsOn = {},
		dependents = {},
		issues = {},
		spend = { minutes = 0, tokens = 0, added = 0, removed = 0, models = {} },
		rounds = { design = 0, code = 0 },
		blockedBy = {},
		single = false,
		topLevel = true,
		launched = false,
	}
	for k, v in (extra or {}) :: { [string]: any } do
		base[k] = v
	end
	return base
end
local function model(): any
	return {
		rafts = { item("R0010"), item("R0020"), item("R0030"), item("R0040") },
		issues = { item("c0010"), item("c0020"), item("c0030"), item("c0040"), item("c0050"), item("c0060") },
		views = {
			rafts = { ready = { "R0030", "R0040" }, ["not"] = { "R0010", "R0020" }, done = {} },
			issues = {
				ready = { "c0040", "c0060" },
				["not"] = { "c0010", "c0020", "c0030", "c0050" },
				done = {},
			},
		},
		columns = {
			game = {
				design = {
					{ raft = "R0010", ids = { "c0010", "c0020", "c0030" } },
					{ raft = nil, ids = { "c0050" } },
				},
			},
		},
		home = {},
		initialView = "board",
		projects = { { name = "game", root = "game/.tracker" } },
		problems = {},
	}
end
local function v(id: string, kind: string, silent: number): any
	return { id = id, kind = kind, silent = silent }
end
local function itemOf(m: any, id: string): any
	for _, list in { m.rafts, m.issues } do
		for _, i in list do
			if i.id == id then
				return i
			end
		end
	end
	error(`no {id}`)
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- The fake DOM: the page's script run against a model, then a card click and the list view.
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
["tab-board", "tab-rafts", "tab-issues", "search", "projects", "board", "columns", "charts", "window", "range", "as-of",
 "list", "pane", "board-data", "stats", "problems", "notes"].forEach(el);
els.board.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash: "" }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, navigator: {},
  console, JSON, Math, String, Array, Object, Number, Date, decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
const target = (sel, attr, value) => ({ closest: s => (s === sel ? { getAttribute: n => (n === attr ? value : null) } : null) });
const key = k => doc.dispatch("keydown", { key: k, target: {}, preventDefault() {} });
const out = { board: els.columns.innerHTML, notes: els.notes.innerHTML };
els.columns.dispatch("click", { target: target("button.card", "data-id", process.argv[3]), preventDefault() {} });
out.pane = els.pane.innerHTML;
key("ArrowRight"); out.rafts = els.list.innerHTML; out.notesOnRafts = els.notes.innerHTML;
els.search.value = "R0040"; els.search.dispatch("keydown", { key: "Enter", target: els.search }); out.raftPane = els.pane.innerHTML;
key("ArrowRight"); out.issues = els.list.innerHTML;
console.log(JSON.stringify(out));
]==]

local function ids(list: { string }): string
	return table.concat(list, ",")
end

return t.spec("c0276 board verdicts", function(it)
	it(
		"a claim that is not live gains heartbeat and minutes; live and unclaimed cards gain neither",
		function()
			local m = board.withVerdicts(model(), {
				v("c0010", "lost", 2130), -- 35.5 minutes: floored, never rounded up
				v("c0020", "parked", 2640),
				v("c0030", "stale", 1000), -- unconfirmed
				v("c0040", "live", 10),
				v("R0010", "nobeat", 600),
				v("R0020", "unknown", 0), -- unknown is shown as stale, never lost
			})
			t.expect(itemOf(m, "c0010").heartbeat).toBe("lost")
			t.expect(itemOf(m, "c0010").minutes).toBe(35)
			t.expect(itemOf(m, "c0020").heartbeat).toBe("parked")
			t.expect(itemOf(m, "c0020").minutes).toBe(44)
			t.expect(itemOf(m, "c0030").heartbeat).toBe("stale")
			t.expect(itemOf(m, "R0010").heartbeat).toBe("nobeat")
			t.expect(itemOf(m, "R0010").minutes).toBe(10)
			t.expect(itemOf(m, "R0020").heartbeat).toBe("stale")
			for _, id in { "c0040", "c0050" } do
				t.expect(itemOf(m, id).heartbeat).toBe(nil) -- live, and not claimed at all
				t.expect(itemOf(m, id).minutes).toBe(nil)
			end
		end
	)

	it("lost work comes first in each bucket and band, longest silent first, the rest as before", function()
		local m = board.withVerdicts(model(), {
			v("c0030", "lost", 3000),
			v("c0020", "lost", 2000),
			v("c0010", "parked", 5000),
			v("c0050", "stale", 9000),
		})
		-- c0030 (silent longest) before c0020, then c0010 and c0050 in the order they had; against id order
		t.expect(ids(m.views.issues["not"])).toBe("c0030,c0020,c0010,c0050")
		t.expect(ids(m.views.issues.ready)).toBe("c0040,c0060") -- nothing lost there yet
		t.expect(ids(m.views.rafts["not"])).toBe("R0010,R0020")
		-- the Ready bucket of each view is ordered too, rafts as well as issues: a lost readied raft is the case
		local ready = board.withVerdicts(model(), { v("R0040", "lost", 400), v("c0060", "lost", 400) })
		t.expect(ids(ready.views.rafts.ready)).toBe("R0040,R0030")
		t.expect(ids(ready.views.issues.ready)).toBe("c0060,c0040")
		t.expect(ids(ready.views.rafts["not"])).toBe("R0010,R0020")
		local doneBucket = model()
		doneBucket.views.rafts.done, doneBucket.views.issues.done = { "R0030", "R0040" }, { "c0040", "c0060" }
		doneBucket.views.rafts.ready, doneBucket.views.issues.ready = {}, {}
		local doneOrdered =
			board.withVerdicts(doneBucket, { v("R0040", "lost", 400), v("c0060", "lost", 400) })
		t.expect(ids(doneOrdered.views.rafts.done)).toBe("R0040,R0030")
		t.expect(ids(doneOrdered.views.issues.done)).toBe("c0060,c0040")
		local bands = m.columns.game.design
		t.expect(bands[1].raft).toBe("R0010") -- the bands keep their order
		t.expect(ids(bands[1].ids)).toBe("c0030,c0020,c0010")
		t.expect(bands[2].raft).toBe(nil)
		t.expect(ids(bands[2].ids)).toBe("c0050")
		-- equally silent lost work keeps the order it had
		local tie = board.withVerdicts(model(), { v("c0030", "lost", 900), v("c0020", "lost", 900) })
		t.expect(ids(tie.views.issues["not"])).toBe("c0020,c0030,c0010,c0050")
	end)

	it(
		"only lost work moves: parked, stale, unknown and nobeat keep their place whatever their silence",
		function()
			for _, kind in { "parked", "stale", "unknown", "nobeat" } do
				-- c0050 is last in its bucket and silent longer than the lost c0010: a rule that promoted its kind would move it
				local m = board.withVerdicts(model(), { v("c0010", "lost", 100), v("c0050", kind, 9000) })
				t.expect(ids(m.views.issues["not"])).toBe("c0010,c0020,c0030,c0050")
				local alone = board.withVerdicts(model(), { v("c0050", kind, 9000), v("c0030", kind, 9000) })
				t.expect(ids(alone.views.issues["not"])).toBe("c0010,c0020,c0030,c0050")
				-- and a lost card behind them still goes first
				local behind =
					board.withVerdicts(model(), { v("c0030", "lost", 100), v("c0010", kind, 9000) })
				t.expect(ids(behind.views.issues["not"])).toBe("c0030,c0010,c0020,c0050")
			end
		end
	)

	it("with no verdict the model is the same model, and the one it is given is never changed", function()
		local before = board.encode(model())
		t.expect(board.encode(board.withVerdicts(model(), {}))).toBe(before)
		t.expect(board.encode(board.withVerdicts(model(), { v("c0010", "live", 5), v("c9999", "lost", 5) })))
			.toBe(before) -- an id the board does not show is ignored
		local given = model()
		board.withVerdicts(given, { v("c0010", "lost", 5000), v("c0050", "lost", 6000) })
		t.expect(board.encode(given)).toBe(before)
		t.expect(itemOf(given, "c0010").heartbeat).toBe(nil)
	end)

	it(
		"the encoded model carries the marks in sorted-key JSON, for the page and the apps that lift it",
		function()
			local m = board.withVerdicts(model(), { v("c0010", "lost", 2130) })
			t.expect(has(board.encode(m), '"heartbeat":"lost"')).toBe(true)
			t.expect(has(board.encode(m), '"minutes":35')).toBe(true)
		end
	)

	it("the page draws lost Nm, parked, stale? and no beat on cards, list rows and the pane", function()
		if fs.isDir(DIR) then
			fs.removeDir(DIR)
		end
		fs.writeDir(DIR)
		local m = board.withVerdicts(model(), {
			v("c0010", "lost", 2130),
			v("c0020", "parked", 2640),
			v("c0030", "lost", 3000),
			v("c0060", "stale", 1000),
			v("c0050", "nobeat", 600),
			v("R0040", "lost", 400),
			v("R0010", "lost", 900),
		})
		-- the chrome of a real model (stats, windows, ranges, charts) from a one-item tracker; the cards are the ones above
		fs.writeDir(`{DIR}/game/.tracker/issues/c0099`)
		fs.writeDir(`{DIR}/z-nile`)
		fs.writeFile(`{DIR}/z-nile/projects.toml`, '[[project]]\nname = "game"\nroot = "game/.tracker"\n')
		fs.writeFile(
			`{DIR}/game/.tracker/issues/c0099/c0099.md`,
			"---\nid: c0099\ntype: chore\ntitle: x\nstatus: new-a-b-c\n---\n\n# c0099\n"
		)
		local real: any = board.collect(nil, DIR, { asOf = 1, refs = {}, worktrees = {}, dispatch = {} })
		real.notes = { "heartbeats unreadable; built without lost-work marks" }
		for _, key in { "rafts", "issues", "views", "columns", "projects" } do
			real[key] = m[key]
		end
		fs.writeFile(`{DIR}/page.html`, board.render(real, fs.readFile(`{board.TOP}/{board.MARKED_PATH}`)))
		fs.writeFile(`{DIR}/harness.js`, HARNESS)
		local ok, r = pcall(process.exec, "node", { `{DIR}/harness.js`, `{DIR}/page.html`, "c0010" })
		if not ok then
			error(`node is required for this spec: {r}`)
		end
		if not r.ok then
			error(r.stderr)
		end
		local out = serde.decode("json", r.stdout)
		local function cardOf(id: string): string
			return string.match(
				out.board,
				`<button type="button" class="card[^"]*" data%-id="{id}">.-</button>`
			) or ""
		end
		t.expect(has(cardOf("c0010"), ">lost 35m<")).toBe(true)
		t.expect(has(cardOf("c0020"), ">parked<")).toBe(true)
		t.expect(has(cardOf("c0030"), ">lost 50m<")).toBe(true)
		t.expect(has(out.issues, ">stale?<")).toBe(true) -- c0060 sits in a bucket, not a band
		t.expect(has(cardOf("c0050"), ">no beat<")).toBe(true)
		t.expect(has(cardOf("c0040"), 'class="mark')).toBe(false) -- not claimed: no mark
		t.expect(has(out.pane, '<span class="mark m-lost">lost 35m</span>')).toBe(true)
		t.expect(has(out.issues, '<span class="mark m-parked">parked</span>')).toBe(true)
		-- a lost raft is drawn in the Rafts list and in its pane heading, as an issue is
		t.expect(has(out.rafts, '<span class="mark m-lost">lost 6m</span>')).toBe(true)
		t.expect(has(out.raftPane, '<span class="mark m-lost">lost 6m</span>')).toBe(true)
		-- a note the engine set (a read that was tried and failed) is drawn above every view
		t.expect(has(out.notes, 'data-notes="1">heartbeats unreadable; built without lost-work marks</p>'))
			.toBe(true)
		t.expect(has(out.notesOnRafts, "heartbeats unreadable")).toBe(true) -- on the Rafts view too, not only the Board
		-- the lists keep the model's order too: lost first, longest silent first, against id order
		local function before(html: string, first: string, second: string): boolean
			local at1 = string.find(html, `data-id="{first}"`, 1, true) or 0
			local at2 = string.find(html, `data-id="{second}"`, 1, true) or 0
			return at1 > 0 and at1 < at2
		end
		t.expect(before(out.issues, "c0030", "c0010")).toBe(true)
		t.expect(before(out.rafts, "R0040", "R0030")).toBe(true)
		-- the band head draws its raft's own mark (a rafting claim stamps the raft only)
		local head = string.match(out.board, 'data%-raft="R0010">(.-)</div>') or ""
		t.expect(has(head, '<span class="mark m-lost">lost 15m</span>')).toBe(true)
		-- lost work leads its band in the drawn column: c0030 (silent longest) before c0010 although its id is higher
		local at30 = string.find(out.board, 'data-id="c0030"', 1, true) or 0
		local at10 = string.find(out.board, 'data-id="c0010"', 1, true) or 0
		local at20 = string.find(out.board, 'data-id="c0020"', 1, true) or 0
		t.expect(at30 > 0 and at30 < at10 and at10 < at20).toBe(true)
		fs.removeDir(DIR)
	end)
end)
