--!strict
-- c0231 AC1: the seatbelt refuses a `yes` whose output no `head` reads straight from its pipe (R0071 review 001 F4;
-- c0191's Decision 2 lists `yes` as a follow), by the `follow` rule, however the program is reached, whatever ends its
-- command, wherever it is nested and wherever its standard output goes.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local function expectRefused(commands: { string }, ctx: boundcmd.Context?)
	for _, command in commands do
		local v = boundcmd.check(command, ctx)
		t.expect(`{command}: {if v.ok then "ok" else tostring(v.rule)}`).toBe(`{command}: follow`)
		t.expect(`{command}: {tostring(v.program)}`).toBe(`{command}: yes`)
	end
end

return t.spec("c0231 a yes that no head reads is refused", function(it)
	it(
		"AC1: a bare yes is refused as a follow, with or without arguments and however it is reached",
		function()
			expectRefused({
				"yes",
				"yes n",
				"yes 'a b'",
				"yes --version", -- BSD yes prints `--version` for ever (E1): no exempt argument
				"/usr/bin/yes",
				"env yes",
				"FOO=1 yes",
				"nice yes",
				"time yes y",
				"timeout 5 yes", -- bounded in time, not in output: the tool shell takes all of it
				"caffeinate -t 5 yes",
				"if yes; then :; fi",
			})
		end
	)

	it("AC1: a yes ended by anything but a pipe is refused: ;, &&, ||, a newline, a group's end", function()
		expectRefused({
			"yes; head -3",
			"yes && head -3",
			"yes || head -3",
			"yes\nhead -3",
			"yes |",
			"(yes)",
			"{ yes; }",
			"echo a; yes",
			"cd x && yes n",
		})
	end)

	it("AC1: a yes inside $(...), backticks, sh -c, eval and a shell's here-document is refused", function()
		expectRefused({
			"echo $(yes)",
			"echo `yes`",
			'x="$(yes n)"',
			"bash -c yes",
			"sh -c 'cd d; yes'",
			"eval yes",
			"bash <<EOF\nyes\nEOF",
		})
	end)

	it("AC1: a yes whose standard output goes elsewhere is refused even before a pipe", function()
		expectRefused({
			"yes > /dev/null",
			"yes >/dev/null",
			"yes >> out",
			"yes 1>/dev/null | head -3",
			"yes > out | head -3",
			"yes &>/dev/null | head -3",
			"yes >&2 | head -3",
		})
	end)
end)
