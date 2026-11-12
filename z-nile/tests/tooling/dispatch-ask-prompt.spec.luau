--!strict
-- R0093 code review 001 F5: a capture's first z-ticket holds only the user's own ask in its exchange, so its prompt
-- says what that file is ("the user's own request ... word for word") and that no step has asked anything yet; it
-- is never told that earlier steps exchanged messages. A step that did not ask, reading a longer history, still is.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function input(step: string, exchange: { string }): dispatch.PromptInput
	return {
		step = step,
		id = "",
		skillPath = `z-nile/skills/{step}/SKILL.md`,
		worktree = "/w",
		stateDir = "/w/.cache/dispatch/new",
		description = "make a thing",
		exchange = exchange,
	}
end

return t.spec("R0093 F5: the prompt of a step whose exchange is only the user's ask", function(it)
	it("names the ask as the user's own request and says nothing has been asked yet", function()
		local p = dispatch.prompt(input("z-ticket", { "001-ask.md" }))
		t.expect(has(p, "The user's own request for this run, word for word, is")).toBe(true)
		t.expect(has(p, "/w/.cache/dispatch/new/exchange/001-ask.md")).toBe(true)
		t.expect(has(p, "No step has asked the user anything yet.")).toBe(true)
		t.expect(has(p, "Earlier steps of this run have already exchanged messages")).toBe(false)
		t.expect(has(p, "This is a re-run")).toBe(false)
	end)

	it("a step that did not ask, reading a longer history, is still told earlier steps exchanged", function()
		local p = dispatch.prompt(input("z-design", { "001-ask.md", "002-question.md", "003-answer.md" }))
		t.expect(has(p, "Earlier steps of this run have already exchanged messages")).toBe(true)
		t.expect(has(p, "001-ask.md, 002-question.md, 003-answer.md")).toBe(true)
		t.expect(has(p, "The user's own request for this run, word for word, is")).toBe(false)
		t.expect(has(p, "No step has asked the user anything yet.")).toBe(false)
	end)
end)
