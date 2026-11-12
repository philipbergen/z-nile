--!strict
-- c0117 AC10: the dispatcher's control of a run, for real with fake CLIs (@tests/lib/fakecli): the chain stops at
-- questions.md and retry keeps the answers; `dispatch new` captures and chains; a review the author starts through the
-- dispatcher runs on its own CLI with the real git and its own state; the tracker's claims from inside a step reach
-- main through the publish broker; a push past the wrapper trips the wire; a step dies with its dispatcher, a dead
-- run is lost (never resumed or signalled), a live run is never dispatched twice, and `stop` signals only a group that
-- is still the run's; the merge gates come from the item's own walk. Fixture under .cache/c0117-control.
local adapters = require("@znile/engine/adapters")
local dispatcher = require("@znile/engine/dispatcher")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[fallback.agent]
model = "claude-opus-5-5"
runtime = "cursor-cli"
max_calls = 2
max_minutes = 60

[roles.idea]
model = "claude-sonnet-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = ["grok", "agent"]

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["grok"]
]]

local h: fakecli.Harness
local function issue(id: string, slug: string): string
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon")
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local function mode(name: string, value: string?)
	fakecli.mode(h, name, value)
end
local function dirOf(id: string): string
	return `{h.f.main}/.cache/dispatch/{id}`
end
local function onOrigin(path: string): string
	return fixture.git(h.f.origin, { "show", `main:{path}` })
end
local function absentAfter(path: string, seconds: number): boolean
	local waited = 0
	while waited < seconds do
		if fs.isFile(path) then
			return false
		end
		waited += task.wait(0.1)
	end
	return not fs.isFile(path)
end

