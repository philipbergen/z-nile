--!strict
-- The spec orchestrator: between `./zn finish` and the spec runner. The gate itself
-- (`z-nile/check.sh`) starts `tests/run` directly. This command runs the specs a
-- finish selected and writes their passing case names to `--out`, a file in git.
--   lune run z-nile/specs -- run --project <name> [--out FILE] [--all | --slow | -- <spec path relative to the home>...]
--     without --slow, a spec in z-nile/tests/slow.tsv is left out; --slow runs only that list
--   lune run z-nile/specs -- scope
--     the one project the change set is confined to, or ALL (c0239)
-- Every listed spec runs. Nothing is reused and nothing is written outside the
-- results file `--out` names and the runner's own results file under the home's .cache.
-- The gate's command lines (the contract for the later Python port) are check.sh's header.

local changes = require("./lib/changed")
local context = require("./lib/context")
local fence = require("./tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./engine/projects")
local select = require("./lib/select")
local serde = require("@lune/serde")
local slow = require("./tests/lib/slow")
local stdio = require("@lune/stdio")
local trace = require("./engine/trace")

local ROOT = (string.gsub(process.cwd, "/+$", ""))

local function fail(message: string, code: number?)
	stdio.ewrite(`specs: {message}\n`)
	process.exit(code or 2)
end

-- the arguments without the separators lune leaves in front
local args: { string } = {}
for _, a in process.args do
	table.insert(args, a)
end
while args[1] == "--" do
	table.remove(args, 1)
end
local command = table.remove(args, 1)

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local function loadRegistry(): projects.Registry
	local ok, reg = pcall(projects.load)
	if not ok then
		fail(`cannot read the project registry: {reg}`)
	end
	return reg :: projects.Registry
end

local function homeOf(reg: projects.Registry, name: string): string
	local p = projects.named(reg, name)
	if p == nil then
		fail(`no project {name} in {projects.FILE}`)
	end
	return (p :: any).home
end

local function prefixOf(home: string): string
	return if home == "." then "" else home .. "/"
end

-- A record from a results file, checked field by field: the file lies in a .cache folder every spec may write, so its
-- content is untrusted input (review 003 F1). nil for anything that is not exactly a record for `file`.
local function validRecord(rec: any, file: string): any
	if
		type(rec) ~= "table"
		or rec.file ~= file
		or type(rec.loaded) ~= "boolean"
		or type(rec.cases) ~= "table"
	then
		return nil
	end
	local cases: { { name: string, ok: boolean } } = {}
	for _, c in rec.cases do
		if type(c) ~= "table" or type(c.name) ~= "string" or type(c.ok) ~= "boolean" then
			return nil
		end
		table.insert(cases, { name = c.name, ok = c.ok })
	end
	local seconds = if type(rec.seconds) == "number" and rec.seconds == rec.seconds then rec.seconds else 0
	return {
		file = file,
		loaded = rec.loaded,
		cases = cases,
		detail = if type(rec.detail) == "string" then rec.detail else "",
		seconds = seconds,
	}
end

