--!strict
-- c0263 AC3 (R1, ruled by the user 2026-11-12): `./zn restack` settles the item records a layer's rebase stops on, by item
-- id, with the union sync and land use, and goes on. Main appends to an active item's record while a layer appends; a
-- layer that moved the item's folder meanwhile; and a record main deleted (an id changed) still stops the restack with
-- the layer, the branch and the tree as they were. Fixture: .cache/c0263-restack-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"
local HUMAN: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
	ZN_DISPATCH = "",
}

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local f: trackerfix.Fixture
local wt, wtMain = "", ""
local env: { [string]: string } = {}

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end
local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function layerRecord(): string
	return `{ISSUES}/active/c0010/provenance.md`
end
local function appendRow(dir: string, path: string, who: string)
	local rec = `{dir}/{path}`
	fs.writeFile(rec, fs.readFile(rec) .. `| 2026-11-08 11:00 | unblocked | human:{who} | by={who} |\n`)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-q", "-m", `layer row {who}` })
end
local function rowsOf(text: string): { string }
	local out: { string } = {}
	for who in string.gmatch(text, "| (human:%w+) |") do
		table.insert(out, who)
	end
	return out
end
local function clean(dir: string)
	t.expect(git(dir, { "status", "--porcelain" })).toBe("")
	t.expect(fs.isDir(`{dir}/.git`) or fs.isFile(`{dir}/.git`)).toBe(true)
	local gitDir = git(dir, { "rev-parse", "--absolute-git-dir" })
	t.expect(fs.isDir(`{gitDir}/rebase-merge`) or fs.isDir(`{gitDir}/rebase-apply`)).toBe(false)
end

