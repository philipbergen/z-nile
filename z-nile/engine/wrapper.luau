--!strict
-- The git and gh rules for dispatched agents (c0117). A convenience layer, not the boundary: the boundary is the
-- agent's own GitHub credential, which can't merge or bypass `main`'s protection, and the dispatcher's tripwire after
-- every step (zz-rules, Dispatch). `z-nile/bin/git` and `z-nile/bin/gh` come first on a model step's PATH; this module
-- decides, pure, from facts `wrap.luau` gathers from the tools themselves:
--   - git: what a push would do is read from git's own resolution (`push --dry-run --porcelain`, after aliases and
--     `-c` resolve), never parsed from the arguments, and what it would put on main is diffed from a private, freshly
--     fetched copy of origin's main (a private ref of the call's own, refs/zn-wrap/<id>/main), never from the tracking ref the agent can rewrite;
--   - gh: an allow-list of commands (no merge, no alias edits), and `gh api` reads plus an allow-list of write
--     endpoints (comments); a GraphQL mutation is a write.
local wrapper = {}

export type Decision = { ok: boolean, why: string? }
export type Update = { flag: string, src: string, dst: string }
export type PushFacts = {
	updates: { Update }, -- git's dry run: every ref the push would update on the remote
	-- why what `src` would put on the fresh main is not tracker state (trackerstate.luau, the one definition), or nil
	check: (src: string) -> string?,
}

local function refuse(why: string): Decision
	return { ok = false, why = why }
end
local OK: Decision = { ok = true }

-- git's options that take their value as the next word, before the command
local GIT_VALUE: { [string]: boolean } = {
	["-C"] = true,
	["-c"] = true,
	["--git-dir"] = true,
	["--work-tree"] = true,
	["--namespace"] = true,
	["--config-env"] = true,
	["--super-prefix"] = true,
	["--exec-path"] = false,
}

