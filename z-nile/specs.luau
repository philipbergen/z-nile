--!strict
-- The spec orchestrator (c0165): between the gate and the spec runner. It decides which spec files to run, runs them
-- through `lune run tests/run` in the project's home (the runner keeps its jail and guards), and keeps results in the
-- shared SQLite db, keyed by a fingerprint of everything a spec can read.
--   lune run z-nile/specs -- run --project <name> [--fresh] [--all | -- <spec path relative to the home>...]
--   lune run z-nile/specs -- digest --mode <affected|full> --projects <a,b> [--base REF]   -- the whole-gate digest
--   lune run z-nile/specs -- gate-check --digest D        -- exit 0 and the stored report when that gate passed
--   lune run z-nile/specs -- gate-record --digest D --mode M --projects P --summary FILE
-- It runs unjailed (check.sh does), so it alone writes the db; the runner's jail denies specs every write outside the
-- home's .cache. Reuse is off wherever the db, the blob read or the context can't be had: every spec then runs as before.

local changes = require("./lib/changed")
local context = require("./lib/context")
local fence = require("./tests/lib/fence")
local fingerprint = require("./lib/fingerprint")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./engine/projects")
local resultsdb = require("./lib/resultsdb")
local reuseplan = require("./lib/reuseplan")
local select = require("./lib/select")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local workspace = require("./lib/workspace")

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

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

local function git(argv: { string }): string?
	local r = process.exec("git", argv, { cwd = ROOT })
	return if r.ok then trim(r.stdout) else nil
end

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

-- the facts a fingerprint is made of; nil and a reason when any is unreadable (reuse off)
type State = { ctx: select.Context, blobs: fingerprint.Blobs, tools: string }
local function readState(reg: projects.Registry): (State?, string?)
	local ctx, why = context.build(reg)
	if ctx == nil then
		return nil, why
	end
	local blobs, blobWhy = workspace.blobs(ROOT)
	if blobs == nil then
		return nil, blobWhy
	end
	return { ctx = ctx, blobs = blobs, tools = workspace.tools(ROOT) }, nil
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

local function noRecordMarker(home: string, pid: string): string
	return `{ROOT}/{prefixOf(home)}.cache/spec-norecord-{pid}`
end

local function hostOs(): "macos" | "linux"
	return if process.os == "macos" then "macos" else "linux"
end