return t.spec("restack unites the records of a rebase", function(it)
	it("sets up a one-layer raft with a record", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/c0010.md"] = `---\nid: c0010\ntype: chore\ntitle: alpha\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# c0010\n\n{CAPTURED}`,
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = "",
		}
		f = trackerfix.new("c0263-restack-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\ncase "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo body; exit 0 ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = table.clone(HUMAN)
		env.PATH = `{bin}:{process.env.PATH or ""}`
		zn(f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		wtMain = trackerfix.trOk(f, f.main, { "worktree", "main-writer" })
		zn(wt, { "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		-- the base record: one published row, in the layer's branch too
		zn(
			wtMain,
			{ "provenance", "record", "c0010", "unblocked", "--actor", "human:Base", "--detail", "by=Base" }
		)
		git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		git(wt, { "push", "-q", "-u", "origin", "R0010/1/c0010" })
	end)

	it("main appends while a layer appends: restack unites both and goes on", function()
		appendRow(wt, layerRecord(), "Layer")
		git(wt, { "push", "-q" })
		git(wtMain, { "pull", "-q", "origin", "main" })
		zn(
			wtMain,
			{ "provenance", "record", "c0010", "unblocked", "--actor", "human:Main", "--detail", "by=Main" }
		)
		local out = zn(wt, { "restack", "R0010" })
		t.expect(has(out, "restacked R0010")).toBe(true)
		clean(wt)
		local text = fs.readFile(`{wt}/{layerRecord()}`)
		t.expect(rowsOf(text)).toEqual({ "human:Base", "human:Main", "human:Layer" })
		t.expect(git(wt, { "rev-parse", "origin/R0010/1/c0010" })).toBe(git(wt, { "rev-parse", "HEAD" }))
		t.expect(git(wt, { "merge-base", "--is-ancestor", "origin/main", "HEAD" })).toBe("")
		-- a second run changes nothing
		t.expect(has(zn(wt, { "restack", "R0010" }), "already stacked")).toBe(true)
	end)

	it("a layer that moved the item's folder while main appended: the record follows the move", function()
		-- one commit moves the folder and appends six rows: too different for git to pair the old record with the new one
		-- (the old path is modified by main and deleted by the layer, the new one added: three stages on two paths)
		git(wt, { "mv", `{ISSUES}/active/c0010`, `{ISSUES}/done/c0010` })
		local moved = `{wt}/{ISSUES}/done/c0010/provenance.md`
		local more = fs.readFile(moved)
		for _, who in { "Mva", "Mvb", "Mvc", "Mvd", "Mve", "Mvf" } do
			more ..= `| 2026-11-08 11:00 | unblocked | human:{who} | by={who} |\n`
		end
		fs.writeFile(moved, more)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "layer move and rows" })
		git(wt, { "push", "-q" })
		git(wtMain, { "pull", "-q", "origin", "main" })
		zn(
			wtMain,
			{ "provenance", "record", "c0010", "unblocked", "--actor", "human:Again", "--detail", "by=Again" }
		)
		local out = zn(wt, { "restack", "R0010" })
		t.expect(has(out, "restacked R0010")).toBe(true)
		clean(wt)
		t.expect(fs.isFile(`{wt}/{layerRecord()}`)).toBe(false)
		t.expect(rowsOf(fs.readFile(`{wt}/{ISSUES}/done/c0010/provenance.md`))).toEqual({
			"human:Base",
			"human:Main",
			"human:Again",
			"human:Layer",
			"human:Mva",
			"human:Mvb",
			"human:Mvc",
			"human:Mvd",
			"human:Mve",
			"human:Mvf",
		})
	end)

	it("a conflict in a file beside the records still stops the restack, with the layer as it was", function()
		local tip0 = git(wt, { "rev-parse", "HEAD" })
		fs.writeDir(`{wt}/pickman/src`)
		fs.writeFile(`{wt}/pickman/src/shared.luau`, "layer\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "layer source" })
		appendRow(wt, `{ISSUES}/done/c0010/provenance.md`, "Beside")
		git(wt, { "push", "-q" })
		local tip = git(wt, { "rev-parse", "HEAD" })
		git(wtMain, { "pull", "-q", "origin", "main" })
		fs.writeDir(`{wtMain}/pickman/src`)
		fs.writeFile(`{wtMain}/pickman/src/shared.luau`, "main\n")
		git(wtMain, { "add", "-A" })
		git(wtMain, { "commit", "-q", "-m", "main source" })
		git(wtMain, { "push", "-q", "origin", "HEAD:main" })
		zn(
			wtMain,
			{ "provenance", "record", "c0010", "unblocked", "--actor", "human:Beside2", "--detail", "by=B" }
		)
		local r = tr(wt, { "restack", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "restack stopped at R0010/1/c0010")).toBe(true)
		t.expect(has(r.stderr, "is not an item record")).toBe(true)
		clean(wt)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip)
		t.expect(git(wt, { "rev-parse", "origin/R0010/1/c0010" })).toBe(tip)
		git(wt, { "reset", "-q", "--hard", tip0 })
		git(wt, { "push", "-q", "--force-with-lease" })
	end)

	it(
		"a record main deleted (an id changed) stops the restack, naming the id, with the layer as it was",
		function()
			appendRow(wt, `{ISSUES}/done/c0010/provenance.md`, "Last")
			git(wt, { "push", "-q" })
			local tip = git(wt, { "rev-parse", "HEAD" })
			git(wtMain, { "pull", "-q", "origin", "main" })
			git(wtMain, { "rm", "-q", "-f", "-r", `{ISSUES}/active/c0010/provenance.md` })
			git(wtMain, { "commit", "-q", "-m", "main drops the record" })
			git(wtMain, { "push", "-q", "origin", "HEAD:main" })
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "restack stopped at R0010/1/c0010")).toBe(true)
			t.expect(has(r.stderr, "c0010:")).toBe(true)
			clean(wt)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip)
			t.expect(git(wt, { "rev-parse", "origin/R0010/1/c0010" })).toBe(tip)
		end
	)
end)
