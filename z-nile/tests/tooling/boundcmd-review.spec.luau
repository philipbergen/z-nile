--!strict
-- c0191 code review 001 (F2, F5, F11): the hook reads perl's bundled and attached switches, does not
-- trust a tooling path that climbs out of the checkout, and reads the import forms of inline Python's `subprocess`.
local boundcmd = require("@znile/engine/boundcmd")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local REFUSED: { { command: string, rule: string } } = {
	{ command = "perl -we 'alarm 5; exec @ARGV' lune run x", rule = "alarm" },
	{ command = "perl -le 'alarm shift; exec @ARGV' 5 lune run x", rule = "alarm" },
	{ command = "perl -e'alarm 5; exec @ARGV' lune run x", rule = "alarm" },
	{ command = "perl -Mstrict -e 'alarm 5; exec @ARGV' lune run x", rule = "alarm" },
	{ command = "perl -I lib -we 'alarm 5; exec @ARGV' lune run x", rule = "alarm" },
	{ command = "perl -le 'while (1) {}'", rule = "unbounded" },
	{ command = "perl -we 'while(1){}'", rule = "unbounded" },
	{ command = "perl -ne 'while(1){}' /dev/null", rule = "unbounded" },
	{ command = "perl -0777ne '1 while 1'", rule = "unbounded" },
	{ command = "perl -E '1 while 1'", rule = "unbounded" },
	{
		command = 'python3 -c \'from subprocess import run; run(["lune", "run", "x"])\'',
		rule = "unbounded",
	},
	{
		command = 'python3 -c \'import subprocess as s; s.run(["lune", "run", "x"])\'',
		rule = "unbounded",
	},
}

local PASSING: { string } = {
	"perl -ne 'print while <>' f",
	"perl -Mfeature=say -e 'say 1'",
	"perl -we 'print 1'",
	"perl script.pl -e 'while (1) {}'",
	"python3 -c 'from subprocess import run; run([\"ls\"], timeout=5)'",
}

return t.spec("hook review fixes", function(it)
	it("perl switches are read as perl reads them; python's import forms are refused", function()
		for _, c in REFUSED do
			local v = boundcmd.check(c.command)
			if v.ok or v.rule ~= c.rule then
				error(
					`{c.command}: expected refusal by {c.rule}, got {if v.ok then "ok" else tostring(v.rule)}`,
					0
				)
			end
		end
		for _, command in PASSING do
			local v = boundcmd.check(command)
			if not v.ok then
				error(`{command}: expected ok, refused by {tostring(v.rule)}`, 0)
			end
		end
	end)

	it("a tooling path that climbs out of the checkout is a probe", function()
		local ctx = { checkout = ROOT, cwd = ROOT }
		t.expect(boundcmd.check(`lune run {ROOT}/tests/run`, ctx).ok).toBe(true)
		t.expect(boundcmd.check(`lune run {ROOT}/../elsewhere/tests/run`, ctx).ok).toBe(false)
		t.expect(boundcmd.check(`lune run {ROOT}/z-nile/../../x/tests/run`, ctx).ok).toBe(false)
	end)
end)
