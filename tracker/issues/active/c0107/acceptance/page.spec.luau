--!strict
-- c0107 AC3: the page has Rafts and Issues, colors each row by its group, and copies the next command.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local ROOT = ".cache/c0107-page"

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function write(path: string, front: { string }, body: string)
	fs.writeDir(`{ROOT}/{dirname(path)}`)
	fs.writeFile(`{ROOT}/{path}`, "---\n" .. table.concat(front, "\n") .. "\n---\n\n" .. body)
end

local function row(html: string, id: string): string
	local marker = `data-id="{id}"`
	local at = string.find(html, marker, 1, true)
	t.expect(at ~= nil).toBe(true)
	local startAt = 1
	local openAt = 1
	while true do
		local found = string.find(html, "<li", startAt, true)
		if not found or found > (at :: number) then
			break
		end
		openAt = found
		startAt = found + 1
	end
	local closeAt = string.find(html, "</li>", at :: number, true)
	t.expect(closeAt ~= nil).toBe(true)
	return string.sub(html, openAt, closeAt)
end

local function findItem(list: { any }, id: string): any
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	error(id)
end

local function place(groups: any, id: string, to: string)
	for _, name in { "ready", "not", "done" } do
		local kept = {}
		for _, item in groups[name] do
			if item ~= id then
				table.insert(kept, item)
			end
		end
		groups[name] = kept
	end
	table.insert(groups[to], id)
	table.sort(groups[to])
end

-- The fake DOM implements the subset the design allows. A copy click's target is the svg inside the
-- button, and that svg's closest also answers li.row. writeText resolves on a microtask. The harness
-- reads the button after a macrotask, so an awaited write is visible too. argv[3] == "sentinel"
-- prints the lists and skips the copy click.
local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8");
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
function el(id) {
  const ls = {}, cl = new Set();
  const e = {
    id, innerHTML: "", textContent: "", value: "", scrollTop: 0, aria: "",
    classList: {
      add: c => cl.add(c), remove: c => cl.delete(c), contains: c => cl.has(c),
      toggle: (c, f) => { const on = f === undefined ? !cl.has(c) : !!f; on ? cl.add(c) : cl.delete(c); return on; },
    },
    addEventListener: (t, f) => (ls[t] = ls[t] || []).push(f),
    dispatch: (t, ev) => (ls[t] || []).forEach(f => f(ev)),
    focus() { sandbox.document.activeElement = e; }, blur() {}, select() {}, scrollIntoView() {},
    getAttribute: n => n === "aria-label" ? e.aria : null,
    setAttribute: (n, v) => { if (n === "aria-label") e.aria = v; },
    closest: () => null,
  };
  return e;
}
function button(cmd) {
  const row = el("row");
  row.getAttribute = n => n === "data-id" ? "R9100" : null;
  const b = el("button");
  b.classList.add("copy");
  b.aria = "Copy " + cmd;
  b.getAttribute = n => n === "data-command" ? cmd : n === "aria-label" ? b.aria : null;
  const child = { closest: sel => sel === "button.copy" ? b : sel === "li.row" ? row : null };
  return { b, child };
}
const ids = ["tab-rafts", "tab-issues", "search", "list", "pane", "board-data"];
const els = {};
ids.forEach(i => (els[i] = el(i)));
const at = {};
ids.forEach(i => (at[i] = html.indexOf('id="' + i + '"')));
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document"), body = el("body");
let loadingAt = -1;
const written = [];
let mode = "ok";
const sandbox = {
  document: {
    getElementById: i => (els[i] && (loadingAt < 0 || (at[i] >= 0 && at[i] < loadingAt)) ? els[i] : null),
    querySelector: () => null,
    addEventListener: doc.addEventListener,
    body, activeElement: body,
  },
  location: { hash: "" },
  history: { replaceState: (a, b, h) => (sandbox.location.hash = h) },
  navigator: { clipboard: { writeText: s => {
    if (mode === "bad") return Promise.reject(new Error("denied"));
    written.push(s);
    return new Promise(r => queueMicrotask(r));
  } } },
  console, JSON, Math, String, Array, Object, decodeURIComponent, encodeURIComponent,
};
sandbox.window = sandbox; sandbox.self = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) { loadingAt = s.index; vm.runInContext(s[2], sandbox); }
loadingAt = -1;
doc.dispatch("DOMContentLoaded", { target: doc, preventDefault() {} });
function key(k, target) {
  const ev = { key: k, target: target || body, metaKey: false, ctrlKey: false, altKey: false, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
  if (target) target.dispatch("keydown", ev);
  doc.dispatch("keydown", ev);
}
if (process.argv[3] === "sentinel") {
  const out = { list: els.list.innerHTML };
  key("ArrowRight");
  out.issues = els.list.innerHTML;
  console.log(JSON.stringify(out));
} else {
const out = {};
out.list = els.list.innerHTML;
out.pane = els.pane.innerHTML;
key("ArrowDown");
out.afterDown = els.pane.innerHTML;
const beforeCopy = els.list.innerHTML;
const okBtn = button("/ready-raft R9100");
els.list.dispatch("click", { target: okBtn.child });
setTimeout(() => {
  out.written = written.slice();
  out.okCopied = okBtn.b.classList.contains("copied");
  out.okLabel = okBtn.b.getAttribute("aria-label");
  out.listSame = els.list.innerHTML === beforeCopy;
  mode = "bad";
  const failBtn = button("/launch-raft R9103");
  out.threw = false;
  try { els.list.dispatch("click", { target: failBtn.child }); } catch (e) { out.threw = true; }
  setTimeout(() => {
    out.failCopied = failBtn.b.classList.contains("copied");
    out.writtenAfterFail = written.slice();
    sandbox.navigator.clipboard = undefined;
    out.bareThrew = false;
    try { els.list.dispatch("click", { target: okBtn.child }); } catch (e) { out.bareThrew = true; }
    key("ArrowRight");
    out.afterRight = els.list.innerHTML;
    out.afterRightPane = els.pane.innerHTML;
    els.search.value = "r9104";
    key("Enter", els.search);
    out.preparingPane = els.pane.innerHTML;
    console.log(JSON.stringify(out));
  }, 0);
}, 0);
}
]==]

