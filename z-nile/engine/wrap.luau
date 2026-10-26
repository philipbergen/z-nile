--!strict
-- The entry of z-nile/bin/git and z-nile/bin/gh (c0117): gathers what the tools themselves say (git's alias, git's own
-- dry run of the push, a private fresh copy of origin's main, gh's aliases), decides with wrapper.luau, then runs the
-- real tool ($ZN_REAL_GIT, $ZN_REAL_GH, set by ./zn dispatch) or refuses with exit 1.
--   lune run z-nile/engine/wrap -- git|gh <args...>
local process = require("@lune/process")
local projects = require("./projects")
local stdio = require("@lune/stdio")
local trackerstate = require("./trackerstate")
local wrapper = require("./wrapper")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local tool = table.remove(args, 1)
if tool ~= "git" and tool ~= "gh" then
	stdio.ewrite("usage: lune run z-nile/engine/wrap -- git|gh <args...>\n")
	process.exit(2)
end
local real = process.env[if tool == "git" then "ZN_REAL_GIT" else "ZN_REAL_GH"]
if not real or real == "" then
	stdio.ewrite(`{tool} (z-nile wrapper): the real {tool} is not known (run under ./zn dispatch)\n`)
	process.exit(2)
end
local realTool = real :: string

local function refuse(why: string): never
	stdio.ewrite(`{tool} (z-nile wrapper): {why}\n`)
	return process.exit(1)
end

local function run(a: { string }): (boolean, string, string)
	local r = process.exec(realTool, a)
	return r.ok, (string.gsub(r.stdout, "%s+$", "")), r.stderr
end

if tool == "git" then
	local globals, command, rest = wrapper.splitGit(args)
	local function with(more: { string }): { string }
		local out = table.clone(globals)
		for _, a in more do
			table.insert(out, a)
		end
		return out
	end
	-- an alias resolves under the same options (`-c alias.p=push` included), up to a few levels
	for _ = 1, 5 do
		if not command then
			break
		end
		local ok, expansion = run(with({ "config", "--get", `alias.{command}` }))
		if not ok or expansion == "" then
			break
		end
		if string.sub(expansion, 1, 1) == "!" then
			refuse(`a shell alias ({command}) is refused under the dispatcher`)
		end
		local words = string.split(expansion, " ")
		local nextCommand = table.remove(words, 1)
		for _, a in rest do
			table.insert(words, a)
		end
		command, rest = nextCommand, words
	end
	if command and wrapper.PLUMBING[command] then
		refuse(`git {command} is refused under the dispatcher: push with git push`)
	end
	if command == "push" then
		-- `-q` would silence the porcelain lines the decision reads
		local dry: { string } = {}
		for _, a in rest do
			if a ~= "-q" and a ~= "--quiet" then
				table.insert(dry, a)
			end
		end
		table.insert(dry, 1, "--porcelain")
		table.insert(dry, 1, "--dry-run")
		table.insert(dry, 1, "push")
		local ok, out, err = run(with(dry))
		local updates = wrapper.parsePorcelain(out)
		if not string.find(out, "\nDone", 1, true) and not string.match(out, "^Done") then
			refuse(`git push refused: its dry run did not finish ({(string.gsub(err, "%s+$", ""))})`)
		end
		if not ok and #updates == 0 then
			refuse(`git push refused: its dry run failed ({(string.gsub(err, "%s+$", ""))})`)
		end
		local url = string.match(out, "To ([^\n]+)") or "origin"
		local fetched: boolean? = nil
		-- a ref of this call's own (review 005 F1: concurrent steps' wrappers never share one), deleted after
		local private =
			`refs/zn-wrap/{string.lower((string.gsub(process.exec("uuidgen", {}).stdout, "%s+", "")))}/main`
		local function fresh(): boolean
			if fetched == nil then
				fetched = (run(with({ "fetch", "-q", url, `+refs/heads/main:{private}` })))
			end
			return fetched :: boolean
		end
		local decision = wrapper.decidePush({
			updates = updates,
			check = function(src: string): string?
				if not fresh() then
					return "could not fetch a fresh copy of main"
				end
				local okSha, sha = run(with({ "rev-parse", "--verify", `{src}^\{commit\}` }))
				if not okSha then
					return `could not resolve {src}`
				end
				-- a fast-forward of the fresh main only (code review 001 F3: `--force`, `+<src>:main` and
				-- `--force-with-lease` that rewind main are refused, whatever tracker state rides on top)
				if not (run(with({ "merge-base", "--is-ancestor", private, sha }))) then
					return "not a fast-forward of main: main only moves forward"
				end
				local okBase, base = run(with({ "merge-base", private, sha }))
				-- tracker state by the fresh main's registry: a branch can't widen what may go to main (lesson
				-- zz-arch/guards-trust-only-origin)
				local _, top = run(with({ "rev-parse", "--show-toplevel" }))
				local reg = projects.at(private, top)
				if not reg then
					return "could not read the fresh main's registry"
				end
				return trackerstate.check(function(a: { string }): (boolean, string)
					local done, said = run(with(a))
					return done, said
				end, if okBase then base else trackerstate.EMPTY_TREE, sha, projects.roots(reg :: any), true)
			end,
		})
		if fetched then
			run(with({ "update-ref", "-d", private }))
		end
		if not decision.ok then
			refuse(decision.why or "refused")
		end
	end
else
	local okA, aliasText = run({ "alias", "list" })
	local decision = wrapper.decideGh(args, if okA then wrapper.parseGhAliases(aliasText) else {})
	if not decision.ok then
		refuse(decision.why or "refused")
	end
end
local r = process.exec(realTool, args, { stdio = "inherit" })
process.exit(r.code)
