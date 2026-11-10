--!strict
-- Which Bash commands an agent may start bare (c0191). Pure over the command text: the PreToolUse hook (z-nile/guard-bash)
-- reads the tool call and asks `check`. A command that starts an interpreter with no time limit is refused with the
-- wrapper to use instead: `./zn run --time 60 -- <command>` (z-nile/lib/bounded.pl). This is a seatbelt, not a jail: it
-- reads one shell line the way a person does (quotes, `;`, `&&`, `||`, `|`, `&`, `$(...)`, backticks, `sh -c '...'`,
-- `eval`, and prefix commands such as `env`, `time` and `xargs`) and refuses only what it positively recognises.
-- Anything it cannot read passes; `./zn reap` is the backstop for what slips through.

local boundcmd = {}

export type Context = {
	monitor: boolean?,
	background: boolean?,
	zn: string?,
	checkout: string?,
	cwd: string?,
	homes: { string }?,
}
export type Verdict = { ok: boolean, rule: string?, program: string?, command: string?, say: string? }

-- `lune run <target>` for these targets is the gate's own tooling: jailed, swept and CPU-limited by the runner
local TOOLING: { [string]: boolean } = {
	["tests/run"] = true,
	["z-nile/tests/run"] = true,
	["pickman/tests/run"] = true,
	["z-nile/affected"] = true,
	["z-nile/watch-check"] = true,
	["z-nile/roots"] = true,
	["scripts/affected"] = true,
}

local INTERPRETERS: { [string]: boolean } = {
	python = true,
	python3 = true,
	node = true,
	ruby = true,
	deno = true,
	bun = true,
	luau = true,
}
local DETACHERS: { [string]: boolean } =
	{ nohup = true, setsid = true, disown = true, daemonize = true, at = true }
-- a multiplexer or launcher is a detacher only in the form that starts something detached (`tmux ls` and `screen -ls` pass)
local function detaches(name: string, args: { string }): boolean
	if DETACHERS[name] then
		return true
	end
	if name == "tmux" then
		local sub = args[1]
		return (
			sub == "new"
			or sub == "new-session"
			or sub == "new-window"
			or sub == "run-shell"
			or sub == "run"
		)
				and table.find(args, "-d") ~= nil
			or sub == "run-shell"
			or sub == "run"
	end
	if name == "screen" then
		-- `-dm`, `-d -m`, `-md`: detached start (`-d` alone reattaches, `-m` alone attaches)
		local d, m = false, false
		for _, a in args do
			if string.match(a, "^%-[%a]*d") then
				d = true
			end
			if string.match(a, "^%-[%a]*m") then
				m = true
			end
		end
		return d and m
	end
	return name == "launchctl" and (args[1] == "submit" or args[1] == "bootstrap" or args[1] == "load")
end
-- `tail -f`, `watch` and `gh ... watch`: they end only when told to
local function FOLLOWERS(name: string, args: { string }): boolean
	if name == "watch" then
		return true
	end
	for _, a in args do
		if name == "tail" and (a == "--follow" or string.match(a, "^%-[%a%d]*[fF]")) then
			return true
		end
		if name == "gh" and (a == "watch" or a == "--watch") then
			return true
		end
	end
	return false
end

-- Inline Python (a `-c` script, or one a here-document feeds `python3 -`) is read the way `perl -e` is: it is refused only
-- when it loops for ever or starts a process with no timeout. A script in a file is refused (its contents are not read).
local function pythonHit(source: string): string?
	-- string literals are data: an edit that mentions `while True:` or `subprocess.` is not a loop or a process
	local script = string.gsub(
		string.gsub(string.gsub(source, '"""(.-)"""', '""'), "'''(.-)'''", "''"),
		"([\"'])[^\"'\n]*%1",
		"%1%1"
	)
	if
		string.find(script, "while%s*%(?%s*True%s*%)?%s*:")
		or string.find(script, "while%s*%(?%s*1%s*%)?%s*:")
	then
		return "loops for ever (`while True`)"
	end
	if string.find(script, "itertools%.count") or string.find(script, "itertools%.cycle") then
		return "iterates for ever (`itertools.count`/`cycle`)"
	end
	if
		string.find(script, "serve_forever")
		or string.find(script, "signal%.pause")
		or string.find(script, "os%.fork")
	then
		return "waits or forks for ever"
	end
	if
		string.find(script, "os%.system")
		or string.find(script, "os%.popen")
		or string.find(script, "os%.exec")
	then
		return "starts a process it cannot give a timeout (`os.system`)"
	end
	if
		(
			string.find(script, "subprocess%.")
			or string.find(script, "from%s+subprocess%s+import")
			or string.find(script, "import%s+subprocess%s+as")
		) and not string.find(script, "timeout%s*=")
	then
		return "starts a process with no `timeout=` (`subprocess`)"
	end
	return nil
