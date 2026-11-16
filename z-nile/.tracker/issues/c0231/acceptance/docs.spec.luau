--!strict
-- c0231 AC7: zz-test, which restates the hook's classes, names a `yes` that no `head` reads among the follows and no
-- longer lists `yes` among what passes (z-design/restated-rules-move-together).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	local path = `{ROOT}/{rel}`
	if not fs.isFile(path) then
		error(`{rel} is missing`, 0)
	end
	return fs.readFile(path)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0231 zz-test restates the yes rule", function(it)
	it(
		"AC7: the hook paragraph lists a yes no head reads among the follows, and not among what passes",
		function()
			local test = read("z-nile/skills/zz-test/SKILL.md")
			local hook = string.match(test, "%- %*%*The hook%*%*[^\n]*") or ""
			t.expect(hook ~= "").toBe(true)
			t.expect(
				has(
					hook,
					"follows (`tail -f`, `watch`, `gh ... watch`, and a `yes` that no `head` reads straight from its pipe, c0231)"
				)
			).toBe(true)
			t.expect(has(hook, "`yes` (it ends in a pipe)")).toBe(false)
		end
	)

	-- review 001 F4, F5 (written, not run): the allow-list exception and the unread spellings are stated
	it(
		"AC7: the hook paragraph says yes needs a recognised consumer and names the group and here-document limits",
		function()
			local test = read("z-nile/skills/zz-test/SKILL.md")
			local hook = string.match(test, "%- %*%*The hook%*%*[^\n]*") or ""
			t.expect(has(hook, "`yes` is the one rule that needs a recognised consumer")).toBe(true)
			t.expect(has(hook, "a `yes` in a group or subshell piped on")).toBe(true)
		end
	)

	it("AC7: the Hooks list names a yes no head reads among the follows", function()
		local test = read("z-nile/skills/zz-test/SKILL.md")
		local hooks = string.match(test, "## Hooks %(Claude Code only%).-\n## ") or ""
		t.expect(has(hooks, "a follow (`tail -f`, `watch`, a `yes` that no `head` reads)")).toBe(true)
	end)
end)
