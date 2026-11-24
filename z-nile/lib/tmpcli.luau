--!strict
-- The command line of z-nile/lib/tmp.luau (c0194), run as `./zn tmp ...` or `lune run z-nile/lib/tmpcli -- ...`:
--   new <kind> [--owner <pid>]   a fresh .cache/.tmp/<kind>.XXXXXX, printed
--   root                         the .cache/.tmp folder itself, made safe, printed
--   verify <tree>                "isolated", or "not isolated: <why>" (exit 1)
--   sweep [--dry-run]            removes the stale trees, one report line each
--   jail [--time <s>] <tree> -- <command>...  runs a command (limit 60 s by default, at most 3600; 124 on the limit) in the tree under tmp.jailProfile, exit code passed on
--   rm <tree>                    removes a tree made by `new` (and nothing else)
--   leftovers [--remove <name>...]  lists the trees in the system temp folder (removes only those named)
-- Every command takes `--dir <checkout or home>` (repeatable for sweep). Without it, the checkout whose .cache/.tmp
-- is this shell's TMPDIR (an agent's session points it at the main checkout's), else the checkout of ./zn.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local tmp = require("./tmp")

local function fail(msg: string)
	stdio.ewrite(`tmp: {msg}\n`)
	process.exit(1)
end

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local cmd = table.remove(args, 1)

local dirs: { string } = {}
local rest: { string } = {}
local owner: string? = nil
local dry = false
local seconds = 60
-- Options are read up to the `--` that follows `jail <tree>`; everything after it is the jailed command's own (review
-- 001 F7).
local stop = #args + 1
if cmd == "jail" then
	for j = 2, #args do
		if args[j] == "--" then
			stop = j
			break
		end
	end
end
local skip = false
for i = 1, #args do
	local a = args[i]
	if skip then
		skip = false
	elseif i < stop and a == "--dir" and args[i + 1] then
		table.insert(dirs, args[i + 1])
		skip = true
	elseif i < stop and a == "--owner" and args[i + 1] then
		owner = args[i + 1]
		skip = true
	elseif i < stop and a == "--dry-run" then
		dry = true
	elseif i < stop and a == "--time" and cmd == "jail" and args[i + 1] then
		local n = tonumber(args[i + 1])
		if n == nil or n ~= math.floor(n) or n < 1 or n > 3600 then
			fail("--time takes whole seconds, 1 to 3600")
		end
		seconds = n :: number
		skip = true
	else
		table.insert(rest, a)
	end
end
local explicit = if #dirs > 0 then dirs[1] else nil
if #dirs == 0 then
	table.insert(dirs, process.env.ZN_TOP or ".")
end

if cmd == "new" and rest[1] and rest[1] ~= "" then
	local tree, why = tmp.new(explicit, rest[1], owner)
	if not tree then
		fail(why or "failed")
	end
	print(tree)
elseif cmd == "root" then
	local root, why = tmp.place(explicit)
	if not root then
		fail(why or "failed")
	end
	print(root)
elseif cmd == "verify" and rest[1] and rest[1] ~= "" then
	local verdict = tmp.verify(rest[1])
	print(verdict)
	process.exit(if verdict == "isolated" then 0 else 1)
elseif cmd == "sweep" then
	-- the session's own folder too (an agent's TMPDIR points at the main checkout's), whatever was named
	local viaTmpdir = string.match(process.env.TMPDIR or "", "^(.*)/%.cache/%.tmp/?$")
	if viaTmpdir and not table.find(dirs, viaTmpdir) then
		table.insert(dirs, viaTmpdir)
	end
	-- each named checkout and its project homes: a home's folder holds that home's run folders and `deploy-beta`'s trees
	local all: { string } = {}
	for _, d in dirs do
		table.insert(all, d)
		for _, home in tmp.homesOf(d) do
			table.insert(all, home)
		end
	end
	for _, d in all do
		local found, why = tmp.sweep(d, dry, tmp.REAL)
		if found then
			for _, line in found do
				stdio.ewrite(`tmp: {if dry then "would remove" else "removed"} {line}\n`)
			end
		else
			fail(why or "failed")
		end
	end
elseif cmd == "jail" and rest[1] and rest[1] ~= "" then
	local argv = table.clone(rest)
	local tree = table.remove(argv, 1) :: string
	if argv[1] == "--" then
		table.remove(argv, 1)
	end
	local common = process.exec("git", { "rev-parse", "--path-format=absolute", "--git-common-dir" })
	local plan, why = tmp.jailPlan(tree, argv, {
		ceilings = process.env.GIT_CEILING_DIRECTORIES or "",
		realGit = process.env.PICKMAN_FENCE_REAL_GIT or "",
		common = if common.ok then (string.gsub(common.stdout, "%s+$", "")) else "",
	})
	if plan then
		fs.writeDir(`{plan.cwd}/.jail-tmp`)
		-- bounded like ./zn run: the limit stops the whole sandboxed group, and 124 says it was the limit (review 001 F6)
		local lib = string.match(debug.info(1, "s"), "^(.*)/[^/]+$") or "."
		local bounded = { `{lib}/bounded.pl`, "--time", tostring(seconds), "--" }
		for _, a in plan.argv do
			table.insert(bounded, a)
		end
		process.exit(process.exec("perl", bounded, { cwd = plan.cwd, stdio = "forward" }).code)
	else
		fail(why or "failed")
	end
elseif cmd == "rm" and rest[1] then
	local removed, why = tmp.removeTree(rest[1])
	if not removed then
		fail(why or `could not remove {rest[1]}`)
	end
elseif cmd == "leftovers" then
	local names: { string } = {}
	if rest[1] == "--remove" then
		for j = 2, #rest do
			table.insert(names, rest[j])
		end
	end
	local lines, why = tmp.leftovers(names, nil, tmp.REAL)
	if why then
		fail(why)
	end
	for _, line in lines do
		print(line)
	end
else
	fail(
		"usage: new <kind> | root | verify <tree> | sweep [--dry-run] | jail [--time <s>] <tree> -- <command>... | rm <tree> | leftovers [--remove <name>...]  [--dir <checkout>]"
	)
end
