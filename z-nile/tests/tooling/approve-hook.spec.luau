--!strict
-- f0423 AC6 (the hook half) and the safety property of amendment 4: the PreToolUse hook refuses an agent's Bash command
-- that records an approval or starts a walkthrough, also through script, expect, unbuffer or a here-string that feeds
-- `y`, and lets the reads and the ruling through.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local REFUSED: { string } = {
	"./zn approve c0001",
	"./zn approve c0001 --publish",
	"./zn approve R0050",
	"./zn approve",
	"./zn approve --walk c0001",
	"./zn approve --apply 20261120T184000Z-a1b2",
	"cd /x && ./zn approve --apply 20261120T184000Z-a1b2",
	"/repo/zn approve --apply 20261120T184000Z-a1b2",
	"yes y | ./zn approve --apply 20261120T184000Z-a1b2",
	"./zn approve --apply 20261120T184000Z-a1b2 <<< y",
	"printf 'y\\n' | ./zn approve c0001",
	"script -q /dev/null ./zn approve --apply 20261120T184000Z-a1b2",
	"script -q /dev/null sh -c './zn approve --apply 20261120T184000Z-a1b2'",
	"yes y | script -q /dev/null sh -c './zn approve c0001; echo $?'",
	"unbuffer ./zn approve R0050",
	"unbuffer -p ./zn approve --apply 20261120T184000Z-a1b2",
	"expect -c 'spawn ./zn approve --apply 20261120T184000Z-a1b2; send \"y\\r\"; expect eof'",
	"expect <<'EOF'\nspawn ./zn approve --apply 20261120T184000Z-a1b2\nsend \"y\\r\"\nexpect eof\nEOF",
	'bash -c "./zn approve c0001 <<< y"',
	"env ZN_APPROVE_SESSION= ./zn approve c0001",
	"./zn run --time 30 -- ./zn approve c0001",
	-- an option that reads does not turn a recording into a read
	"./zn approve --apply 20261120T184000Z-a1b2 --check",
	"./zn approve c0001 --check --publish",
	"./zn rework c0001 --stage design --note x",
	"script -q /dev/null ./zn rework c0001 --stage code --note x",
}

local PASSED: { string } = {
	"./zn approve c0001 --check",
	"./zn approve --check c0001",
	"./zn approve R0050 --queue",
	"./zn approve --walk c0001 --queue",
	"./zn approve --queue",
	"./zn approve --ruling 20261120T184000Z-a1b2 c0001 approve",
	"./zn approve --ruling 20261120T184000Z-a1b2 c0001 change --stage design --guess G2 --note 'keep it' --lesson r --ask 'why?'",
	"./zn rework c0001 --lessons",
	"./zn guesses c0001",
	"git commit -m 'explain ./zn approve --apply in the docs'",
	"echo 'run ./zn approve c0001 yourself'",
	"grep -n 'zn approve' z-nile/skills/zz-rules/SKILL.md",
	"script -q /dev/null ./zn list",
	"unbuffer ./zn approve c0001 --check",
}

return t.spec("approve: the hook refuses an agent's recording", function(it)
	it(
		"refuses every way of running a terminal-only form of approve or rework, naming the way out",
		function()
			for _, command in REFUSED do
				local v = boundcmd.check(command, nil)
				t.expect(`{command} -> {if v.ok then "passed" else v.rule}`).toBe(`{command} -> approve`)
				t.expect(
					string.find(v.say or "", "--ruling", 1, true) ~= nil
						or string.find(v.say or "", "--lessons", 1, true) ~= nil
				).toBe(true)
			end
		end
	)

	it("passes the reads, the ruling, the lessons and mentions of the command", function()
		for _, command in PASSED do
			local v = boundcmd.check(command, nil)
			t.expect(`{command} -> {if v.ok then "passed" else v.rule}`).toBe(`{command} -> passed`)
		end
	end)

	it("the refusal for approve says only the person records; the one for rework says the same", function()
		local a = boundcmd.check("./zn approve --apply 20261120T184000Z-a1b2", nil)
		t.expect(string.find(a.say or "", "only the person does that, in a terminal", 1, true) ~= nil)
			.toBe(true)
		local r = boundcmd.check("./zn rework c0001 --stage design --note x", nil)
		t.expect(string.find(r.say or "", "only from the person's own terminal", 1, true) ~= nil).toBe(true)
	end)
end)
