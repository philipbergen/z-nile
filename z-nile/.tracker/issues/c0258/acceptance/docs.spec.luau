--!strict
-- c0258 AC5: zz-rules' Landing a change, step 2, states land's new rules (the regate rule, the ten pushes, a push that
-- reported a failure but landed, "already landed", -h/--help) and no longer says a lost push never reruns the gate; the
-- z-ticket lesson on removing a capture worktree counts `already landed on main` as landed and says land gives up
-- after ten lost races. Reads both from the checkout's top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local text = fs.readFile(`{root}/z-nile/skills/zz-rules/SKILL.md`)
-- the Landing step that describes land
local step = string.match(text, "\n2%. %*%*Push and open the PR%*%*[^\n]*") or ""

-- the capture lesson whose check names land's success line
local lesson = fs.readFile(`{root}/z-nile/skills/z-ticket/lessons/confirm-landed-before-removing.md`)

local function has(needle: string): boolean
	return string.find(step, needle, 1, true) ~= nil
end

return t.spec("c0258 docs", function(it)
	it("AC5: the Landing step describes land", function()
		t.expect(has("A capture lands with `./zn land` instead (no PR)")).toBe(true)
	end)

	it("AC5: it states when a lost race reruns the gate, and how many pushes land makes", function()
		t.expect(has("up to ten pushes")).toBe(true)
		t.expect(has("it runs the gate again only when `main` moved by more than tracker state")).toBe(true)
		t.expect(has("or changed one of the capture's files since the gate passed")).toBe(true)
	end)

	it("AC5: it states the landed-after-a-failed-push and already-landed outcomes", function()
		t.expect(has("A push that reports a failure while `origin/main` holds its commit has landed"))
			.toBe(true)
		t.expect(has("says `already landed` and exits 0")).toBe(true)
	end)

	it("AC5: it states -h and --help", function()
		t.expect(has("Every `./zn` command prints its usage for `-h` or `--help` and runs nothing"))
			.toBe(true)
	end)

	it("AC5: the old rule that a lost push never reruns the gate is gone, everywhere in the skill", function()
		t.expect((string.find(text, "a lost push retries the push, not the gate", 1, true))).toBe(nil)
	end)

	it(
		"AC5: the capture lesson counts already landed as landed, and gives up after ten lost races, not three",
		function()
			t.expect(string.find(lesson, "`already landed on main`", 1, true) ~= nil).toBe(true)
			-- the rule, not the history (its Why tells of lands that lost three times)
			t.expect((string.find(lesson, "loses the race to `main` three times", 1, true))).toBe(nil)
			t.expect(string.find(lesson, "loses the race to `main` ten times", 1, true) ~= nil).toBe(true)
		end
	)
end)
