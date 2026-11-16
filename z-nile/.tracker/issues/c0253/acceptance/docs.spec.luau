--!strict
-- c0253 AC12: the z-work skill, the README (the workflow picture, the worker section and its "what each way in does"
-- paragraph), zz-rules, zz-test's reaper paragraph and the root rules file say what the supervisor does, and no longer say what
-- it overtook (restated rules move together: lesson z-design/restated-rules-move-together). Needles hold whether c0175 lands
-- before or after this issue. Reads the real tree, plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end
local function before(text: string, first: string, second: string, where: string)
	local a, b = string.find(text, first, 1, true), string.find(text, second, 1, true)
	if a == nil or b == nil or a >= b then
		error(`{where}: "{first}" must come before "{second}"`, 2)
	end
end

return t.spec("c0253 the docs say what the supervisor does", function(it)
	it(
		"AC12: the z-work skill puts the headless session first, starts the supervisor with the person's CLI, and ends a worker session at its raft",
		function()
			local s = read("z-nile/skills/z-work/SKILL.md")
			before(s, "**A headless session**", "(the supervisor)", "z-work")
			at(s, "Run `./zn work --detach --cli <the CLI you are running in>`", "z-work")
			at(s, "`./zn work status`", "z-work")
			at(s, "`./zn work stop`", "z-work")
			at(s, "`z-work --here`", "z-work")
			at(s, "`/z-run <R-id>` is the person's own worker and does not start the supervisor", "z-work")
			at(s, "Never run `./zn resolve`", "z-work")
			at(s, "<raft folder>/notes.md", "z-work")
			at(s, "When `./zn done` says the raft waits for a lander, stop", "z-work")
			at(
				s,
				"closing or clearing this CLI ends the session's background commands and so the supervisor",
				"z-work"
			)
			at(s, "A worker session never takes a second raft", "z-work")
			absent(s, "run `./zn work next` with no raft", "z-work")
		end
	)

	it(
		"AC12: the README's picture has the worker draft the design and the person approve it, and the worker section says what each way in does",
		function()
			local r = read("z-nile/README.md")
			at(r, 'des["approve the drafted design (./zn approve), or design by hand: z-design"]', "README")
			at(r, "none claimable: draft the design of a confirmed idea", "README")
			at(r, "What each way in does.", "README")
			at(
				r,
				"`z-work --here` and `/z-run <R>` keep the person's own session as the worker for one raft",
				"README"
			)
			at(r, "ending the session is the clearing", "README")
			at(r, "`./zn work run --cli <name>`", "README")
			at(r, "`~/.config/zn/host.toml`", "README")
			at(r, "polling `origin/main` with no model running", "README")
			at(r, "`ZN_ENGINE_CPU` (1800 s of CPU) limits the supervisor itself", "README")
			absent(r, "in the same context, and stops when none is claimable", "README")
			absent(r, "or a wrapper launches one headless (`./zn work`)", "README")
			absent(r, 'design, acceptance tests, review, approve"]', "README")
			absent(r, "*captured* (c0253)", "README")
		end
	)

	it("AC12: zz-rules, zz-test's reaper paragraph and the root rules file agree", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "which starts the supervisor (`./zn work --detach --cli <the CLI>`", "zz-rules")
		local test = read("z-nile/skills/zz-test/SKILL.md")
		at(test, "never stops the one detached supervisor (c0253)", "zz-test")
		local a = read("AGENTS.md")
		at(a, "it starts the supervisor, `./zn work --detach --cli <your CLI>`", "the root rules file")
		at(a, "except the one detached worker supervisor", "the root rules file")
		at(
			a,
			"`/z-run <R-id>` in a session in the main checkout: that is z-work with that raft named",
			"the root rules file"
		)
	end)
end)