-- ---------------------------------------------------------------------------------------------------- run
local function runCommand()
	local project: string? = nil
	local outFile: string? = nil
	local all, slowOnly = false, false
	local files: { string } = {}
	local i = 1
	local afterDashes = false
	while i <= #args do
		local a = args[i]
		if afterDashes then
			table.insert(files, a)
		elseif a == "--" then
			afterDashes = true
		elseif a == "--project" then
			project = args[i + 1]
			i += 1
		elseif a == "--out" then
			outFile = args[i + 1]
			i += 1
		elseif a == "--all" then
			all = true
		elseif a == "--slow" then
			slowOnly = true
		else
			fail(`unknown argument {a}`)
		end
		i += 1
	end
	if project == nil then
		fail("run needs --project <name>")
	end
	local reg = loadRegistry()
	local home = homeOf(reg, project :: string)
	local prefix = prefixOf(home)
	if all or #files == 0 then
		files = {}
		local abs: { string } = {}
		collect(`{if home == "." then "." else home}/tests`, abs)
		for _, p in abs do
			table.insert(files, string.sub(p, #(if home == "." then "./" else home .. "/") + 1))
		end
	end
	local tiers = if project == "z-nile" then slow.load(ROOT) else {}
	files = slow.keep(files, tiers, if slowOnly then "slow" else "fast")
	table.sort(files)

	local code = 0
	local byFile: { [string]: any } = {}
	if #files > 0 then
		local resultsFile = `{ROOT}/{prefix}.cache/spec-results-{fence.myPid()}.json`
		pcall(fs.writeDir, `{ROOT}/{prefix}.cache`)
		pcall(fs.removeFile, resultsFile)
		local argv = { "run", "tests/run", "--" }
		for _, f in files do
			table.insert(argv, f)
		end
		local r = process.exec("lune", argv, {
			cwd = if home == "." then ROOT else `{ROOT}/{home}`,
			env = { PICKMAN_RESULTS = resultsFile },
			stdio = "forward",
		})
		code = r.code

		local doc: any = nil
		local readOk, text = pcall(fs.readFile, resultsFile)
		if readOk then
			local decOk, decoded = pcall(serde.decode, "json" :: "json", text :: string)
			if decOk then
				doc = decoded
			end
		end
		pcall(fs.removeFile, resultsFile)
		if doc ~= nil and type(doc) == "table" and type(doc.files) == "table" then
			for _, f in files do
				for _, rec in doc.files do
					if type(rec) == "table" and rec.file == f then
						byFile[f] = validRecord(rec, f)
					end
				end
			end
		else
			doc = nil
		end
		if doc == nil then
			stdio.write("results file missing\n")
			if code == 0 then
				code = 1
			end
		else
			for _, f in files do
				if byFile[f] == nil then
					stdio.write(`FAIL {f}: no result for it\n`)
					code = 1
				end
			end
		end
	end
	if outFile ~= nil and code == 0 then
		local recorded: { trace.RecordedSpec } = {}
		local existingSpecs: { [string]: boolean } = {}
		for _, f in files do
			local rec = byFile[f]
			local greenCases: { string } = {}
			if rec ~= nil and type(rec.cases) == "table" then
				for _, c in rec.cases do
					if type(c) == "table" and c.ok == true and type(c.name) == "string" then
						table.insert(greenCases, c.name)
					end
				end
			end
			local fullPath = prefix .. f
			existingSpecs[fullPath] = true
			table.insert(recorded, { spec = fullPath, cases = greenCases })
		end
		if fs.isFile(outFile) then
			local prev, _ = trace.parseResults(fs.readFile(outFile))
			if prev ~= nil then
				for specPath, casesMap in prev do
					if not existingSpecs[specPath] then
						local list: { string } = {}
						for caseName in casesMap do
							table.insert(list, caseName)
						end
						table.sort(list)
						table.insert(recorded, { spec = specPath, cases = list })
					end
				end
			end
		end
		fs.writeFile(outFile, trace.renderResults(recorded))
	end
	process.exit(if code == 0 then 0 else 1)
end

-- c0239: the project the whole change set (the branch against its base, uncommitted and untracked files: what the
-- affected gate selects from) is confined to, or ALL. Prints that and nothing else; any unreadable fact is ALL.
local function scopeCommand()
	local ok, answer = pcall(function(): string
		local reg = loadRegistry()
		local ctx = context.build(reg)
		if ctx == nil then
			return "ALL"
		end
		return select.scope(ctx, changes.files(nil))
	end)
	print(if ok then answer else "ALL")
	process.exit(0)
end

if command == "run" then
	runCommand()
elseif command == "scope" then
	scopeCommand()
else
	fail("usage: specs run|scope (see the file's header)")
end
