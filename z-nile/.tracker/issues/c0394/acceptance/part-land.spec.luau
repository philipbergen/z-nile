--!strict
-- c0394 AC2 to AC9, on c0248's layers: an added issue is published to origin/main, placed in the raft's order, never
-- committed on a layer, and shown on main while it waits; nothing lands above a waiting issue; `done` lands through the
-- member below the first waiting one and the raft stays active; reject is one published commit; stop gives a waiting added issue
-- back with the rest of its raft. Real git in a fixture under .cache/c0394-part-land (a bare origin whose path
-- contains github.com, a worktree per raft and a `gh` stub that keeps each PR's base), built as c0248's own
-- tests/acceptance/c0248/layers-land.spec.luau builds its rafts: a layer is start, work, finish, a tool-stamped review
-- committed in the issue's folder, and a landing is a final-review-NNN.md and trace-NNN.md in the raft folder.
--   R0010 is the user's example: it holds T1 (c0010); while T1's layer is open T2 is added in front (--before) and
--         T3 last, so the raft is T2, T1, T3. Nothing lands while T2 waits; T2 is approved and implemented, T1 is
--         restacked on it, T2 and T1 land through T1 with T3 waiting; T3 is approved, implemented and lands the raft.
--   R0020 holds V1 and gains W last: V1 lands through itself, then W is rejected, which moves the raft to done/.
--   R0030 holds X1 and gains Z in front of it: Z is rejected, which lets X1 land.
-- Approving and rejecting are the human's commands: they run under `script`, which gives them a terminal.
-- Needs c0248 (`depends_on`): its marker (`layers: reviewed`), complete layers, the per-landing files. Until c0248 is on
-- main these cases fail at the first command only c0248 or c0394 has; each tool command c0394 adds is first run as the
-- tool should run it, and when the tool does not yet make an added issue, the setup makes the same state by hand so the
-- later cases fail only for their own rule.
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local LESSONS = "z-nile/skills/zz-rules/lessons"
local T1 = "c0010"
local FOUND2 = "R0010 c0010 review-001 F3 high"
local FOUND3 = "R0010 c0010 layer"

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nThe {slug} theme.\n\n## Order & dependencies\n{issues}\n`
end

-- gh keeps each pull request's base in a file, numbered by the layer's branch: R00<r>0/<n>/... is PR <r><n>
local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
num() { echo "$1" | sed -n 's|^R00\(.\)0/\(.\)/.*|\1\2|p'; }
after() { want="$1"; shift; prev=""; for a in "$@"; do if [ "$prev" = "$want" ]; then echo "$a"; return; fi; prev="$a"; done; }
case "$1 $2" in
  "pr list") case "$*" in *number*) n=$(num "$(after --head "$@")"); [ -n "$n" ] && echo "$n" ;; esac; exit 0 ;;
  "pr create") n=$(num "$(after --head "$@")"); after --base "$@" > "@STATE@/base-$n"; echo "https://github.com/x/y/pull/$n"; exit 0 ;;
  "pr view") cat "@STATE@/base-$3" 2>/dev/null || echo main; exit 0 ;;
  "pr edit") n="$3"
    case "$*" in
      *--body-file*) cat > "@STATE@/body-$n.md" ;;
      *--base*) after --base "$@" > "@STATE@/base-$n" ;;
    esac
    exit 0 ;;
esac
exit 0
]=]

local f: trackerfix.Fixture
local log, state = "", ""
local env: { [string]: string } = {}
local wt1, wt2, wt3, wt4 = "", "", "", ""
local X = "" -- the added issue of R0040
local patchC = ""
local reviewsC: { string } = {}
local T2, T3, W, Z, Z2 = "", "", "", "", "" -- the added issues

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function zn(dir: string, args: { string }): string
	return must(tr(dir, args), "./zn " .. table.concat(args, " "))
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

-- ./zn <args> with a terminal on stdin and stdout, as the human runs approve and reject
local function human(dir: string, args: { string }): fixture.Result
	local merged: { [string]: string } = { PATH = env.PATH, HOME = process.env.HOME or "" }
	local argv = { "-q", "/dev/null", "./zn" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "script", argv, { env = merged })
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local function tree(): string
	return git(f.origin, { "ls-tree", "-r", "--name-only", "main" })
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

local function where(out: string, id: string): number
	return (string.find(out, id, 1, true)) or math.huge
end

local function stackText(raftId: string): string
	git(f.other, { "fetch", "-q", "--prune", "origin" })
	return zn(f.other, { "stack", raftId })
end

local function stackLine(raftId: string, id: string): string
	for line in string.gmatch(stackText(raftId), "[^\n]+") do
		if has(line, id) then
			return line
		end
	end
	return ""
end

