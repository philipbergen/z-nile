--!strict
-- c0254 AC6: the README's claim paragraph (the user's 2026-11-08 scope decision: it follows the raft claim, and the
-- `preparing` claim is a worker drafting a design for a person to approve), and the two skills that restate the rules it
-- changes, say what a worker on several hosts does and no longer say what it overtook (restated rules move together). Reads the
-- real tree, plain finds only.
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

return t.spec("c0254 the docs say what a worker on several hosts does", function(it)
	it("AC6: the claim paragraph follows the raft claim and says what a preparing claim is", function()
		local s = read("z-nile/README.md")
		absent(s, "a lost race means taking the next item", "README")
		at(s, "The push is the lock: a lost race means taking the next raft.", "README")
		at(s, "A `preparing` claim means a worker drafting the design for a person to approve.", "README")
		at(s, "exit 6 (`taken`)", "README")
	end)

	it(
		"AC6: the paragraph names the pushes, the trailer, the spend cells and where who-holds-what shows",
		function()
			local s = read("z-nile/README.md")
			at(s, "pushes its layer branch and a prep branch after every commit", "README")
			at(s, "builds its own worktree from the pushed branch", "README")
			at(s, "never pushes that branch again", "README")
			at(s, "`Worker:` trailer with the worker's host, CLI and model", "README")
			at(s, "spend rows record the host, the CLI and the model", "README")
			at(s, '("held by") and `./zn work status`', "README")
		end
	)

	it("AC6: the capability table lists the feature as built", function()
		at(
			read("z-nile/README.md"),
			"| workers on several hosts, worker identity in spend | c0254 | exists |",
			"README"
		)
	end)

	it("AC6: zz-rules and z-design say a prep commit goes through ./zn commit and is pushed", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "and in an issue's prep worktree (`prep-<slug>`", "zz-rules")
		at(rules, "Both push the branch after every commit", "zz-rules")
		at(rules, "**Several hosts (c0254).**", "zz-rules")
		at(rules, "exit 6 (`taken`)", "zz-rules")
		local design = read("z-nile/skills/z-design/SKILL.md")
		at(
			design,
			'`./zn commit -m "tracker: prep c0010 <title>"`, which pushes `prep-<slug>` after every commit',
			"z-design"
		)
	end)
end)
