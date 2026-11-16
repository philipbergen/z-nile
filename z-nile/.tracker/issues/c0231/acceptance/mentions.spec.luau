--!strict
-- c0231 AC4: a `yes` that is no command passes: a mention, an argument, data, a `case` pattern; after its `esac` a case
-- hides nothing.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local function expectOk(commands: { string }, ctx: boundcmd.Context?)
	for _, command in commands do
		local v = boundcmd.check(command, ctx)
		t.expect(`{command}: {if v.ok then "ok" else tostring(v.rule)}`).toBe(`{command}: ok`)
	end
end

return t.spec("c0231 a yes that is no command passes", function(it)
	it("AC4: a yes that is no command passes: mentions, arguments, data and case patterns", function()
		expectOk({
			"echo yes",
			"printf 'yes\\n'",
			'grep -rn "yes" z-nile/skills',
			"git commit -m yes",
			"cat <<EOF\nyes\nEOF",
			"# yes",
			"which yes",
			'[ "$a" = yes ] && echo ok',
			'case "$a" in yes) echo y;; esac',
			'case "$a" in no) echo n;; yes) echo y;; esac',
			'case "$a" in y|yes) echo y;; *) echo n;; esac',
			'case "$a" in (yes) echo y;; esac',
			'case "$a" in\n  no) echo n ;;\n  yes) echo y ;;\nesac',
		})
	end)

	it("AC4: after its esac, a case no longer hides a yes", function()
		local v = boundcmd.check('case "$a" in no) echo n;; esac; (yes)')
		t.expect(if v.ok then "ok" else tostring(v.rule)).toBe("follow")
	end)
end)
