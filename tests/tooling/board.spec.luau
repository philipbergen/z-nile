--!strict
-- c0400: the board's own unit cases: the JSON writer, an empty tracker, and opening (the default, `--open` and `-O`).
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

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
    focus() {}, blur() {}, select() {}, scrollIntoView() {}, getAttribute: () => null, closest: () => null };
}
const els = {};
["tab-active", "tab-waiting", "tab-done", "search", "list", "pane", "board-data"].forEach(i => (els[i] = el(i)));
els["board-data"].textContent = scripts.find(x => /id="board-data"/.test(x[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, console, JSON, Math, String, Array, Object,
  decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const x of scripts) if (!/json/.test(x[1])) vm.runInContext(x[2], sandbox);
const key = (k, extra) => { const ev = Object.assign({ key: k, target: {}, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } }, extra); doc.dispatch("keydown", ev); return ev.defaultPrevented; };
const out = { listBefore: els.list.innerHTML };
if (query) { els.search.value = query; els.search.dispatch("keydown", { key: "Enter", target: els.search }); }
out.miss = els.search.classList.contains("miss");
out.metaPrevented = key("ArrowLeft", { metaKey: true });
out.altPrevented = key("ArrowLeft", { altKey: true });
out.list = els.list.innerHTML; out.pane = els.pane.innerHTML;
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
		t.expect(m.tabs).toEqual({ done = {}, active = {}, waiting = {} })
		t.expect(m.home).toEqual({})
		t.expect(m.initialTab).toBe("waiting")
	end)

	it("--open runs the opener on the page, and does not eat the next argument", function()
		local dir = ".cache/board-unit-open"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		-- fake openers, so the gate never launches a browser
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{dir}/bin/{name}`, `#!/bin/sh\necho "$@" > "{process.cwd}{dir}/opened"\n`)
			process.exec("chmod", { "+x", `{dir}/bin/{name}` })
		end
		local out = `{dir}/page.html`
		local r = process.exec("scripts/tracker.sh", { "board", "--open", "--out", out }, {
			env = { PATH = `{process.cwd}{dir}/bin:{process.env.PATH or ""}` },
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
		fs.writeFile(page, board.render(board.collect(`{HOSTILE}/tracker`), fs.readFile(board.MARKED_PATH)))
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
		local out = `{dir}/page.html`
		local r = process.exec("scripts/tracker.sh", { "board", "--open", "--out", out }, {
			env = { PATH = `{process.cwd}{dir}/bin:{process.env.PATH or ""}` },
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(out)).toBe(true)
		t.expect(string.find(r.stderr, "warning:", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, out, 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "warning", 1, true))).toBe(nil)
		fs.removeDir(dir)
	end)

	it("board refuses a positional path and an --out that looks like a flag, and writes nothing", function()
		local stray = process.exec("scripts/tracker.sh", { "board", ".cache/board-unit-stray.html" })
		t.expect(stray.ok).toBe(false)
		t.expect(fs.isFile(".cache/board-unit-stray.html")).toBe(false)
		local flag = process.exec("scripts/tracker.sh", { "board", "--out", "--open" })
		t.expect(flag.ok).toBe(false)
		t.expect(fs.isFile("--open")).toBe(false)
	end)

	it("board prints the absolute path of a relative --out", function()
		local out = ".cache/board-unit-abs/page.html"
		local r = process.exec("scripts/tracker.sh", { "board", "--out", out, "-O" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, `{process.cwd}{out}`, 1, true) ~= nil).toBe(true)
		fs.removeDir(".cache/board-unit-abs")
	end)
end)
