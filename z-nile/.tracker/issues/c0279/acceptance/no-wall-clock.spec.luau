--!strict
-- c0279 AC1: the dispatch stop case and its fake wait for nothing on the wall clock. Text pins on the promoted spec and
-- the fake CLI (the behaviour under a slow machine is check.sh's AC2, which delays the fake): the case reads the
-- grandchild's pid and waits on that process's death, and the fakes that run git, gh or the stop beat the way every
-- other long-running fake does, so a loaded machine cannot stall them (stall_seconds is 2).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SPEC = fs.readFile(`{TOP}/z-nile/tests/acceptance/c0117/dispatch-cli.spec.luau`)
local FAKE = fs.readFile(`{TOP}/z-nile/tests/lib/fakecli.luau`)

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- the text from `from` up to the next `it(` of the spec
local function caseText(from: string): string
	local a = string.find(SPEC, from, 1, true)
	assert(a, `case not found: {from}`)
	local b = string.find(SPEC, "\n\tit(", a + 1, true) or #SPEC
	return string.sub(SPEC, a, b)
end
-- one `name) ... ;;` line of the fake's case statement, as written in fakecli.luau
local function fakeMode(name: string): string
	local a = string.find(FAKE, `{name}) `, 1, true)
	assert(a, `fake mode not found: {name}`)
	local b = string.find(FAKE, ";;", a, true) :: number
	return string.sub(FAKE, a, b)
end

return t.spec("c0279 dispatch stop waits for nothing on the wall clock", function(it)
	it("the stop case waits on the grandchild's death, not on a file it would touch", function()
		local c = caseText([[it("dispatch stop kills the running step's group]])
		t.expect(has(c, "absentAfter")).toBe(false)
		t.expect(has(c, "grandchild-stop.pid")).toBe(true)
		t.expect(has(c, "deadWithin(")).toBe(true)
		t.expect(has(c, [[t.expect(state("c0060").outcome).toBe("stopped")]])).toBe(true)
		t.expect(has(c, [[t.expect(count(log(), "claude step=z-design")).toBe(2)]])).toBe(true)
	end)

	it("the stop fake beats, records the grandchild's pid and leaves it alive for far longer than any wait", function()
		local m = fakeMode("stop")
		t.expect(has(m, [[echo '{"type":"system"}'; sleep 0.5; done]])).toBe(true)
		t.expect(has(m, "grandchild-stop.pid")).toBe(true)
		t.expect(has(m, "sleep 2; touch")).toBe(false)
		t.expect(has(m, "FAKE_DELAY")).toBe(true)
	end)

	it("every fake prints its first line before any slow work", function()
		local shebang = string.find(FAKE, [["#!/bin/sh",]], 1, true)
		local first = string.find(FAKE, [=[[[echo '{"type":"system"}']],]=], 1, true)
		local slow = string.find(FAKE, [['step=$(printf]], 1, true)
		t.expect(shebang ~= nil and first ~= nil and slow ~= nil).toBe(true)
		t.expect((shebang :: number) < (first :: number)).toBe(true)
		t.expect((first :: number) < (slow :: number)).toBe(true)
	end)

	it("the push fake beats too, so a slow git or gh cannot stall the step", function()
		local m = fakeMode("push")
		t.expect(has(m, [[sleep 0.5; done]])).toBe(true)
		t.expect(has(m, "FAKE_DELAY")).toBe(true)
		t.expect(has(m, "kill $hb")).toBe(true)
	end)
end)
