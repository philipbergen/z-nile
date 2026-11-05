--!strict
-- R0079 review 001 (F1, F3, F4, F5): the reaper reads macOS's framework Python as python3, the hook refuses the detaching
-- forms of tmux, screen, at and launchctl while `tmux ls` and `screen -ls` pass, a few more spellings of a
-- process with no timeout, and every `ps` the reaper runs is pinned to the C locale.
local boundcmd = require("@znile/engine/boundcmd")
local fs = require("@lune/fs")
local process = require("@lune/process")
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local FRAMEWORK =
	"/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"
local CTX: boundcmd.Context = { zn = "/x/zn" }

local function refused(command: string): string?
	local v = boundcmd.check(command, CTX)
	return if v.ok then nil else v.rule
end

return t.spec("review 001 fixes", function(it)
	it(
		"F1: the framework Python is python3 for the reaper, and nothing else inside an application is",
		function()
			t.expect(reap.name(`{FRAMEWORK} probe.py`)).toBe("python3")
			t.expect(reap.isFrameworkPython(`{FRAMEWORK} probe.py`)).toBe(true)
			t.expect(reap.name("/Applications/Foo.app/Contents/MacOS/Python x")).toBe("Python")
			t.expect(reap.isFrameworkPython("/Applications/Foo.app/Contents/MacOS/Python x")).toBe(false)
			t.expect(reap.isFrameworkPython("/x/Python.framework/Versions/3/bin/python3 x")).toBe(false)
			-- an orphaned framework Python in scope is a leak; the same process under an application that is not Python is not
			local function proc(command: string): reap.Proc
				return {
					pid = 1000,
					ppid = 1,
					uid = 501,
					age = 3600,
					cpu = 3500,
					start = "Sat Oct 31 13:00:00 2026",
					command = command,
					cwd = "/Users/me/code/pickman/.worktree/R",
				}
			end
			local o: reap.Options = {
				uid = 501,
				now = 1793500000,
				minAge = 60,
				grace = 5,
				roots = { "/Users/me/code/pickman" },
				scratch = {},
				self = { 7 },
				under = nil,
				sessionAnywhere = true,
			}
			t.expect(#reap.decide({ proc(`{FRAMEWORK} probe.py`) }, o)).toBe(1)
			t.expect(#reap.decide({ proc("/Applications/Foo.app/Contents/MacOS/Foo x") }, o)).toBe(0)
		end
	)

	it("F3: detaching forms are refused and the listing forms pass", function()
		for _, c in
			{
				"tmux new -d 'lune run x'",
				"tmux new-session -d -s a sleep 99",
				"screen -dm lune x",
				"screen -d -m x",
				"at now",
				"launchctl submit -l a -- sleep 1",
			}
		do
			t.expect(refused(c) ~= nil).toBe(true)
		end
		for _, c in
			{ "tmux ls", "tmux list-sessions", "screen -ls", "launchctl list", "echo yes", "at_home=1 ls" }
		do
			t.expect(refused(c)).toBe(nil)
		end
		t.expect(refused("tmux new -d x")).toBe("detach")
	end)

	it("F4: the cheap spellings of a process with no timeout are refused", function()
		for _, c in
			{
				"python3 -c 'from subprocess import run; run([\"x\"])'",
				"python3 -c 'import subprocess as s; s.run([\"x\"])'",
				'python3 -c \'import os; os.execvp("x", ["x"])\'',
			}
		do
			t.expect(refused(c) ~= nil).toBe(true)
		end
		t.expect(refused("python3 -c 'from subprocess import run; run([\"x\"], timeout=5)'")).toBe(nil)
		t.expect(refused("python3 -c 'print(1)'")).toBe(nil)
	end)

	it("F5: every ps the reaper runs is pinned to the C locale", function()
		local text = fs.readFile(`{ROOT}/z-nile/engine/main.luau`)
		local count = 0
		for line in string.gmatch(text, "[^\n]+") do
			if string.find(line, '"ps"', 1, true) then
				count += 1
				t.expect(string.find(line, '"LC_ALL=C", "ps"', 1, true) ~= nil).toBe(true)
			end
		end
		t.expect(count >= 3).toBe(true)
	end)
end)