return t.spec("c0117 the dispatcher's control of a run", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0117-control", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "seventh-thing"),
			["pickman/.tracker/issues/c0080/c0080.md"] = issue("c0080", "eighth-thing"),
			["pickman/.tracker/issues/c0080/.models.toml"] = "[dispatch]\nauto_merge = []\n",
			["pickman/.tracker/issues/c0090/c0090.md"] = issue("c0090", "ninth-thing"),
			["pickman/.tracker/issues/c0090/.models.toml"] = '[roles.design]\ncli = "agent"\nmodel = "claude-opus-5-5"\nruntime = "cursor-cli"\nmax_calls = 2\nmax_minutes = 60\nfallbacks = []\n',
			["pickman/.tracker/issues/c0091/c0091.md"] = issue("c0091", "tenth-thing"),
			["pickman/.tracker/issues/c0101/c0101.md"] = issue("c0101", "conc-one"),
			["pickman/.tracker/issues/c0095/c0095.md"] = issue("c0095", "long-review"),
			["pickman/.tracker/issues/c0095/.models.toml"] = "[dispatch]\ntool_seconds = 8\nstall_seconds = 8\n",
			["pickman/.tracker/issues/c0097/c0097.md"] = issue("c0097", "silent-review"),
			["pickman/.tracker/issues/c0097/.models.toml"] = "[dispatch]\ntool_seconds = 24\nstall_seconds = 10\n",
			["pickman/.tracker/issues/c0096/c0096.md"] = string.gsub(
				trackerfix.stub("c0096", "rafted-thing", "prepared-quiet-copper-falcon"),
				"design: draft",
				"design: ready"
			),
			["pickman/.tracker/issues/c0096/.models.toml"] = '[dispatch]\nauto_merge = ["raft"]\n',
			["pickman/.tracker/issues/c0091/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0091/acceptance/a.spec.luau\n",
			["pickman/.tracker/issues/c0102/c0102.md"] = issue("c0102", "conc-two"),
		})
	end)

	it(
		"stops the chain at questions.md, starts nothing more, and retry keeps the answers and reruns",
		function()
			fakecli.clear(h)
			mode("claude", "questions")
			local r = zn({ "dispatch", "c0010" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "needs the user")).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			t.expect(zn({ "dispatch", "c0010" }).code).toBe(3)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			mode("claude", "ok")
			local retry = zn({ "dispatch", "retry", "c0010" })
			t.expect(fs.isFile(`{dirOf("c0010")}/answered-1.md`)).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(2)
			-- the fake claimed nothing: the chain stops instead of designing again
			t.expect(retry.code).toBe(1)
			t.expect(has(retry.stdout, "still new on origin/main")).toBe(true)
		end
	)

	it("captures a new issue (z-ticket), records its capture row, and chains into its design", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "questions")
		local r = zn({ "dispatch", "new", "a dispatched thing" })
		t.expect(r.code).toBe(3)
		local id = string.match(fakecli.log(h), "issues/(c%d%d%d%d)/") :: string
		t.expect(id ~= nil).toBe(true)
		t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
		t.expect(count(fakecli.log(h), "claude step=z-design mode=questions")).toBe(1)
		local rows = fakecli.rows(h, id) :: { any }
		t.expect(rows[1].phase).toBe("capture")
		t.expect(rows[1].model).toBe("claude-sonnet-5")
		t.expect(fs.isFile(`{dirOf(id)}/questions.md`)).toBe(true)
	end)

	it(
		"a review the author starts through the dispatcher runs on its own CLI, with the real git and its own state",
		function()
			fakecli.clear(h)
			-- the author ends up on grok (claude is out of quota for it); the review's own walk puts it on claude
			mode("claude.z-design", "quota")
			mode("grok.z-design", "author")
			mode("claude.zz-review", "reviewer")
			local r = zn({ "dispatch", "z-design", "c0020" })
			if not r.ok then
				error(r.stdout .. r.stderr .. fakecli.log(h))
			end
			local l = fakecli.log(h)
			t.expect(has(l, "gitstatus=0")).toBe(true)
			t.expect(has(l, "review=0")).toBe(true)
			local wt = `{h.f.main}/.worktree/prep-second-thing`
			t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/c0020/design-review-001.md`)).toBe(true)
			local rows = fakecli.rows(h, "c0020") :: { any }
			local review: any = nil
			for _, row in rows do
				if row.subject == "design-review-001" then
					review = row
				end
			end
			t.expect(review ~= nil).toBe(true)
			t.expect(review.model).toBe("claude-opus-5-5-xhigh")
			t.expect(review.phase).toBe("design-review")
			-- the author's state is its own, and the review's sits beside it
			local author = fakecli.state(h, "c0020")
			t.expect(author.outcome).toBe("ok")
			t.expect(author.cli).toBe("grok")
			-- the nested folder names its item (review 002 F11)
			t.expect(fs.isFile(`{dirOf("c0020")}/zz-review-design-c0020-1/state.json`)).toBe(true)
			local nestedState = fakecli.state(h, "c0020", "zz-review-design-c0020-1")
			t.expect(nestedState.cli).toBe("claude")
			t.expect(nestedState.outcome).toBe("ok")
		end
	)

	it(
		"a claim from inside a step reaches main through the publish broker, and the tripwire stays quiet",
		function()
			fakecli.clear(h)
			mode("claude", "claim")
			local r = zn({ "dispatch", "z-design", "c0030" })
			if not r.ok then
				error(r.stdout .. r.stderr .. fakecli.log(h))
			end
			t.expect(has(fakecli.log(h), "claim=0")).toBe(true)
			t.expect(
				string.match(onOrigin("pickman/.tracker/issues/c0030/c0030.md"), "\nstatus: preparing%-")
					~= nil
			)
				.toBe(true)
			t.expect(#fakecli.state(h, "c0030").pushed).toBe(1)
		end
	)

	it(
		"a code push past the wrapper (the real git) trips the wire: exit 5, and the step's spend is kept",
		function()
			fakecli.clear(h)
			mode("claude", "tripwire")
			local r = zn({ "dispatch", "z-design", "c0040" })
			t.expect(r.code).toBe(5)
			t.expect(has(fakecli.log(h), "realpush=0")).toBe(true)
			local s = fakecli.state(h, "c0040")
			t.expect(s.outcome).toBe("tripwire")
			t.expect(has(s.detail, "code.lua")).toBe(true)
			t.expect((fakecli.rows(h, "c0040") :: { any })[1].tokens).toBe(123)
			-- the chain does not go on after it, and nor does any other run, until the user vets main
			t.expect(zn({ "dispatch", "c0040" }).code).toBe(5)
			t.expect(zn({ "dispatch", "z-design", "c0010", "--dry-run" }).ok).toBe(true)
			t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(5)
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		end
	)

	it("a code push straight to main between runs stops the next run until the user vets main", function()
		fakecli.clear(h)
		trackerfix.elsewhere(h.f, { ["src/direct.lua"] = "return 1\n" }, "a direct code push")
		local r = zn({ "dispatch", "z-design", "c0010" })
		t.expect(r.code).toBe(5)
		t.expect(has(r.stdout, "src/direct.lua")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		-- tracker state pushed by another terminal is vetted without the user
		trackerfix.elsewhere(
			h.f,
			{ ["pickman/.tracker/issues/c0010/notes.md"] = "notes\n" },
			"tracker state elsewhere"
		)
		t.expect(zn({ "dispatch", "z-design", "c0010" }).code ~= 5).toBe(true)
	end)

	it("a step that removes or rewrites the watermark trips the wire after that same step", function()
		local function step(script: string): fixture.Result
			fakecli.clear(h)
			fs.writeFile(`{h.fakes}/script.sh`, script)
			mode("claude", "script")
			return zn({ "dispatch", "z-design", "c0010" })
		end
		local function push(name: string): string
			return `git fetch -q origin main; git checkout -q -B {name} FETCH_HEAD; echo {name} > {name}.lua; git add {name}.lua; git -c user.name=f -c user.email=f@example.invalid commit -q -m {name}; "$ZN_REAL_GIT" push -q origin HEAD:main; `
		end
		local removed = step(push("w1") .. [[find "$ZN_WATERMARK_DIR" -name main-seen -exec rm {} \;]])
		t.expect(removed.code).toBe(5)
		t.expect(fakecli.state(h, "c0010").outcome).toBe("tripwire")
		-- caught by what the step pushed, vetted from the run's own copy whatever the file says (review 004 F1)
		t.expect(has(fakecli.state(h, "c0010").detail, "w1.lua")).toBe(true)
		-- between runs a missing watermark is never trusted
		t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(5)
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		local rewritten =
			step(push("w2") .. [[git rev-parse HEAD > "$(find "$ZN_WATERMARK_DIR" -name main-seen)"]])
		t.expect(rewritten.code).toBe(5)
		t.expect(has(fakecli.state(h, "c0010").detail, "w2.lua")).toBe(true)
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		-- no watermark, and an item with no run yet (so no mirror): never trusted on first use
		do
			local dir = h.f.base .. "/watermark"
			local only = ""
			for _, d in fs.readDir(dir) do
				only = `{dir}/{d}/main-seen`
			end
			local saved = fs.readFile(only)
			fs.removeFile(only)
			local first = zn({ "dispatch", "z-design", "c0012" })
			t.expect(first.code).toBe(5)
			t.expect(has(first.stdout, "there is no watermark")).toBe(true)
			fs.writeFile(only, saved)
		end
		-- a watermark set back between runs (to a commit main still has) is behind the item's mirror
		fakecli.clear(h)
		t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(0)
		local mark = h.f.base .. "/watermark"
		local file = ""
		for _, d in fs.readDir(mark) do
			file = `{mark}/{d}/main-seen`
		end
		local now = fs.readFile(file)
		fs.writeFile(file, fixture.git(h.f.origin, { "rev-parse", "main~2" }) .. "\n")
		local back = zn({ "dispatch", "z-design", "c0010" })
		t.expect(back.code).toBe(5)
		t.expect(has(back.stdout, "the watermark went back")).toBe(true)
		fs.writeFile(file, now)
	end)

	it(
		"a step that repoints origin, or adds a push URL, trips the wire; a URL changed between runs stops the next",
		function()
			local function step(script: string): fixture.Result
				fakecli.clear(h)
				fs.writeFile(`{h.fakes}/script.sh`, script)
				mode("claude", "script")
				return zn({ "dispatch", "z-design", "c0010" })
			end
			local frozen = `{h.f.base}/frozen.git`
			fixture.git(h.f.main, { "clone", "-q", "--bare", h.f.origin, frozen })
			local blind = step(
				`git fetch -q origin main; git checkout -q -B r FETCH_HEAD; echo r > r.lua; git add r.lua; git -c user.name=f -c user.email=f@example.invalid commit -q -m r; "$ZN_REAL_GIT" push -q origin HEAD:main; git config remote.origin.url {frozen}; git config remote.origin.pushurl {h.f.origin}`
			)
			t.expect(blind.code).toBe(5)
			t.expect(has(fakecli.state(h, "c0010").detail, "origin's configuration changed during the step"))
				.toBe(true)
			fixture.git(h.f.main, { "config", "--unset", "remote.origin.pushurl" })
			-- the URL as the step left it, at the next run: changed since the last run
			local next = zn({ "dispatch", "z-design", "c0010" })
			t.expect(next.code).toBe(5)
			t.expect(has(next.stdout, "origin's URL changed since the last run")).toBe(true)
			fixture.git(h.f.main, { "config", "remote.origin.url", h.f.origin })
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			local pushurl = step(`git config remote.origin.pushurl {frozen}`)
			t.expect(pushurl.code).toBe(5)
			fixture.git(h.f.main, { "config", "--unset", "remote.origin.pushurl" })
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		end
	)

	it("vet --dry-run lists what it would accept and writes nothing", function()
		fakecli.clear(h)
		trackerfix.elsewhere(h.f, { ["src/dry.lua"] = "return 1\n" }, "a code commit")
		local dry = zn({ "dispatch", "vet", "--dry-run" })
		t.expect(dry.ok).toBe(true)
		t.expect(has(dry.stdout, "NOT VETTED, you accept it")).toBe(true)
		t.expect(has(dry.stdout, "src/dry.lua")).toBe(true)
		t.expect(has(dry.stdout, "dry run: nothing written")).toBe(true)
		t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(5)
		local vet = zn({ "dispatch", "vet" })
		t.expect(has(vet.stdout, "main vetted at")).toBe(true)
	end)

	it(
		"two dispatchers at once never trip each other: another run's honest advance of the watermark is no trip",
		function()
			-- review 004 case C: while B's step runs, the user's other terminal publishes tracker state and runs A (its
			-- environment is the step's without the step's own variables: the spec's guards stay, so no `env` that clears
			-- them all, which repo-fence refuses)
			fakecli.clear(h)
			mode("claude", "script")
			local script = [==[if [ "$id" = c0102 ]; then echo "A step ran"; exit 0; fi
userpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
G=$ZN_REAL_GIT
( cd @OTHER@ && $G pull -q origin main && echo note > pickman/.tracker/issues/c0101/note.md && $G add -A && $G -c user.name=u -c user.email=u@example.invalid commit -qm "other terminal: tracker state" && $G push -q origin HEAD:main; echo otherpush=$? )
( cd @MAIN@ && env -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR -u ZN_DISPATCH_HOME -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCHER_PID -u ZN_REAL_GIT -u ZN_REAL_GH -u GITHUB_TOKEN PATH="$userpath" ZN_AGENT_TOKEN_FILE="$ZN_AGENT_TOKEN_FILE_SAVED" ZN_WATERMARK_DIR="@BASE@/watermark" GH_TOKEN=the-users-token bash scripts/tracker.sh dispatch z-design c0102; echo "A exit=$?" )
]==]
			script = string.gsub(
				string.gsub(string.gsub(script, "@OTHER@", h.f.other), "@MAIN@", h.f.main),
				"@BASE@",
				h.f.base
			)
			fs.writeFile(`{h.fakes}/script.sh`, script)
			local b = zn({ "dispatch", "z-design", "c0101" }, { ZN_AGENT_TOKEN_FILE_SAVED = h.token })
			t.expect(has(fakecli.log(h), "otherpush=0")).toBe(true)
			t.expect(has(fakecli.log(h), "A exit=0")).toBe(true)
			t.expect(b.code).toBe(0)
			t.expect(fakecli.state(h, "c0101").outcome).toBe("ok")
		end
	)

	it(
		"each run fetches into refs of its own: two runs publishing at once both pass, even with a shared ref locked",
		function()
			-- review 005 F1: a lock on the old shared ref stands for another fetch holding it; a run of its own never sees it
			fakecli.clear(h)
			local lockDir = `{h.f.main}/.git/refs/zn-dispatch`
			fs.writeDir(lockDir)
			fs.writeFile(`{lockDir}/main.lock`, "")
			mode("claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				'for i in 1 2 3 4 5; do ./zn new issue c "$id-note-$i" --project pickman --desc "from $id" > /dev/null 2>&1; echo "published=$?"; done\n'
			)
			local results: { [string]: fixture.Result } = {}
			local done = 0
			for _, id in { "c0101", "c0102" } do
				task.spawn(function()
					results[id] = zn({ "dispatch", "z-design", id })
					done += 1
				end)
			end
			local waited = 0
			while done < 2 and waited < 240 do
				waited += task.wait(0.2)
			end
			fs.removeFile(`{lockDir}/main.lock`)
			t.expect(done).toBe(2)
			t.expect(results.c0101.code).toBe(0)
			t.expect(results.c0102.code).toBe(0)
			t.expect(count(fakecli.log(h), "published=0")).toBe(10)
			-- and each run's refs are gone at its end
			t.expect(fixture.git(h.f.main, { "for-each-ref", "refs/zn-dispatch/" })).toBe("")
		end
	)

	it("a fetch that fails on a lock is retried; a lost run's leftover refs are swept", function()
		fakecli.clear(h)
		fs.writeFile(`{h.fakes}/fetchfail`, "2\n")
		local r = zn({ "dispatch", "z-design", "c0010" })
		t.expect(r.code).toBe(0)
		t.expect((string.gsub(fs.readFile(`{h.fakes}/fetchfail`), "%s+$", ""))).toBe("0")
		fs.removeFile(`{h.fakes}/fetchfail`)
		-- a ref a lost run left (no one holds its lock) goes at the next run's start
		fixture.git(h.f.main, { "update-ref", "refs/zn-dispatch/run-dead/main", "HEAD" })
		t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(0)
		t.expect(fixture.git(h.f.main, { "for-each-ref", "refs/zn-dispatch/" })).toBe("")
	end)

	it("the shared watermark only moves forward: an older main never overwrites a newer one", function()
		local dir = `{h.f.base}/mark-forward`
		local path = `{dir}/main-seen`
		local older = fixture.git(h.f.origin, { "rev-parse", "main~1" })
		local newer = fixture.git(h.f.origin, { "rev-parse", "main" })
		fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
		t.expect(dispatcher.advanceMark(h.f.main, path, older)).toBe(nil)
		t.expect(dispatcher.advanceMark(h.f.main, path, newer)).toBe(nil)
		t.expect((string.gsub(fs.readFile(path), "%s+$", ""))).toBe(newer)
		-- the late writer of the older main leaves the file as it is
		t.expect(dispatcher.advanceMark(h.f.main, path, older)).toBe(nil)
		t.expect((string.gsub(fs.readFile(path), "%s+$", ""))).toBe(newer)
		-- a diverged commit is refused; the user's vet (force) writes it
		fixture.git(h.f.other, { "fetch", "-q", "origin", "main" })
		fixture.git(h.f.other, { "checkout", "-q", "-B", "diverged", "FETCH_HEAD~1" })
		fs.writeFile(`{h.f.other}/diverged.md`, "x\n")
		fixture.git(h.f.other, { "add", "-A" })
		fixture.git(h.f.other, { "commit", "-q", "-m", "diverged" })
		local side = fixture.git(h.f.other, { "rev-parse", "HEAD" })
		fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/diverged" })
		fixture.git(h.f.other, { "checkout", "-q", "main" })
		fixture.git(h.f.main, { "fetch", "-q", "origin", "diverged" })
		t.expect(has(dispatcher.advanceMark(h.f.main, path, side) or "", "diverged")).toBe(true)
		t.expect(dispatcher.advanceMark(h.f.main, path, side, true)).toBe(nil)
		t.expect((string.gsub(fs.readFile(path), "%s+$", ""))).toBe(side)
	end)

	it(
		"an author waiting on a long nested review stays alive by its heartbeat; a quiet one still stalls",
		function()
			-- review 004 F2: the author waits on one shell command (its review) for longer than tool_seconds (5 s here)
			fakecli.clear(h)
			mode("claude.z-design", "waitreview")
			mode("claude.zz-review", "slowreview")
			local r = zn({ "dispatch", "z-design", "c0095" })
			local s = fakecli.state(h, "c0095")
			t.expect(s.outcome).toBe("ok")
			t.expect(r.code).toBe(0)
			t.expect(has(fakecli.log(h), "review=0")).toBe(true)
			-- claude's own shell-command limits raised in the step's environment
			t.expect(has(fakecli.log(h), "bashmax=7200000")).toBe(true)
			-- a nested reviewer that goes quiet: it stalls at its own limits and its beats stop, so nothing hangs
			fakecli.clear(h)
			mode("claude.z-design", "waitreview")
			mode("claude.zz-review", "quietreview")
			zn({ "dispatch", "z-design", "c0095" })
			local newest, n = "", 0
			for _, name in fs.readDir(dirOf("c0095")) do
				local k = tonumber(string.match(name, "^zz%-review%-design%-c0095%-(%d+)$") or "")
				if k and k > n then
					newest, n = name, k
				end
			end
			t.expect(fakecli.state(h, "c0095", newest).outcome).toBe("stalled")
		end
	)

	it(
		"a reviewer silent but within its own limits keeps its author alive past the author's own limit",
		function()
			-- review 005 F3: a beat says "alive and within my limits"; here the author's limit is stall_seconds = 10 and
			-- the reviewer is silent 18 s inside one tool call, within its tool_seconds = 24
			fakecli.clear(h)
			mode("claude.z-design", "waitplain")
			mode("claude.zz-review", "silenttool")
			local r = zn({ "dispatch", "z-design", "c0097" })
			t.expect(fakecli.state(h, "c0097").outcome).toBe("ok")
			t.expect(r.code).toBe(0)
			t.expect(has(fakecli.log(h), "review=0")).toBe(true)
		end
	)

	it(
		"the rafting gate merges a PR of its own raft's files, and waits for code, another item's check, settings or a stale head",
		function()
			-- review 004 F3: real heads on the fixture origin, auto_merge = ["raft"] in the item's own walk
			fakecli.clear(h)
			-- a GitHub-looking origin, rewritten to the fixture's own (the chain asks the fake gh about PRs)
			local url = "https://github.com/zn-fixture/c0117.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			local function prJson(n: number, head: string): string
				return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
			end
			local doc = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/issues/c0096/c0096.md" })
			local raft = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096]\n---\n"
			local own = {
				["pickman/.tracker/rafts/R0050/R0050.md"] = raft,
				["pickman/.tracker/issues/c0096/c0096.md"] = (
					string.gsub(doc, "\nraft: \n", "\nraft: R0050\n")
				),
			}
			local function with(extra: { [string]: string }): { [string]: string }
				local out = table.clone(own)
				for k, v in extra do
					out[k] = v
				end
				return out
			end
			local function gate(n: number, files: { [string]: string }, head: string?): fixture.Result
				local sha = fakecli.pullRequest(h, n, files)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(n, head or sha))
				return zn({ "dispatch", "c0096" })
			end
			-- waits: code
			local code = gate(21, with({ ["src/x.lua"] = "return 1\n" }))
			t.expect(code.code).toBe(4)
			t.expect(has(code.stdout, "src/x.lua")).toBe(true)
			-- waits: another item's check.sh (c0091 is no member)
			local check = gate(22, with({ ["pickman/.tracker/issues/c0091/check.sh"] = "exit 0\n" }))
			t.expect(check.code).toBe(4)
			t.expect(has(check.stdout, "c0091")).toBe(true)
			-- waits: settings
			local settings = gate(
				23,
				with({
					["pickman/.tracker/issues/c0096/.models.toml"] = '[dispatch]\nauto_merge = ["raft", "prep"]\n',
				})
			)
			t.expect(settings.code).toBe(4)
			t.expect(has(settings.stdout, "configuration")).toBe(true)
			-- waits: a stale head
			local stale = gate(24, own, "0000000000000000000000000000000000000000")
			t.expect(stale.code).toBe(4)
			t.expect(has(stale.stdout, "is not the head GitHub reports")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge")).toBe(false)
			-- merges: the raft's own document and its member's raft: line, pinned to the head
			local sha = fakecli.pullRequest(h, 25, own)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(25, sha))
			zn({ "dispatch", "c0096" })
			t.expect(has(fakecli.log(h), `realgh pr merge 25 --squash --match-head-commit {sha}`)).toBe(true)
		end
	)

	it("a detached process's late code push after a step is caught at the next run", function()
		fakecli.clear(h)
		mode("claude", "late")
		local r = zn({ "dispatch", "z-design", "c0060" })
		t.expect(r.ok).toBe(true)
		local waited = 0
		while
			waited < 10
			and fixture.exec(h.f.origin, "git", { "cat-file", "-e", "main:late.lua" }).ok == false
		do
			waited += task.wait(0.2)
		end
		t.expect(fixture.exec(h.f.origin, "git", { "cat-file", "-e", "main:late.lua" }).ok).toBe(true)
		local next = zn({ "dispatch", "z-design", "c0060" })
		t.expect(next.code).toBe(5)
		t.expect(has(next.stdout, "late.lua")).toBe(true)
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
	end)

	it("a cursor step that never shows a call still stops at its wall-time ceiling (max_minutes)", function()
		local dir = `{h.f.base}/wall`
		fs.writeDir(dir)
		local r = runner.run({
			-- calls with ids, one a second: under max_calls, never quiet, never unknown
			argv = {
				"sh",
				"-c",
				[[i=0; while :; do i=$((i+1)); echo '{"type":"assistant","message":{"content":[]},"model_call_id":"m-'$i'"}'; echo '{"type":"user"}'; sleep 0.2; done]],
			},
			cwd = dir,
			env = { PATH = process.env.PATH or "" },
			adapter = adapters.get("cursor-cli"),
			cap = 1000000,
			maxCalls = 1000,
			maxSeconds = 1,
			stallSeconds = 30,
			toolSeconds = 30,
			stateDir = dir,
		})
		t.expect(r.outcome).toBe("cap")
		t.expect(has(r.detail, "of wall time")).toBe(true)
	end)

	it("a stop while the step is starting is a request, never a lost run", function()
		local dir = dirOf("c0050")
		fs.writeDir(dir)
		local held = runner.holdLock(`{dir}/lock`)
		fs.writeFile(
			`{dir}/state.json`,
			serde.encode(
				"json",
				{ id = "c0050", mode = "step", outcome = "running", history = {}, pending = {} }
			)
		)
		local r = zn({ "dispatch", "stop", "c0050" })
		t.expect(has(r.stdout, "stop requested")).toBe(true)
		t.expect(fakecli.state(h, "c0050").outcome).toBe("running")
		t.expect(fs.isFile(`{dir}/stop`)).toBe(true);
		(held :: any).stdin:close()
		fs.removeFile(`{dir}/stop`)
		fs.writeFile(
			`{dir}/state.json`,
			serde.encode("json", { id = "c0050", mode = "step", history = {}, pending = {} })
		)
	end)

	it(
		"a step dies with its dispatcher; the dead run is lost, never resumed, and retry takes it over",
		function()
			fakecli.clear(h)
			mode("claude", "orphan")
			local r = zn({ "dispatch", "z-design", "c0050" })
			t.expect(r.ok).toBe(false)
			t.expect(absentAfter(`{h.fakes}/grandchild-orphan`, 5)).toBe(true)
			local again = zn({ "dispatch", "z-design", "c0050" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stdout, "lost")).toBe(true)
			t.expect(fakecli.state(h, "c0050").outcome).toBe("lost")
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			mode("claude", "ok")
			t.expect(zn({ "dispatch", "retry", "c0050" }).ok).toBe(true)
			t.expect(fakecli.state(h, "c0050").outcome).toBe("ok")
		end
	)

	it("a live run is never dispatched twice", function()
		fakecli.clear(h)
		local dir = dirOf("c0060")
		fs.writeDir(dir)
		local holder = runner.holdLock(`{dir}/lock`)
		t.expect(holder ~= nil).toBe(true)
		local r = zn({ "dispatch", "z-design", "c0060" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "is being dispatched")).toBe(true)
		t.expect(fakecli.log(h)).toBe("");
		(holder :: any).stdin:close()
	end)

	it("stop signals only a group that is still the run's, and never a group id of 1", function()
		local dir = dirOf("c0060")
		local me =
			tonumber((string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+", ""))) :: number
		-- a group id that names a live process (this spec's own) whose run lock nobody holds: a stale state
		-- a group id of 1 with a held lock: never signalled (`kill -- -1` would signal every process of the user)
		local held = runner.holdLock(`{dir}/held.lock`)
		for _, run in
			{ { pgid = me, lockFile = `{dir}/nobody.lock` }, { pgid = 1, lockFile = `{dir}/held.lock` } }
		do
			fs.writeFile(
				`{dir}/state.json`,
				serde.encode("json", {
					id = "c0060",
					mode = "step",
					outcome = "running",
					run = run,
					history = {},
					pending = {},
				})
			)
			local r = zn({ "dispatch", "stop", "c0060" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "lost")).toBe(true)
			t.expect(fakecli.state(h, "c0060").outcome).toBe("lost")
		end
		(held :: any).stdin:close()
		-- this spec's own process (the stale group id above) is alive
		t.expect(process.exec("kill", { "-0", tostring(me) }).ok).toBe(true)
	end)

	it(
		"a cursor step stops after max_calls model calls, and a finished one records the real total",
		function()
			fakecli.clear(h)
			mode("agent", "calls")
			local r = zn({ "dispatch", "z-design", "c0090" })
			t.expect(r.ok).toBe(false)
			local s = fakecli.state(h, "c0090")
			t.expect(s.outcome).toBe("cap")
			t.expect(string.find(s.detail, "passed max_calls 2 at call 3", 1, true) ~= nil).toBe(true)
			-- fail closed: a stream with no model_call_id stops as cap-unknown
			fakecli.clear(h)
			mode("agent", "noids")
			t.expect(zn({ "dispatch", "z-design", "c0090" }).ok).toBe(false)
			t.expect(fakecli.state(h, "c0090").outcome).toBe("cap-unknown")
			fakecli.clear(h)
			local ok = zn({ "dispatch", "z-design", "c0090" })
			t.expect(ok.ok).toBe(true)
			local rows = fakecli.rows(h, "c0090")
			t.expect(rows ~= nil).toBe(true)
			local list = rows :: { any }
			t.expect(list[#list].tokens).toBe(300 + 9)
			t.expect(list[#list].model).toBe("claude-opus-5-5-high")
		end
	)

	it(
		"stops at the prep gate whatever the item's walk allows, and merges the rafting gate with the real gh itself",
		function()
			fakecli.clear(h)
			-- a GitHub-looking origin, rewritten to the fixture's own (the chain asks the fake gh about PRs)
			local url = "https://github.com/zn-fixture/c0117.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			-- each PR is a real head on origin (refs/pull/<n>/head), which the gate fetches and judges (review 003 F5)
			local function prJson(n: number, head: string): string
				return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
			end
			local head7 = fakecli.pullRequest(h, 7, { ["pickman/.tracker/issues/c0070/x.md"] = "notes\n" })
			fs.writeFile(`{h.fakes}/pr-prep-seventh-thing.json`, prJson(7, head7))
			mode("claude", "claim")
			-- c0283: auto_merge = ["prep"] at the root has no effect: the prep gate never merges, and says who does
			local merged = zn({ "dispatch", "c0070" })
			t.expect(has(fakecli.log(h), "realgh pr merge 7")).toBe(false)
			t.expect(merged.code).toBe(4)
			t.expect(has(merged.stdout, "waits for the user's approval and merge")).toBe(true)
			t.expect(has(merged.stdout, "./zn approve c0070")).toBe(true)
			-- an item-level auto_merge = [] wins: the chain waits at the gate, and nothing is merged
			local head8 = fakecli.pullRequest(h, 8, { ["pickman/.tracker/issues/c0080/x.md"] = "notes\n" })
			fs.writeFile(`{h.fakes}/pr-prep-eighth-thing.json`, prJson(8, head8))
			local waiting = zn({ "dispatch", "c0080" })
			t.expect(waiting.code).toBe(4)
			t.expect(has(waiting.stdout, "#8 waits for a merge")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 8")).toBe(false)
			-- a prep PR whose head carries code waits for a human, whatever auto_merge says
			local head9 = fakecli.pullRequest(
				h,
				9,
				{ ["pickman/.tracker/issues/c0091/x.md"] = "x\n", ["src/x.lua"] = "return 1\n" }
			)
			fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, prJson(9, head9))
			local carries = zn({ "dispatch", "c0091" })
			t.expect(carries.code).toBe(4)
			t.expect(has(carries.stdout, "src/x.lua")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 9")).toBe(false)
			-- a prep PR that touches another item's documents waits too
			local other = fakecli.pullRequest(h, 14, { ["pickman/.tracker/issues/c0070/y.md"] = "y\n" })
			fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, prJson(14, other))
			local elsewhere = zn({ "dispatch", "c0091" })
			t.expect(elsewhere.code).toBe(4)
			t.expect(has(elsewhere.stdout, "outside the issue's own folder")).toBe(true)
			-- a rename of code into the issue's folder: gh would list only the new path; the head's raw diff shows both
			trackerfix.elsewhere(h.f, { ["src/guard.lua"] = "return 1\n" }, "code a human merged")
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			local head10 = fakecli.pullRequest(
				h,
				10,
				{},
				{ ["src/guard.lua"] = "pickman/.tracker/issues/c0091/guard.lua" }
			)
			fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, prJson(10, head10))
			local renamed = zn({ "dispatch", "c0091" })
			t.expect(renamed.code).toBe(4)
			t.expect(has(renamed.stdout, "src/guard.lua")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 10")).toBe(false)
			-- the issue's own .models.toml in a prep PR: configuration that grants authority, a human's (review 003 F4)
			local head11 = fakecli.pullRequest(
				h,
				11,
				{ ["pickman/.tracker/issues/c0091/.models.toml"] = '[dispatch]\nauto_merge = ["prep"]\n' }
			)
			fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, prJson(11, head11))
			t.expect(has(zn({ "dispatch", "c0091" }).stdout, "configuration")).toBe(true)
			-- a head gh reports that isn't the one on origin waits
			fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, prJson(9, head7))
			local stale = zn({ "dispatch", "c0091" })
			t.expect(stale.code).toBe(4)
			t.expect(has(stale.stdout, "is not the head GitHub reports")).toBe(true)
			-- a code commit on main that GitHub reports as a pull request's merge into main is vetted; into another
			-- branch, never (review 003 F6)
			trackerfix.elsewhere(h.f, { ["src/side.lua"] = "return 1\n" }, "merged into a side branch")
			local side = fixture.git(h.f.origin, { "rev-parse", "main" })
			fs.writeFile(
				`{h.fakes}/pulls-{side}.json`,
				`[\{"number":12,"merged_at":"2026-10-21T00:00:00Z","merge_commit_sha":"{side}","base":\{"ref":"side"\}\}]`
			)
			local sideRun = zn({ "dispatch", "c0099" })
			t.expect(sideRun.code).toBe(5)
			t.expect(has(sideRun.stdout, "src/side.lua")).toBe(true)
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			trackerfix.elsewhere(h.f, { ["src/merged.lua"] = "return 1\n" }, "a merged PR")
			local sha = fixture.git(h.f.origin, { "rev-parse", "main" })
			fs.writeFile(
				`{h.fakes}/pulls-{sha}.json`,
				`[\{"number":13,"merged_at":"2026-10-21T00:00:00Z","merge_commit_sha":"{sha}","base":\{"ref":"main"\}\}]`
			)
			t.expect(zn({ "dispatch", "z-design", "c0010", "--dry-run" }).ok).toBe(true)
			t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(0)
		end
	)
end)
