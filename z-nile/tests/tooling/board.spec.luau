--!strict
-- c0400: the board's own unit cases: the JSON writer, an empty tracker, and opening (the default, `--open` and `-O`).
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- The checkout's top: ./zn runs there and resolves a relative --out from there; MARKED_PATH is relative to it (c0120).
-- Fixtures stay under this home's .cache (the working directory, HERE), the only place a spec may write.
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local HOME = string.sub(HERE, #TOP + 2) -- this home, relative to the top
local function tracker(args: { string }, env: { [string]: string }?): process.ExecResult
	return process.exec("scripts/tracker.sh", args, { cwd = TOP, env = env })
end

local EMPTY = ".cache/board-unit-empty"
local HOSTILE = ".cache/board-unit-hostile"

-- A minimal fake DOM (the subset the page may use), loading the page with a hash and an optional search,
-- and printing what the page shows. Never literal require text: the repo scanner would read it.
local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), hash = process.argv[3] || "", query = process.argv[4] || "";
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
function el(id) {
  const ls = {}, cl = new Set();
  return { id, innerHTML: "", textContent: "", value: "", scrollTop: 0,
    classList: { add: c => cl.add(c), remove: c => cl.delete(c), contains: c => cl.has(c),
      toggle: (c, f) => { (f === undefined ? !cl.has(c) : f) ? cl.add(c) : cl.delete(c); } },
    addEventListener: (t, f) => (ls[t] = ls[t] || []).push(f), dispatch: (t, e) => (ls[t] || []).forEach(f => f(e)),
    focus() {}, blur() {}, select() {}, scrollIntoView() {}, setAttribute() {}, removeAttribute() {}, getAttribute: () => null, closest: () => null };
}
const els = {};
["tab-rafts", "tab-issues", "search", "list", "pane", "board-data", "columns", "flow"].forEach(i => (els[i] = el(i)));
els["board-data"].textContent = scripts.find(x => /id="board-data"/.test(x[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, console, JSON, Math, String, Array, Object,
  decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const x of scripts) if (!/json/.test(x[1])) vm.runInContext(x[2], sandbox);
if (!hash) els["tab-rafts"].dispatch("click", {}); // c0118: the page opens on Board; these cases read the Rafts pane
const key = (k, extra) => { const ev = Object.assign({ key: k, target: {}, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } }, extra); doc.dispatch("keydown", ev); return ev.defaultPrevented; };
const out = { listBefore: els.list.innerHTML + els.columns.innerHTML + els.flow.innerHTML };
if (query) { els.search.value = query; els.search.dispatch("keydown", { key: "Enter", target: els.search }); }
out.miss = els.search.classList.contains("miss");
out.metaPrevented = key("ArrowLeft", { metaKey: true });
out.altPrevented = key("ArrowLeft", { altKey: true });
out.list = els.list.innerHTML + els.columns.innerHTML + els.flow.innerHTML; out.pane = els.pane.innerHTML;
console.log(JSON.stringify(out));
]==]

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
  else if (st.k === "load") sandbox.znBoard.load(JSON.parse(els["board-data"].textContent));
  out.push(snap());
}
console.log(JSON.stringify(out));
]==]