return t.spec("c0107 board page", function(it)
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	write("rafts/R9100/R9100.md", {
		"id: R9100",
		"type: feature",
		"title: ReadyRaft",
		"issues: [f9100, c9101]",
		"design: ready",
		"status: prepared-a-b-c",
	}, "# R9100: ReadyRaft\n")
	write("rafts/active/R9103/R9103.md", {
		"id: R9103",
		"type: feature",
		"title: LaunchRaft",
		"issues: [f9103]",
		"design: draft",
	}, "# R9103: LaunchRaft\n")
	write("rafts/R9101/R9101.md", {
		"id: R9101",
		"type: chore",
		"title: DraftRaft",
		"issues: [c9103]",
		"design: draft",
	}, "# R9101: DraftRaft\n")
	write("rafts/R9104/R9104.md", {
		"id: R9104",
		"type: defect",
		"title: PreparingRaft",
		"issues: [f9104]",
		"design: ready",
		"status: preparing-quiet-copper-falcon",
	}, "# R9104: PreparingRaft\n")
	write("rafts/done/R9102/R9102.md", {
		"id: R9102",
		"type: defect",
		"title: DoneRaft",
		"issues: [d9104]",
		"design: ready",
	}, "# R9102: DoneRaft\n")
	write("issues/f9100/f9100.md", {
		"id: f9100",
		"type: feature",
		"title: ReadyFeature",
		"raft: R9100",
		"depends_on: [c9102]",
		"design: ready",
	}, "# f9100: ReadyFeature\n")
	write("issues/c9101/c9101.md", {
		"id: c9101",
		"type: chore",
		"title: MixedChore",
		"raft: R9100",
		"depends_on: []",
		"design: ready",
	}, "# c9101: MixedChore\n")
	write("issues/active/f9103/f9103.md", {
		"id: f9103",
		"type: feature",
		"title: LaunchFeature",
		"raft: R9103",
		"depends_on: []",
		"design: draft",
	}, "# f9103: LaunchFeature\n")
	write("issues/c9103/c9103.md", {
		"id: c9103",
		"type: chore",
		"title: DraftChore",
		"raft: R9101",
		"depends_on: []",
		"design: draft",
	}, "# c9103: DraftChore\n")
	write("issues/f9104/f9104.md", {
		"id: f9104",
		"type: defect",
		"title: PreparingDefect",
		"raft: R9104",
		"depends_on: []",
		"design: draft",
	}, "# f9104: PreparingDefect\n")
	write("issues/c9102/c9102.md", {
		"id: c9102",
		"type: feature",
		"title: LooseFeature",
		"raft:",
		"depends_on: []",
		"design: draft",
	}, "# c9102: LooseFeature\n")
	write("issues/done/d9104/d9104.md", {
		"id: d9104",
		"type: defect",
		"title: DoneDefect",
		"raft: R9102",
		"depends_on: []",
		"design: ready",
	}, "# d9104: DoneDefect\n")

	local page = `{ROOT}/page.html`
	fs.writeFile(page, board.render(board.collect(ROOT) :: any, fs.readFile(board.MARKED_PATH)))
	fs.writeFile(`{ROOT}/harness.js`, HARNESS)

	it("replaces Active, Waiting and Done with Rafts and Issues", function()
		local html = fs.readFile(page)
		t.expect(string.find(html, 'id="tab-rafts"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, 'id="tab-issues"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ">Rafts<", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ">Issues<", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ".copy.copied { outline: 2px solid #22c55e; }", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ".s-prepared { background: #22c55e33; }", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ".s-preparing { background: #f59e0b33; }", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, ".s-new { background: #d1d5db33; }", 1, true) ~= nil).toBe(true)
		t.expect((string.find(html, ".s-ready { background: #22c55e33; }", 1, true))).toBe(nil)
		t.expect((string.find(html, ".s-reviewed { background: #f59e0b33; }", 1, true))).toBe(nil)
		t.expect((string.find(html, ".s-draft { background: #d1d5db33; }", 1, true))).toBe(nil)
		for _, id in { "tab-active", "tab-waiting", "tab-done" } do
			t.expect((string.find(html, `id="{id}"`, 1, true))).toBe(nil)
		end
	end)

	it("orders Ready, then Not ready, then Done, and copies only a real command", function()
		local run = process.exec("node", { `{ROOT}/harness.js`, page })
		if not run.ok then
			error(run.stderr)
		end
		local shown = serde.decode("json", run.stdout)
		local list = shown.list
		local readyAt = string.find(list, '<li class="group">Ready</li>', 1, true)
		local notAt = string.find(list, '<li class="group">Not ready</li>', 1, true)
		local doneAt = string.find(list, '<li class="group">Done</li>', 1, true)
		local r9100 = string.find(list, 'data-id="R9100"', 1, true)
		local r9103 = string.find(list, 'data-id="R9103"', 1, true)
		local r9101 = string.find(list, 'data-id="R9101"', 1, true)
		local r9104 = string.find(list, 'data-id="R9104"', 1, true)
		local r9102 = string.find(list, 'data-id="R9102"', 1, true)
		t.expect(readyAt ~= nil and notAt ~= nil and doneAt ~= nil).toBe(true)
		t.expect(readyAt < r9100 and r9100 < r9103 and r9103 < notAt).toBe(true)
		t.expect(notAt < r9101 and r9101 < r9104 and r9104 < doneAt and doneAt < r9102).toBe(true)
		local readyRow = row(list, "R9100")
		t.expect(string.find(readyRow, 'class="row ready', 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, 'class="type t-mix"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, ">mix<", 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, 'data-command="/ready-raft R9100"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, "<svg", 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, "s-prepared", 1, true) ~= nil).toBe(true)
		t.expect(string.find(readyRow, ">prepared<", 1, true) ~= nil).toBe(true)
		local launchRow = row(list, "R9103")
		t.expect(string.find(launchRow, 'class="row ready', 1, true) ~= nil).toBe(true)
		t.expect(string.find(launchRow, "s-active", 1, true) ~= nil).toBe(true)
		t.expect(string.find(launchRow, 'data-command="/launch-raft R9103"', 1, true) ~= nil).toBe(true)
		local draftRow = row(list, "R9101")
		t.expect(string.find(draftRow, 'class="row not', 1, true) ~= nil).toBe(true)
		t.expect((string.find(draftRow, "copy", 1, true))).toBe(nil)
		local preparingRow = row(list, "R9104")
		t.expect(string.find(preparingRow, 'class="row not', 1, true) ~= nil).toBe(true)
		t.expect((string.find(preparingRow, "copy", 1, true))).toBe(nil)
		t.expect(string.find(preparingRow, ">preparing<", 1, true) ~= nil).toBe(true)
		t.expect((string.find(preparingRow, ">ready<", 1, true))).toBe(nil)
		t.expect(string.find(shown.pane, "ReadyRaft", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.afterDown, "LaunchRaft", 1, true) ~= nil).toBe(true)
		t.expect(shown.written).toEqual({ "/ready-raft R9100" })
		t.expect(shown.okCopied).toBe(true)
		t.expect(shown.okLabel).toBe("Copied")
		t.expect(shown.threw).toBe(false)
		t.expect(shown.failCopied).toBe(false)
		t.expect(shown.writtenAfterFail).toEqual({ "/ready-raft R9100" })
		t.expect(shown.listSame).toBe(true)
		t.expect(shown.bareThrew).toBe(false)
		local choreRow = row(shown.afterRight, "c9101")
		t.expect(string.find(choreRow, 'class="type t-chore"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.afterRight, 'data-command="/ticket-prep c9102"', 1, true) ~= nil)
			.toBe(true)
		t.expect((string.find(shown.afterRight, 'data-id="R9100"', 1, true))).toBe(nil)
		t.expect(string.find(shown.afterRightPane, "MixedChore", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.preparingPane, ">R9104<", 1, true) ~= nil).toBe(true)
		t.expect(string.find(shown.preparingPane, ">preparing<", 1, true) ~= nil).toBe(true)
		for _, html in
			{ list, shown.pane, shown.afterDown, shown.afterRight, shown.afterRightPane, shown.preparingPane }
		do
			t.expect((string.find(html, ">ready<", 1, true))).toBe(nil)
		end
	end)

	it("follows views and command when they contradict stage", function()
		local sent = board.collect(ROOT) :: any
		place(sent.views.rafts, "R9101", "ready")
		findItem(sent.rafts, "R9101").command = "/sentinel R9101"
		place(sent.views.rafts, "R9100", "done")
		findItem(sent.rafts, "R9100").command = nil
		place(sent.views.issues, "c9103", "ready")
		findItem(sent.issues, "c9103").command = "/sentinel c9103"
		place(sent.views.issues, "c9102", "done")
		findItem(sent.issues, "c9102").command = nil
		local sentinel = `{ROOT}/sentinel.html`
		fs.writeFile(sentinel, board.render(sent, fs.readFile(board.MARKED_PATH)))
		local run = process.exec("node", { `{ROOT}/harness.js`, sentinel, "sentinel" })
		if not run.ok then
			error(run.stderr)
		end
		local shown = serde.decode("json", run.stdout)
		local list = shown.list
		local readyAt = string.find(list, '<li class="group">Ready</li>', 1, true)
		local doneAt = string.find(list, '<li class="group">Done</li>', 1, true)
		local forced = row(list, "R9101")
		local retired = row(list, "R9100")
		t.expect(readyAt ~= nil and doneAt ~= nil and readyAt < doneAt).toBe(true)
		t.expect(string.find(forced, 'class="row ready', 1, true) ~= nil).toBe(true)
		t.expect(string.find(forced, 'data-command="/sentinel R9101"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(forced, ">preparing<", 1, true) ~= nil).toBe(true)
		local r9100at = string.find(list, 'data-id="R9100"', 1, true)
		t.expect(r9100at ~= nil and doneAt ~= nil and (doneAt :: number) < (r9100at :: number)).toBe(true)
		t.expect(string.find(retired, 'class="row done', 1, true) ~= nil).toBe(true)
		t.expect((string.find(retired, "copy", 1, true))).toBe(nil)
		local issues = shown.issues
		local promoted = row(issues, "c9103")
		local closed = row(issues, "c9102")
		t.expect(string.find(promoted, 'class="row ready', 1, true) ~= nil).toBe(true)
		t.expect(string.find(promoted, 'data-command="/sentinel c9103"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(closed, 'class="row done', 1, true) ~= nil).toBe(true)
		t.expect((string.find(closed, "copy", 1, true))).toBe(nil)
		fs.removeDir(ROOT)
	end)
end)