-- git's own options before the command, the command, and the rest.
function wrapper.splitGit(args: { string }): ({ string }, string?, { string })
	local globals: { string } = {}
	local i = 1
	while i <= #args do
		local a = args[i]
		if string.sub(a, 1, 1) ~= "-" then
			return globals, a, table.move(args, i + 1, #args, 1, {})
		end
		table.insert(globals, a)
		if GIT_VALUE[a] and not string.find(a, "=", 1, true) then
			table.insert(globals, args[i + 1] or "")
			i += 1
		end
		i += 1
	end
	return globals, nil, {}
end

-- The commands that send objects to a remote without `git push`'s dry run: refused under the dispatcher.
wrapper.PLUMBING = { ["send-pack"] = true, ["http-push"] = true, ["receive-pack"] = true }

-- Reads `git push --dry-run --porcelain`'s lines: `<flag>\t<src>:<dst>\t<summary>`.
function wrapper.parsePorcelain(text: string): { Update }
	local out: { Update } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local flag, src, dst = string.match(line, "^(.)\t([^:\t]*):([^\t]+)\t")
		if flag and dst then
			table.insert(out, { flag = flag, src = src :: string, dst = dst })
		end
	end
	return out
end

-- A push passes when nothing it updates is main, or it fast-forwards main with tracker state only.
function wrapper.decidePush(f: PushFacts): Decision
	for _, u in f.updates do
		if u.dst == "refs/heads/main" then
			if u.flag == "-" or u.src == "(delete)" or u.src == "" then
				return refuse("git push would delete main")
			end
			-- never a rewind of main, however spelled (code review 001 F3): a forced update is refused here, and the
			-- check below refuses a source that does not descend from the freshly fetched main
			if u.flag == "+" then
				return refuse("git push would rewrite main (a forced update): main only moves forward")
			end
			local why = f.check(u.src)
			if why then
				return refuse(
					`git push to main refused: {why} (open a pull request; only ./zn publishes to main)`
				)
			end
		end
	end
	return OK
end

-- gh's global options that take a value before the command.
local GH_VALUE: { [string]: boolean } = { ["-R"] = true, ["--repo"] = true, ["--hostname"] = true }
-- The gh commands a dispatched agent may run (the skills' own: tests walk them); everything else is refused.
wrapper.GH_ALLOWED = {
	pr = {
		create = true,
		view = true,
		comment = true,
		ready = true,
		edit = true,
		list = true,
		checks = true,
		diff = true,
		status = true,
		close = true,
	},
	issue = { view = true, list = true, comment = true },
	run = { view = true, list = true, watch = true, rerun = true, download = true },
	workflow = { run = true, view = true, list = true },
	release = { download = true, view = true, list = true },
	repo = { view = true },
	auth = { status = true },
	api = {},
} :: { [string]: { [string]: boolean } }
-- `gh api` write endpoints a dispatched agent may use (a PR or issue comment); any other write is refused.
-- (code review 003 F3: owner and repository as GitHub names them, so no `?` or `#` rides in a segment; gh's own
-- `{owner}` and `{repo}` placeholders are read as names before matching)
wrapper.API_WRITES = {
	"^/?repos/[%w%-%._]+/[%w%-%._]+/issues/%d+/comments$",
	"^/?repos/[%w%-%._]+/[%w%-%._]+/pulls/%d+/comments$",
}

-- gh's words after its global options, with an alias expanded by `aliases` (name -> expansion words).
function wrapper.splitGh(args: { string }, aliases: { [string]: { string } }): { string }
	local words: { string } = {}
	local i = 1
	while i <= #args do
		local a = args[i]
		local attached = string.match(a, "^%-%-repo=")
			or string.match(a, "^%-%-hostname=")
			or string.match(a, "^%-R.")
		if GH_VALUE[a] then
			i += 1
		elseif not attached then
			table.move(args, i, #args, 1, words)
			break
		end
		i += 1
	end
	local expansion = words[1] and aliases[words[1]]
	if expansion then
		local out = table.clone(expansion)
		for j = 2, #words do
			table.insert(out, words[j])
		end
		return out
	end
	return words
end

-- `gh api`'s options (code review 001 F4: an option's value is never taken for the endpoint). Each value-taking option
-- by what its value is; the flags take none; any other option is refused (fail closed), never guessed.
local API_VALUE: { [string]: string } = {
	["-X"] = "method",
	["--method"] = "method",
	["-F"] = "field",
	["--field"] = "field",
	["-f"] = "field",
	["--raw-field"] = "field",
	["--input"] = "field",
	["-H"] = "other",
	["--header"] = "other",
	["-q"] = "other",
	["--jq"] = "other",
	["-t"] = "other",
	["--template"] = "other",
	["-p"] = "other",
	["--preview"] = "other",
	["--hostname"] = "other",
	["--cache"] = "other",
}
local API_FLAGS: { [string]: boolean } = {
	["-i"] = true,
	["--include"] = true,
	["--paginate"] = true,
	["--silent"] = true,
	["--slurp"] = true,
	["--verbose"] = true,
}

local function apiDecision(rest: { string }): Decision
	local endpoint = ""
	local method: string? = nil
	local fields = false
	local query = ""
	local unseen: string? = nil
	local i = 1
	while i <= #rest do
		local a = rest[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			-- the option's name and its value: `--name=value`, `-Xvalue`, or the next word
			local name, value = a, nil :: string?
			local long, attached = string.match(a, "^(%-%-[^=]+)=(.*)$")
			if long then
				name, value = long, attached
			elseif string.sub(a, 2, 2) ~= "-" and #a > 2 then
				name, value = string.sub(a, 1, 2), string.sub(a, 3)
			end
			local kind = API_VALUE[name]
			if kind then
				if value == nil then
					value = rest[i + 1] or ""
					i += 1
				end
				if kind == "method" then
					method = string.upper(value :: string)
				elseif kind == "field" then
					fields = true
					-- a body gh reads itself (code review 002 F2): `--input <file|->`, a field `key=@file` or `key=@-`
					if name == "--input" or string.match(value :: string, "^[^=]*=@") then
						unseen = `{name} {value}`
					end
					if string.match(value :: string, "^query=") then
						query = value :: string
					end
				end
			elseif not (API_FLAGS[name] and value == nil) then
				return refuse(`gh api option {a} is not one the wrapper knows: refused (fail closed)`)
			end
		elseif endpoint == "" then
			endpoint = a
		else
			return refuse(`gh api with two endpoints ({endpoint}, {a}) refused`)
		end
		i += 1
	end
	if endpoint == "graphql" then
		-- the wrapper judges only the query it can read: a body gh reads from a file or stdin is refused (fail closed)
		if unseen then
			return refuse(
				`gh api graphql with a body gh reads itself ({unseen}) is refused under the dispatcher: pass the query inline`
			)
		end
		if string.find(string.lower(query), "mutation", 1, true) then
			return refuse("gh api graphql mutations are refused under the dispatcher")
		end
		return OK
	end
	local writes = (method ~= nil and method ~= "GET") or (method == nil and fields)
	if not writes then
		return OK
	end
	local named = string.gsub(string.gsub(endpoint, "{owner}", "owner"), "{repo}", "repo")
	for _, pattern in wrapper.API_WRITES do
		if string.match(named, pattern) and (method == nil or method == "POST") then
			return OK
		end
	end
	return refuse(`gh api write to {endpoint} refused: only PR and issue comments are an agent's to write`)
end

function wrapper.decideGh(args: { string }, aliases: { [string]: { string } }): Decision
	local words = wrapper.splitGh(args, aliases)
	local command, sub = words[1], words[2]
	if not command or command == "--help" or command == "--version" or command == "help" then
		return OK
	end
	local allowed = wrapper.GH_ALLOWED[command]
	if not allowed then
		return refuse(`gh {command} is not a dispatched agent's (the dispatcher merges; zz-rules, Dispatch)`)
	end
	if command == "api" then
		return apiDecision(table.move(words, 2, #words, 1, {}))
	end
	if not sub or not allowed[sub] then
		return refuse(
			`gh {command} {sub or ""} is not a dispatched agent's (the dispatcher merges; zz-rules, Dispatch)`
		)
	end
	return OK
end

-- `gh alias list`'s lines (`name: expansion`), as words; an alias that runs a shell (`!…`) expands to `!`.
function wrapper.parseGhAliases(text: string): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local name, expansion = string.match(line, "^%s*([^:%s]+):%s*(.-)%s*$")
		if name and expansion then
			if string.sub(expansion, 1, 1) == "!" then
				out[name] = { "!" }
			else
				out[name] = string.split((string.gsub(expansion, "^'(.*)'$", "%1")), " ")
			end
		end
	end
	return out
end

return wrapper