return t.spec("board unit", function(it)
	it("encode escapes quotes, backslashes, control characters and <", function()
		t.expect(board.encode('a"b\\c')).toBe('"a\\"b\\\\c"')
		t.expect(board.encode("x\ny\rz\tw")).toBe('"x\\ny\\rz\\tw"')
		t.expect(board.encode("\1")).toBe('"\\u0001"')
		t.expect(board.encode("</script>")).toBe('"\\u003c/script>"')
	end)

	it("encode keeps unicode bytes as they are", function()
		t.expect(board.encode("héllo — ✓")).toBe('"héllo — ✓"')
	end)

	it("encode nests, orders keys, and writes booleans and numbers", function()
		local nested: any = { z = { 1, 2, { b = true, a = false } :: any }, a = 3, m = {} }
		t.expect(board.encode(nested)).toBe('{"a":3,"m":[],"z":[1,2,{"a":false,"b":true}]}')
	end)

	it("encode refuses a value it cannot write", function()
		local ok = pcall(board.encode, { f = function() end })
		t.expect(ok).toBe(false)
	end)

	it("collect on a tree with no tracker directories gives an empty model", function()
		if fs.isDir(EMPTY) then
			fs.removeDir(EMPTY)
		end
		fs.writeDir(EMPTY)
		local m = board.collect(EMPTY)
		fs.removeDir(EMPTY)
		t.expect(m.rafts).toEqual({})
		t.expect(m.issues).toEqual({})
		t.expect(m.views).toEqual({
			rafts = { ready = {}, ["not"] = {}, done = {} },
			issues = { ready = {}, ["not"] = {}, done = {} },
		})
		t.expect(m.home).toEqual({})
		t.expect(m.initialView).toBe("flow")
		t.expect(m.flow).toEqual({ bands = {} })
		local raw = m :: any
		t.expect(raw.tabs).toBe(nil)
		t.expect(raw.initialTab).toBe(nil)
	end)

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
		t.expect(has(shown[1].flow, "dependency cycle among: R0010, c0030")).toBe(true)
		t.expect(has(shown[1].flow, 'data-problems="1"')).toBe(true)
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
		t.expect(has(firstBand, "chip")).toBe(false)
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

	it("--open runs the opener on the page, and does not eat the next argument", function()
		local dir = ".cache/board-unit-open"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		-- fake openers, so the gate never launches a browser
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{dir}/bin/{name}`, `#!/bin/sh\necho "$@" > "{HERE}/{dir}/opened"\n`)
			process.exec("chmod", { "+x", `{dir}/bin/{name}` })
		end
		local out = `{HERE}/{dir}/page.html`
		local r = tracker({ "board", "--open", "--out", out }, {
			PATH = `{HERE}/{dir}/bin:{process.env.PATH or ""}`,
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(out)).toBe(true)
		t.expect(string.find(fs.readFile(`{dir}/opened`), out, 1, true) ~= nil).toBe(true)
		fs.removeDir(dir)
	end)

	-- a raft whose document has placeholder text, and an issue depending on a name that is not an id
	local function hostileFixture(): string
		if fs.isDir(HOSTILE) then
			fs.removeDir(HOSTILE)
		end
		fs.writeDir(`{HOSTILE}/tracker/rafts/R0010`)
		fs.writeDir(`{HOSTILE}/tracker/issues/c0010`)
		fs.writeFile(
			`{HOSTILE}/tracker/rafts/R0010/R0010.md`,
			"---\nid: R0010\ntype: chore\ntitle: Alpha\ndesign: ready\n---\n\n<!-- hidden hint -->\nStarted at <sha> and `<code>`.\n"
		)
		fs.writeFile(
			`{HOSTILE}/tracker/issues/c0010/c0010.md`,
			"---\nid: c0010\ntype: chore\ntitle: One\nraft: R0010\ndepends_on: [constructor]\n---\n\n# c0010\n"
		)
		local page = `{HOSTILE}/page.html`
		-- render reads its template by the top-relative TEMPLATE_PATH; specs run in their home, so point it at the top
		local template = board.TEMPLATE_PATH
		board.TEMPLATE_PATH = `{TOP}/{template}`
		local ok, html =
			pcall(board.render, board.collect(`{HOSTILE}/tracker`), fs.readFile(`{TOP}/{board.MARKED_PATH}`))
		board.TEMPLATE_PATH = template
		if not ok then
			error(html, 0)
		end
		fs.writeFile(page, html)
		fs.writeFile(`{HOSTILE}/harness.js`, HARNESS)
		return page
	end

	local function showPage(page: string, hash: string, query: string): any
		local ok, r = pcall(process.exec, "node", { `{HOSTILE}/harness.js`, page, hash, query })
		if not ok then
			error(`node is required for this spec (preinstalled on GitHub runners): {r}`)
		end
		if not r.ok then
			error(r.stderr)
		end
		return serde.decode("json", r.stdout)
	end

	it("names that are not ids are a miss or a no-match, never a throw", function()
		local page = hostileFixture()
		for _, hash in { "#constructor", "#__proto__", "#%", "#%E0", "#zzz" } do
			local shown = showPage(page, hash, "")
			t.expect(string.find(shown.list, "R0010", 1, true) ~= nil).toBe(true)
		end
		for _, query in { "constructor", "__proto__", "hasOwnProperty" } do
			t.expect(showPage(page, "", query).miss).toBe(true)
		end
		t.expect(showPage(page, "", "r0010").miss).toBe(false)
		-- the dependency named `constructor` is text, not a lookup through Object.prototype
		t.expect((string.find(showPage(page, "#c0010", "").pane, "undefined", 1, true))).toBe(nil)
	end)

	it("shows placeholder text in documents, and hides only comments", function()
		local pane = showPage(hostileFixture(), "", "").pane
		t.expect(string.find(pane, "&lt;sha&gt;", 1, true) ~= nil).toBe(true)
		t.expect(string.find(pane, "<code>&lt;code&gt;</code>", 1, true) ~= nil).toBe(true)
		t.expect((string.find(pane, "hidden hint", 1, true))).toBe(nil)
	end)

	it("keeps browser shortcuts: Cmd or Alt with an arrow is not taken", function()
		local shown = showPage(hostileFixture(), "", "")
		t.expect(shown.metaPrevented).toBe(false)
		t.expect(shown.altPrevented).toBe(false)
		t.expect(shown.list == shown.listBefore).toBe(true)
		fs.removeDir(HOSTILE)
	end)

	it("pane id links are real links, so Tab reaches them", function()
		local pane = showPage(hostileFixture(), "", "").pane
		t.expect(string.find(pane, '<a class="jump" data-id="c0010" href="#c0010">', 1, true) ~= nil)
			.toBe(true)
		fs.removeDir(HOSTILE)
	end)

	it("--open with an opener that fails warns on stderr and still succeeds", function()
		local dir = ".cache/board-unit-fail"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{dir}/bin/{name}`, "#!/bin/sh\nexit 3\n")
			process.exec("chmod", { "+x", `{dir}/bin/{name}` })
		end
		local out = `{HERE}/{dir}/page.html`
		local r = tracker({ "board", "--open", "--out", out }, {
			PATH = `{HERE}/{dir}/bin:{process.env.PATH or ""}`,
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(out)).toBe(true)
		t.expect(string.find(r.stderr, "warning:", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, out, 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "warning", 1, true))).toBe(nil)
		fs.removeDir(dir)
	end)

	it("board refuses a positional path and an --out that looks like a flag, and writes nothing", function()
		local stray = tracker({ "board", `{HOME}/.cache/board-unit-stray.html` })
		t.expect(stray.ok).toBe(false)
		t.expect(fs.isFile(".cache/board-unit-stray.html")).toBe(false)
		local flag = tracker({ "board", "--out", "--open" })
		t.expect(flag.ok).toBe(false)
		t.expect(fs.isFile(`{TOP}/--open`)).toBe(false)
	end)

	it("board prints the absolute path of a relative --out", function()
		local out = `{HOME}/.cache/board-unit-abs/page.html` -- relative to the top, where ./zn runs
		local r = tracker({ "board", "--out", out, "-O" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, `{TOP}/{out}`, 1, true) ~= nil).toBe(true)
		fs.removeDir(".cache/board-unit-abs")
	end)
end)
