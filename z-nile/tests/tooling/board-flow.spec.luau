--!strict
-- f0422: the Flow view and the tributaries: the bands and the model fields behind them, the page (opened in a node harness)
-- and its tributary chips. Fast: it runs in both gates (board.spec.luau, which holds the older board cases, is in slow.tsv).
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- The checkout's top: MARKED_PATH and the template are relative to it. Fixtures stay under this home's .cache.
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- f0422: the Flow page. Opens the page with a hash, runs steps (click a flow card, a chip, a Board card; key; search;
-- tab; load) and prints a snapshot after each. Never literal require text: the repo scanner would read it.
local FLOW_HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), hash = process.argv[3] || "", raw = JSON.parse(process.argv[4] || "[]"), steps = Array.isArray(raw) ? raw : [];
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
["tab-flow", "tab-board", "tab-rafts", "tab-issues", "search", "projects", "board", "columns", "charts", "problems",
 "window", "range", "as-of", "list", "pane", "board-data", "stats", "flow"].forEach(el);
els.board.setAttribute("hidden", ""); els.flow.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, navigator: {},
  console, JSON, Math, String, Array, Object, Number, Date, decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
const pick = (h, re) => { const m = h.match(re); return m ? m[1] : null; };
const target = (sel, id) => ({ closest: s => (s === sel ? { getAttribute: n => (n === "data-id" ? id : null) } : null) });
const snap = () => ({ flow: els.flow.innerHTML, columns: els.columns.innerHTML, pane: els.pane.innerHTML, list: els.list.innerHTML,
  flowHidden: els.flow.hasAttribute("hidden"), boardHidden: els.board.hasAttribute("hidden"), listHidden: els.list.hasAttribute("hidden"),
  tabFlow: els["tab-flow"].classList.contains("on"), tabBoard: els["tab-board"].classList.contains("on"), hash: sandbox.location.hash,
  flowSel: pick(els.flow.innerHTML, /class="card sel" data-id="([^"]*)"/), boardSel: pick(els.columns.innerHTML, /class="card sel" data-id="([^"]*)"/) });
const out = [snap()];
for (const st of steps) {
  if (st.k === "flowcard") els.flow.dispatch("click", { target: target("div.card", st.id), preventDefault() {} });
  else if (st.k === "chip") els.flow.dispatch("click", { target: target("a.jump", st.id), preventDefault() {} });
  else if (st.k === "boardcard") els.columns.dispatch("click", { target: target("button.card", st.id), preventDefault() {} });
  else if (st.k === "key") doc.dispatch("keydown", { key: st.key, target: {}, preventDefault() {} });
  else if (st.k === "search") { els.search.value = st.q; els.search.dispatch("keydown", { key: "Enter", target: els.search }); }
  else if (st.k === "tab") els["tab-" + st.name].dispatch("click", {});
  else if (st.k === "tributary") els.flow.dispatch("click", { target: { closest: s => (s === "button.tr" ? { getAttribute: n => (n === "data-tributary" ? st.name : null) } : null) }, preventDefault() {} });
  else if (st.k === "project") els.projects.dispatch("click", { target: { closest: s => (s === "button[data-project]" ? { getAttribute: n => (n === "data-project" ? st.name : null) } : null) } });
  else if (st.k === "load") sandbox.znBoard.load(JSON.parse(els["board-data"].textContent));
  out.push(snap());
}
console.log(JSON.stringify(out));
]==]

