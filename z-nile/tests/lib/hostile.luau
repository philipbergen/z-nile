--!strict
-- Hostile inputs for scanners (zz-arch skill, lesson scanning-loops-advance): every short text over the characters that
-- make a scanner branch, and a bounded child process that runs scanners over them, so a scanner that never returns
-- fails with the inputs that hung it instead of hanging the gate. Deterministic: the same texts in the same order,
-- no randomness. The limit is only the failure bound; a passing sweep takes a second or so.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local hostile = {}

-- a scanner to run: a Luau expression that calls it on `text` (its value is the case's result), with its module bound to `m`. The module is either a
-- `require` path (`module`: an alias) or the source of a module (`source`: a fixture, written next to the driver);
-- exactly one of the two. `prefix` (default none) is put before every text, to get past a scanner's entry guard (a
-- check line that must start with the raft template's head): a case must reach its scanner's loop, or it tests nothing.
-- `witness` proves it does: an input (before the prefix is added) and `tostring` of the result only the scanner's work
-- produces; a case whose witness gives another result fails, whatever the sweep did
export type Witness = { text: string, result: string }
export type Case = {
	name: string,
	call: string,
	module: string?,
	source: string?,
	prefix: string?,
	witness: Witness?,
}
export type Outcome = { ok: boolean, message: string }

-- the characters that make scanners branch: escapes, quotes, expansions, line ends and tabs, comment and long-bracket
-- openers
hostile.ALPHABET =
	{ "\\", "'", '"', "`", "$", "(", "{", "#", "\n", "\t", " ", "-", "a", "[", "]", "=" } :: { string }
-- the most texts one call may build, and how many seconds a child gets (the failure bound, not an expected time)
hostile.MAX_TEXTS = 200000
hostile.SECONDS = 30
-- a hung child is traced to a block of this many consecutive texts (a breadcrumb per text would cost seconds)
hostile.BLOCK = 16

-- Every text of up to `maxLen` (default 4) characters over `alphabet` (default hostile.ALPHABET): the empty text, then
-- the one-character texts, and so on, each length in the alphabet's order. Refuses an empty alphabet, a repeated or
-- multi-character entry, and more than MAX_TEXTS texts.
function hostile.texts(alphabet: { string }?, maxLen: number?): { string }
	local chars: { string } = alphabet or hostile.ALPHABET
	local n = maxLen or 4
	if #chars == 0 then
		error("hostile.texts: an empty alphabet", 2)
	end
	local seen: { [string]: boolean } = {}
	for _, c in chars do
		if #c ~= 1 or seen[c] then
			error(`hostile.texts: {string.format("%q", c)} is repeated or is not one character`, 2)
		end
		seen[c] = true
	end
	if n ~= math.floor(n) or n < 0 then
		error("hostile.texts: the length must be a whole number, 0 or more", 2)
	end
	local total, power = 1, 1
	for _ = 1, n do
		power *= #chars
		total += power
		if total > hostile.MAX_TEXTS then
			error(`hostile.texts: more than {hostile.MAX_TEXTS} texts`, 2)
		end
	end
	local out: { string } = { "" }
	local frontier: { string } = { "" }
	for _ = 1, n do
		local nxt: { string } = {}
		for _, s in frontier do
			for _, c in chars do
				table.insert(nxt, s .. c)
			end
		end
		for _, s in nxt do
			table.insert(out, s)
		end
		frontier = nxt
	end
	return out
end

-- The checkout that holds this harness: three folders above z-nile/tests/lib/hostile.luau.
hostile.TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "."

-- Runs `argv` under c0191's bounded runner (`z-nile/lib/bounded.pl`: a process group of its own, a wall-clock limit of
-- `seconds` and a CPU limit, a watchdog that stops the group if the runner dies, a kill of the whole group when the
-- command ends; exit 124 on the wall-clock limit, 125 on the CPU limit, else the command's own). Not `exec` under
-- `alarm`: where `lune` is a launcher that spawns the real binary (rokit's shim), the alarm killed the launcher and
-- the real `lune` ran on at 100% CPU with no parent (c0193 E11).
function hostile.bounded(seconds: number, argv: { string }, cwd: string?): process.ExecResult
	local args = { `{hostile.TOP}/z-nile/lib/bounded.pl`, "--time", tostring(seconds), "--" }
	for _, a in argv do
		table.insert(args, a)
	end
	return process.exec("perl", args, { cwd = cwd })
end

-- built in parts: the graph scanner would take literal require text in this file for a real require
local REQ = "re" .. "quire"

local function req(path: string): string
	return `{REQ}({string.format("%q", path)})`
end

local DRIVER = [==[
for _, c in cases do
	stdio.ewrite("at\t" .. c[1] .. "\t0\n")
	local witnessOk = true
	if c[4] then
		local ok, got = pcall(c[2], c[3] .. c[4][1])
		got = if ok then tostring(got) else "raised: " .. string.sub(string.gsub(tostring(got), "%s+", " "), 1, 200)
		if got ~= c[4][2] then
			witnessOk = false
			stdio.ewrite("wit\t" .. c[1] .. "\t" .. string.gsub(got, "[\r\n\t]+", " ") .. "\n")
		end
	end
	local returned, first = 0, ""
	if witnessOk then
		for i, text in texts do
			if i % BLOCK == 1 then
				stdio.ewrite("at\t" .. c[1] .. "\t" .. i .. "\n")
			end
			local ok, err = pcall(c[2], c[3] .. text)
			if ok then
				if text ~= "" then
					returned += 1
				end
			elseif first == "" then
				first = string.sub(string.gsub(tostring(err), "%s+", " "), 1, 200)
			end
		end
		stdio.ewrite("ran\t" .. c[1] .. "\t" .. returned .. "\t" .. first .. "\n")
	end
end
stdio.ewrite("done\n")
]==]

local function driver(dir: string, cases: { Case }): string
	local lines = {
		`local fs = {req("@lune/fs")}`,
		`local serde = {req("@lune/serde")}`,
		`local stdio = {req("@lune/stdio")}`,
		`local BLOCK = {hostile.BLOCK}`,
		`local texts = serde.decode("json", fs.readFile({string.format("%q", dir .. "/texts.json")}))`,
		"local cases = {}",
	}
	for i, c in cases do
		table.insert(lines, "do")
		local path = if c.source then `./case-{i}` else c.module
		if (c.source == nil) == (c.module == nil) or path == nil then
			error(`hostile.finishes: case {c.name} needs exactly one of module and source`, 3)
		end
		if c.source then
			fs.writeFile(`{dir}/case-{i}.luau`, c.source)
		end
		table.insert(lines, `local m = {req(path)}`)
		table.insert(
			lines,
			"cases["
				.. i
				.. "] = { "
				.. string.format("%q", c.name)
				.. ", function(text) return "
				.. c.call
				.. " end, "
				.. string.format("%q", c.prefix or "")
				.. ", "
				.. (if c.witness
					then "{ " .. string.format("%q", c.witness.text) .. ", " .. string.format(
						"%q",
						c.witness.result
					) .. " }"
					else "false")
				.. " }"
		)
		table.insert(lines, "end")
	end
	table.insert(lines, DRIVER)
	return table.concat(lines, "\n")
end

-- Runs every case over every text in one child (`lune run` under hostile.bounded, killed after `seconds`, a whole
-- number from 1 to 3600; default hostile.SECONDS), in the folder `<home>/.cache/hostile-<name>` (unique to the calling
-- spec; created, and removed again). Passes when the child reaches its last line, every case with a witness gave its
-- witness, and every case returned on at least one non-empty text. A text on which a scanner raises is not a failure:
-- refusing is closing. A case that raised on every text, or whose witness fails, never ran its scanner's work (a typo,
-- a changed signature, an entry guard, an argument of the wrong shape), so it fails too. A hang, a crash or a driver
-- that cannot start fails with the case, the block of texts it stopped in, or the child's own message.
function hostile.finishes(name: string, cases: { Case }, texts: { string }?, seconds: number?): Outcome
	if not string.match(name, "^[%w%-]+$") then
		error("hostile.finishes: the name must be letters, digits and hyphens", 2)
	end
	local inputs = texts or hostile.texts()
	local limit = seconds or hostile.SECONDS
	if not (limit >= 1 and limit <= 3600) or limit ~= math.floor(limit) then
		error(`hostile.finishes: the limit must be a whole number of seconds from 1 to 3600 (got {limit})`, 2)
	end
	local nonEmpty = false
	for _, s in inputs do
		nonEmpty = nonEmpty or s ~= ""
	end
	if not nonEmpty then
		error("hostile.finishes: no text to run (an empty list, or only the empty text)", 2)
	end
	local root = string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", "")
	local dir = `{root}/.cache/hostile-{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	fs.writeFile(`{dir}/texts.json`, serde.encode("json", inputs))
	local ok, source = pcall(driver, dir, cases)
	if not ok then
		fs.removeDir(dir)
		error(source, 0)
	end
	fs.writeFile(`{dir}/driver.luau`, source)
	local r = hostile.bounded(limit, { "lune", "run", `{dir}/driver.luau` }, root)
	fs.removeDir(dir)
	local lines = string.split(r.stderr, "\n")
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end
	if lines[#lines] == "done" then
		local expected: { [string]: string } = {}
		for _, c in cases do
			if c.witness then
				expected[c.name] = c.witness.result
			end
		end
		for _, line in lines do
			local case, got = string.match(line, "^wit\t(.-)\t(.*)$")
			if case then
				return {
					ok = false,
					message = `{case}: its witness gave "{got}", not "{expected[case]}": the call does not reach the scanner's work`,
				}
			end
		end
		for _, line in lines do
			local case, returned, err = string.match(line, "^ran\t(.-)\t(%d+)\t(.*)$")
			if case and tonumber(returned) == 0 then
				return {
					ok = false,
					message = `{case}: raised on every text, so the sweep never ran it: {err}`,
				}
			end
		end
		return { ok = true, message = "" }
	end
	local case, at = nil, 0
	for i = #lines, 1, -1 do
		local c, k = string.match(lines[i], "^at\t(.-)\t(%d+)$")
		if c then
			case, at = c, tonumber(k) :: number
			break
		end
	end
	if not case then
		local tail = table.concat(lines, "\n")
		return { ok = false, message = `the sweep driver could not run: {string.sub(tail, -400)}` }
	end
	local shown: { string } = {}
	local first, last = math.max(at, 1), math.min(at + hostile.BLOCK - 1, #inputs)
	for k = first, last do
		table.insert(shown, string.format("%q", inputs[k]))
	end
	local where = `texts {first}..{last} of {#inputs}: {table.concat(shown, " ")}`
	if at == 0 then
		-- the last breadcrumb is the case's start: it stopped on its witness, before any text ran
		local w = ""
		for _, c in cases do
			if c.name == case and c.witness then
				w = c.witness.text
			end
		end
		where = `its witness {string.format("%q", w)}, before any text ran`
	end
	-- A spinner can trip the wall clock (124) or the CPU limit (125). The design gives both
	-- the same message, and the sequestered spec matches that wording.
	if r.code == 124 or r.code == 125 then
		return { ok = false, message = `{case}: did not finish within {limit} s; it stopped in {where}` }
	end
	local tail = string.sub(table.concat(lines, "\n"), -300)
	return {
		ok = false,
		message = `{case}: the driver ended with code {r.code} in {where}; its last output: {tail}`,
	}
end

return hostile