-- ---------------------------------------------------------------------------------------------------- run
local function runCommand()
	local project: string? = nil
	local fresh, all = false, false
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
		elseif a == "--fresh" then
			fresh = true
		elseif a == "--all" then
			all = true
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
	table.sort(files)

	-- reuse
	local state, why = readState(reg)
	local db: resultsdb.Db? = nil
	local reason: string? = why
	if state ~= nil then
		local path, pathWhy = workspace.dbPath(ROOT)
		if path == nil then
			reason = pathWhy
		else
			local opened, openWhy = resultsdb.open(path)
			if opened == nil then
				reason = openWhy
			else
				db = opened
			end
		end
	end
	if db == nil then
		stdio.write(`reuse off: {reason}\n`)
	end

	local fps: { [string]: string } = {}
	local toRun: { string } = {}
	local reusedCases, reusedFiles = 0, 0
	if db ~= nil and state ~= nil then
		local refs: { string } = {}
		for _, f in files do
			for _, r in fingerprint.refs(state.ctx, prefix .. f) do
				table.insert(refs, r)
			end
		end
		local gitState = workspace.gitState(ROOT, refs)
		if gitState == nil then
			db = nil
			stdio.write("reuse off: git state unreadable\n")
		else
			local list: { string } = {}
			for _, f in files do
				fps[f] =
					fingerprint.of(state.ctx, prefix .. f, state.blobs, state.tools, "affected", gitState)
				table.insert(list, fps[f])
			end
			local rowsOk, rows = pcall(resultsdb.rows, db :: resultsdb.Db, list)
			if not rowsOk then
				-- a db that can't be read turns reuse off; it never fails the gate
				stdio.write(`reuse off: {rows}\n`)
				db = nil
				rows = {}
			end
			for _, f in files do
				local row = rows[fps[f]]
				if reuseplan.decide(row, fresh) == "reuse" then
					stdio.write(`reused {f}\n`)
					reusedFiles += 1
					reusedCases += #(row :: any).cases
				else
					table.insert(toRun, f)
				end
			end
		end
	end
	if db == nil then
		toRun = files
	end

	local code = 0
	if #toRun > 0 then
		local resultsFile = `{ROOT}/{prefix}.cache/spec-results-{fence.myPid()}.json`
		pcall(fs.writeDir, `{ROOT}/{prefix}.cache`)
		pcall(fs.removeFile, resultsFile)
		local argv = { "run", "tests/run", "--" }
		for _, f in toRun do
			table.insert(argv, f)
		end
		local r = process.exec("lune", argv, {
			cwd = if home == "." then ROOT else `{ROOT}/{home}`,
			env = { PICKMAN_RESULTS = resultsFile },
			stdio = "forward",
		})
		code = r.code

		-- what the run recorded, and whether it may stand for the spec's content
		local doc: any = nil
		local readOk, text = pcall(fs.readFile, resultsFile)
		if readOk then
			local decOk, decoded = pcall(serde.decode, "json" :: "json", text :: string)
			if decOk then
				doc = decoded
			end
		end
		pcall(fs.removeFile, resultsFile)
		local byFile: { [string]: any } = {}
		if doc ~= nil and type(doc.files) == "table" then
			for _, rec in doc.files do
				byFile[rec.file] = rec
			end
		end
		if doc == nil then
			stdio.write(`results file missing: nothing from this run is recorded\n`)
			if code == 0 then
				code = 1
			end
		else
			for _, f in toRun do
				if byFile[f] == nil then
					stdio.write(`FAIL {f}: no result for it\n`)
					code = 1
				end
			end
		end
		if db ~= nil and state ~= nil and doc ~= nil then
			if code ~= 0 then
				-- no pass is recorded from a run that did not exit 0 (a spec can pass and the runner still fail, as the browser guard does)
				stdio.write(`results not recorded: the run exited {code}\n`)
			elseif not reuseplan.records(doc.jail or "", hostOs()) then
				stdio.write(`not recorded: {doc.jail or ""}\n`)
				local pid = process.env.PICKMAN_GATE_PID
				if pid ~= nil and pid ~= "" then
					pcall(fs.writeFile, noRecordMarker(home, pid), "")
				end
			else
				local after = workspace.blobs(ROOT)
				local now = os.time()
				-- the refs the run's specs declare, read once for all of them
				local union: { string } = {}
				local seen: { [string]: boolean } = {}
				for _, f in toRun do
					for _, ref in fingerprint.refs(state.ctx, prefix .. f) do
						if not seen[ref] then
							seen[ref] = true
							table.insert(union, ref)
						end
					end
				end
				local gitAfter = workspace.gitState(ROOT, union)
				local items: { resultsdb.Item } = {}
				for _, f in toRun do
					local rec = byFile[f]
					-- the same fingerprint under the content now: nothing it reads changed while it ran
					local stands = after ~= nil
						and gitAfter ~= nil
						and fingerprint.of(
								state.ctx,
								prefix .. f,
								after :: fingerprint.Blobs,
								state.tools,
								"affected",
								gitAfter :: fingerprint.GitState
							)
							== fps[f]
					if rec ~= nil and stands then
						table.insert(items, {
							fp = fps[f],
							home = home,
							spec = f,
							loaded = rec.loaded == true,
							cases = rec.cases or {},
							detail = if rec.detail ~= "" then rec.detail else nil,
							seconds = rec.seconds or 0,
						})
					end
				end
				-- one call, one transaction: every row and the prune, or nothing
				pcall(resultsdb.recordMany, db :: resultsdb.Db, items, now)
			end
		end
	end
	if reusedFiles > 0 then
		-- one closing line for the reused part; the runner printed its own for what it ran
		if #toRun == 0 then
			stdio.write(`{reusedCases} passed, 0 failed, {#files} spec files\n`)
		else
			stdio.write(`{reusedCases} reused cases in {reusedFiles} spec files\n`)
		end
	end
	process.exit(if code == 0 then 0 else 1)
end

