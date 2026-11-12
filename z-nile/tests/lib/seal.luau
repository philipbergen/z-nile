--!strict
-- Writes a matching approval.md beside a prepared issue in a fixture, so `./zn ready` can succeed.
-- `./zn approve` refuses in the fixture's main checkout and without a terminal, and the engine never
-- approves by itself. The caller commits the files (a seed commit, or its own). This writes nothing
-- for an issue that is not design: ready, has an unruled open-list bullet, or has no check.sh.

local approval = require("@znile/engine/approval")
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local openlist = require("@znile/engine/openlist")
local paths = require("@znile/engine/paths")
local store = require("@znile/engine/store")
local trace = require("@znile/engine/trace")

local seal = {}

local function hasCheck(text: string): boolean
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, '^%s*check "') then
			return true
		end
	end
	return false
end

local function docsUnder(dir: string, rel: string, out: { string })
	local base = if rel == "" then dir else `{dir}/{rel}`
	if not fs.isDir(base) then
		return
	end
	for _, name in fs.readDir(base) do
		if name ~= ".git" and name ~= ".cache" then
			local child = if rel == "" then name else `{rel}/{name}`
			local full = `{dir}/{child}`
			if fs.isDir(full) then
				docsUnder(dir, child, out)
			elseif string.match(child, "/([fdc]%d%d%d%d)/%1%.md$") then
				table.insert(out, child)
			end
		end
	end
end

-- Approval files for backlog issues in `dir` that ready would ask for. Returns how many it wrote.
function seal.stamp(dir: string, who: string?): number
	local name = contract.who(who or "fixture")
	if name == "" then
		return 0
	end
	local when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
	local docs: { string } = {}
	docsUnder(dir, "", docs)
	local wrote = 0
	for _, docRel in docs do
		if
			string.find(docRel, "/issues/active/", 1, true) or string.find(docRel, "/issues/done/", 1, true)
		then
			continue
		end
		local id = string.match(docRel, "([fdc]%d%d%d%d)/%.md$") :: string
		local itemDir = string.match(docRel, "^(.*)/[^/]+$") :: string
		local root = paths.rootOf(itemDir)
		if not root then
			continue
		end
		local doc = fs.readFile(`{dir}/{docRel}`)
		if string.match(doc, "\ndesign: ready\n") == nil then
			continue
		end
		if #openlist.pending(doc) > 0 then
			continue
		end
		local checkRel = `{itemDir}/check.sh`
		if not fs.isFile(`{dir}/{checkRel}`) or not hasCheck(fs.readFile(`{dir}/{checkRel}`)) then
			continue
		end
		local item: store.Item = {
			id = id,
			kind = "issue",
			state = "backlog",
			dir = itemDir,
			doc = docRel,
			slug = "",
			root = root,
		}
		local found = approval.verdict(dir, item)
		if found and found.state == "holds" then
			continue
		end
		local text = approval.append(dir, item, name, when)
		if not text then
			continue
		end
		fs.writeFile(`{dir}/{approval.file(item)}`, text)
		wrote += 1
	end
	return wrote
end

-- Writes a filled trace.md for a finished raft stack in `dir` and amends the top layer commit so
-- existing stack/done specs keep their single-commit layer shape while satisfying trace --check.
function seal.trace(dir: string, raftId: string)
	local skelRes = fixture.exec(dir, "bash", { "scripts/tracker.sh", "trace", raftId })
	if not skelRes.ok then
		error(`seal.trace {raftId} failed: {skelRes.stderr}{skelRes.stdout}`, 2)
	end
	local parsed, err = trace.parse(skelRes.stdout)
	if not parsed or err ~= nil then
		error(`seal.trace parse {raftId} failed: {err or "nil"}`, 2)
	end
	local raftFind = fixture.exec(dir, "bash", { "scripts/tracker.sh", "find", raftId })
	if not raftFind.ok then
		error(`seal.trace find {raftId} failed: {raftFind.stderr}`, 2)
	end
	local raftDir = (string.gsub(raftFind.stdout, "%s+$", ""))
	local issueDirs: { [string]: string } = {}
	local checkLines: { [string]: number } = {}
	for _, row in parsed.claims do
		local issueId = string.match(row.claimId, "^([^:]+):") :: string
		if issueId and not issueDirs[issueId] then
			local found = fixture.exec(dir, "bash", { "scripts/tracker.sh", "find", issueId })
			if not found.ok then
				error(`seal.trace find {issueId} failed: {found.stderr}`, 2)
			end
			local idir = (string.gsub(found.stdout, "%s+$", ""))
			issueDirs[issueId] = idir
			local checkText = fs.readFile(`{dir}/{idir}/check.sh`)
			local lineNo = 1
			local idx = 0
			for line in string.gmatch(checkText .. "\n", "([^\n]*)\n") do
				idx += 1
				if string.match(line, "^%s*check%s+") then
					lineNo = idx
					break
				end
			end
			checkLines[issueId] = lineNo
		end
	end
	local firstClaim = if #parsed.claims > 0 then parsed.claims[1].claimId else ""
	local codeRef = `{raftDir}/review-001.md:1`
	if #parsed.sources > 0 then
		codeRef = `{parsed.sources[1].file}:1`
	else
		local changed = fixture.git(dir, { "diff", "--name-only", "HEAD~1", "HEAD" })
		for p in string.gmatch(changed .. "\n", "([^\n]+)\n") do
			if p ~= "" and fs.isFile(`{dir}/{p}`) then
				codeRef = `{p}:1`
				break
			end
		end
	end
	local lines: { string } = {
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
		local issueId = string.match(row.claimId, "^([^:]+):") :: string
		local idir = issueDirs[issueId]
		local designRef = `{idir}/{issueId}.md:1`
		local testRef = `{idir}/check.sh:{checkLines[issueId] or 1}`
		table.insert(lines, `| {row.rawClaim} | {designRef} | {testRef} | {codeRef} |`)
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
	local traceRel = `{raftDir}/trace.md`
	fs.writeFile(`{dir}/{traceRel}`, table.concat(lines, "\n"))
	local commitEnv: { [string]: string }? = nil
	if not fixture.exec(dir, "git", { "config", "user.email" }).ok then
		commitEnv = {
			GIT_AUTHOR_NAME = "fixture",
			GIT_AUTHOR_EMAIL = "fixture@example.invalid",
			GIT_COMMITTER_NAME = "fixture",
			GIT_COMMITTER_EMAIL = "fixture@example.invalid",
		}
	end
	fixture.git(dir, { "add", traceRel }, { env = commitEnv })
	fixture.git(dir, { "commit", "-q", "--amend", "--no-edit" }, { env = commitEnv })
	if fixture.exec(dir, "git", { "remote", "get-url", "origin" }).ok then
		local branch = fixture.git(dir, { "branch", "--show-current" })
		if
			branch ~= "" and fixture.exec(dir, "git", { "rev-parse", "--verify", "-q", `origin/{branch}` }).ok
		then
			fixture.git(dir, { "push", "-q", "--force-with-lease", "origin", branch })
		end
	end
end

return seal
