--!strict
-- c0254 AC1, AC4, AC5: the real `./zn dispatch <id> --worker` of two hosts over the fake CLIs, end to end on a fixture under
-- .cache/c0254-chain: two clones of one bare origin stand for two machines. A worker whose item another worker holds ends its
-- run with exit 6 before any step and starts no session; a race lost between the pick and the claim step (made to happen by a
-- hook that runs host A's claim while host B creates its worktree) ends the same way and leaves no worktree and no failed step
-- on host B; a plain dispatch of the same item behaves as before. The claim step runs as the worker whose session follows it,
-- the model's own claim in its session passes, and the rows a step spent carry the step's CLI, not the dispatcher's
-- environment's. Fake CLIs only: no model, no network, no real host.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local MODELS = [[
[dispatch]
stall_seconds = 60
tool_seconds = 120

[fallback.claude]
model = "claude-opus-5-5"
runtime = "claude-cli"

[roles.design]
model = "grok-4.7"
cli = "grok"
runtime = "grok-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = ["claude"]

[roles.implementation]
model = "grok-4.7"
cli = "grok"
runtime = "grok-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = ["claude"]
]]

local h: fakecli.Harness

local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-10\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- `./zn <args>` in host B's clone, with the fakes first on PATH as fakecli.zn does for host A
local function znB(args: { string }, extra: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		GH_TOKEN = "the-users-token",
	}
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(h.f.other, "bash", argv, { env = env })
end
local function stateOn(dir: string, id: string): any
	local file = `{dir}/.cache/dispatch/{id}/state.json`
	if not fs.isFile(file) then
		return nil
	end
	return (require("@lune/serde") :: any).decode("json", fs.readFile(file))
end
local function stampOnOrigin(id: string): string
	local text = fixture.git(h.f.origin, { "show", `main:pickman/.tracker/issues/{id}/{id}.md` })
	return string.match(text, "\nstatus: (%S+)\n") or ""
end