-- ---------------------------------------------------------------------------------------------------- digest
-- The digest of a whole affected gate: the projects it covers, the base it compares with, the tools, every file's blob
-- and, when the selection holds a `*` spec, HEAD; always the union of the selected specs' declared refs.
local function digestOf(mode: string, names: { string }, base: string?): string?
	local reg = loadRegistry()
	local state = readState(reg)
	if state == nil then
		return nil
	end
	local starred = false
	local refSet: { [string]: boolean } = {}
	local changed = changes.files(base)
	for _, name in names do
		local sel = select.affected(state.ctx, changed, name)
		local specs: { string } = {}
		local prefix = prefixOf(homeOf(reg, name))
		if sel == "ALL" then
			for _, f in state.ctx.graph.files do
				if string.match(f, "%.spec%.luau$") and string.sub(f, 1, #prefix) == prefix then
					table.insert(specs, f)
				end
			end
		else
			for _, f in sel :: { string } do
				table.insert(specs, prefix .. f)
			end
		end
		for _, spec in specs do
			for _, e in (state.ctx.inputs[spec] :: { string }?) or ({} :: { string }) do
				if e == "*" then
					starred = true
				end
			end
			for _, ref in fingerprint.refs(state.ctx, spec) do
				refSet[ref] = true
			end
		end
	end
	local refs: { string } = {}
	for ref in refSet do
		table.insert(refs, ref)
	end
	table.sort(refs)
	local gitState = workspace.gitState(ROOT, refs)
	if gitState == nil then
		return nil
	end
	local baseRef = base
		or (if git({ "rev-parse", "--verify", "-q", "origin/main" }) ~= nil then "origin/main" else "main")
	local extra =
		fingerprint.digestExtra(mode, names, git({ "rev-parse", baseRef }) or "?", starred, gitState, refs)
	return fingerprint.digest(state.blobs, state.tools, extra)
end

local function optionValues(): { [string]: string }
	local out: { [string]: string } = {}
	local i = 1
	while i <= #args do
		local a = args[i]
		if string.sub(a, 1, 2) == "--" and args[i + 1] ~= nil then
			out[string.sub(a, 3)] = args[i + 1]
			i += 1
		end
		i += 1
	end
	return out
end

local function digestCommand()
	local opt = optionValues()
	local names = string.split(opt.projects or "", ",")
	if opt.mode ~= "affected" or #names == 0 or names[1] == "" then
		fail("digest needs --mode affected and --projects a,b")
	end
	local d = digestOf(opt.mode, names, opt.base)
	if d ~= nil then
		print(d)
	end
	process.exit(0)
end

local function openDb(): resultsdb.Db?
	local path = workspace.dbPath(ROOT)
	if path == nil then
		return nil
	end
	return (resultsdb.open(path))
end

local function gateCheckCommand()
	local opt = optionValues()
	local db = openDb()
	if db == nil or opt.digest == nil or opt.digest == "" then
		process.exit(1)
	end
	local gate = resultsdb.gatePassed(db :: resultsdb.Db, opt.digest)
	if gate == nil then
		process.exit(1)
	end
	print("reused: an affected gate passed on this content")
	stdio.write((gate :: any).summary)
	process.exit(0)
end

local function gateRecordCommand()
	local opt = optionValues()
	if opt.digest == nil or opt.mode == nil or opt.projects == nil or opt.summary == nil then
		fail("gate-record needs --digest, --mode, --projects and --summary")
	end
	local reg = loadRegistry()
	local db = openDb() -- the db exists after a record, whether or not this gate may record
	local pid = process.env.PICKMAN_GATE_PID
	if pid ~= nil and pid ~= "" then
		for _, name in string.split(opt.projects, ",") do
			local p = projects.named(reg, name)
			if p ~= nil and fs.isFile(noRecordMarker((p :: any).home, pid)) then
				process.exit(0) -- a run of this gate was not recorded: neither is the gate
			end
		end
	end
	if db == nil then
		process.exit(0)
	end
	local ok, summary = pcall(fs.readFile, opt.summary)
	if ok then
		pcall(
			resultsdb.recordGate,
			db :: resultsdb.Db,
			opt.digest,
			opt.mode,
			opt.projects,
			summary :: string,
			os.time()
		)
	end
	process.exit(0)
end

if command == "run" then
	runCommand()
elseif command == "digest" then
	digestCommand()
elseif command == "gate-check" then
	gateCheckCommand()
elseif command == "gate-record" then
	gateRecordCommand()
else
	fail("usage: specs run|digest|gate-check|gate-record (see the file's header)")
end
