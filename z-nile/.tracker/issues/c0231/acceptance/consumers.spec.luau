--!strict
-- c0231 AC3: a pipe into anything but a `head` that stops at its count does not end `yes`: a filter, a loop, xargs,
-- another program, a `head` later in the pipeline, a negative count, `xargs head`. Each is refused as a follow.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local function expectRefused(commands: { string }, ctx: boundcmd.Context?)
	for _, command in commands do
		local v = boundcmd.check(command, ctx)
		t.expect(`{command}: {if v.ok then "ok" else tostring(v.rule)}`).toBe(`{command}: follow`)
		t.expect(`{command}: {tostring(v.program)}`).toBe(`{command}: yes`)
	end
end

return t.spec("c0231 only a head that stops ends yes", function(it)
	it(
		"AC3: a pipe into anything but head does not end yes: filters, loops, xargs, other programs",
		function()
			expectRefused({
				"yes | cat",
				"yes | wc -l",
				"yes | tee out",
				"yes | grep -q n",
				"yes | sed 's/y/n/'",
				"yes | while read -r l; do echo $l; done",
				"yes | xargs echo",
				"yes | rm -i a b",
				"yes | ./installer",
				"yes | git add -p",
			})
		end
	)

	it("AC3: the wrapper after the pipe is no excuse for yes when its own output is sent away", function()
		expectRefused({
			"yes > out | ./zn run --time 5 -- cat",
			"yes 2>&1 >/dev/null | ./zn run --time 5 -- cat",
			"echo ./zn | yes | cat",
		})
	end)

	it("AC3: only the stage straight after yes counts: a head later in the pipeline does not", function()
		expectRefused({
			"yes | sort | head -3",
			"yes | grep -v y | head -1",
			"yes | cat | head",
		})
	end)

	it(
		"AC3: a head that reads all of its input first does not end yes: a negative count, xargs head",
		function()
			expectRefused({
				"yes | head -n -3",
				"yes | head -n-3",
				"yes | head -c -1",
				"yes | head --lines=-2",
				"yes | head --bytes=-2",
				-- review 001 F7 (written, not run): option clusters and abbreviations that carry a negative count
				"yes | head -qn -3",
				"yes | head -vn-3",
				"yes | head --lin=-3",
				"yes | head --lines -2",
				"yes | xargs head",
				"yes | xargs -n1 head -1",
			})
		end
	)
end)