return t.spec("c0254 two hosts run the dispatcher's worker mode", function(it)
	it("sets up two clones of one origin, draft issues, a prepared raft and the fake CLIs", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = MODELS,
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Carry\nslug: carry\nsingle: false\nissues: [c0020]\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0020/c0020.md"] = `---\nid: c0020\ntype: chore\ntitle: c0020\nslug: c0020\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# c0020\n`,
			["pickman/.tracker/issues/c0020/check.sh"] = CHECK,
		}
		for _, id in { "c0010", "c0011", "c0012", "c0013" } do
			seed[`pickman/.tracker/issues/{id}/{id}.md`] = draft(id)
			seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
		end
		h = fakecli.new("c0254-chain", seed)
	end)

	it(
		"AC1: an issue host A claimed first ends host B's run with exit 6 before any step, starting no session",
		function()
			local wt = string.gsub(fakecli.zn(h, { "worktree", "prep-c0010" }).stdout, "%s+$", "")
			t.expect(fakecli.zn(h, { "-C", wt :: string, "status", "c0010", "preparing" }).ok).toBe(true)
			fakecli.clear(h)
			local r = znB({ "dispatch", "c0010", "--worker", "--pick", "draft" })
			t.expect(r.code).toBe(6)
			t.expect(has(r.stdout, "c0010 is no longer the draft it was picked as")).toBe(true)
			t.expect(fakecli.log(h)).toBe("")
			t.expect(fs.isDir(`{h.f.other}/.worktree/prep-c0010`)).toBe(false)
			local st = stateOn(h.f.other, "c0010")
			t.expect(st == nil or #st.history == 0).toBe(true)
		end
	)

	it("AC1: a plain dispatch of the same item is as it was: a failure, not the taken exit", function()
		local r = znB({ "dispatch", "c0010" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout .. r.stderr, "is being prepared by another terminal")).toBe(true)
	end)

	it("AC1: a raft host A readied first ends host B's run with exit 6, and no session runs on it", function()
		local ready = fakecli.zn(h, { "ready", "R0010" })
		if not ready.ok then
			error(`ready R0010 failed ({ready.code}): {ready.stderr}{ready.stdout}`)
		end
		fakecli.clear(h)
		local r = znB({ "dispatch", "R0010", "--worker", "--pick", "raft" })
		t.expect(r.code).toBe(6)
		t.expect(has(r.stdout, "R0010 is no longer the raft it was picked as")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"AC1: a race lost between the pick and the claim step ends the run `taken` and leaves nothing on the losing host",
		function()
			-- host B's worktree is created by its claim step; a post-checkout hook runs host A's claim at that moment
			local hook = `{h.f.other}/.git/hooks/post-checkout`
			local mark = `{h.f.base}/hook.mark`
			fs.writeFile(
				hook,
				`#!/bin/sh\n[ -f "{mark}" ] && exit 0\ntouch "{mark}"\ncd "{h.f.main}" || exit 0\nwt=$(env -i PATH="$PATH" HOME="$HOME" ./zn worktree hook-claim) || exit 0\ncd "$wt" && env -i PATH="$PATH" HOME="$HOME" ./zn status c0011 preparing >> "{mark}" 2>&1\nexit 0\n`
			)
			process.exec("chmod", { "+x", hook })
			fakecli.clear(h)
			local r = znB({ "dispatch", "c0011", "--worker", "--pick", "draft" })
			fs.removeFile(hook)
			t.expect(fs.isFile(mark)).toBe(true)
			t.expect(string.sub(stampOnOrigin("c0011"), 1, 10)).toBe("preparing-")
			t.expect(r.code).toBe(6)
			t.expect(has(r.stdout, "c0011 was claimed by another worker first")).toBe(true)
			t.expect(fakecli.log(h)).toBe("")
			t.expect(fs.isDir(`{h.f.other}/.worktree/prep-c0011`)).toBe(false)
			local st = stateOn(h.f.other, "c0011")
			t.expect(st ~= nil and #st.history == 0 and st.claim == nil).toBe(true)
		end
	)

	it(
		"AC4, AC5: the claim step runs as the worker that follows it, the model's own claim passes, and the rows carry the step's CLI",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "grok", "claim")
			local r = fakecli.zn(
				h,
				{ "dispatch", "c0012", "--worker", "--pick", "draft" },
				{ CLAUDECODE = "1", CLAUDE_CODE_SESSION_ID = "s" }
			)
			local out = r.stdout .. r.stderr
			-- the chain's end is not the point (no prep PR opens under a fake); the claim and the session are
			t.expect(has(out, "dispatch: claim c0012")).toBe(true)
			local body = fixture.git(
				h.f.origin,
				{ "log", "main", "-1", "--format=%B", "--grep=^tracker: c0012 preparing" }
			)
			local line = string.match(body, "(Worker: [^\n]+)") :: string
			t.expect(has(line, "cli=grok model=grok-4.7 attempt=")).toBe(true)
			t.expect(has(line, "cli=claude")).toBe(false)
			-- the model's own `./zn status c0012 preparing` in its session was refused by nobody
			t.expect(has(fakecli.log(h), "claim=0")).toBe(true)
			-- and the session was told, in its prompt, that the issue is already claimed
			t.expect(has(fakecli.log(h), "is already claimed for this run (stamp `preparing-")).toBe(true)
			local st = fakecli.state(h, "c0012")
			t.expect(st.claim.stamp).toBe(stampOnOrigin("c0012"))
			local rows = fakecli.rows(h, "c0012") or {}
			local seenCli = false
			for _, row in rows do
				if row.phase == "prep" then
					t.expect(row.cli).toBe("grok")
					t.expect(row.host ~= nil and row.host ~= "").toBe(true)
					seenCli = true
				end
			end
			t.expect(seenCli).toBe(true)
		end
	)

	it(
		"AC3: a push the session's own commit was refused under a taken claim ends the run with exit 7, naming it",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "grok", "script")
			-- inside the session: host B takes the claim over (a restamp pushed to origin by B's clone), then the session commits
			fs.writeFile(
				`{h.fakes}/script.sh`,
				`cd "{h.f.other}" && "$ZN_REAL_GIT" pull -q origin main && f=pickman/.tracker/issues/c0013/c0013.md && sed -i.bak 's/^status: .*/status: preparing-taken-by-other/' "$f" && rm -f "$f.bak" && "$ZN_REAL_GIT" -c user.name=o -c user.email=o@example.invalid commit -qam takeover && "$ZN_REAL_GIT" push -q origin HEAD:main\ncd "$OLDPWD" && echo late > pickman/.tracker/issues/c0013/late.md && ./zn commit -m "tracker: prep c0013 late"; echo "commit=$?"\n`
			)
			local r = fakecli.zn(h, { "dispatch", "c0013", "--worker", "--pick", "draft" })
			local out = r.stdout .. r.stderr
			t.expect(r.code).toBe(7)
			t.expect(has(out, "a push was refused under a live claim")).toBe(true)
			t.expect(has(fakecli.log(h), "commit=7")).toBe(true)
			t.expect(fakecli.state(h, "c0013").outcome).toBe("push-refused")
			t.expect(fs.isFile(`{h.f.main}/.worktree/prep-c0013/.cache/push-refused`)).toBe(false)
		end
	)
end)
