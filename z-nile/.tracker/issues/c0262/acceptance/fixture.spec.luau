--!strict
-- c0262: real git. A ticket's layer carries bookkeeping (a design review, a harvest, a final review); the view
-- built from it holds none of that, `./zn final` reads the reviews committed on the layer, and `./zn done`
-- refuses a stack with a ticket that stands off course. Fixture under .cache/final-e2e-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local FAST_PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local DOC = table.concat({
	"---",
	"id: c0010",
	"type: chore",
	"title: alpha module",
	"slug: c0010",
	"raft: R0010",
	"depends_on: []",
	"emergent: false",
	"design: ready",
	"created: 2026-11-13",
	`status: {PREPARED}`,
	"---",
	"",
	"# c0010: alpha module",
	"",
	"## Problem",
	"User: the alpha value is not computed.",
	"",
	"## Solution",
	"Add `pickman/src/alpha.luau` returning the alpha table.",
	"",
	"## Design",
	"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
	"",
	"## Unknowns & experiments",
	"A compromise: design-review-001 F4 was refuted.",
	"",
	"## Acceptance criteria",
	"- AC1: alpha module exists",
	"",
}, "\n")

local function reviewText(verdict: string, view: string, gap: string?): string
	local body = "## Findings\n"
	if gap then
		body ..= `### F1\nGap: {gap}\nMeasured against: "the alpha value"\nmissing\n\n`
	end
	return `{body}View: {view}\nVerdict: {verdict}\n`
end

return t.spec("c0262 the final review on a real layer", function(it)
	it(
		"AC10: the view holds no trail, the state follows the reviews on the layer, done refuses off course",
		function()
			local check = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
				.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
			local raftCheck = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
				.. 'check "RC1: module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
			local f = trackerfix.new("final-e2e-github.com", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["z-nile/projects.toml"] = FAST_PROJECTS,
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			})
			for _, rel in
				{
					".luaurc",
					"pickman/.luaurc",
					"pickman/tests/run.luau",
					"pickman/tests/lib",
					"z-nile/tests/run.luau",
					"z-nile/tests/lib",
				}
			do
				local parent = string.match(rel, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{f.main}/{parent}`)
				end
				process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
			end
			write(f.main, "pickman/.tracker/issues/c0010/c0010.md", DOC)
			write(f.main, "pickman/.tracker/issues/c0010/check.sh", check)
			write(f.main, "pickman/.tracker/issues/c0010/acceptance/a.spec.luau", "--!strict\nreturn nil\n")
			write(
				f.main,
				"pickman/.tracker/rafts/R0010/R0010.md",
				table.concat({
					"---",
					"id: R0010",
					"type: chore",
					"title: one ticket",
					"slug: one-ticket",
					"single: false",
					"issues: [c0010]",
					"design: ready",
					"created: 2026-11-13",
					`status: {PREPARED}`,
					"---",
					"",
					"# R0010: one ticket",
					"",
					"## Order & dependencies",
					"c0010",
					"",
				}, "\n")
			)
			write(f.main, "pickman/.tracker/rafts/R0010/check.sh", raftCheck)
			require("@tests/lib/seal").stamp(f.main, "final-e2e")
			git(f.main, { "add", "-A" })
			git(f.main, { "commit", "-qm", "prep R0010" })
			git(f.main, { "push", "-q", "origin", "HEAD:main" })
			local bin = `{f.base}/bin`
			fs.writeDir(bin)
			fs.writeFile(
				`{bin}/gh`,
				'#!/bin/sh\ncase "$1 $2" in\n  "pr list") echo 1; exit 0 ;;\n  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo main; exit 0 ;;\n  "pr edit") exit 0 ;;\nesac\nexit 0\n'
			)
			process.exec("chmod", { "+x", `{bin}/gh` })
			local env = { PATH = `{bin}:{process.env.PATH or ""}` }
			trackerfix.trOk(f, f.main, { "ready", "R0010" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
			local function zn(args: { string }): fixture.Result
				return trackerfix.tr(f, wt, args, env)
			end
			local function znOk(args: { string }): string
				local r = zn(args)
				if not r.ok then
					error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
				end
				return (string.gsub(r.stdout, "%s+$", ""))
			end

			znOk({ "start", "R0010" })
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
			local dir = "pickman/.tracker/issues/active/c0010"
			write(wt, `{dir}/design-review-001.md`, "SECRET-REVIEW-TRAIL\n")
			write(wt, `{dir}/harvest.md`, "SECRET-HARVEST\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0010 implementation" })

			-- finished and unreviewed: the worker's next action is the ticket's final review, before any next layer
			znOk({ "finish", "c0010" })
			t.expect(has(znOk({ "work", "next", "R0010" }), "final-review-ticket")).toBe(true)

			-- no review yet
			t.expect(has(znOk({ "final", "c0010" }), "c0010: none")).toBe(true)

			-- the view
			local listed = znOk({ "final", "c0010", "--view" })
			local view = `{wt}/.cache/final/c0010`
			t.expect(has(listed, "ask.md")).toBe(true)
			t.expect(has(listed, "diff.patch")).toBe(true)
			local diff = fs.readFile(`{view}/diff.patch`)
			t.expect(has(diff, "alpha.luau")).toBe(true)
			t.expect(has(diff, "SECRET-REVIEW-TRAIL")).toBe(false)
			t.expect(has(diff, "SECRET-HARVEST")).toBe(false)
			local everything = ""
			for _, name in
				{
					"README.md",
					"ask.md",
					"design.md",
					"diff.patch",
					"contract/check.sh",
					"contract/acceptance/a.spec.luau",
				}
			do
				everything ..= fs.readFile(`{view}/{name}`)
			end
			t.expect(has(everything, "SECRET")).toBe(false)
			t.expect(has(everything, "A compromise")).toBe(false)
			t.expect(has(fs.readFile(`{view}/design.md`), "alpha = 1")).toBe(true)
			local readme = fs.readFile(`{view}/README.md`)
			local id = string.match(readme, "View: (%x+)") or ""
			t.expect(#id).toBe(64)

			-- off course on this view: redo by gap; a later view makes it review-again
			write(wt, `{dir}/final-review-001.md`, reviewText("off-course", id, "implementation"))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 1" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: redo-layer")).toBe(true)
			-- done refuses a ticket that stands off course
			local refused = zn({ "done", "R0010" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr .. refused.stdout, "c0010: the final review is redo-layer"))
				.toBe(true)

			-- the layer is rebuilt: the view changes, the review runs again
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 2 }\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "rebuilt" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: review-again")).toBe(true)
			znOk({ "final", "c0010", "--view" })
			local id2 = string.match(fs.readFile(`{view}/README.md`), "View: (%x+)") or ""
			t.expect(id2 ~= id).toBe(true)

			-- on course on the rebuilt view
			write(wt, `{dir}/final-review-002.md`, reviewText("on-course", id2, nil))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 2" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: on-course")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), "final-review-ticket")).toBe(false)

			-- a second off-course verdict blocks, even on a ticket that was once on course
			write(wt, `{dir}/final-review-002.md`, reviewText("off-course", id2, "design"))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 2 off" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: blocked")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), "blocked")).toBe(true)
		end
	)
end)