end

local SHELLS: { [string]: boolean } = { sh = true, bash = true, zsh = true, dash = true }
-- commands that run another command: skip them (and their options) to find the program
local PREFIX: { [string]: boolean } = {
	env = true,
	time = true,
	command = true,
	exec = true,
	sudo = true,
	nice = true,
	xargs = true,
	timeout = true,
	stdbuf = true,
}
local EXEMPT_ARG: { [string]: boolean } = {
	["--version"] = true,
	["-v"] = true,
	["-V"] = true,
	["--help"] = true,
	["-h"] = true,
	help = true,
	setup = true,
	list = true,
}

local function basename(path: string): string
	return string.match(path, "([^/]*)$") or path
end

-- the call being judged (set by `check`): a Monitor command is bounded by its own timeout, so loops and follows pass
local CTX: {
	monitor: boolean,
	background: boolean,
	zn: string,
	checkout: string?,
	cwd: string?,
	dir: string?,
	line: string,
	homes: { string }?,
} =
	{
		monitor = false,
		background = false,
		zn = "./zn",
		checkout = nil,
		cwd = nil,
		dir = nil,
		line = "",
		homes = nil,
	}

-- `./x`, `../x`, `pickman/x` and `z-nile/x` all name the same tooling entry from any folder under the repository
local function normalise(target: string): string
	local t = target
	repeat
		local before = t
		t = string.gsub(t, "^%./", "")
		t = string.gsub(t, "^%.%./", "")
		t = string.gsub(t, "%.luau$", "")
		if t == before then
			break
		end
	until false
	return t
end

-- Whether `a` is `b` or inside it
local function insideOf(a: string, b: string): boolean
	local base = (string.gsub(b, "/+$", ""))
	return a == base or string.sub(a, 1, #base + 1) == base .. "/"
end

-- `<home>/tests/run` for a home of the registry (c0244): the same jailed runner as pickman's. A name that is not one plain
-- folder adds nothing (the registry only yields plain names, so these checks are a second fence and `normalise` already
-- strips `./` and `../`). Without `homes` (the registry could not be read) only TOOLING's entries count.
local function homeRunner(t: string): boolean
	local homes: { string } = CTX.homes or {}
	for _, home in homes do
		if
			home ~= ""
			and home ~= "."
			and home ~= ".."
			and not string.find(home, "/", 1, true)
			and t == `{home}/tests/run`
		then
			return true
		end
	end
	return false
end

-- The entry in TOOLING, in this checkout: a relative target from a folder inside it, or an absolute one under it (its
-- worktrees are inside it). A scratch copy of the tooling is not the gate's. Without a known checkout (the hook was
-- not told) the path alone decides.
local function toolingMatch(target: string): boolean
	local t = normalise(target)
	local checkout = CTX.checkout
	if string.sub(target, 1, 1) == "/" then
		if checkout ~= nil and not insideOf(target, checkout) then
			return false
		end
		if TOOLING[t] then
			return true
		end
		for key in TOOLING do
			if #t > #key and string.sub(t, -#key - 1) == "/" .. key then
				return true
			end
		end
		return false
	end
	-- the folder the command runs in: the call's, moved by the `cd`s before it (`checkText` keeps it); nil when a `cd` went
	-- somewhere the scanner cannot resolve, and then the entry does not match
	if checkout ~= nil and CTX.cwd ~= nil and (CTX.dir == nil or not insideOf(CTX.dir, checkout)) then
		return false
	end
	return TOOLING[t] == true or homeRunner(t)
end