local function work(dir: string, issueId: string, file: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{issueId} work`)
end

local function finishSha(dir: string, issueId: string): string
	for line in string.gmatch(git(dir, { "log", "--format=%H%x09%s", "-120" }) .. "\n", "([^\n]*)\n") do
		local sha, subject = string.match(line, "^(%x+)\t(.*)$")
		if sha and subject and string.sub(subject, 1, #issueId + 2) == `{issueId}: ` then
			return sha
		end
	end
	error(`no finish commit for {issueId}`, 2)
end

local function patchOf(dir: string, sha: string): string
	local r =
		fixture.exec(dir, "bash", { "-c", `git show --format= --no-color {sha} | git patch-id --stable` })
	return string.match(r.stdout, "^(%x+)") or ""
end

local function reviewFiles(dir: string, issueId: string): { string }
	local out: { string } = {}
	local base = `{dir}/{zn(dir, { "find", issueId })}`
	for _, name in fs.readDir(base) do
		if string.match(name, "^review%-%d+%.md$") or string.match(name, "^refute%-%d+%.md$") then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- A layer's review as the reviewer writes it (no stamp), committed by the tool, which stamps it.
local function review(dir: string, issueId: string)
	local folder = zn(dir, { "find", issueId })
	local top = 0
	for _, name in fs.readDir(`{dir}/{folder}`) do
		top = math.max(top, tonumber((string.match(name, "^review%-(%d+)%.md$"))) or 0)
	end
	write(dir, `{folder}/review-{string.format("%03d", top + 1)}.md`, "# Review\n\nVerdict: approve\n")
	zn(dir, { "commit", "-m", `tracker: review {issueId}` })
	git(dir, { "push", "-q" })
end

-- The final review and the trace of one landing, committed on the layer `dir` is on after its finish. Each landing has
-- its own: the round is the newest final review not yet on origin/main, else one more than the last on it.
local function sealBind(dir: string, raftId: string, through: string?)
	local args = { "trace", raftId }
	if through then
		table.insert(args, "--through")
		table.insert(args, through)
	end
	local parsed, err = trace.parse(zn(dir, args))
	if not parsed then
		error(`trace skeleton did not parse: {err}`, 2)
	end
	local raftDir = zn(dir, { "find", raftId })
	local top, topLocal = 0, 0
	for _, name in fs.readDir(`{dir}/{raftDir}`) do
		local k = tonumber((string.match(name, "^final%-review%-(%d+)%.md$")))
		if k then
			if fixture.exec(dir, "git", { "cat-file", "-e", `origin/main:{raftDir}/{name}` }).ok then
				top = math.max(top, k)
			end
			topLocal = math.max(topLocal, k)
		end
	end
	local num = string.format("%03d", if topLocal > top then topLocal else top + 1)
	local issueDirs: { [string]: string } = {}
	local checkLines: { [string]: number } = {}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		if not issueDirs[id] then
			issueDirs[id] = zn(dir, { "find", id })
			checkLines[id] = 1
			local idx = 0
			for line in string.gmatch(fs.readFile(`{dir}/{issueDirs[id]}/check.sh`) .. "\n", "([^\n]*)\n") do
				idx += 1
				if string.match(line, "^%s*check%s+") then
					checkLines[id] = idx
					break
				end
			end
		end
	end
	local codeRef = if #parsed.sources > 0 then `{parsed.sources[1].file}:1` else "none"
	local firstClaim = if #parsed.claims > 0 then parsed.claims[1].claimId else ""
	local lines = {
		`# Trace: {raftId}`,
		"",
		`Commit: {parsed.commit}`,
		"",
		"## Claims",
		"",
		"| claim | design | test | code |",
		"|---|---|---|---|",
	}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		table.insert(
			lines,
			`| {row.rawClaim} | {issueDirs[id]}/{id}.md:1 | {issueDirs[id]}/check.sh:{checkLines[id]} | {codeRef} |`
		)
	end
	table.insert(lines, "")
	table.insert(lines, "## Source files")
	table.insert(lines, "")
	table.insert(lines, "| file | claims |")
	table.insert(lines, "|---|---|")
	for _, srow in parsed.sources do
		table.insert(lines, `| {srow.file} | {firstClaim} |`)
	end
	table.insert(lines, "")
	write(dir, `{raftDir}/trace-{num}.md`, table.concat(lines, "\n"))
	write(dir, `{raftDir}/final-review-{num}.md`, `# Final Review {num}\n\nVerdict: approve\n`)
	git(dir, { "add", "-A", raftDir })
	git(dir, { "commit", "-qm", `{raftId}: final-review-{num}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

-- Starts a raft's first layer in a new worktree.
local function begin(raft: string): string
	local dir = trackerfix.trOk(f, f.main, { "worktree", raft })
	zn(dir, { "start", raft })
	return dir
end

-- Main moved (the added issue was published): put the layer back on it, as the tool tells to.
local function restacked(dir: string, raft: string)
	local branch = git(dir, { "branch", "--show-current" })
	git(dir, { "push", "-q", "origin", branch })
	zn(dir, { "restack", raft })
	git(dir, { "fetch", "-q", "origin" })
	git(dir, { "reset", "-q", "--hard", `origin/{branch}` })
end

-- ./zn new issue c <slug> --raft <raft> --wait --found <found> [--before <id>]
local function add(dir: string, raft: string, slug: string, found: string, before: string?): fixture.Result
	local args = { "new", "issue", "c", slug, "--raft", raft, "--wait", "--found", found }
	if before then
		table.insert(args, "--before")
		table.insert(args, before)
	end
	return tr(dir, args)
end

local function idOf(r: fixture.Result): string
	return string.match(r.stdout, "(c%d%d%d%d) waits for approval")
		or string.match(r.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md")
		or ""
end

-- The added issue as the tool should have published it: waits, found, before and idea in its frontmatter, and in the
-- raft's issues: line, on origin/main. When the tool did not publish it, publish what it made in the worktree.
local function ensurePublished(dir: string, raft: string, id: string, found: string, before: string?)
	local docPath = `{ROOT}/issues/active/{id}/{id}.md`
	if onOrigin(docPath) ~= nil then
		return
	end
	local doc = fs.readFile(`{dir}/{docPath}`)
	local extra = ""
	if not has(doc, "\nwaits: approval\n") then
		extra ..= "waits: approval\n"
	end
	if not has(doc, "\nfound: ") then
		extra ..= `found: {found}\n`
	end
	if before and not has(doc, "\nbefore: ") then
		extra ..= `before: {before}\n`
	end
	if extra ~= "" then
		doc = string.gsub(doc, "\nemergent: true\n", `\nemergent: true\n{extra}`, 1)
	end
	local raftPath = `{ROOT}/rafts/active/{raft}/{raft}.md`
	local rd = onOrigin(raftPath) or ""
	local line = string.match(rd, "\nissues: %[([^\n]*)%]") or ""
	if not has(line, id) then
		rd = string.gsub(rd, "\nissues: %[[^\n]*%]", `\nissues: [{line}, {id}]`, 1)
	end
	trackerfix.elsewhere(f, { [docPath] = doc, [raftPath] = rd }, `tracker: add {id} to {raft}`)
	-- what the tool made in the worktree is not part of the layer
	git(dir, { "checkout", "-q", "--", "." })
	git(dir, { "clean", "-fdq" })
end

-- The added issue designed to ready and published to main by another terminal (its prep, with its own pull request).
local function designOnMain(id: string)
	git(f.other, { "pull", "-q", "origin", "main" })
	local docPath = `{ROOT}/issues/active/{id}/{id}.md`
	local doc = fs.readFile(`{f.other}/{docPath}`)
	local front = string.match(doc, "^(%-%-%-\n.-\n%-%-%-\n)") :: string
	front = string.gsub(front, "design: %a+", "design: ready", 1)
	local body =
		`\n# {id}\n\n## Problem\nA finding.\n\n## Solution\nFix it.\n\n## Design\nGuess (prep) G1: the small way.\n\n## Acceptance criteria\n- AC1: it is fixed\n\n## Test plan\nThe check.\n`
	-- with c0369 section 5's explainer page of f0339's shape, naming this contract (re-prep of 2026-11-17)
	local hash = contract.hash((contract.build(front .. body, CHECK, {})) :: contract.Parts)
	trackerfix.elsewhere(f, {
		[docPath] = front .. body,
		[`{ROOT}/issues/active/{id}/check.sh`] = CHECK,
		[`{ROOT}/issues/active/{id}/acceptance/.gitkeep`] = "",
		[`{ROOT}/issues/active/{id}/explainer.html`] = `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{id}</title></head><body>`
			.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
			.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
			.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
			.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
			.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
			.. "</body></html>\n",
	}, `design {id}`)
end

-- The user approves an issue that is on origin/main with one command from the main checkout: c0369 records it in a
-- worktree of origin/main of its own and publishes it (the re-prep of 2026-11-17).
-- With c0369 section 5's fixture: stub openers first on PATH, and `yes y |` types the answer f0339 asks for (the exit
-- code is echoed inside script), so the helper holds before and after f0339.
local function approveOnMain(id: string)
	git(f.main, { "fetch", "-q", "origin" })
	local stubs = `{f.base}/stubs`
	if not fs.isDir(stubs) then
		fs.writeDir(stubs)
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{stubs}/{name}`, "#!/bin/sh\nexit 0\n")
			fixture.exec(f.main, "chmod", { "+x", `{stubs}/{name}` })
		end
	end
	local r = fixture.exec(
		f.main,
		"sh",
		{ "-c", `yes y | script -q /dev/null sh -c './zn approve {id}; echo "zn-exit=$?"'` },
		{ env = { PATH = `{stubs}:{env.PATH}`, HOME = process.env.HOME or "" } }
	)
	if
		string.match(r.stdout, "zn%-exit=(%d+)") ~= "0"
		or not has(r.stdout, `published {id} to origin/main: it counts now`)
	then
		error(`approve {id} failed: {say(r)}`, 0)
	end
end

return t.spec(
	"c0394 an added issue is placed in the raft, and the raft lands as far as its place allows",
	function(it)
		it("sets up four readied rafts behind a local github-shaped origin", function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
				[`{LESSONS}/idle-finding.md`] = "---\ntitle: An idle finding is not worth doing\nwhen: build\ntags: [finding, not-worth-doing]\ncheck: Is this finding the idle kind?\n---\nIt costs more than it saves.\n",
				[`{LESSONS}/plain-note.md`] = "---\ntitle: A plain note\nwhen: build\ntags: [finding]\ncheck: Is this a plain note?\n---\nNothing more.\n",
			}
			for _, row in
				{ { "R0010", "alpha", T1 }, { "R0020", "beta", "c0030" }, { "R0030", "gamma", "c0040" } }
			do
				local raft, slug, id = row[1], row[2], row[3]
				seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(raft, slug, id)
				seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
				seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, slug, raft)
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
				seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
			end
			-- R0040 holds A (c0060), B (c0070) and C (c0080)
			seed[`{ROOT}/rafts/R0040/R0040.md`] = raftDoc("R0040", "delta", "c0060, c0070, c0080")
			seed[`{ROOT}/rafts/R0040/check.sh`] = CHECK
			for _, id in { "c0060", "c0070", "c0080" } do
				seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, "delta", "R0040")
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
				seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
			end
			f = trackerfix.new("c0394-part-land-github.com", seed)
			local bin = `{f.base}/bin`
			log, state = `{f.base}/gh.log`, `{f.base}/gh-state`
			fs.writeDir(bin)
			fs.writeDir(state)
			fs.writeFile(`{bin}/gh`, (string.gsub((string.gsub(GH, "@LOG@", log)), "@STATE@", state)))
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			for _, raft in { "R0010", "R0020", "R0030", "R0040" } do
				trackerfix.trOk(f, f.main, { "ready", raft })
			end
			wt1 = begin("R0010")
			t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
			-- c0248 marks the rafts it readies: their layers are reviewed and every landing has its own files
			git(f.other, { "pull", "-q", "origin", "main" })
			t.expect(has(fs.readFile(`{f.other}/{ROOT}/rafts/active/R0010/R0010.md`), "\nlayers: reviewed\n"))
				.toBe(true)
		end)

		it(
			"new issue --raft --wait publishes the issue and the raft's issues: line in one commit, commits nothing on the layer, and says tell the user",
			function()
				-- T1's layer is open with work on it. T2 breaks with T1 (in front of the layer you are on); T3 can wait (last)
				work(wt1, T1, "alpha")
				local layerCommits = git(wt1, { "rev-list", "--count", "origin/main..HEAD" })
				local r2 = add(wt1, "R0010", "found-in-front", FOUND2, T1)
				T2 = idOf(r2)
				t.expect(T2 ~= "").toBe(true)
				-- each publication moves origin/main: put the layer back on it before the next
				ensurePublished(wt1, "R0010", T2, FOUND2, T1)
				restacked(wt1, "R0010")
				local r3 = add(wt1, "R0010", "found-last", FOUND3, nil)
				T3 = idOf(r3)
				t.expect(T3 ~= "").toBe(true)
				ensurePublished(wt1, "R0010", T3, FOUND3, nil)
				restacked(wt1, "R0010")

				t.expect(r2.ok).toBe(true)
				t.expect(has(r2.stdout, `{T2} waits for approval in R0010, before {T1}: tell the user`))
					.toBe(true)
				t.expect(r3.ok).toBe(true)
				t.expect(has(r3.stdout, `{T3} waits for approval in R0010, last: tell the user`)).toBe(true)
				-- published: the issue, with its record, and the raft's issues: line
				local doc2 = onOrigin(`{ROOT}/issues/active/{T2}/{T2}.md`) or ""
				for _, line in
					{
						"waits: approval",
						`found: {FOUND2}`,
						`before: {T1}`,
						"emergent: true",
						"idea: finding",
					}
				do
					t.expect(has(doc2, `\n{line}\n`)).toBe(true)
				end
				local doc3 = onOrigin(`{ROOT}/issues/active/{T3}/{T3}.md`) or ""
				t.expect(has(doc3, "\nwaits: approval\n")).toBe(true)
				t.expect(has(doc3, `\nfound: {FOUND3}\n`)).toBe(true)
				t.expect(has(doc3, "\nbefore: ")).toBe(false)
				local line = string.match(
					onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) or "",
					"\nissues: %[([^\n]*)%]"
				) or ""
				for _, id in { T1, T2, T3 } do
					t.expect(has(line, id)).toBe(true)
				end
				-- both edits in one commit, with the subject the design names
				local sha = git(
					f.origin,
					{ "log", "-1", "--format=%H", `--grep=^tracker: add {T2} to R0010 (before {T1})`, "main" }
				)
				t.expect(sha ~= "").toBe(true)
				local files = git(f.origin, { "show", "--name-only", "--format=", sha })
				t.expect(has(files, `issues/active/{T2}/{T2}.md`)).toBe(true)
				t.expect(has(files, "rafts/active/R0010/R0010.md")).toBe(true)
				t.expect(
					git(
						f.origin,
						{ "log", "-1", "--format=%H", `--grep=^tracker: add {T3} to R0010 (last)`, "main" }
					) ~= ""
				).toBe(true)
				-- nothing was committed on the layer
				t.expect(git(wt1, { "rev-list", "--count", "origin/main..HEAD" })).toBe(layerCommits)
			end
		)

		it("sets up T1 complete with T2 in front and T3 last", function()
			zn(wt1, { "finish", T1 })
			review(wt1, T1)
			t.expect(git(wt1, { "log", "--format=%s", "-3" }) ~= "").toBe(true)
		end)

		it("stack prints T2, T1, T3 and T1 keeps its branch and pull request", function()
			local out = stackText("R0010")
			t.expect(where(out, T2) < where(out, T1)).toBe(true)
			t.expect(where(out, T1) < where(out, T3)).toBe(true)
			t.expect(has(stackLine("R0010", T1), "R0010/1/c0010")).toBe(true)
			t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
			-- one branch and one pull request, for T1: no layer exists for T2 or T3
			local calls = fs.readFile(log)
			local _, created =
				string.gsub(calls, "pr create %-%-draft %-%-base main %-%-head R0010/1/c0010", "")
			t.expect(created).toBe(1)
			t.expect(has(calls, `/{T2}`)).toBe(false)
			t.expect(has(calls, `/{T3}`)).toBe(false)
		end)

		it("work next, list and the board read on main show T2 waiting and where it was found", function()
			git(f.main, { "pull", "-q", "origin", "main" })
			-- nothing lands (T2 waits in front of the only complete layer): the action is wait, naming T2
			local nextStep = tr(f.main, { "work", "next", "R0010" })
			t.expect(nextStep.ok).toBe(true)
			t.expect(has(nextStep.stdout, "R0010: wait")).toBe(true)
			t.expect(has(nextStep.stdout, `R0010 waits for the user: ./zn approve {T2}, or ./zn reject {T2}`))
				.toBe(true)
			-- ./zn list prints `waits (<found>)` after the title of a waiting issue
			local listed = zn(f.main, { "list", "active" })
			local row = ""
			for line in string.gmatch(listed, "[^\n]+") do
				if has(line, T2) then
					row = line
				end
			end
			t.expect(has(row, `waits ({FOUND2})`)).toBe(true)
			-- the board card says it waits for approval and where it was found
			zn(f.main, { "board", "-O" })
			local html = fs.readFile(`{f.main}/.cache/board.html`)
			t.expect(has(html, "waits for approval")).toBe(true)
			t.expect(has(html, FOUND2)).toBe(true)
		end)

		it("done lands nothing while T2 waits in front, and names T2", function()
			local before = git(f.origin, { "rev-parse", "main" })
			local r = tr(wt1, { "done", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					say(r),
					`R0010 has nothing to land: {T2} waits for ./zn approve {T2}, or ./zn reject {T2}`
				)
			)
				.toBe(true)
			t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
			t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`)).toBe(nil)
		end)

		it(
			"after approve, T2 opens in front as the next free layer number, T1 is restacked on it and stays reviewed",
			function()
				designOnMain(T2)
				approveOnMain(T2)
				local patch1 = patchOf(wt1, finishSha(wt1, T1))
				local reviews1 = reviewFiles(wt1, T1)
				git(wt1, { "fetch", "-q", "origin" })
				local started = tr(wt1, { "start", "R0010" })
				t.expect(started.ok).toBe(true)
				-- T1 keeps layer 1: the layer opened in front takes the next free number, cut from origin/main
				t.expect(git(wt1, { "branch", "--show-current" })).toBe(`R0010/2/{T2}`)
				t.expect(has(fs.readFile(log), `--base main --head R0010/2/{T2}`)).toBe(true)
				work(wt1, T2, "second")
				zn(wt1, { "finish", T2 })
				review(wt1, T2)
				zn(wt1, { "restack", "R0010" })
				git(wt1, { "fetch", "-q", "origin" })
				-- T1 now sits on T2's layer and its pull request targets it
				local below = fixture.exec(
					f.main,
					"git",
					{ "merge-base", "--is-ancestor", `origin/R0010/2/{T2}`, "origin/R0010/1/c0010" }
				)
				t.expect(below.ok).toBe(true)
				t.expect(has(fs.readFile(log), `--base R0010/2/{T2}`)).toBe(true)
				git(wt1, { "switch", "-q", "R0010/1/c0010" })
				git(wt1, { "reset", "-q", "--hard", "origin/R0010/1/c0010" })
				-- the rebase changed the commit and not the patch, so the review is still current
				t.expect(patchOf(wt1, finishSha(wt1, T1))).toBe(patch1)
				t.expect(reviewFiles(wt1, T1)).toEqual(reviews1)
				t.expect(has(stackLine("R0010", T1), " complete")).toBe(true)
			end
		)

		it("worktree re-entered checks out the layer of the last member with one", function()
			-- the highest layer number is T2's (2); the last member in the order that has a layer is T1 (1)
			t.expect(has(git(wt1, { "branch", "-r" }), `R0010/2/{T2}`)).toBe(true)
			git(f.main, { "worktree", "remove", "--force", wt1 })
			local path = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
			t.expect(path).toBe(wt1)
			t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		end)

		it(
			"done with no --through lands T2 and T1 and leaves the raft and T3 active on origin/main",
			function()
				sealBind(wt1, "R0010", nil)
				local r = tr(wt1, { "done", "R0010" })
				t.expect(r.ok).toBe(true)
				t.expect(has(r.stdout, `landed R0010 through {T1}: {T3} waits for ./zn approve {T3}`))
					.toBe(true)
				t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/issues/done/{T2}/{T2}.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
				t.expect(onOrigin(`{ROOT}/issues/active/{T3}/{T3}.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/issues/done/{T3}/{T3}.md`)).toBe(nil)
				local bind = git(f.origin, { "log", "-1", "--format=%B", "main" })
				local subject = string.match(bind, "^[^\n]*") or ""
				t.expect(has(subject, "R0010: bind")).toBe(true)
				t.expect(where(subject, T2) < where(subject, T1)).toBe(true) -- landed in the raft's order
				t.expect(has(bind, `Trace: {ROOT}/rafts/active/R0010/trace-001.md`)).toBe(true)
				t.expect(has(tree(), `{ROOT}/rafts/active/R0010/final-review-001.md`)).toBe(true)
			end
		)

		it("audit is green after that landing", function()
			git(f.main, { "pull", "-q", "origin", "main" })
			-- the landing happened: members done, the raft and the waiting issue still active
			t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/{T3}/{T3}.md`) ~= nil).toBe(true)
			local r = tr(f.main, { "audit" })
			t.expect(has(say(r), "0 errors")).toBe(true)
			t.expect(r.ok).toBe(true)
		end)

		it("--through refuses an issue at or above a waiting member", function()
			local before = git(f.origin, { "rev-parse", "main" })
			local r = tr(wt1, { "done", "R0010", "--through", T3 })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), T3)).toBe(true)
			t.expect(has(say(r), "waits")).toBe(true)
			t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
		end)

		it("--wait needs --raft and --found, and --before needs an unlanded member", function()
			local before = git(f.origin, { "rev-parse", "main" })
			local bare = tr(wt1, { "new", "issue", "c", "found-bare", "--wait", "--found", FOUND3 })
			local noFound = tr(wt1, { "new", "issue", "c", "found-unplaced", "--raft", "R0010", "--wait" })
			-- T1 has landed: it is not an unlanded member any more
			local landed = tr(wt1, {
				"new",
				"issue",
				"c",
				"found-landed",
				"--raft",
				"R0010",
				"--wait",
				"--found",
				FOUND3,
				"--before",
				T1,
			})
			local nowhere = tr(wt1, {
				"new",
				"issue",
				"c",
				"found-nowhere",
				"--raft",
				"R0010",
				"--wait",
				"--found",
				FOUND3,
				"--before",
				"c9999",
			})
			local unchanged = git(f.origin, { "rev-parse", "main" }) == before
			-- a tool that does not refuse leaves stray issues behind: clean the worktree so the cases below stand alone
			git(wt1, { "checkout", "-q", "--", "." })
			git(wt1, { "clean", "-fdq" })
			t.expect(bare.ok).toBe(false)
			t.expect(
				has(say(bare), "--wait needs --raft <R-id>: an added issue is made in the raft that found it")
			)
				.toBe(true)
			t.expect(noFound.ok).toBe(false)
			t.expect(has(say(noFound), "--found")).toBe(true)
			t.expect(landed.ok).toBe(false)
			t.expect(has(say(landed), `--before {T1}: {T1} is not an unlanded member of R0010`)).toBe(true)
			t.expect(nowhere.ok).toBe(false)
			t.expect(has(say(nowhere), "--before c9999: c9999 is not an unlanded member of R0010")).toBe(true)
			t.expect(unchanged).toBe(true)
		end)

		it("work next says wait when only T3 is left", function()
			local r = tr(wt1, { "work", "next", "R0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "R0010: wait")).toBe(true)
			t.expect(has(r.stdout, `R0010 waits for the user: ./zn approve {T3}, or ./zn reject {T3}`))
				.toBe(true)
		end)

		it("after approve, T3's layer starts on origin/main and done lands the raft", function()
			designOnMain(T3)
			approveOnMain(T3)
			git(wt1, { "fetch", "-q", "origin" })
			local started = tr(wt1, { "start", "R0010" })
			t.expect(started.ok).toBe(true)
			-- the next free number (T1 is 1, T2 is 2), cut from origin/main, which holds the first landing
			t.expect(git(wt1, { "branch", "--show-current" })).toBe(`R0010/3/{T3}`)
			t.expect(has(fs.readFile(log), `--base main --head R0010/3/{T3}`)).toBe(true)
			work(wt1, T3, "third")
			zn(wt1, { "finish", T3 })
			review(wt1, T3)
			sealBind(wt1, "R0010", nil)
			local r = tr(wt1, { "done", "R0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "landed R0010")).toBe(true)
			t.expect(has(r.stdout, "through")).toBe(false)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`)).toBe(nil)
			for _, id in { T1, T2, T3 } do
				t.expect(onOrigin(`{ROOT}/issues/done/{id}/{id}.md`) ~= nil).toBe(true)
			end
			-- the second landing has its own final review and trace
			t.expect(has(tree(), `{ROOT}/rafts/done/R0010/final-review-002.md`)).toBe(true)
			t.expect(has(tree(), `{ROOT}/rafts/done/R0010/trace-002.md`)).toBe(true)
		end)

		it("sets up R0040 with C built above a waiting X, and A and B landed", function()
			-- A, B, C in order; X is added in front of C while B is open, so the raft is A, B, X, C
			wt4 = begin("R0040")
			work(wt4, "c0060", "a")
			zn(wt4, { "finish", "c0060" })
			review(wt4, "c0060")
			zn(wt4, { "start", "R0040" })
			work(wt4, "c0070", "b")
			local rx = add(wt4, "R0040", "found-before-c", "R0040 c0070 layer", "c0080")
			X = idOf(rx)
			t.expect(X ~= "").toBe(true)
			ensurePublished(wt4, "R0040", X, "R0040 c0070 layer", "c0080")
			restacked(wt4, "R0040")
			zn(wt4, { "finish", "c0070" })
			review(wt4, "c0070")
			-- work goes on above the waiting X: C's layer opens, and is finished and reviewed
			zn(wt4, { "start", "R0040" })
			t.expect(git(wt4, { "branch", "--show-current" })).toBe("R0040/3/c0080")
			work(wt4, "c0080", "c")
			zn(wt4, { "finish", "c0080" })
			review(wt4, "c0080")
			patchC = patchOf(wt4, finishSha(wt4, "c0080"))
			reviewsC = reviewFiles(wt4, "c0080")
			-- A and B land (through B, the member below X); C does not
			git(wt4, { "switch", "-q", "R0040/2/c0070" })
			sealBind(wt4, "R0040", nil)
			local landed = tr(wt4, { "done", "R0040" })
			t.expect(landed.ok).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0060/c0060.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0070/c0070.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0080/c0080.md`)).toBe(nil)
		end)

		it(
			"a layer finished above a waiting issue stays finished when the layers below land, and is restacked on the issue once it is approved",
			function()
				git(wt4, { "fetch", "-q", "origin" })
				-- C's layer is as it was: the landing below did not touch it
				git(wt4, { "switch", "-q", "R0040/3/c0080" })
				git(wt4, { "reset", "-q", "--hard", "origin/R0040/3/c0080" })
				t.expect(patchOf(wt4, finishSha(wt4, "c0080"))).toBe(patchC)
				t.expect(reviewFiles(wt4, "c0080")).toEqual(reviewsC)
				-- X is approved and built; it is cut from origin/main, below C
				designOnMain(X)
				approveOnMain(X)
				git(wt4, { "fetch", "-q", "origin" })
				local started = tr(wt4, { "start", "R0040" })
				t.expect(started.ok).toBe(true)
				t.expect(git(wt4, { "branch", "--show-current" })).toBe(`R0040/4/{X}`)
				t.expect(has(fs.readFile(log), `--base main --head R0040/4/{X}`)).toBe(true)
				work(wt4, X, "x")
				zn(wt4, { "finish", X })
				review(wt4, X)
				-- restack puts C on X without a conflict
				local restack = tr(wt4, { "restack", "R0040" })
				t.expect(restack.ok).toBe(true)
				git(wt4, { "fetch", "-q", "origin" })
				local below = fixture.exec(
					f.main,
					"git",
					{ "merge-base", "--is-ancestor", `origin/R0040/4/{X}`, "origin/R0040/3/c0080" }
				)
				t.expect(below.ok).toBe(true)
				-- C is finished again on its new base, its patch and review are the same
				git(wt4, { "switch", "-q", "R0040/3/c0080" })
				git(wt4, { "reset", "-q", "--hard", "origin/R0040/3/c0080" })
				zn(wt4, { "finish", "c0080" })
				t.expect(patchOf(wt4, finishSha(wt4, "c0080"))).toBe(patchC)
				t.expect(reviewFiles(wt4, "c0080")).toEqual(reviewsC)
				t.expect(has(stackLine("R0040", "c0080"), " complete")).toBe(true)
			end
		)

		it("sets up R0020 landed through V1 with W last waiting", function()
			wt2 = begin("R0020")
			work(wt2, "c0030", "beta")
			local rw = add(wt2, "R0020", "found-last", "R0020 c0030 layer", nil)
			W = idOf(rw)
			t.expect(W ~= "").toBe(true)
			ensurePublished(wt2, "R0020", W, "R0020 c0030 layer", nil)
			restacked(wt2, "R0020")
			zn(wt2, { "finish", "c0030" })
			review(wt2, "c0030")
			sealBind(wt2, "R0020", nil)
			local landed = tr(wt2, { "done", "R0020" })
			t.expect(landed.ok).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) ~= nil).toBe(true)
		end)

		it(
			"stop gives a waiting added issue back with the rest, still a member of its raft, and ready takes it back",
			function()
				-- R0020 has landed V1 (c0030) and W waits, last; W's design is a stub (draft)
				git(f.main, { "pull", "-q", "origin", "main" })
				local stopped = tr(f.main, { "stop", "R0020" })
				t.expect(stopped.ok).toBe(true)
				-- the landed member stays in done/; the added issue is out of active/, a backlog issue of the same raft
				t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/issues/active/{W}/{W}.md`)).toBe(nil)
				local back = onOrigin(`{ROOT}/issues/{W}/{W}.md`) or ""
				t.expect(back ~= "").toBe(true)
				for _, line in { "raft: R0020", "waits: approval", "found: R0020 c0030 layer" } do
					t.expect(has(back, `\n{line}\n`)).toBe(true)
				end
				t.expect(has(back, "\nstatus: new")).toBe(true) -- its design is not ready
				local raftLine = string.match(
					onOrigin(`{ROOT}/rafts/R0020/R0020.md`) or "",
					"\nissues: %[([^\n]*)%]"
				) or ""
				t.expect(has(raftLine, W)).toBe(true)
				-- ready takes it back to active/ with the others, although its design is a draft, because it waits
				local readied = tr(f.main, { "ready", "R0020" })
				if not readied.ok then
					error(`ready R0020 refused: {say(readied)}`, 0)
				end
				t.expect(onOrigin(`{ROOT}/issues/active/{W}/{W}.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
			end
		)

		it("sets up R0030 with Z2 in front of Z in front of X1", function()
			wt3 = begin("R0030")
			work(wt3, "c0040", "gamma")
			local rz = add(wt3, "R0030", "found-in-front", "R0030 c0040 review-001 F1 high", "c0040")
			Z = idOf(rz)
			t.expect(Z ~= "").toBe(true)
			ensurePublished(wt3, "R0030", Z, "R0030 c0040 review-001 F1 high", "c0040")
			restacked(wt3, "R0030")
			-- Z2 goes in front of Z: an added issue placed before another added issue
			local rz2 = add(wt3, "R0030", "found-before-found", "R0030 c0040 review-001 F2 high", Z)
			Z2 = idOf(rz2)
			t.expect(Z2 ~= "").toBe(true)
			ensurePublished(wt3, "R0030", Z2, "R0030 c0040 review-001 F2 high", Z)
			restacked(wt3, "R0030")
			zn(wt3, { "finish", "c0040" })
			review(wt3, "c0040")
		end)

		it(
			"reject needs a not-worth-doing lesson, removes a waiting issue in one published commit, and moves a raft with nothing left to done",
			function()
				git(wt2, { "fetch", "-q", "origin" })
				local before = git(f.origin, { "rev-parse", "main" })
				-- a lesson that does not exist, a lesson without the tag, and a member that does not wait: all refused
				local unknown = human(wt2, { "reject", W, "--lesson", "no-such-lesson" })
				t.expect(unknown.ok).toBe(false)
				t.expect(has(say(unknown), "no-such-lesson")).toBe(true)
				local untagged = human(wt2, { "reject", W, "--lesson", "plain-note" })
				t.expect(untagged.ok).toBe(false)
				t.expect(has(say(untagged), "not-worth-doing")).toBe(true)
				local member = human(wt2, { "reject", "c0030", "--lesson", "idle-finding" })
				t.expect(member.ok).toBe(false)
				t.expect(has(say(member), "c0030")).toBe(true)
				-- the human's command: a pipe without a terminal is refused too
				t.expect(tr(wt2, { "reject", W, "--lesson", "idle-finding" }).ok).toBe(false)
				t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
				t.expect(onOrigin(`{ROOT}/issues/active/{W}/{W}.md`) ~= nil).toBe(true)

				-- W was the last member left: one published commit removes it and moves the raft to done/
				local rejected = human(wt2, { "reject", W, "--lesson", "idle-finding" })
				t.expect(rejected.ok).toBe(true)
				t.expect(git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
				t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" }))
					.toBe(`tracker: reject {W} (idle-finding)`)
				t.expect(onOrigin(`{ROOT}/issues/active/{W}/{W}.md`)).toBe(nil)
				t.expect(onOrigin(`{ROOT}/rafts/done/R0020/R0020.md`) ~= nil).toBe(true)
				t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`)).toBe(nil)
				t.expect(has(git(f.origin, { "log", "--format=%s", "main" }), "tracker: close")).toBe(false)
				local line = string.match(
					onOrigin(`{ROOT}/rafts/done/R0020/R0020.md`) or "",
					"\nissues: %[([^\n]*)%]"
				) or ""
				t.expect(has(line, W)).toBe(false)
			end
		)

		it("reject re-points an issue placed before the rejected one", function()
			-- Z2 waits in front of Z, which waits in front of X1; rejecting Z takes Z2 to Z's own place
			git(wt3, { "fetch", "-q", "origin" })
			local rejected = human(wt3, { "reject", Z, "--lesson", "idle-finding" })
			t.expect(rejected.ok).toBe(true)
			t.expect(has(say(rejected), Z2)).toBe(true) -- the command says Z2 was re-pointed
			t.expect(has(say(rejected), "before")).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/{Z}/{Z}.md`)).toBe(nil)
			t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" }))
				.toBe(`tracker: reject {Z} (idle-finding)`)
			local doc = onOrigin(`{ROOT}/issues/active/{Z2}/{Z2}.md`) or ""
			t.expect(doc ~= "").toBe(true)
			t.expect(has(doc, `\nbefore: {Z}\n`)).toBe(false)
			-- Z's own before: was c0040: Z2 takes it (or, with no before:, the key is gone and Z2 goes last)
			t.expect(has(doc, "\nbefore: c0040\n") or not has(doc, "\nbefore: ")).toBe(true)
		end)

		it("reject of an issue in front lets the layer behind it land", function()
			-- Z2 still waits in front of X1: nothing lands
			t.expect(tr(wt3, { "done", "R0030" }).ok).toBe(false)
			git(wt3, { "fetch", "-q", "origin" })
			local rejected = human(wt3, { "reject", Z2, "--lesson", "idle-finding" })
			t.expect(rejected.ok).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/{Z2}/{Z2}.md`)).toBe(nil)
			t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" }))
				.toBe(`tracker: reject {Z2} (idle-finding)`)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0030/R0030.md`) ~= nil).toBe(true) -- X1 has not landed yet
			-- main moved: restack, write the landing's final review and trace again, and land the raft
			zn(wt3, { "restack", "R0030" })
			git(wt3, { "fetch", "-q", "origin" })
			git(wt3, { "reset", "-q", "--hard", "origin/R0030/1/c0040" })
			sealBind(wt3, "R0030", nil)
			local landed = tr(wt3, { "done", "R0030" })
			t.expect(landed.ok).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0040/c0040.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0030/R0030.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0030/R0030.md`)).toBe(nil)
		end)
	end
)
