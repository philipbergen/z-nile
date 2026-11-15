--!strict
-- d0295 AC4: z-raft, its lessons, the raft template and the prompt template agree with stack.order on where an order
-- against other rafts is written: `## Cross-raft waits`, never the Order, which `./zn start` reads as layers.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function at(text: string, needle: string, where: string): number
	local s = string.find(text, needle, 1, true)
	if not s then
		error(`{where} lacks: {needle}`, 2)
	end
	return s
end
local function lacks(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still says: {needle}`, 2)
	end
end

return t.spec("d0295 where a raft writes an order against other rafts", function(it)
	it(
		"z-raft's §3 says the Order names members only and cross-raft order goes under Cross-raft waits",
		function()
			local s = read("z-nile/skills/z-raft/SKILL.md")
			local w = "z-raft §3"
			at(s, "- **Order & dependencies**: the members in `depends_on` order, then by id", w)
			at(
				s,
				"`./zn start` reads every item id in this section as a layer, so it names only members, each once",
				w
			)
			at(s, "a layer branch such as `R0090/1/c0261` names its member again", w)
			at(
				s,
				"- **Cross-raft waits**: an order against another raft or its issues goes under `## Cross-raft waits`, after the Order, in both rafts' documents",
				w
			)
			at(
				s,
				"It is never read as a layer, and the raft's prompt carries it. Write `None.` when there are none.",
				w
			)
		end
	)

	it("z-raft's §5 says status prepared, ready and work refuse an Order start would refuse", function()
		local s = read("z-nile/skills/z-raft/SKILL.md")
		local w = "z-raft §5"
		local five = at(s, "## 5. Prepare and land", w)
		local said = at(
			s,
			"It also refuses a raft that `./zn start` would refuse for its order (an item id in the Order that is not a member, one named twice, a dependent named before its `depends_on`, or a `depends_on` cycle among its members), and `./zn ready` and `./zn work` refuse the same faults of the Order's text.",
			w
		)
		t.expect(said > five).toBe(true)
	end)

	it("the lessons name the section and no longer say the commands before start skip the check", function()
		local both = read("z-nile/skills/z-raft/lessons/cross-raft-order-written-in-both.md")
		at(
			both,
			"does Y's raft document say it under `## Cross-raft waits`",
			"cross-raft-order-written-in-both check"
		)
		at(
			both,
			"write the order under `## Cross-raft waits` in both raft documents",
			"cross-raft-order-written-in-both"
		)
		local once = read("z-nile/skills/z-raft/lessons/order-names-members-once.md")
		lacks(once, "do not run it", "order-names-members-once")
		lacks(once, "layergit.raftSection", "order-names-members-once")
		at(
			once,
			"Since d0295, `./zn status <R> prepared` runs it too, and `ready` and `work` refuse the same faults of the Order's text",
			"order-names-members-once"
		)
		at(once, "as `stack.orderSection` cuts it", "order-names-members-once check")
	end)

	it("the raft template has Cross-raft waits right after the Order, and the prompt renders it", function()
		local doc = read("z-nile/templates/raft/doc.md")
		local order = at(doc, "\n## Order & dependencies\n", "raft template")
		local waits = at(doc, "\n## Cross-raft waits\n", "raft template")
		local next = at(doc, "\n## Experiments phase\n", "raft template")
		t.expect(order < waits and waits < next).toBe(true)
		local orderBody = string.sub(doc, order, waits)
		at(orderBody, "Member ids only, each once", "raft template Order comment")
		-- the comments reach every prompt whose raft leaves them: they name no real item or raft id
		local comments = string.sub(doc, order, next)
		if string.find(comments, "[fdcR]%d%d%d%d") then
			error(`the raft template's Order or Cross-raft waits comment names an id: {comments}`)
		end
		at(
			string.sub(doc, waits, next),
			"Write None. when there are none.",
			"raft template Cross-raft waits comment"
		)
		local prompt = read("z-nile/templates/prompt.md")
		local o = at(prompt, "### Order & dependencies\n{{ORDER}}\n", "prompt template")
		local c = at(prompt, "### Cross-raft waits\n{{CROSS_RAFT}}\n", "prompt template")
		t.expect(o < c).toBe(true)
	end)
end)
