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
		"AC12: the z-work skill puts the headless session first, starts the supervisor with the person's CLI, loops across rafts for --here, and ends a headless or named-raft session at its raft",
		function()
			local s = read("z-nile/skills/z-work/SKILL.md")
			before(s, "**A headless session**", "(the supervisor)", "z-work")
			at(s, "Run `./zn work --detach --cli <the CLI you are running in>`", "z-work")
			at(s, "`./zn work status`", "z-work")
			at(s, "`./zn work stop`", "z-work")
			at(s, "`z-work --here` (this session loops across rafts)", "z-work")
			at(s, "`/z-run <R-id>` / `./zn work <R-id>` (this session carries the one raft named, then stops)", "z-work")
			at(s, "\"Session loops across rafts\"", "z-work")
			at(s, "A `z-work --here` session says one line (what landed or was released, and what it takes next), then runs `./zn work next` with no raft", "z-work")
			at(s, "A release adds one to the count you pass as `--released`", "z-work")
			at(s, "Neither a headless session nor a session given a raft takes a second raft", "z-work")
			at(s, "`/z-run <R-id>` is the person's own worker and does not start the supervisor", "z-work")
			at(s, "Never run `./zn resolve`", "z-work")
			at(s, "<raft folder>/notes.md", "z-work")
			at(s, "When `./zn done` says the raft waits for a lander, stop", "z-work")
			at(
				s,
				"closing or clearing this CLI ends the session's background commands and so the supervisor",
				"z-work"
			)
			absent(s, "A worker session never takes a second raft", "z-work")
			absent(s, "context never crosses rafts", "z-work")
		end
	)

	it(
		"AC12: the README's picture has the worker draft the design and the person approve it, and the worker section says what each way in does",
		function()
			local r = read("z-nile/README.md")
			at(r, 'des["approve the drafted design (./zn approve), or design by hand: z-design"]', "README")
			at(r, "none claimable: draft the design of a confirmed idea", "README")
			at(r, "What each way in does.", "README")
			at(r, "`z-work --here` keeps the person's own session as the worker across rafts", "README")
			at(r, "`/z-run <R>` and `./zn work <R>` carry the one raft named and stop at its end", "README")
			at(r, "a `z-work --here` session carries its own across rafts", "README")
			at(r, "No context carries from one raft to the next in the supervisor's sessions", "README")
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
		at(rules, "`z-work --here` is the session itself taking the next raft and then the next", "zz-rules")
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