-- Splits one shell line into simple commands (each a list of words, quotes removed) and the sub-commands inside
-- `$(...)` and backticks (as text, to be checked in turn).
local function split(text: string): ({ { string } }, { string }, { string }, { string })
	local commands: { { string } } = {}
	local ends: { string } = {} -- what ended each command: `;`, `|`, `&`, `&&`, a newline, ...
	local texts: { string } = {} -- each command's own text, quotes and all
	local segStart = 1
	local inner: { string } = {}
	local words: { string } = {}
	local word: { string }, started = {}, false
	local function endWord()
		if started then
			table.insert(words, table.concat(word))
		end
		word, started = {}, false
	end
	local function endCommand(sep: string?, at: number?)
		endWord()
		if #words > 0 then
			table.insert(commands, words)
			table.insert(ends, sep or "")
			table.insert(texts, (string.gsub(string.sub(text, segStart, (at or #text + 1) - 1), "^%s+", "")))
		end
		words = {}
		segStart = (at or #text) + #(sep or "")
	end
	local i, n = 1, #text
	while i <= n do
		local c = string.sub(text, i, i)
		local two = string.sub(text, i, i + 1)
		-- `2>&1`, `>&2`, `<&3`, `&>log`: a redirection, part of its word, never a separator
		local redirect = c == "&"
			and two ~= "&&"
			and (
				string.sub(text, i - 1, i - 1) == ">"
				or string.sub(text, i - 1, i - 1) == "<"
				or string.sub(text, i + 1, i + 1) == ">"
			)
		if c == "'" then
			local close = string.find(text, "'", i + 1, true) or n + 1
			table.insert(word, string.sub(text, i + 1, close - 1))
			started = true
			i = close + 1
		elseif c == '"' then
			started = true
			i += 1
			while i <= n and string.sub(text, i, i) ~= '"' do
				local d = string.sub(text, i, i)
				if d == "\\" and i < n then
					table.insert(word, string.sub(text, i + 1, i + 1))
					i += 2
				elseif string.sub(text, i, i + 1) == "$(" then
					local depth, j = 1, i + 2
					while j <= n and depth > 0 do
						local e = string.sub(text, j, j)
						depth += if e == "(" then 1 elseif e == ")" then -1 else 0
						j += 1
					end
					table.insert(inner, string.sub(text, i + 2, j - 2))
					table.insert(word, string.sub(text, i, j - 1))
					i = j
				else
					table.insert(word, d)
					i += 1
				end
			end
			i += 1
		elseif c == "\\" then
			table.insert(word, string.sub(text, i + 1, i + 1))
			started = true
			i += 2
		elseif two == "$(" then
			local depth, j = 1, i + 2
			while j <= n and depth > 0 do
				local e = string.sub(text, j, j)
				depth += if e == "(" then 1 elseif e == ")" then -1 else 0
				j += 1
			end
			table.insert(inner, string.sub(text, i + 2, j - 2))
			table.insert(word, string.sub(text, i, j - 1))
			started = true
			i = j
		elseif c == "`" then
			local close = string.find(text, "`", i + 1, true) or n + 1
			table.insert(inner, string.sub(text, i + 1, close - 1))
			table.insert(word, string.sub(text, i, close))
			started = true
			i = close + 1
		elseif c == "#" and not started then
			local nl = string.find(text, "\n", i, true) or n + 1
			i = nl
		elseif c == ";" or c == "|" or (c == "&" and not redirect) or c == "\n" or c == "(" or c == ")" then
			local sep = if two == "&&" or two == "||" or two == "|&" then two else c
			if sep == "&" and #words == 0 and not started and #ends > 0 then
				ends[#ends] = "&" -- `(cmd)&` and `{ cmd; }&`: the group before it is the job
				segStart = i + 1
			else
				endCommand(sep, i)
			end
			i += #sep
		elseif c == " " or c == "\t" then
			endWord()
			i += 1
		elseif (c == "{" or c == "}") and not started then
			endCommand(c, i) -- a brace group word: `{ cmd; }` starts a command, the brace is no program
			i += 1
		else
			table.insert(word, c)
			started = true
			i += 1
		end
	end
	endCommand()
	return commands, inner, ends, texts
end

local function isAssignment(w: string): boolean
	return string.match(w, "^[%a_][%w_]*=") ~= nil
end

local function refuse(rule: string, program: string, command: string, say: string): Verdict
	return { ok = false, rule = rule, program = program, command = command, say = say }
end

local OK: Verdict = { ok = true }

local checkText: (text: string, depth: number) -> Verdict

-- options of the prefix commands that take a value (the value is not the program)
local VALUE_OPTS: { [string]: { string } } = {
	timeout = { "-s", "-k", "--signal", "--kill-after" },
	sudo = { "-u", "-g", "-C", "-h", "-p", "-r", "-t", "-U" },
	nice = { "-n" },
	env = { "-u", "-C" },
	xargs = { "-n", "-I", "-P", "-L", "-d", "-s", "-E" },
	stdbuf = { "-i", "-o", "-e" },
}

local KEYWORD: { [string]: boolean } = {
	["do"] = true,
	["then"] = true,
	["else"] = true,
	["elif"] = true,
	["if"] = true,
	["while"] = true,
	["until"] = true,
	["!"] = true,
}

-- the program of a simple command and its arguments, after assignments, keywords and prefix commands
local function resolve(words: { string }): (string?, { string }, string?)
	local i = 1
	local loop: string? = nil
	while i <= #words do
		local w = words[i]
		if isAssignment(w) or KEYWORD[w] then
			if w == "while" or w == "until" then
				loop = w
			end
			i += 1
		elseif PREFIX[basename(w)] and i < #words then
			local prefix = basename(w)
			i += 1
			-- its options and (for env) assignments, and the duration `timeout` takes
			while i <= #words do
				local a = words[i]
				if prefix == "env" and (a == "-S" or a == "--split-string") and words[i + 1] ~= nil then
					-- `env -S 'cmd args'` runs the string as a command line
					return "sh", { "-c", words[i + 1] }, loop
				end
				local values = VALUE_OPTS[prefix]
				if values ~= nil and table.find(values, a) and words[i + 1] ~= nil then
					i += 2
					continue
				end
				local duration = (prefix == "timeout" or prefix == "nice")
					and string.match(a, "^[%d%.]+[smhd]?$") ~= nil
				if string.sub(a, 1, 1) == "-" or isAssignment(a) or duration then
					i += 1
				else
					break
				end
			end
		else
			break
		end
	end
	local program: string? = words[i]
	if program ~= nil and string.match(program, "^%d*[<>]") then
		program = nil -- a redirection left at the start of a command (`) > log 2>&1`) starts nothing
	end
	if program == nil then
		return nil, {}, loop
	end
	return program, table.move(words, i + 1, #words, 1, {}), loop
end

-- A command that is the gate, the wrapper or a check: bounded by its own means
local function boundedish(words: { string }): boolean
	local program, args = resolve(words)
	if program == nil then
		return false
	end
	local name = basename(program)
	if name == "zn" or name == "bounded.pl" or name == "ci-verify.sh" or string.match(name, "check%.sh$") then
		return true
	end
	if SHELLS[name] then
		for _, a in args do
			if string.match(a, "check%.sh$") then
				return true
			end
		end
	end
	if name == "lune" and args[1] == "run" and args[2] ~= nil then
		return toolingMatch(args[2])
	end
	return false
end

local checkCommand: (words: { string }, depth: number, raw: string?) -> Verdict

function checkCommand(words: { string }, depth: number, raw: string?): Verdict
	local program, args, loop = resolve(words)
	if
		loop ~= nil
		and not CTX.monitor
		and not (loop == "while" and program ~= nil and basename(program) == "read")
	then
		-- (`while read` ends at the end of its input)
		local line = string.sub(table.concat(words, " "), 1, 100)
		return refuse(
			"loop",
			loop,
			line,
			`a \`{loop}\` loop has no end of its own, and a foreground call past its timeout moves to the background and runs on. Run it as \`{CTX.zn} run --time <seconds> -- bash <script>\` (up to 3600; put the loop in a script file when it has quotes in it), or use the Monitor tool, which stops it at its timeout.`
		)
	end
	if program == nil then
		return OK
	end
	local name = basename(program)
	local line = raw or table.concat(table.move(words, #words - #args, #words, 1, {}), " ")
	if #line > 100 then
		line = string.sub(line, 1, 100) .. "..."
	end
	if name == "caffeinate" then
		local at = table.find(args, "-t")
		if at == nil then
			return refuse(
				"unbounded",
				name,
				line,
				`\`caffeinate\` without \`-t <seconds>\` never ends. Add \`-t\`, or run it as \`{CTX.zn} run --time <seconds> -- {line}\`.`
			)
		end
		-- `caffeinate -t N <command>` runs the command: judge it
		local rest = table.move(args, at + 2, #args, 1, {})
		return if #rest > 0 then checkCommand(rest, depth) else OK
	elseif not CTX.monitor and FOLLOWERS(name, args) then
		return refuse(
			"follow",
			name,
			line,
			`\`{name}\` here follows or watches for ever, and a foreground call past its timeout moves to the background and runs on. Run it as \`{CTX.zn} run --time <seconds> -- {line}\` (up to 3600), or use the Monitor tool.`
		)
	elseif detaches(name, args) then
		return refuse(
			"detach",
			name,
			line,
			`\`{name}\` would leave a process behind that nothing owns. Run it through \`{CTX.zn} run --time <seconds> -- <command>\`, which stops it when it ends, when you do, and at its limit.`
		)
	elseif SHELLS[name] then
		for k, a in args do
			if string.match(a, "^%-[%a]*c$") and args[k + 1] ~= nil then
				local at = if args[k + 1] == "--" and args[k + 2] ~= nil then k + 2 else k + 1
				return checkText(args[at], depth + 1)
			end
		end
		return OK
	elseif name == "eval" then
		return checkText(table.concat(args, " "), depth + 1)
	elseif name == "perl" then
		for k, a in args do
			local script = args[k + 1]
			if
				(a == "-e" or a == "-E")
				and script ~= nil
				and (
					string.find(script, "while%s*%(%s*1%s*%)")
					or string.find(script, "while%s+1%f[%W]")
					or string.find(script, "1%s+while%f[%W]")
					or string.find(script, "for%s*%(%s*;%s*;")
					or string.find(script, "until%s*%(%s*0%s*%)")
				)
			then
				return refuse(
					"unbounded",
					name,
					line,
					`this \`perl -e\` loops for ever. Run it as \`{CTX.zn} run --time <seconds> -- perl -e ...\`.`
				)
			end
			if (a == "-e" or a == "-E") and script ~= nil and string.find(script, "%f[%w_]alarm%f[^%w_]") then
				return refuse(
					"alarm",
					name,
					line,
					`\`perl -e 'alarm ...; exec @ARGV'\` stops only its own process: the process a command starts under it (\`lune\` starts its tool as a child) keeps running, orphaned. Use \`{CTX.zn} run --time <seconds> -- <command>\`, which stops the whole group.`
				)
			end
		end
		return OK
	elseif name == "lune" then
		for _, a in args do
			if a == "--help" or a == "-h" or a == "--version" then
				return OK
			end
		end
		local sub: string? = nil
		local k = 1
		while k <= #args do
			local a = args[k]
			if string.sub(a, 1, 1) == "-" and not EXEMPT_ARG[a] then
				k += 1
			else
				sub = a
				break
			end
		end
		if sub == nil or EXEMPT_ARG[sub] then
			return OK
		end
		local target: string? = nil
		if sub == "run" then
			for j = k + 1, #args do
				if string.sub(args[j], 1, 1) ~= "-" then
					target = args[j]
					break
				end
			end
		else
			target = sub -- `lune script` runs the script too
		end
		if sub == "repl" then
			return refuse(
				"interactive",
				name,
				line,
				`\`lune repl\` waits for input for ever; use \`{CTX.zn} run --time 30 -- lune run <script>\`.`
			)
		end
		if target ~= nil and toolingMatch(target) then
			return OK
		end
		return refuse(
			"unbounded",
			name,
			line,
			`\`{line}\` has no time limit, and nothing stops it when you end. Run it as \`{CTX.zn} run --time 60 -- {line}\` (the gate, \`./zn …\`, check.sh files and \`lune run tests/run\` need no wrapper).`
		)
	elseif INTERPRETERS[name] then
		if args[1] ~= nil and EXEMPT_ARG[args[1]] then
			return OK
		end
		if name == "python" or name == "python3" then
			-- `-c <script>` is read; `-` (a script on stdin, normally a here-document, read in `check`) passes; a file,
			-- `-m <module>` and the bare REPL are refused like any interpreter
			local k = 1
			while k <= #args do
				local a = args[k]
				if a == "-c" and args[k + 1] ~= nil then
					local hit = pythonHit(args[k + 1])
					if hit == nil then
						return OK
					end
					return refuse(
						"unbounded",
						name,
						line,
						`this \`{name} -c\` script {hit}. Run it as \`{CTX.zn} run --time 60 -- {name} ...\`, or add a timeout.`
					)
				elseif a == "-" then
					for _, b in args do
						-- `python3 - < probe.py`: a file fed on stdin is a file; a here-document (`<<`) is read in `check`
						if string.match(b, "^<[^<]") or b == "<" then
							return refuse(
								"unbounded",
								name,
								line,
								`a script fed from a file (\`{line}\`) is a file: its contents are not read. Run it as \`{CTX.zn} run --time 60 -- {name} ...\`.`
							)
						end
					end
					return OK
				elseif a == "-m" or string.sub(a, 1, 1) ~= "-" then
					break
				end
				k += 1
			end
		end
		return refuse(
			"unbounded",
			name,
			line,
			`\`{name}\` has no time limit, and nothing stops it when you end. Run it as \`{CTX.zn} run --time 60 -- {line}\`.`
		)
	elseif name == "rojo" then
		local serve = args[1] == "serve"
		for _, a in args do
			if a == "--watch" then
				serve = true
			end
		end
		if serve then
			return refuse(
				"unbounded",
				name,
				line,
				`\`rojo serve\` and \`--watch\` never end. Run it as \`{CTX.zn} run --time 300 -- rojo ...\`.`
			)
		end
	end
	return OK
end

function checkText(text: string, depth: number): Verdict
	if depth > 6 then
		return OK -- too deep to read: the backstop covers it
	end
	local commands, inner, _, texts = split(text)
	local start = CTX.dir
	for k, words in commands do
		local v = checkCommand(words, depth, texts[k])
		if not v.ok then
			CTX.dir = start
			return v
		end
		-- a `cd` moves the folder for the commands after it; an operand the scanner cannot resolve (a variable, `~`, `-`,
		-- none) leaves it unknown, and an unknown folder refuses the tooling match
		local program, args = resolve(words)
		if program ~= nil and basename(program) == "cd" and CTX.dir ~= nil then
			local operand = args[1]
			if operand == nil or string.find(operand, "[%$~`]") or operand == "-" then
				CTX.dir = nil
			else
				local parts: { string } = {}
				local from = if string.sub(operand, 1, 1) == "/" then operand else CTX.dir .. "/" .. operand
				for part in string.gmatch(from, "[^/]+") do
					if part == ".." then
						table.remove(parts)
					elseif part ~= "." then
						table.insert(parts, part)
					end
				end
				CTX.dir = "/" .. table.concat(parts, "/")
			end
		end
	end
	CTX.dir = start
	for _, sub in inner do
		local v = checkText(sub, depth + 1)
		if not v.ok then
			return v
		end
	end
	return OK
end

-- The verdict for one Bash command line. `ok = false` carries the rule that refused it, the program, the offending
-- command (cut at 100 characters) and the message to show the agent.
-- Commands that end by themselves and start nothing: a background call may mix them with the bounded ones
local TRIVIAL: { [string]: boolean } = {
	cd = true,
	echo = true,
	export = true,
	["true"] = true,
	["false"] = true,
	test = true,
	["["] = true,
	[":"] = true,
	pwd = true,
	printf = true,
	set = true,
	exit = true,
	wait = true,
	sleep = true,
	ls = true,
	mkdir = true,
	rm = true,
	rmdir = true,
	cp = true,
	mv = true,
	touch = true,
	ln = true,
	chmod = true,
	["[["] = true,
	["]]"] = true,
	read = true,
	basename = true,
	dirname = true,
	realpath = true,
	date = true,
	["for"] = true, -- a counted loop ends with its list (an unbounded one is refused on its own)
	case = true,
	done = true,
	fi = true,
	esac = true,
	["break"] = true,
	continue = true,
	["return"] = true,
	-- they end by themselves (a follow or a watch is refused on its own)
	git = true,
	gh = true,
	jq = true,
	seq = true,
	uptime = true,
	diff = true,
}

-- The filters end at the end of their input: after a pipe that is the end of the stage before; first in a command they
-- need a file to read (this many operands) or a `<` redirect, or they read the tool shell's stdin, which never closes.
-- (A follow is refused on its own.)
local FILTER_MIN: { [string]: number } = {
	cat = 1,
	head = 1,
	tail = 1,
	sort = 1,
	wc = 1,
	uniq = 1,
	cut = 1,
	sed = 2,
	awk = 2,
	grep = 2,
	tee = 99,
	tr = 99,
}

local function operands(args: { string }): (number, boolean)
	local n, redirected = 0, false
	local i = 1
	while i <= #args do
		local a = args[i]
		local skip = 1
		if a == "<" then
			redirected = true
			skip = 2 -- its file
		elseif string.match(a, "^%d*<") then
			redirected = true
		elseif
			a == ">"
			or a == ">>"
			or string.match(a, "^%d+>>?$")
			or a == "-n"
			or a == "-c"
			or a == "-e"
			or a == "-f"
			or a == "-s"
			or a == "-d"
		then
			skip = 2 -- a redirection's file, or an option's value, is no operand
		elseif string.sub(a, 1, 1) ~= "-" and not string.match(a, "^%d*>") then
			n += 1
		end
		i += skip
	end
	return n, redirected
end

function boundcmd.check(command: string, ctx: Context?): Verdict
	local c: Context = ctx or {}
	CTX.monitor, CTX.background, CTX.zn = c.monitor == true, c.background == true, c.zn or "./zn"
	CTX.checkout, CTX.cwd, CTX.dir, CTX.line = c.checkout, c.cwd, c.cwd, command
	CTX.homes = c.homes
	local text, bodies, pyBodies = boundcmd.withoutHeredocs(command)
	-- `for ((;;))` and the like: a C-style loop with no condition (quoted text does not count)
	local bare = string.gsub(string.gsub(text, "'[^']*'", "''"), '"[^"]*"', '""')
	if not CTX.monitor and string.find(bare, "%f[%w]for%s*%(%([^%)\n]-;%s*;") then
		return refuse(
			"loop",
			"for",
			string.sub(command, 1, 100),
			`a \`for ((;;))\` loop has no end of its own. Run it as \`{CTX.zn} run --time <seconds> -- bash <script>\` (up to 3600), or use the Monitor tool.`
		)
	end
	local v = checkText(text, 0)
	-- a `python3 -` whose script is not a here-document in this line (a pipe, a variable) cannot be read
	local dashes = 0
	for _, words in split(text) do
		local program, args = resolve(words)
		if program ~= nil and (basename(program) == "python" or basename(program) == "python3") then
			for _, a in args do
				if a == "-c" or a == "-m" or (string.sub(a, 1, 1) ~= "-" and a ~= "-") then
					break
				elseif a == "-" then
					dashes += 1
					break
				end
			end
		end
	end
	if v.ok and dashes > #pyBodies then
		v = refuse(
			"unbounded",
			"python3",
			string.sub(command, 1, 100),
			`a \`python3 -\` script that is not a here-document in this call cannot be read. Pass it as a here-document or \`-c\`, or run it as \`{CTX.zn} run --time 60 -- python3 -\`.`
		)
	end
	for _, body in pyBodies do
		local hit = pythonHit(body)
		if v.ok and hit ~= nil then
			v = refuse(
				"unbounded",
				"python3",
				string.sub(command, 1, 100),
				`this python script {hit}. Run it as \`{CTX.zn} run --time 60 -- python3 ...\` with the same here-document, or add a timeout.`
			)
		end
	end
	for _, body in bodies do
		if v.ok then
			v = checkText(body, 1) -- a here-document a shell reads is code
		end
	end
	if v.ok then
		local commands, _, ends = split(text)
		if CTX.background then
			-- every command of a background call must be bounded by its own means or end by itself
			local loose: string? = nil
			for k, words in commands do
				local program, args = resolve(words)
				if program ~= nil and not boundedish(words) and loose == nil then
					local nm = basename(program)
					local need = FILTER_MIN[nm]
					if need ~= nil then
						local piped = k > 1 and (ends[k - 1] == "|" or ends[k - 1] == "|&")
						local n, redirected = operands(args)
						if not piped and not redirected and n < need then
							loose = nm
						end
					elseif not TRIVIAL[nm] then
						loose = nm
					end
				end
			end
			if loose ~= nil then
				return refuse(
					"background",
					loose or "",
					string.sub(command, 1, 100),
					`a background call has no one waiting for it, and nothing stops it when you end, and every command in it must be bounded{if loose
						then ` (\`{loose}\` is not)`
						else ""}. Start it as \`{CTX.zn} run --time <seconds> -- <command>\` (up to 3600), or run only the gate, \`{CTX.zn}\` commands and check.sh files.`
				)
			end
		end
		-- a job started with a single `&`: the call's shell ends (or a Monitor's expires) and the job's parent is gone, and
		-- the wrapper (which stops its command when the process that started it is gone) stops a wrapped one at once;
		-- an unwrapped one is a leak. Unless the call waits for it.
		local waits = false
		for _, words in commands do
			local program = resolve(words)
			waits = waits or (program ~= nil and basename(program) == "wait")
		end
		for _, sep in ends do
			if sep == "&" and not waits then
				return refuse(
					"background",
					"&",
					string.sub(command, 1, 100),
					`a job started with \`&\` has no one waiting for it when the call returns. Start it with the Bash tool's run_in_background: true, wrapped as \`{CTX.zn} run --time <seconds> -- <command>\` (up to 3600); or add a \`wait\` to the call.`
				)
			end
		end
	end
	return v
end

-- The text with the bodies of here-documents (`<<EOF` ... `EOF`) removed, and the bodies a shell reads, which are code.
-- A `<<` counts only as an operator that has its terminator line later (an unterminated one, a `<<<` here-string, a
-- shift in `$((1<<2))` and a `<<` in a quoted string hide nothing), and a body is data unless the command that
-- reads it is a shell.
function boundcmd.withoutHeredocs(text: string): (string, { string }, { string })
	local lines = string.split(text, "\n")
	local out: { string } = {}
	local bodies: { string } = {}
	local pyBodies: { string } = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		table.insert(out, line)
		local before, dash, _, word = string.match(line, "^(.-[^<])<<(%-?)%s*(['\"]?)([%w_]+)%3")
		if word == nil then
			before, dash, word = string.match(line, "^(.-[^<])<<(%-?)%s*\\([%w_]+)") -- `<<\EOF`
		end
		local terminated: number? = nil
		if before ~= nil and word ~= nil and not string.find(before, "%(%(") then
			for j = i + 1, #lines do
				if lines[j] == word or (dash == "-" and (string.gsub(lines[j], "^\t+", "")) == word) then
					terminated = j
					break
				end
			end
		end
		if terminated ~= nil and before ~= nil then
			-- the command that owns the here-document: the last simple command before the `<<`, as `split` reads it
			local segment = split(before)
			local first = if #segment > 0 then resolve(segment[#segment]) else nil
			local after = string.match(line, "<<%-?%s*['\"]?[%w_]+['\"]?(.*)$") or ""
			local piped = string.match(after, "|%s*[%w/]-%f[%w](%a[%w]*)%f[%W]")
			local isPython = (first ~= nil and (basename(first) == "python" or basename(first) == "python3"))
				or piped == "python"
				or piped == "python3"
			if isPython then
				table.insert(pyBodies, table.concat(lines, "\n", i + 1, terminated - 1))
			end
			local reads = first ~= nil
				and (SHELLS[basename(first)] or first == "eval" or first == "source" or first == ".")
			-- a body that a shell reads is code, whether the command names the shell or pipes into it (`cat <<EOF | bash`)
			if reads or (piped ~= nil and SHELLS[piped]) then
				table.insert(bodies, table.concat(lines, "\n", i + 1, terminated - 1))
			end
			i = terminated
		end
		i += 1
	end
	return table.concat(out, "\n"), bodies, pyBodies
end

-- The refusal as the hook prints it.
function boundcmd.explain(v: Verdict): string
	return `refused by z-nile ({v.rule}): {v.say}`
end

return boundcmd
