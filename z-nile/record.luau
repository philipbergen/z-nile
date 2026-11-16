--!strict
-- Appends one measurement to the checkout's cache. Exit 0 on success. A failure is printed and is a non-zero
-- exit; the caller that measured a command ignores it, so a row that cannot be written never fails that command.
-- The gate, a spec run and ./zn run append from the runner itself and do not start this.
local costrow = require("./engine/costrow")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sessionread = require("./engine/sessionread")
local sessions = require("./engine/sessions")
local stdio = require("@lune/stdio")

local root = process.env.ZN_TOP or process.cwd
local phase = "test"
local report: string? = nil
local subject = "measured"
local id = ""
local model: string? = nil
local tokens: number? = nil
local wall: number? = nil
local cpu: number? = nil
local ai: number? = nil
local test: number? = nil
local readSessions = false
local sinceIso: string? = nil
local extraFlags: { string } = {}

local i = 1
local args = process.args
while i <= #args do
	local a = args[i]
	local function take(): string
		i += 1
		return args[i] or ""
	end
	if a == "--phase" then
		phase = take()
	elseif a == "--report" then
		report = take()
	elseif a == "--subject" then
		subject = take()
	elseif a == "--id" then
		id = take()
	elseif a == "--model" then
		model = take()
	elseif a == "--tokens" then
		tokens = tonumber(take())
	elseif a == "--wall" then
		wall = tonumber(take())
	elseif a == "--cpu" then
		cpu = tonumber(take())
	elseif a == "--ai" then
		ai = tonumber(take())
	elseif a == "--test" then
		test = tonumber(take())
	elseif a == "--since" then
		sinceIso = take()
		readSessions = true
	elseif a == "--sessions" then
		readSessions = true
	elseif a == "--unmeasured" then
		table.insert(extraFlags, take())
	end
	i += 1
end

local flags: { string } = {}
for _, name in extraFlags do
	table.insert(flags, name)
end
if report and report ~= "" then
	if fs.isFile(report) then
		local w, c = costrow.report(fs.readFile(report))
		if wall == nil then
			wall = w
		end
		if cpu == nil then
			cpu = c
		end
	end
	if wall == nil then
		table.insert(flags, "wall")
	end
	if cpu == nil then
		table.insert(flags, "cpu")
	end
end
if phase == "test" and test == nil and wall ~= nil then
	test = wall
end
if readSessions then
	local untilIso = os.date("!%Y-%m-%dT%H:%M:%S") :: string .. ".999Z"
	local since = sinceIso or ((os.date("!%Y-%m-%dT%H:%M:%S") :: string) .. ".000Z")
	local sinceUnix = sessions.unix(since) or 0
	local untilUnix = sessions.unix(untilIso) or (sinceUnix + 1)
	local ok, reading = pcall(sessionread.span, process.cwd, since, sinceUnix, untilIso, untilUnix)
	if ok and reading then
		local got = reading :: any
		if tokens == nil then
			tokens = got.tokens
		end
		if ai == nil then
			ai = got.ai
		end
		if model == nil then
			model = got.model
		end
		if got.note and got.note ~= "" then
			subject = `{subject} {got.note}`
		end
		if got.unmeasured then
			table.insert(flags, got.unmeasured)
		end
	else
		table.insert(flags, "ai")
		table.insert(flags, "tokens")
	end
end
local branch, head = costrow.branchOf(root)
local kind = if phase == "test" then "test" elseif phase == "other" then "run" else "row"
local appended = costrow.append(root, {
	ms = 0,
	kind = kind,
	phase = phase,
	subject = subject,
	wall = wall,
	cpu = cpu,
	ai = ai,
	test = test,
	tokens = tokens,
	model = model,
	unmeasured = if #flags > 0 then table.concat(flags, ",") else nil,
	id = id,
	branch = branch,
	head = head,
})
if not appended then
	stdio.ewrite("record: could not append the measurement\n")
	process.exit(1)
end
print(costrow.bufferFile(root))
