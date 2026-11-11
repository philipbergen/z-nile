--!strict
-- Writes one measured row as its own file under `<item>/spend.d/`. Two checkouts appending for the same ticket
-- create different files, so a merge keeps both and neither side rewrites a shared file. spend.md stays the readable
-- ledger of reported rows; the reader assembles it with these files.
local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local ledger = require("./ledger")
local process = require("@lune/process")
local projects = require("./projects")
local store = require("./store")

local costrow = {}

local seq = 0

export type Write = {
	root: string,
	id: string,
	phase: string,
	subject: string,
	dir: string?,
	when: string?,
	wall: number?,
	cpu: number?,
	ai: number?,
	test: number?,
	tokens: number?,
	model: string?,
	added: number?,
	removed: number?,
	unmeasured: string?,
}

function costrow.report(text: string): (number?, number?)
	local wall = tonumber(string.match(text, "wall=([%d%.%-]+)"))
	local cpu = tonumber(string.match(text, "cpu=([%d%.%-]+)"))
	return wall, cpu
end

local function slug(s: string): string
	return (string.gsub(s, "[^%w._%-]", "-"))
end

function costrow.dirFor(root: string, id: string): string
	if string.match(id, "^[fdcR]%d%d%d%d$") then
		local ok, reg = pcall(projects.load, root)
		if ok then
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
		end
	end
	return `{root}/z-nile/.tracker/measures/{slug(id)}`
end

function costrow.owner(root: string): string
	local forced = process.env.ZN_MEASURE_ID
	if forced and forced ~= "" then
		return forced
	end
	local focus = `{root}/.cache/tracker-focus`
	if fs.isFile(focus) then
		local id = string.match(fs.readFile(focus), "%S+")
		if id and id ~= "" then
			return id
		end
	end
	local branch = process.exec("git", { "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = root })
	local name = if branch.ok then string.match(branch.stdout, "%S+") else nil
	if name and name ~= "" and name ~= "HEAD" then
		return name
	end
	return "unknown"
end

-- The path written, or nil and the reason. A failure here is the caller's to ignore: measuring never fails the
-- command it measured.
function costrow.write(w: Write): (string?, string?)
	if not ledger.isPhase(w.phase) then
		return nil, `unknown phase {w.phase}`
	end
	if w.model and not ledger.isModel(w.model) then
		return nil, `not a model id: {w.model}`
	end
	local dir = w.dir or costrow.dirFor(w.root, w.id)
	local made, err = pcall(fs.writeDir, `{dir}/spend.d`)
	if not made then
		return nil, tostring(err)
	end
	-- The second, the fraction, the pid and a random salt, and a bump when that name is already there.
	-- Two spends in one second (one process, or two machines) each get their own file.
	seq += 1
	local pid = tonumber(tostring((process :: any).pid)) or 0
	-- Wall-clock milliseconds, not os.clock: each ./zn spend is a new process, and os.clock starts near 0,
	-- so a later row could sort before an earlier one. The salt only separates two writes in the same millisecond.
	local ms = DateTime.now().unixTimestampMillis
	local stamp = os.date("!%Y%m%dT%H%M%SZ", math.floor(ms / 1000)) :: string
	local frac = string.format("%03d", ms % 1000)
	local salt = string.format("%04x", math.random(0, 0xffff))
	local path = `{dir}/spend.d/{stamp}-{frac}-{pid}-{seq}-{salt}.md`
	while fs.isFile(path) do
		seq += 1
		salt = string.format("%04x", math.random(0, 0xffff))
		path = `{dir}/spend.d/{stamp}-{frac}-{pid}-{seq}-{salt}.md`
	end
	local row: ledger.Row = {
		when = w.when or (os.date("!%Y-%m-%d %H:%M") :: string),
		subject = w.subject,
		added = w.added or 0,
		removed = w.removed or 0,
		minutes = 0,
		how = "measured",
		phase = w.phase,
		tokens = w.tokens,
		model = w.model,
		wall = w.wall,
		cpu = w.cpu,
		ai = w.ai,
		test = w.test,
		unmeasured = w.unmeasured,
	}
	local text = ledger.render(w.id, w.id, { row })
	local wrote, werr = pcall(fs.writeFile, path, text)
	if not wrote then
		return nil, tostring(werr)
	end
	return path, nil
end

return costrow
