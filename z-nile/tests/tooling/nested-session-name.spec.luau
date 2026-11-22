--!strict
-- d0439: a model CLI the engine starts runs under its own name. The session-end reaper finds the ending session as the
-- nearest ancestor whose program name is `claude` (reap.sessionRoot). A nested `claude -p` started by its resolved
-- real path (`.../claude/versions/2.1.330`) is not named `claude`, so its own SessionEnd hook took the OUTER session
-- for the one ending and stopped every other tool shell of it. The runner executes `program` (the resolved file) with
-- argv[1] as the name it runs as. `ps` is not allowed in the specs' jail, so the name is read from inside the started
-- program: bash's `$0` under `-c` with no further arguments is its argv[0], and `$BASH` is the file bash finds for its
-- argv[0] (an argv[0] with no slash is looked up on PATH, so a fake reached by its name names the fake's path).
local adapters = require("@znile/engine/adapters")
local fs = require("@lune/fs")
local modelstep = require("@znile/engine/modelstep")
local process = require("@lune/process")
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/nested-session-name`

local function mkdir(path: string)
	process.exec("mkdir", { "-p", path })
end

local function fresh()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	mkdir(`{base}/versions`)
	mkdir(`{base}/bin`)
	-- the CLI's real file under a versions folder, as the native install keeps it, and the PATH entry that links to it
	process.exec("ln", { "-s", "/bin/bash", `{base}/versions/9.9.9` })
	process.exec("ln", { "-s", `{base}/versions/9.9.9`, `{base}/bin/claude` })
end

-- the claude stream lines that carry `text` as the model's answer (the text is expanded by the shell that prints it)
local function answer(text: string): string
	return `printf '%s\\n' '\{"type":"assistant","message":\{"id":"m1","usage":\{"input_tokens":1,"output_tokens":1},"content":[\{"type":"text","text":"'"{text}"'"}]}}' '\{"type":"result","subtype":"success","is_error":false}'`
end

return t.spec("a model CLI the engine starts runs under its own name (d0439)", function(it)
	it("the runner executes the program it is given under argv[1]'s name", function()
		fresh()
		mkdir(`{base}/state1`)
		local result, text = modelstep.launch({
			argv = { "claude", "-c", answer("argv0=$0") },
			program = `{base}/versions/9.9.9`,
			cwd = base,
			-- no real CLI is on this PATH: a runner that looked `claude` up by name would find none
			env = { PATH = "/usr/bin:/bin" },
			adapter = adapters.get("claude-cli"),
			cap = 1000000,
			stallSeconds = 30,
			toolSeconds = 30,
			stateDir = `{base}/state1`,
		})
		t.expect(result.outcome).toBe("ok")
		t.expect(string.find(text, "argv0=claude", 1, true) ~= nil).toBe(true)
		-- and that is the name the reaper reads as a session's process
		t.expect(reap.name("claude -p hello --output-format stream-json")).toBe("claude")
		t.expect(reap.name(`{base}/versions/9.9.9 -p hello`)).toBe("9.9.9")
	end)

	it("a drive starts the CLI it resolved under the CLI's name, not its real path", function()
		fresh()
		-- bash runs the prompt as its script (`claude -p <prompt> ...` is `bash -p <script> ...`)
		local script = `{base}/prompt.sh`
		fs.writeFile(script, answer("bash=$BASH") .. "\n")
		local driven = modelstep.drive({
			spec = {
				cli = "claude",
				model = "fake-model",
				rank = 1,
				runtime = "claude-cli",
				maxTokens = 1000000,
			},
			settings = { autoMerge = {}, stallSeconds = 30, toolSeconds = 30 },
			prompt = script,
			cwd = base,
			stateDir = `{base}/state2`,
			path = `{base}/bin:/usr/bin:/bin`,
		})
		t.expect(driven.outcome).toBe("ok")
		-- argv[0] `claude` is found on PATH as the link; the real path would have named the versions file
		t.expect(string.find(driven.prose, `bash={base}/bin/claude`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(driven.prose, "versions/9.9.9", 1, true) == nil).toBe(true)
	end)
end)
