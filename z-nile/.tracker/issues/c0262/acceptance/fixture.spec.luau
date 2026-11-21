--!strict
-- c0262: real git. A ticket's layer carries bookkeeping (a design review, a harvest, a final review); the view
-- built from it holds none of that, `./zn final` reads the reviews committed on the layer, and `./zn done`
-- refuses a stack with a ticket that stands off course. Fixture under .cache/final-e2e-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
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
	"final: ticket",
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
			local env = { PATH = `{bin}:{process.env.PATH or ""}`, ZN_FINAL_VIEW_ROOT = `{f.base}/views` }
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

			local dir = "pickman/.tracker/issues/active/c0010"
			znOk({ "start", "R0010" })
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
			write(wt, `{dir}/design-review-001.md`, "SECRET-REVIEW-TRAIL\n")
			write(wt, `{dir}/harvest.md`, "SECRET-HARVEST\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0010 implementation" })

			-- finished: the layer's own code review comes first (c0248, a raft readied with layers: reviewed), then the
			-- ticket's final review, before any next layer
			znOk({ "finish", "c0010" })
			t.expect(has(znOk({ "work", "next", "R0010" }), ": review c0010 - ")).toBe(true)
			seal.layerReview(wt, "c0010")
			t.expect(has(znOk({ "work", "next", "R0010" }), ": final-review-ticket c0010 - ")).toBe(true)
			t.expect(has(znOk({ "final", "c0010" }), "c0010: none")).toBe(true)
			-- reviewed but not on course: the layer is finished, not complete (completion.layer with `final`)
			t.expect(has(znOk({ "stack", "R0010" }), " c0010 finished ")).toBe(true)
			-- an older review sits on origin/main in the ticket's folder (a ticket that went back to z-design leaves
			-- its reviews there): it counts, and it judged another view
			trackerfix.elsewhere(
				f,
				{ [`{dir}/final-review-001.md`] = reviewText("on-course", string.rep("a", 64), nil) },
				"an earlier review"
			)
			git(wt, { "fetch", "-q", "origin" })
			-- the layer does not carry it yet: the review is read from origin/main's folder, and judged another view
			t.expect(has(znOk({ "final", "c0010" }), "c0010: review-again")).toBe(true)
			-- restacked onto the moved main, the layer carries it too
			znOk({ "restack", "R0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: review-again")).toBe(true)

			-- the view, written outside every checkout
			local listed = znOk({ "final", "c0010", "--view" })
			local view = `{f.base}/views/c0010`
			t.expect(has(listed, `{view}`)).toBe(true)
			t.expect(has(listed, "ask.md")).toBe(true)
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
			t.expect(fs.isFile(`{view}/design-changes.patch`)).toBe(false)
			local id = string.match(fs.readFile(`{view}/README.md`), "View: (%x+)") or ""
			t.expect(#id).toBe(64)

			-- off course on this view: redo by gap. done refuses.
			write(wt, `{dir}/final-review-002.md`, reviewText("off-course", id, "implementation"))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 2" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: redo-layer")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), ": rebuild c0010 - ")).toBe(true)
			local refused = zn({ "done", "R0010" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr .. refused.stdout, "c0010: the final review is redo-layer"))
				.toBe(true)

			-- the layer is rebuilt, and its design edited on the layer: re-finished (the committed review is kept),
			-- the view changed, the edit shown apart as a claim, and done still refuses (the redo is not reviewed yet)
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 2 }\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "rebuilt" })
			znOk({ "finish", "c0010" })
			seal.layerReview(wt, "c0010")
			-- (an approved ticket's design cannot change before the finish; after it the document may, which is why the
			-- view shows the change apart)
			write(
				wt,
				`{dir}/c0010.md`,
				(string.gsub(DOC, "Export `{ alpha = 1 }`", "Export `{ alpha = 2 }`"))
					.. "\n## Verification log\nTHE-WORKERS-NOTE\n"
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "design note" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: review-again")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), ": final-review-ticket c0010 - ")).toBe(true)
			local again = zn({ "done", "R0010" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr .. again.stdout, "c0010: the final review is review-again")).toBe(true)
			znOk({ "final", "c0010", "--view" })
			local id2 = string.match(fs.readFile(`{view}/README.md`), "View: (%x+)") or ""
			t.expect(id2 ~= id).toBe(true)
			t.expect(has(fs.readFile(`{view}/design.md`), "alpha = 1")).toBe(true)
			local changes = fs.readFile(`{view}/design-changes.patch`)
			t.expect(has(changes, "alpha = 2")).toBe(true)
			t.expect(has(changes, "THE-WORKERS-NOTE")).toBe(false)

			-- on course on the rebuilt view; main moves on (a capture touches z-nile/next, an engine file changes):
			-- the review still stands and the diff does not show main's work
			write(wt, `{dir}/final-review-003.md`, reviewText("on-course", id2, nil))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 3" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: on-course")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), ": final-review-ticket c0010 - ")).toBe(false)
			t.expect(has(znOk({ "stack", "R0010" }), " c0010 complete ")).toBe(true)
			trackerfix.elsewhere(
				f,
				{ ["z-nile/next"] = "999\n", ["pickman/src/mainonly.luau"] = "--!strict\nreturn {}\n" },
				"main moves on"
			)
			git(wt, { "fetch", "-q", "origin" })
			znOk({ "restack", "R0010" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: on-course")).toBe(true)
			znOk({ "final", "c0010", "--view" })
			local moved = fs.readFile(`{view}/diff.patch`)
			t.expect(has(moved, "mainonly")).toBe(false)
			t.expect(has(moved, "z-nile/next")).toBe(false)
			t.expect(has(moved, "alpha.luau")).toBe(true)

			-- a second off-course verdict blocks, even on a ticket that was once on course
			write(wt, `{dir}/final-review-003.md`, reviewText("off-course", id2, "design"))
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 3 off" })
			t.expect(has(znOk({ "final", "c0010" }), "c0010: blocked")).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), ": blocked c0010 - ")).toBe(true)
		end
	)
	it(
		"AC10: ./zn status <id> prepared marks the ticket final: ticket; an issue prepared before carries no mark",
		function()
			local f = trackerfix.new("final-mark-github.com", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["z-nile/projects.toml"] = FAST_PROJECTS,
				["pickman/.tracker/issues/c0020/c0020.md"] = (
					string.gsub(
						(string.gsub((string.gsub(DOC, "id: c0010", "id: c0020")), "raft: R0010", "raft: ")),
						`status: {(string.gsub(PREPARED, "%-", "%%-"))}\nfinal: ticket\n`,
						"status: new\n"
					)
				),
			})
			local doc = "pickman/.tracker/issues/c0020/c0020.md"
			t.expect(has(fs.readFile(`{f.main}/{doc}`), "final: ticket")).toBe(false)
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-c0020" })
			trackerfix.trOk(f, wt, { "status", "c0020", "preparing" })
			trackerfix.trOk(f, wt, { "status", "c0020", "prepared" })
			local front = string.match(fs.readFile(`{wt}/{doc}`), "^%-%-%-\n(.-)\n%-%-%-") or ""
			t.expect(has(front, "\nfinal: ticket")).toBe(true)
		end
	)
end)
