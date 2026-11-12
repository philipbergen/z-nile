--!strict
-- Measurements land in the checkout's `.cache/measure.tsv` (one appended line, gitignored). A tool commit
-- folds the lines for its tickets into `spend.d/<writer>.tsv`: one file per machine and checkout, one row
-- per line, runs of one stage collapsed. Nothing a check or a probe does writes a tracked path.
local DateTime = require("@lune/datetime")
local buffer = require("./buffer")
local fs = require("@lune/fs")
local ledger = require("./ledger")
local process = require("@lune/process")
local projects = require("./projects")
local store = require("./store")

local costrow = {}

export type PlannedFile = { path: string, text: string, previous: string? }
export type Planned = { files: { PlannedFile }, bufferText: string, bufferPrevious: string? }

function costrow.report(text: string): (number?, number?)
	local wall = tonumber(string.match(text, "wall=([%d%.%-]+)"))
	local cpu = tonumber(string.match(text, "cpu=([%d%.%-]+)"))
	return wall, cpu
end

function costrow.bufferFile(root: string): string
	local path = `{root}/.cache/measure.tsv`
	return path
end

function costrow.locate(root: string, id: string): string?
	if not string.match(id, "^[fdcR]%d%d%d%d$") then
		return nil
	end
	local ok, reg = pcall(projects.load, root)
	if not ok then
		return nil
	end
	local kind = if string.sub(id, 1, 1) == "R" then "raft" else "issue"
	for _, rel in projects.roots(reg) do
		local base = if rel == "." then root else `{root}/{rel}`
		for _, state in { "backlog", "active", "done" } do
			local dir = store.dirFor(kind, state :: store.State, id, base)
			if fs.isDir(dir) then
				return dir
			end
		end
	end
	return nil
end

function costrow.branchOf(root: string): (string, string)
	local branch = process.exec("git", { "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = root })
	local head = process.exec("git", { "rev-parse", "HEAD" }, { cwd = root })
	local name = if branch.ok then string.match(branch.stdout, "%S+") or "" else ""
	if name == "HEAD" then
		name = ""
	end
	local sha = if head.ok then string.match(head.stdout, "%S+") or "" else ""
	return name, sha
end

function costrow.writer(root: string): string
	local host = process.exec("hostname", {})
	local name = if host.ok then string.match(host.stdout, "%S+") or "host" else "host"
	name = (string.gsub(string.lower(name), "[^%w._%-]", "-"))
	local sum = 0
	for i = 1, #root do
		sum = (sum * 33 + (string.byte(root, i) :: number)) % 4294967296
	end
	return `{name}-{string.format("%08x", sum)}`
end

function costrow.append(root: string, line: buffer.Line): boolean
	if line.ms == 0 then
		line.ms = DateTime.now().unixTimestampMillis
	end
	local ran = process.exec("perl", {
		"-e",
		"require $ARGV[0]; znmeasure::append($ARGV[1], $ARGV[2]);",
		`{root}/z-nile/lib/measure.pl`,
		root,
		buffer.render(line),
	})
	return ran.ok
end

local function readFile(path: string): string?
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	return nil
end

function costrow.plan(
	root: string,
	homes: { [string]: string },
	extra: { [string]: { ledger.Row } }?,
	takeBegins: boolean
): Planned
	local path = costrow.bufferFile(root)
	local previous = readFile(path)
	local lines = buffer.parse(previous or "")
	local branch, head = costrow.branchOf(root)
	local ids: { string } = {}
	for id in homes do
		table.insert(ids, id)
	end
	local folded = buffer.fold(lines, ids, branch, head, DateTime.now().unixTimestampMillis, takeBegins)
	local byId: { [string]: { ledger.Row } } = folded.rows
	if extra then
		for id, more in extra do
			local list = byId[id]
			if not list then
				list = {}
				byId[id] = list
			end
			for _, row in more do
				table.insert(list, row)
			end
		end
	end
	local writer = costrow.writer(root)
	local files: { PlannedFile } = {}
	for id, list in byId do
		local dir = homes[id]
		if dir and #list > 0 and string.sub(id, 1, 1) ~= "R" then
			local file = `{dir}/spend.d/{writer}.tsv`
			local had = readFile(file)
			table.insert(files, { path = file, text = buffer.appendTsv(had, list), previous = had })
		end
	end
	table.sort(files, function(a: PlannedFile, b: PlannedFile): boolean
		return a.path < b.path
	end)
	return { files = files, bufferText = buffer.renderLines(folded.kept), bufferPrevious = previous }
end

local function parentOf(path: string): string
	return (string.match(path, "^(.*)/[^/]+$")) or "."
end

function costrow.writeFiles(planned: Planned): { string }
	local paths: { string } = {}
	for _, file in planned.files do
		fs.writeDir(parentOf(file.path))
		fs.writeFile(file.path, file.text)
		table.insert(paths, file.path)
	end
	return paths
end

function costrow.writeBuffer(root: string, planned: Planned)
	local path = costrow.bufferFile(root)
	local text = planned.bufferText
	local current = readFile(path)
	local previous = planned.bufferPrevious
	if previous and current and string.sub(current, 1, #previous) == previous and #current > #previous then
		text ..= string.sub(current, #previous + 1)
	end
	if text == "" then
		if fs.isFile(path) then
			fs.removeFile(path)
		end
		return
	end
	fs.writeDir(parentOf(path))
	fs.writeFile(path, text)
end

function costrow.restore(planned: Planned)
	for _, file in planned.files do
		if file.previous == nil then
			if fs.isFile(file.path) then
				fs.removeFile(file.path)
			end
		else
			fs.writeFile(file.path, file.previous)
		end
	end
end

function costrow.place(
	root: string,
	homes: { [string]: string },
	extra: { [string]: { ledger.Row } }?,
	takeBegins: boolean
): { string }
	local ok, planned = pcall(costrow.plan, root, homes, extra, takeBegins)
	if not ok or not planned then
		return {}
	end
	local wrote, paths = pcall(costrow.writeFiles, planned)
	if not wrote or not paths then
		pcall(costrow.restore, planned)
		return {}
	end
	local kept = pcall(costrow.writeBuffer, root, planned)
	if not kept then
		pcall(costrow.restore, planned)
		return {}
	end
	return paths
end

function costrow.readMeasured(dir: string): { ledger.Row }
	local rows: { ledger.Row } = {}
	local folder = `{dir}/spend.d`
	if not fs.isDir(folder) then
		return rows
	end
	local names = fs.readDir(folder)
	table.sort(names)
	for _, name in names do
		local file = `{folder}/{name}`
		if string.sub(name, -4) == ".tsv" then
			local parsed, err = buffer.parseTsv(fs.readFile(file))
			if not parsed then
				error(`{file} does not parse: {err}`, 0)
			end
			for _, row in parsed do
				table.insert(rows, row)
			end
		elseif string.sub(name, -3) == ".md" then
			local parsed, err = ledger.parse(fs.readFile(file))
			if not parsed then
				error(`{file} does not parse: {err}`, 0)
			end
			for _, row in parsed.rows do
				table.insert(rows, row)
			end
		end
	end
	return rows
end

return costrow