return t.spec("board flow", function(it)
	-- f0422: the flow view and the band, unblocks and waitsOn fields, on a small tracker
	it(
		"flow puts open units in bands, most unblocking first, and leaves done and closed items out",
		function()
			local dir = ".cache/board-unit-flow"
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			local function doc(path: string, id: string, front: string)
				fs.writeDir(path)
				fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
			end
			local base = `{dir}/tracker`
			-- R0009 is done; R0010 waits on nothing; R0011 on R0010; R0012 on R0011 and the raftless c0020
			doc(`{base}/rafts/done/R0009`, "R0009", "type: chore\ntitle: Landed\nstatus: done")
			doc(`{base}/issues/done/c0009`, "c0009", "type: chore\ntitle: Landed\nraft: R0009\nstatus: done")
			doc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: First")
			doc(`{base}/issues/c0010`, "c0010", "type: chore\ntitle: First\nraft: R0010\ndepends_on: [c0009]")
			doc(`{base}/rafts/R0011`, "R0011", "type: feature\ntitle: Second")
			doc(
				`{base}/issues/c0011`,
				"c0011",
				"type: feature\ntitle: Second\nraft: R0011\ndepends_on: [c0010]"
			)
			doc(`{base}/rafts/R0012`, "R0012", "type: feature\ntitle: Third")
			doc(
				`{base}/issues/c0012`,
				"c0012",
				"type: feature\ntitle: Third\nraft: R0012\ndepends_on: [c0011, c0020]"
			)
			-- raftless: c0020 waits on nothing; c0021 only on the done c0009; c0022 on the raft R0012 and on c0020;
			-- c0023 is closed (won't do) and c0024 depends on it
			doc(`{base}/issues/c0020`, "c0020", "type: defect\ntitle: Loose")
			doc(`{base}/issues/c0021`, "c0021", "type: defect\ntitle: Loose done dep\ndepends_on: [c0009]")
			doc(`{base}/issues/c0022`, "c0022", "type: chore\ntitle: Late\ndepends_on: [c0012, c0020]")
			doc(
				`{base}/issues/c0023`,
				"c0023",
				"type: chore\ntitle: Dropped\nstatus: closed-quiet-copper-falcon\nwont_do: no"
			)
			doc(`{base}/issues/c0024`, "c0024", "type: chore\ntitle: After dropped\ndepends_on: [c0023]")
			local m = board.collect(base)
			fs.removeDir(dir)
			t.expect(m.flow).toEqual({
				bands = {
					{ n = 0, ids = { "R0010", "c0020", "c0021", "c0024" } },
					{ n = 1, ids = { "R0011" } },
					{ n = 2, ids = { "R0012" } },
					{ n = 3, ids = { "c0022" } },
				},
			})
			local function find(id: string): any
				for _, r in m.rafts do
					if r.id == id then
						return r
					end
				end
				for _, i in m.issues do
					if i.id == id then
						return i
					end
				end
				return nil
			end
			t.expect(find("R0010").band).toBe(0)
			t.expect(find("R0010").unblocks).toBe(3)
			t.expect(find("R0012").waitsOn).toEqual({ "R0011", "c0020" })
			t.expect(find("c0020").unblocks).toBe(2)
			t.expect(find("c0022").waitsOn).toEqual({ "R0012", "c0020" })
			t.expect(find("c0022").band).toBe(3)
			t.expect(find("c0021").waitsOn).toEqual({})
			-- done, closed-dependent and member issues are not units
			t.expect(find("R0009").band).toBe(nil)
			t.expect(find("R0009").unblocks).toBe(0)
			t.expect(find("c0010").band).toBe(nil)
			t.expect(find("c0009").band).toBe(nil)
			t.expect(find("c0024").band).toBe(0)
		end
	)

	-- f0422: fixtures for the model and page cases below
	local function fdoc(path: string, id: string, front: string)
		fs.writeDir(path)
		fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
	end
	local function freshDir(dir: string)
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
	end
	local function modelItem(m: board.Model, id: string): any
		for _, r in m.rafts do
			if r.id == id then
				return r
			end
		end
		for _, i in m.issues do
			if i.id == id then
				return i
			end
		end
		return nil
	end
	-- the page for a tracker folder, written beside it with the harness
	local function pageOf(dir: string): string
		local template = board.TEMPLATE_PATH
		board.TEMPLATE_PATH = `{TOP}/{template}`
		local ok, html =
			pcall(board.render, board.collect(`{dir}/tracker`), fs.readFile(`{TOP}/{board.MARKED_PATH}`))
		board.TEMPLATE_PATH = template
		if not ok then
			error(html, 0)
		end
		fs.writeFile(`{dir}/page.html`, html)
		fs.writeFile(`{dir}/flow-harness.js`, FLOW_HARNESS)
		return `{dir}/page.html`
	end
	local function runPage(dir: string, hash: string, steps: { any }): { any }
		local ok, r = pcall(
			process.exec,
			"node",
			{ `{dir}/flow-harness.js`, `{dir}/page.html`, hash, serde.encode("json", steps) }
		)
		if not ok then
			error(`node is required for this spec (preinstalled on GitHub runners): {r}`)
		end
		if not r.ok then
			error(r.stderr)
		end
		return serde.decode("json", r.stdout)
	end
	local function count(text: string, needle: string): number
		local n, at = 0, 1
		while true do
			local found = string.find(text, needle, at, true)
			if not found then
				return n
			end
			n += 1
			at = found + #needle
		end
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	it(
		"flow waits: a raftless issue on a member of an active raft, and one wait per raft however many members",
		function()
			local dir = ".cache/board-unit-flow-members"
			freshDir(dir)
			local base = `{dir}/tracker`
			fdoc(`{base}/rafts/active/R0013`, "R0013", "type: chore\ntitle: Active\ndesign: ready")
			fdoc(`{base}/issues/active/c0013`, "c0013", "type: chore\ntitle: Member\nraft: R0013")
			fdoc(`{base}/issues/c0025`, "c0025", "type: chore\ntitle: After member\ndepends_on: [c0013]")
			fdoc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: Two members")
			fdoc(`{base}/issues/c0010`, "c0010", "type: chore\ntitle: One\nraft: R0010")
			fdoc(`{base}/issues/c0014`, "c0014", "type: chore\ntitle: Two\nraft: R0010")
			fdoc(
				`{base}/issues/c0026`,
				"c0026",
				"type: chore\ntitle: Raftless on both\ndepends_on: [c0010, c0014]"
			)
			fdoc(`{base}/rafts/R0014`, "R0014", "type: chore\ntitle: Raft on both")
			fdoc(
				`{base}/issues/c0015`,
				"c0015",
				"type: chore\ntitle: Third\nraft: R0014\ndepends_on: [c0010, c0014]"
			)
			local m = board.collect(base)
			fs.removeDir(dir)
			t.expect(modelItem(m, "c0025").waitsOn).toEqual({ "R0013" })
			t.expect(modelItem(m, "c0025").band).toBe(1)
			t.expect(modelItem(m, "c0026").waitsOn).toEqual({ "R0010" })
			t.expect(modelItem(m, "R0014").waitsOn).toEqual({ "R0010" })
			t.expect(modelItem(m, "R0010").unblocks).toBe(2)
			for _, raft in m.rafts do
				if raft.state ~= "done" then
					t.expect(raft.band == 0).toBe(raft.topLevel)
				end
			end
			t.expect(#m.problems).toBe(0)
		end
	)

	it("a dependency cycle is a problem naming its members, and the units still get a band", function()
		local dir = ".cache/board-unit-flow-cycle"
		freshDir(dir)
		local base = `{dir}/tracker`
		fdoc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: In the cycle")
		fdoc(
			`{base}/issues/c0010`,
			"c0010",
			"type: chore\ntitle: Waits on X\nraft: R0010\ndepends_on: [c0030]"
		)
		fdoc(`{base}/issues/c0011`, "c0011", "type: chore\ntitle: Other member\nraft: R0010")
		fdoc(`{base}/issues/c0030`, "c0030", "type: chore\ntitle: X\ndepends_on: [c0011]")
		fdoc(`{base}/issues/c0031`, "c0031", "type: chore\ntitle: Behind\ndepends_on: [c0030]")
		pageOf(dir)
		local m = board.collect(base)
		t.expect(m.problems).toEqual({ "dependency cycle among: R0010, c0030" })
		t.expect(modelItem(m, "R0010").band).toBe(1)
		t.expect(modelItem(m, "c0030").band).toBe(1)
		t.expect(modelItem(m, "c0031").band).toBe(1)
		-- the Flow view shows the problems note too
		local shown = runPage(dir, "", {})
		t.expect(has(shown[1].flow, "1 dependency cycle: R0010, c0030")).toBe(true)
		t.expect(has(shown[1].flow, 'data-cycles="1"')).toBe(true)
		t.expect(has(shown[1].flow, "could not be read")).toBe(false) -- a cycle is not an unreadable file
		fs.removeDir(dir)
	end)

	-- R0010 (member c0010) is workable; R0011 waits on it; c0020 is raftless with a hostile title; c0022 waits on R0011 and c0020
	local function flowPageFixture(dir: string)
		freshDir(dir)
		local base = `{dir}/tracker`
		fdoc(`{base}/rafts/done/R0009`, "R0009", "type: chore\ntitle: Landed\nstatus: done")
		fdoc(`{base}/issues/done/c0009`, "c0009", "type: chore\ntitle: Landed\nraft: R0009\nstatus: done")
		fdoc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: First")
		fdoc(`{base}/issues/c0010`, "c0010", "type: chore\ntitle: First member\nraft: R0010")
		fdoc(`{base}/rafts/R0011`, "R0011", "type: feature\ntitle: Second")
		fdoc(
			`{base}/issues/c0011`,
			"c0011",
			"type: feature\ntitle: Second member\nraft: R0011\ndepends_on: [c0010]"
		)
		fdoc(`{base}/issues/c0020`, "c0020", "type: defect\ntitle: <img src=x onerror=alert(1)>")
		fdoc(`{base}/issues/c0022`, "c0022", "type: chore\ntitle: Late\ndepends_on: [c0011, c0020]")
		fs.writeFile(`{dir}/marker`, "x")
		pageOf(dir)
	end

	it("the page opens on Flow with headings, counts, badges and chips, and escapes titles", function()
		local dir = ".cache/board-unit-flow-page"
		flowPageFixture(dir)
		local shown = runPage(dir, "", {})
		local open = shown[1]
		t.expect(open.tabFlow).toBe(true)
		t.expect(open.flowHidden).toBe(false)
		t.expect(open.boardHidden).toBe(true)
		t.expect(open.listHidden).toBe(true)
		t.expect(open.flowSel).toBe("R0010")
		local flow = open.flow
		t.expect(has(flow, '<h3>Workable now <span class="n">2</span></h3>')).toBe(true)
		t.expect(has(flow, '<h3>After 1 step <span class="n">1</span></h3>')).toBe(true)
		t.expect(has(flow, '<h3>After 2 steps <span class="n">1</span></h3>')).toBe(true)
		-- three cards unblock something (R0010: 2, R0011: 1, c0020: 1); c0022 unblocks nothing and has no badge
		t.expect(count(flow, 'class="unb"')).toBe(3)
		t.expect(has(flow, '<span class="unb">unblocks 2</span>')).toBe(true)
		-- chips only above band 0: R0011 waits on R0010; c0022 on R0011 and c0020, as links
		local firstBand = string.match(flow, '^(.-)data%-band="1"') or ""
		t.expect(has(firstBand, "chip jump")).toBe(false)
		t.expect(count(flow, 'class="chip jump"')).toBe(3)
		t.expect(has(flow, 'waits on</span> <a class="chip jump" data-id="R0010" href="#R0010">R0010</a>'))
			.toBe(true)
		-- the hostile title is text
		t.expect(has(flow, "&lt;img src=x onerror=alert(1)&gt;")).toBe(true)
		t.expect(has(flow, "<img")).toBe(false)
		fs.removeDir(dir)
	end)

	it(
		"flow cards select, arrows move within Flow, chips jump, and a load keeps the view and the selection",
		function()
			local dir = ".cache/board-unit-flow-nav"
			flowPageFixture(dir)
			local shown = runPage(dir, "", {
				{ k = "key", key = "ArrowDown" },
				{ k = "key", key = "ArrowDown" },
				{ k = "key", key = "ArrowUp" },
				{ k = "flowcard", id = "R0011" },
				{ k = "load" },
				{ k = "chip", id = "c0020" },
				{ k = "boardcard", id = "c0010" },
			})
			t.expect(shown[2].flowSel).toBe("c0020")
			t.expect(shown[3].flowSel).toBe("R0011")
			t.expect(shown[4].flowSel).toBe("c0020")
			t.expect(shown[4].flowHidden).toBe(false)
			t.expect(has(shown[4].pane, '<span class="id">c0020</span>')).toBe(true)
			t.expect(shown[5].flowSel).toBe("R0011")
			t.expect(has(shown[5].pane, '<span class="id">R0011</span>')).toBe(true)
			t.expect(shown[6].flowSel).toBe("R0011")
			t.expect(shown[6].flowHidden).toBe(false)
			t.expect(shown[7].flowSel).toBe("c0020")
			-- a click on a Board card while Flow shows switches to Board and selects that card
			t.expect(shown[8].boardHidden).toBe(false)
			t.expect(shown[8].flowHidden).toBe(true)
			t.expect(shown[8].boardSel).toBe("c0010")
			t.expect(has(shown[8].pane, '<span class="id">c0010</span>')).toBe(true)
			fs.removeDir(dir)
		end
	)

	it(
		"a search or #id link keeps Flow for a unit and opens the Board for a raft member, else the lists",
		function()
			local dir = ".cache/board-unit-flow-go"
			flowPageFixture(dir)
			local shown = runPage(dir, "", {
				{ k = "search", q = "R0011" },
				{ k = "tab", name = "flow" },
				{ k = "search", q = "c0010" },
				{ k = "tab", name = "flow" },
				{ k = "search", q = "c0009" },
			})
			t.expect(shown[2].flowHidden).toBe(false)
			t.expect(shown[2].flowSel).toBe("R0011")
			t.expect(shown[4].boardHidden).toBe(false)
			t.expect(shown[4].boardSel).toBe("c0010")
			t.expect(shown[6].flowHidden).toBe(true)
			t.expect(shown[6].boardHidden).toBe(true)
			t.expect(shown[6].listHidden).toBe(false)
			-- a hash link to a raft member opens the Board with its card selected
			local linked = runPage(dir, "#c0010", {})[1]
			t.expect(linked.boardHidden).toBe(false)
			t.expect(linked.boardSel).toBe("c0010")
			fs.removeDir(dir)
		end
	)

	-- f0422 slice 2: alpha lists R0009 (done), R0010 (active, so in flight) and c0020; beta lists R0011, R0012 (no
	-- members), c0021 (an active raftless issue) and c0022, which waits on R0011 through its member c0011.
	local TRIBUTARIES = '[[tributary]]\nname = "alpha"\npurpose = "The first body."\n\n'
		.. '[[tributary]]\nname = "beta"\npurpose = "The <b>second</b> body."\n'
	local function tributaryFixture(dir: string)
		freshDir(dir)
		local base = `{dir}/tracker`
		fdoc(`{base}/rafts/done/R0009`, "R0009", "type: chore\ntitle: Landed\nstatus: done\ntributary: alpha")
		fdoc(`{base}/issues/done/c0009`, "c0009", "type: chore\ntitle: Landed\nraft: R0009\nstatus: done")
		fdoc(
			`{base}/rafts/active/R0010`,
			"R0010",
			"type: chore\ntitle: Running\ndesign: ready\nstatus: active-a-b-c\ntributary: alpha"
		)
		fdoc(
			`{base}/issues/active/c0010`,
			"c0010",
			"type: chore\ntitle: Running member\nraft: R0010\nstatus: active-a-b-c"
		)
		fdoc(`{base}/rafts/R0011`, "R0011", "type: chore\ntitle: Not started\ntributary: beta")
		fdoc(`{base}/issues/c0011`, "c0011", "type: chore\ntitle: Member\nraft: R0011\ntributary: alpha")
		fdoc(`{base}/rafts/R0012`, "R0012", "type: chore\ntitle: Empty raft\ntributary: beta")
		fdoc(`{base}/issues/c0020`, "c0020", "type: chore\ntitle: Raftless\ntributary: alpha")
		fdoc(
			`{base}/issues/active/c0021`,
			"c0021",
			"type: chore\ntitle: Raftless running\nstatus: active-d-e-f\ntributary: beta"
		)
		fdoc(
			`{base}/issues/c0022`,
			"c0022",
			"type: chore\ntitle: After the member\ndepends_on: [c0011]\ntributary: beta"
		)
		fs.writeFile(`{base}/tributaries.toml`, TRIBUTARIES)
		pageOf(dir)
	end

	it("the model gives each unit its tributary and each tributary four counts", function()
		local dir = ".cache/board-unit-trib-model"
		tributaryFixture(dir)
		local m = board.collect(`{dir}/tracker`)
		fs.removeDir(dir)
		t.expect(modelItem(m, "R0010").tributary).toBe("alpha")
		t.expect(modelItem(m, "c0010").tributary).toBe("alpha") -- a member is in its raft's
		t.expect(modelItem(m, "c0022").tributary).toBe("beta")
		t.expect(modelItem(m, "R0010").inFlight).toBe(true)
		t.expect(modelItem(m, "c0021").inFlight).toBe(true)
		t.expect(modelItem(m, "R0011").inFlight).toBe(false)
		t.expect(modelItem(m, "R0009").inFlight).toBe(false) -- a done raft is not in flight
		local rows = m.tributaries.tracker
		t.expect(#rows).toBe(2)
		-- waiting for the owner's approval is 0 until a fact in the inputs says so (a later slice)
		t.expect(rows[1]).toEqual({
			name = "alpha",
			purpose = "The first body.",
			implicit = false,
			done = 1,
			inFlight = 1,
			waiting = 0,
			notStarted = 1,
		})
		t.expect(rows[2].name).toBe("beta")
		t.expect(rows[2].done).toBe(0)
		t.expect(rows[2].inFlight).toBe(1)
		t.expect(rows[2].notStarted).toBe(2) -- R0011 and c0022; the empty raft R0012 is no work
		t.expect(modelItem(m, "c0011").tributary).toBe("beta") -- a member takes its raft's, whatever its own line says
		t.expect(modelItem(m, "R0012").work).toBe(false)
		t.expect(modelItem(m, "R0011").work).toBe(true)
		t.expect(modelItem(m, "c0011").work).toBe(false)
		t.expect(#m.problems).toBe(0)
	end)

	local NO_FACTS: any = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }

	it(
		"with no tributaries file a project has unsorted and earlier-work, shown as a chip only while open units are unsorted",
		function()
			local dir = ".cache/board-unit-trib-none"
			freshDir(dir)
			local base = `{dir}/tracker`
			fdoc(`{base}/issues/c0020`, "c0020", "type: chore\ntitle: Raftless")
			fdoc(`{base}/issues/done/c0021`, "c0021", "type: chore\ntitle: Landed\nstatus: done")
			fdoc(
				`{base}/issues/done/c0022`,
				"c0022",
				"type: chore\ntitle: Landed, named\nstatus: done\ntributary: kept"
			)
			fs.writeFile(`{base}/tributaries.toml`, '[[tributary]]\nname = "kept"\npurpose = "Kept."\n')
			local m = board.collect(base)
			t.expect(modelItem(m, "c0020").tributary).toBe("unsorted")
			t.expect(modelItem(m, "c0021").tributary).toBe("earlier-work")
			t.expect(modelItem(m, "c0022").tributary).toBe("kept") -- a done unit with a line stays where it is named
			local rows = m.tributaries.tracker
			t.expect(#rows).toBe(3)
			t.expect(rows[1].name).toBe("kept")
			t.expect(rows[1].done).toBe(1)
			t.expect(rows[2].name).toBe("unsorted")
			t.expect(rows[2].notStarted).toBe(1)
			t.expect(rows[3].name).toBe("earlier-work")
			t.expect(rows[3].done).toBe(1)
			pageOf(dir)
			local flow = runPage(dir, "", {})[1].flow
			t.expect(has(flow, ">unsorted 0/0/0/1</button>")).toBe(true)
			t.expect(has(flow, ">earlier-work")).toBe(false) -- nothing open to filter to
			fs.removeFile(`{base}/tributaries.toml`)
			local bare = board.collect(base)
			t.expect(#bare.tributaries.tracker).toBe(3 - 1) -- unsorted and earlier-work; c0022's line names nothing now
			t.expect(#bare.problems).toBe(1)
			t.expect(has(bare.problems[1], "c0022.md") and has(bare.problems[1], "does not define"))
				.toBe(true)
			fs.removeDir(dir)
		end
	)

	it(
		"a malformed file, a units key and a tributary: line that names nothing are problems naming their file",
		function()
			local dir = ".cache/board-unit-trib-bad"
			freshDir(dir)
			local base = `{dir}/tracker`
			fdoc(`{base}/issues/c0020`, "c0020", "type: chore\ntitle: Raftless\ntributary: nope")
			fs.writeFile(`{base}/tributaries.toml`, "[[tributary")
			local bad = board.collect(base)
			t.expect(#bad.problems).toBe(1)
			t.expect(has(bad.problems[1], "tributaries.toml")).toBe(true)
			fs.writeFile(
				`{base}/tributaries.toml`,
				'[[tributary]]\nname = "a"\npurpose = "A."\nunits = ["c0020"]\n'
			)
			local units = board.collect(base)
			t.expect(#units.problems).toBe(1)
			t.expect(has(units.problems[1], "membership is the unit's own tributary: line")).toBe(true)
			fs.writeFile(`{base}/tributaries.toml`, '[[tributary]]\nname = "a"\npurpose = "A."\n')
			local named = board.collect(base)
			fs.removeDir(dir)
			t.expect(#named.problems).toBe(1)
			t.expect(has(named.problems[1], "c0020.md")).toBe(true)
			t.expect(has(named.problems[1], "tributary: nope")).toBe(true)
			t.expect(modelItem(named, "c0020").tributary).toBe("unsorted")
		end
	)

	it(
		"a raft is in flight only when it is in active/: a leftover branch on a backlog or done raft does not count",
		function()
			local dir = ".cache/board-unit-trib-refs"
			tributaryFixture(dir)
			local facts: any = {
				asOf = nil,
				refs = {
					{ name = "origin/R0011-left", at = 5 },
					{ name = "origin/R0009-left", at = 5 },
					{ name = "origin/R0010-run", at = 5 },
				},
				worktrees = {},
				dispatch = {},
			}
			local m = board.collect(`{dir}/tracker`, nil, facts)
			fs.removeDir(dir)
			t.expect(modelItem(m, "R0011").launched).toBe(true) -- the branch is real, and still no flight
			t.expect(modelItem(m, "R0011").inFlight).toBe(false)
			t.expect(modelItem(m, "R0009").inFlight).toBe(false)
			t.expect(modelItem(m, "R0010").inFlight).toBe(true)
			t.expect(m.tributaries.tracker[2].inFlight).toBe(1) -- beta: c0021 only
			t.expect(m.tributaries.tracker[1].done).toBe(1)
		end
	)

	it("a member's raft in another project gives it its tributary, whichever project comes first", function()
		local dir = ".cache/board-unit-trib-cross"
		freshDir(dir)
		fs.writeDir(`{dir}/z-nile`)
		fs.writeFile(
			`{dir}/z-nile/projects.toml`,
			'[[project]]\nname = "one"\nroot = "one/.tracker"\n\n[[project]]\nname = "two"\nroot = "two/.tracker"\n'
		)
		fdoc(`{dir}/two/.tracker/rafts/R0030`, "R0030", "type: chore\ntitle: Raft in two\ntributary: z")
		fdoc(`{dir}/one/.tracker/issues/c0020`, "c0020", "type: chore\ntitle: Member in one\nraft: R0030")
		fs.writeFile(`{dir}/two/.tracker/tributaries.toml`, '[[tributary]]\nname = "z"\npurpose = "Z."\n')
		local m = board.collect(nil, dir, NO_FACTS)
		fs.removeDir(dir)
		t.expect(modelItem(m, "c0020").tributary).toBe("z")
		t.expect(modelItem(m, "R0030").tributary).toBe("z")
		t.expect(#m.tributaries.one).toBe(0) -- a member is no unit of its own project
		t.expect(m.tributaries.two[1].name).toBe("z")
		t.expect(m.tributaries.two[1].notStarted).toBe(1) -- the raft counts once, and is work through its member in project one
	end)

	it(
		"a search or link to a unit the filter hides clears the filter and stays on Flow; to another project it resets",
		function()
			local dir = ".cache/board-unit-trib-go"
			tributaryFixture(dir)
			local shown = runPage(dir, "", {
				{ k = "tributary", name = "beta" },
				{ k = "search", q = "c0020" },
			})
			t.expect(shown[3].flowHidden).toBe(false)
			t.expect(shown[3].flowSel).toBe("c0020")
			t.expect(has(shown[3].flow, 'class="chip tr on" data-tributary=""')).toBe(true) -- All again
			t.expect(has(shown[3].flow, 'data-id="R0010"')).toBe(true)
			-- a hash link to a raft with no members is not on Flow at all: it opens in the Rafts list
			local empty = runPage(dir, "#R0012", {})[1]
			t.expect(empty.flowHidden).toBe(true)
			t.expect(empty.listHidden).toBe(false)
			t.expect(has(empty.list, 'data-id="R0012"')).toBe(true)
			t.expect(has(empty.pane, "Empty raft")).toBe(true)
			local searched = runPage(dir, "", { { k = "search", q = "R0012" } })[2]
			t.expect(searched.flowHidden).toBe(true)
			t.expect(has(searched.pane, "Empty raft")).toBe(true)
			fs.removeDir(dir)
		end
	)

	it("a search for a unit of another project resets the filter", function()
		local dir = ".cache/board-unit-trib-go2"
		freshDir(dir)
		fs.writeDir(`{dir}/z-nile`)
		fs.writeFile(
			`{dir}/z-nile/projects.toml`,
			'[[project]]\nname = "one"\nroot = "one/.tracker"\n\n[[project]]\nname = "two"\nroot = "two/.tracker"\n'
		)
		fdoc(`{dir}/one/.tracker/issues/c0020`, "c0020", "type: chore\ntitle: In one\ntributary: x")
		fdoc(`{dir}/one/.tracker/issues/c0021`, "c0021", "type: chore\ntitle: Also in one\ntributary: y")
		fs.writeFile(
			`{dir}/one/.tracker/tributaries.toml`,
			'[[tributary]]\nname = "x"\npurpose = "X."\n\n[[tributary]]\nname = "y"\npurpose = "Y."\n'
		)
		fdoc(`{dir}/two/.tracker/issues/f0030`, "f0030", "type: feature\ntitle: In two")
		local template = board.TEMPLATE_PATH
		board.TEMPLATE_PATH = `{TOP}/{template}`
		local ok, html =
			pcall(board.render, board.collect(nil, dir, NO_FACTS), fs.readFile(`{TOP}/{board.MARKED_PATH}`))
		board.TEMPLATE_PATH = template
		if not ok then
			error(html, 0)
		end
		fs.writeFile(`{dir}/page.html`, html)
		fs.writeFile(`{dir}/flow-harness.js`, FLOW_HARNESS)
		local shown = runPage(
			dir,
			"",
			{ { k = "tributary", name = "y" }, { k = "search", q = "f0030" }, { k = "search", q = "c0020" } }
		)
		fs.removeDir(dir)
		t.expect(has(shown[3].flow, 'data-id="f0030"')).toBe(true)
		t.expect(has(shown[3].flow, 'class="chip tr on" data-tributary=""')).toBe(true) -- reset to All with the project
		t.expect(has(shown[4].flow, 'data-id="c0020"') and has(shown[4].flow, 'data-id="c0021"')).toBe(true)
	end)

	it("the arrow keys move through the filtered cards only, and stop at the last", function()
		local dir = ".cache/board-unit-trib-arrows"
		tributaryFixture(dir)
		local shown = runPage(dir, "", {
			{ k = "tributary", name = "beta" },
			{ k = "key", key = "ArrowDown" },
			{ k = "key", key = "ArrowDown" },
			{ k = "key", key = "ArrowDown" },
			{ k = "key", key = "ArrowUp" },
		})
		fs.removeDir(dir)
		t.expect(shown[2].flowSel).toBe("c0021") -- beta's in-flight card first
		t.expect(shown[3].flowSel).toBe("R0011")
		t.expect(shown[4].flowSel).toBe("c0022")
		t.expect(shown[5].flowSel).toBe("c0022") -- the last
		t.expect(shown[6].flowSel).toBe("R0011")
	end)

	it("a chip's in-flight plus not-started is the number of Flow cards under its filter", function()
		local dir = ".cache/board-unit-trib-sum"
		tributaryFixture(dir)
		local m = board.collect(`{dir}/tracker`)
		local shown =
			runPage(dir, "", { { k = "tributary", name = "alpha" }, { k = "tributary", name = "beta" } })
		fs.removeDir(dir)
		for n, row in m.tributaries.tracker do
			local cards = count(shown[n + 1].flow, 'role="button"')
			t.expect(cards).toBe(row.inFlight + row.notStarted)
		end
	end)

	it("Flow splits band 0 into In flight and Workable now, and does not show an empty raft", function()
		local dir = ".cache/board-unit-trib-flow"
		tributaryFixture(dir)
		local shown = runPage(dir, "", {})
		local flow = shown[1].flow
		fs.removeDir(dir)
		local flight = string.match(flow, 'data%-section="flight">(.-)data%-section=') or ""
		local now = string.match(flow, 'data%-section="now">(.-)data%-section=') or ""
		t.expect(string.find(flow, "In flight", 1, true) < string.find(flow, "Workable now", 1, true))
			.toBe(true)
		t.expect(has(flight, 'data-id="R0010"') and has(flight, 'data-id="c0021"')).toBe(true)
		t.expect(has(flight, 'data-id="R0011"')).toBe(false)
		t.expect(has(now, 'data-id="R0011"') and has(now, 'data-id="c0020"')).toBe(true)
		t.expect(has(now, 'data-id="R0010"')).toBe(false)
		t.expect(has(flow, 'data-id="R0012"')).toBe(false) -- no members, not done: not work
		t.expect(has(flow, 'data-id="c0022"')).toBe(true) -- band 1, unchanged
		t.expect(shown[1].flowSel).toBe("R0010") -- the in-flight section comes first in the arrow order
	end)

	it(
		"the chips show each tributary's counts and purpose, and a click filters Flow, surviving a load",
		function()
			local dir = ".cache/board-unit-trib-chips"
			tributaryFixture(dir)
			local shown = runPage(
				dir,
				"",
				{ { k = "tributary", name = "beta" }, { k = "load" }, { k = "tributary", name = "" } }
			)
			fs.removeDir(dir)
			local open = shown[1].flow
			t.expect(has(open, 'data-tributary="">All</button>')).toBe(true)
			t.expect(has(open, ">alpha 1/1/0/1</button>")).toBe(true)
			t.expect(has(open, ">beta 0/1/0/2</button>")).toBe(true)
			t.expect(
				has(
					open,
					'title="beta: 0 done, 1 in flight, 0 waiting for approval, 2 not started. The &lt;b&gt;second&lt;/b&gt; body."'
				)
			).toBe(true)
			-- with All, each card names its tributary
			t.expect(has(open, '<span class="trname note">alpha</span>')).toBe(true)
			local beta = shown[2].flow
			t.expect(
				has(beta, 'data-id="c0021"') and has(beta, 'data-id="R0011"') and has(beta, 'data-id="c0022"')
			)
				.toBe(true)
			t.expect(has(beta, 'data-id="R0010"') or has(beta, 'data-id="c0020"')).toBe(false)
			t.expect(has(beta, "trname")).toBe(false) -- filtered: the label is redundant
			t.expect(has(beta, 'class="chip tr on" data-tributary="beta"')).toBe(true)
			t.expect(shown[2].flowSel).toBe("c0021")
			t.expect(has(shown[3].flow, 'data-id="R0010"')).toBe(false) -- the filter survived znBoard.load
			t.expect(has(shown[3].flow, 'data-id="c0021"')).toBe(true)
			t.expect(has(shown[4].flow, 'data-id="R0010"') and has(shown[4].flow, 'data-id="c0021"'))
				.toBe(true) -- All again
		end
	)

	it("the filter resets to All when the project changes", function()
		local dir = ".cache/board-unit-trib-projects"
		freshDir(dir)
		fs.writeDir(`{dir}/z-nile`)
		fs.writeFile(
			`{dir}/z-nile/projects.toml`,
			'[[project]]\nname = "one"\nroot = "one/.tracker"\n\n[[project]]\nname = "two"\nroot = "two/.tracker"\n'
		)
		fdoc(`{dir}/one/.tracker/issues/c0020`, "c0020", "type: chore\ntitle: In one\ntributary: x")
		fdoc(`{dir}/one/.tracker/issues/c0021`, "c0021", "type: chore\ntitle: Also in one\ntributary: y")
		fs.writeFile(
			`{dir}/one/.tracker/tributaries.toml`,
			'[[tributary]]\nname = "x"\npurpose = "X."\n\n[[tributary]]\nname = "y"\npurpose = "Y."\n'
		)
		fdoc(`{dir}/two/.tracker/issues/f0030`, "f0030", "type: feature\ntitle: In two\ntributary: z")
		fs.writeFile(`{dir}/two/.tracker/tributaries.toml`, '[[tributary]]\nname = "z"\npurpose = "Z."\n')
		local template = board.TEMPLATE_PATH
		board.TEMPLATE_PATH = `{TOP}/{template}`
		local ok, html = pcall(
			board.render,
			board.collect(nil, dir, { refs = {}, worktrees = {}, dispatch = {} }),
			fs.readFile(`{TOP}/{board.MARKED_PATH}`)
		)
		board.TEMPLATE_PATH = template
		if not ok then
			error(html, 0)
		end
		fs.writeFile(`{dir}/page.html`, html)
		fs.writeFile(`{dir}/flow-harness.js`, FLOW_HARNESS)
		local shown = runPage(dir, "", {
			{ k = "tributary", name = "y" },
			{ k = "project", name = "two" },
			{ k = "project", name = "one" },
		})
		fs.removeDir(dir)
		t.expect(has(shown[2].flow, 'data-id="c0021"') and not has(shown[2].flow, 'data-id="c0020"'))
			.toBe(true)
		t.expect(has(shown[3].flow, 'data-id="f0030"')).toBe(true)
		t.expect(has(shown[3].flow, 'data-tributary="z"')).toBe(true)
		t.expect(has(shown[4].flow, 'data-id="c0020"') and has(shown[4].flow, 'data-id="c0021"')).toBe(true) -- All, not y
	end)

	it("a cycle and an unreadable file are two notes, each worded for what it is", function()
		local dir = ".cache/board-unit-trib-notes"
		freshDir(dir)
		local base = `{dir}/tracker`
		fdoc(`{base}/issues/c0010`, "c0010", "type: chore\ntitle: A\ndepends_on: [c0011]")
		fdoc(`{base}/issues/c0011`, "c0011", "type: chore\ntitle: B\ndepends_on: [c0010]")
		fs.writeFile(`{base}/tributaries.toml`, "[[tributary")
		pageOf(dir)
		local flow = runPage(dir, "", {})[1].flow
		fs.removeDir(dir)
		t.expect(has(flow, "1 file could not be read: ")).toBe(true)
		t.expect(has(flow, "tributaries.toml")).toBe(true)
		t.expect(has(flow, "1 dependency cycle: c0010, c0011")).toBe(true)
		t.expect(has(flow, "files could not be read")).toBe(false)
	end)

	it(
		"a unit's row in Rafts and Issues carries the Flow card's unblocks badge and waits-on chips",
		function()
			local dir = ".cache/board-unit-trib-rows"
			tributaryFixture(dir)
			local shown = runPage(dir, "", { { k = "tab", name = "rafts" }, { k = "tab", name = "issues" } })
			local flow = shown[1].flow
			local rafts, issues = shown[2].list, shown[3].list
			fs.removeDir(dir)
			local function row(list: string, id: string): string
				return string.match(list, `<li class="row [^"]*" data%-id="{id}">(.-)</li>`) or ""
			end
			-- the same two pieces, byte for byte, as on the card: R0011 unblocks c0022; c0022 waits on R0011
			t.expect(has(row(rafts, "R0011"), '<span class="unb">unblocks 1</span>')).toBe(true)
			t.expect(has(flow, '<span class="unb">unblocks 1</span><span class="id">R0011</span>')).toBe(true)
			local chips =
				'<div class="chips"><span class="note">waits on</span> <a class="chip jump" data-id="R0011" href="#R0011">R0011</a></div>'
			t.expect(has(row(issues, "c0022"), chips)).toBe(true)
			t.expect(has(flow, chips)).toBe(true)
			t.expect(has(row(issues, "c0020"), "unb")).toBe(false) -- unblocks nothing, waits on nothing
			t.expect(has(row(rafts, "R0009"), "unb")).toBe(false) -- a done raft is no unit
			t.expect(has(row(issues, "c0011"), "unb")).toBe(false) -- a member is not a unit
			t.expect(has(row(issues, "c0011"), "waits on")).toBe(false)
		end
	)

	it(
		"an issue's pane shows Waiting for, Depends on and Dependents like a raft's, and a member names its raft's band",
		function()
			local dir = ".cache/board-unit-trib-pane"
			tributaryFixture(dir)
			local shown = runPage(dir, "", {
				{ k = "search", q = "c0022" },
				{ k = "search", q = "c0011" },
				{ k = "search", q = "R0011" },
			})
			fs.removeDir(dir)
			local loose, member, raft = shown[2].pane, shown[3].pane, shown[4].pane
			local waiting = string.find(loose, "<h3>Waiting for</h3>", 1, true)
			local depends = string.find(loose, "<h3>Depends on</h3>", 1, true)
			t.expect(waiting ~= nil and depends ~= nil and waiting < depends).toBe(true)
			t.expect(has(string.sub(loose, waiting :: number, depends :: number), 'data-id="R0011"'))
				.toBe(true) -- its open wait, the raft
			t.expect(has(string.sub(loose, depends :: number), 'data-id="c0011"')).toBe(true) -- its own depends_on, as before
			t.expect(has(member, "Worked as part of R0011: band 0, unblocks 1")).toBe(true)
			t.expect(has(member, "<h3>Waiting for</h3>")).toBe(false)
			t.expect(has(loose, "Its raft is the unit")).toBe(false)
			local rw = string.find(raft, "<h3>Waiting for</h3>", 1, true)
			t.expect(rw == nil).toBe(true) -- R0011 waits on nothing
		end
	)
end)
