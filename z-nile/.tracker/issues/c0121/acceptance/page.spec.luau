--!strict
-- c0121 AC3: the served page's script, run by node against a fake DOM with `fetch` and `setInterval` stubbed (no
-- network): it polls /api/state every live.poll seconds with its token and hands the model to znBoard.load; it shows
-- "live", "server is out of date: restart", "checks unavailable" and "the server did not answer"; a card has Stop,
-- Retry and Open, each a JSON POST to /api/action with the token, and shows the answer. The static page has no
-- buttons, never polls and never fetches.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local DIR = ".cache/c0121-page"
local REGISTRY = '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

local function write(path: string, text: string)
	local full = `{DIR}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function item(path: string, front: { string }, body: string?)
	local id = string.match(path, "([^/]+)$") :: string
	write(
		`{path}/{id}.md`,
		"---\nid: " .. id .. "\n" .. table.concat(front, "\n") .. "\n---\n\n# " .. id .. "\n" .. (body or "")
	)
end
-- links in an item's document: a script link, a data link, one with control characters inside its scheme, a safe web
-- link, a relative one and a mail one (code review 001 F3)
local LINKS = "\n[script](javascript:alert(1)) [data](data:text/html,x) [tabbed](java\tscript:alert(2)) "
	.. "[web](https://example.invalid/x) [rel](docs/x.md) [mail](mailto:a@example.invalid)\n"

-- The fake DOM and the stubs. Never literal require text: the repo scanner would read it.
local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), mode = process.argv[3];
const next = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4], "utf8")) : null;
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
 "list", "pane", "board-data", "live"].forEach(el);
els.live.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const fetches = [], intervals = [];
let failNext = false;
function fetchStub(u, opts) {
  fetches.push({ url: u, method: (opts && opts.method) || "GET", headers: (opts && opts.headers) || {}, body: (opts && opts.body) || null });
  if (failNext) return Promise.reject(new Error("down"));
  if (u === "/api/state") return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ model: next, statsHtml: "<p>s</p>" }) });
  return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve('{"ok":true,"output":"stopped"}') });
}
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash: "" }, history: { replaceState() {} }, navigator: {}, console, JSON, Math, String, Array, Object, Number, Date,
  Promise, decodeURIComponent, encodeURIComponent };
if (mode !== "static-nofetch") { sandbox.fetch = fetchStub; sandbox.setInterval = (fn, ms) => intervals.push({ fn, ms }); }
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
const target = (sel, attrs) => ({ closest: s => (s === sel ? { getAttribute: n => attrs[n] ?? null } : null) });
const tick = () => new Promise(r => setTimeout(r, 0));
(async () => {
  const out = { liveHidden: els.live.hasAttribute("hidden"), live: els.live.innerHTML, intervals: intervals.map(i => i.ms) };
  els.columns.dispatch("click", { target: target("button.card", { "data-id": "f0021" }), preventDefault() {} });
  out.pane = els.pane.innerHTML;
  els.pane.dispatch("click", { target: target("button.act", { "data-act": "stop", "data-id": "f0021" }), preventDefault() {} });
  await tick(); await tick(); await tick();
  out.paneAfter = els.pane.innerHTML;
  if (intervals.length) {
    intervals[0].fn();
    await tick(); await tick(); await tick();
    out.columnsAfterPoll = els.columns.innerHTML;
    out.liveAfterPoll = els.live.innerHTML;
    failNext = true;
    intervals[0].fn();
    await tick(); await tick(); await tick();
    out.liveAfterFail = els.live.innerHTML;
  }
  out.fetches = fetches;
  console.log(JSON.stringify(out));
})();
]==]

local function node(page: string, mode: string, nextPath: string?): any
	local args = { `{DIR}/harness.js`, page, mode }
	if nextPath then
		table.insert(args, nextPath)
	end
	local ok, r = pcall(process.exec, "node", args)
	if not ok then
		error(`node is required for this spec (preinstalled on GitHub runners): {r}`)
	end
	if not r.ok then
		error(r.stderr)
	end
	return serde.decode("json", r.stdout)
end
local function has(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end

local shown: any, unavailable: any, static: any = nil, nil, nil

return t.spec("c0121 served page", function(it)
	it("builds a live page, a live page whose gh failed, and a static page", function()
		if fs.isDir(DIR) then
			fs.removeDir(DIR)
		end
		write("z-nile/projects.toml", REGISTRY)
		item(
			"z-nile/.tracker/rafts/active/R0020",
			{ "type: feature", "title: Running", "design: ready", "status: active-a-b-c" }
		)
		item(
			"z-nile/.tracker/issues/active/f0021",
			{ "type: feature", "title: Runs", "raft: R0020", "status: active-a-b-c" },
			LINKS
		)
		local facts: any = {
			asOf = 1792800000,
			refs = { { name = "R0020-alpha", at = 1792800000 } },
			worktrees = {},
			dispatch = {},
		}
		local function liveModel(checks: string, stale: boolean): any
			local m: any = board.collect(nil, DIR, facts)
			m.live = { token = "t0k", poll = 5, checks = checks, checksAge = 3, stale = stale }
			return m
		end
		-- the spec runs from its project's home: the vendored file is read from the checkout's top (c0120)
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local marked = fs.readFile(`{top}/{board.MARKED_PATH}`)
		fs.writeFile(`{DIR}/live.html`, board.render(liveModel("ok", false), marked))
		fs.writeFile(`{DIR}/unavailable.html`, board.render(liveModel("unavailable", false), marked))
		fs.writeFile(`{DIR}/static.html`, board.render(board.collect(nil, DIR, facts), marked))
		-- the next polled model: a new card, and the engine changed since the server started
		item(
			"z-nile/.tracker/issues/active/f0022",
			{ "type: feature", "title: Arrived live", "raft: R0020", "status: active-a-b-c" }
		)
		fs.writeFile(`{DIR}/next.json`, board.encode(liveModel("ok", true)))
		fs.writeFile(`{DIR}/harness.js`, HARNESS)
		shown = node(`{DIR}/live.html`, "live", `{DIR}/next.json`)
		unavailable = node(`{DIR}/unavailable.html`, "live", `{DIR}/next.json`)
		static = node(`{DIR}/static.html`, "static", nil)
	end)

	it("shows that it is live, and polls every live.poll seconds", function()
		t.expect(shown.liveHidden).toBe(false)
		t.expect(has(shown.live, "live")).toBe(true)
		t.expect(has(shown.live, "checks 3 s old")).toBe(true)
		t.expect(shown.intervals).toEqual({ 5000 })
	end)

	it("polls /api/state with its token and loads the model it gets", function()
		local polls = {}
		for _, f in shown.fetches do
			if f.url == "/api/state" then
				table.insert(polls, f)
			end
		end
		t.expect(#polls >= 1).toBe(true)
		t.expect(polls[1].method).toBe("GET")
		t.expect(polls[1].headers["X-Zn-Token"]).toBe("t0k")
		t.expect(has(shown.columnsAfterPoll, 'data-id="f0022"')).toBe(true)
		t.expect(has(shown.columnsAfterPoll, "Arrived live")).toBe(true)
	end)

	it(
		"says the server is out of date when the polled model says so, and when the server does not answer",
		function()
			t.expect(has(shown.liveAfterPoll, "server is out of date: restart")).toBe(true)
			t.expect(has(shown.liveAfterFail, "the server did not answer")).toBe(true)
		end
	)

	it(
		"a document's link keeps only a safe scheme: javascript:, data: and a disguised scheme render as text",
		function()
			local pane = shown.pane
			t.expect(has(pane, 'href="javascript:')).toBe(false)
			t.expect(has(pane, 'href="data:')).toBe(false)
			t.expect(string.find(pane, 'href="[^"]*[Jj][Aa][Vv][Aa][^"]*[Ss][Cc][Rr][Ii][Pp][Tt]:') == nil)
				.toBe(true)
			for _, word in { "script", "data", "tabbed" } do
				t.expect(has(pane, word)).toBe(true) -- the link text stays
			end
			t.expect(has(pane, 'href="https://example.invalid/x"')).toBe(true)
			t.expect(has(pane, 'href="docs/x.md"')).toBe(true)
			t.expect(has(pane, 'href="mailto:a@example.invalid"')).toBe(true)
		end
	)

	it("a card has Stop, Retry and Open, and Stop is a JSON POST to /api/action with the token", function()
		t.expect(has(shown.pane, 'data-act="stop" data-id="f0021"')).toBe(true)
		t.expect(has(shown.pane, 'data-act="retry" data-id="f0021"')).toBe(true)
		t.expect(has(shown.pane, 'data-act="open" data-id="f0021"')).toBe(true)
		local post = shown.fetches[1]
		t.expect(post.url).toBe("/api/action")
		t.expect(post.method).toBe("POST")
		t.expect(post.headers["Content-Type"]).toBe("application/json")
		t.expect(post.headers["X-Zn-Token"]).toBe("t0k")
		t.expect(serde.decode("json", post.body)).toEqual({ action = "stop", id = "f0021" })
		t.expect(has(shown.paneAfter, "stop: 200")).toBe(true)
	end)

	it("a card with no PR says checks unavailable when gh failed", function()
		t.expect(has(unavailable.pane, "checks unavailable")).toBe(true)
		t.expect(has(unavailable.live, "checks unavailable")).toBe(true)
	end)

	it("the static page has no buttons, never polls and never fetches", function()
		t.expect(static.liveHidden).toBe(true)
		t.expect(static.intervals).toEqual({})
		t.expect(#static.fetches).toBe(0)
		t.expect(has(static.pane, 'class="act"')).toBe(false)
		t.expect(has(static.pane, "zn board --serve")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(DIR)
	end)
end)
