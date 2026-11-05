--!strict
-- The reads behind a fingerprint (c0165): every file's git blob id (tracked, modified and untracked), git's state for
-- the refs a spec declares, the tools line, and the path of the shared results db. Adapter: it runs git and the tools,
-- and it writes nothing to git (no object, no index). Every read fails closed: nil and a reason, never a partial answer.

local fingerprint = require("./fingerprint")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local workspace = {}

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

-- git runs in the checkout (its cwd) with the subcommand first, the way a person types it: a wrapper on PATH sees it so
local function git(root: string, args: { string }, stdin: string?): (boolean, string)
	local r = if stdin
		then process.exec("git", args, { cwd = root, stdio = { stdin = stdin } })
		else process.exec("git", args, { cwd = root })
	return r.ok, r.stdout
end

local function nulSplit(text: string): { string }
	local out: { string } = {}
	for item in string.gmatch(text, "([^\0]+)") do
		table.insert(out, item)
	end
	return out
end

-- Whether a file is executable (git's 100755): asked of `test`, which Lune's fs does not expose.
local function executable(path: string): boolean
	return process.exec("test", { "-x", path }).ok
end

-- repo path -> "<mode> <blob id>" for every file present, tracked or not; ignored files are absent.
function workspace.blobs(root: string): (fingerprint.Blobs?, string?)
	local ok, staged = git(root, { "ls-files", "-s", "-z" })
	if not ok then
		return nil, "git ls-files failed"
	end
	local blobs: fingerprint.Blobs = {}
	for _, entry in nulSplit(staged) do
		local mode, id, _, path = string.match(entry, "^(%d+) (%x+) (%d)\t(.+)$")
		if mode == nil then
			return nil, `unreadable ls-files entry: {entry}`
		end
		if string.find(path, "\n", 1, true) then
			return nil, `a path holds a newline: {path}`
		end
		blobs[path] = `{mode} {id}`
	end
	local okMod, modified = git(root, { "ls-files", "-m", "-z" })
	local okNew, others = git(root, { "ls-files", "--others", "--exclude-standard", "-z" })
	if not okMod or not okNew then
		return nil, "git ls-files failed"
	end
	local toHash: { string } = {}
	for _, list in { nulSplit(modified), nulSplit(others) } do
		for _, path in list do
			if string.find(path, "\n", 1, true) then
				return nil, `a path holds a newline: {path}`
			end
			if fs.isFile(`{root}/{path}`) then
				table.insert(toHash, path)
			else
				blobs[path] = nil -- deleted
			end
		end
	end
	if #toHash > 0 then
		-- hash-object without -w computes the id and writes no object
		local okHash, out =
			git(root, { "hash-object", "--no-filters", "--stdin-paths" }, table.concat(toHash, "\n") .. "\n")
		if not okHash then
			return nil, "git hash-object failed"
		end
		local ids: { string } = {}
		for id in string.gmatch(out, "(%x+)\n") do
			table.insert(ids, id)
		end
		if #ids ~= #toHash then
			return nil, "hash-object returned another number of ids than paths"
		end
		for i, path in toHash do
			blobs[path] = `{if executable(`{root}/{path}`) then "100755" else "100644"} {ids[i]}`
		end
	end
	return blobs, nil
end

-- HEAD and only the requested full refs; a missing ref is absent, not an error.
function workspace.gitState(root: string, refs: { string }): (fingerprint.GitState?, string?)
	local ok, head = git(root, { "rev-parse", "HEAD" })
	if not ok then
		return nil, "git rev-parse HEAD failed"
	end
	local state: fingerprint.GitState = { head = trim(head), refs = {} }
	for _, ref in refs do
		local okRef, commit = git(root, { "rev-parse", "--verify", "-q", `{ref}^\{commit\}` })
		if okRef then
			state.refs[ref] = trim(commit)
		end
	end
	return state, nil
end

local function firstLine(s: string): string
	return string.match(s, "^[^\n]*") or ""
end

-- `uname -sm`, then --version of lune, rojo, selene, stylua, luau-lsp and git, then the sha256 of the types the gate
-- downloads, joined by " | "; a tool that fails to answer gives "<name>?".
function workspace.tools(root: string): string
	local parts: { string } = {}
	local u = process.exec("uname", { "-sm" })
	table.insert(parts, if u.ok then trim(u.stdout) else "uname?")
	for _, tool in { "lune", "rojo", "selene", "stylua", "luau-lsp", "git" } do
		local ok, r = pcall(process.exec, tool, { "--version" })
		if ok and r.ok then
			table.insert(parts, firstLine(r.stdout))
		else
			table.insert(parts, `{tool}?`)
		end
	end
	local types = `{root}/.cache/globalTypes.d.luau`
	table.insert(parts, if fs.isFile(types) then serde.hash("sha256", fs.readFile(types)) else "types?")
	return table.concat(parts, " | ")
end

-- <main checkout>/.claude/.znile_tests.sqlite: the parent of git's common dir, which must be <checkout>/.git.
-- Inside a spec run (PICKMAN_TEST_FENCE set) a result outside a .cache folder is refused: a nested orchestrator may
-- write only a fixture's db, never the real checkout's.
function workspace.dbPath(root: string): (string?, string?)
	local ok, out = git(root, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
	if not ok then
		return nil, "not in a git repository"
	end
	local common = trim(out)
	if string.sub(common, -5) ~= "/.git" then
		return nil, `the git common dir is not <checkout>/.git: {common}`
	end
	local path = `{string.sub(common, 1, -6)}/.claude/.znile_tests.sqlite`
	if
		process.env.PICKMAN_TEST_FENCE ~= nil
		and process.env.PICKMAN_TEST_FENCE ~= ""
		and not string.find(path, "/.cache/", 1, true)
	then
		return nil, `refusing a db outside .cache while a spec runs: {path}`
	end
	return path, nil
end

return workspace
