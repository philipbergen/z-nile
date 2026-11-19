--!strict
-- f0417 AC3, AC4: c0260's idea loop runs up to five challenges, the cap rounds.luau holds; z-work's idea fact says
-- when the idea stage can run and what the person must do otherwise; and the guess-mode Confirmation line. Pure.
local idea = require("@znile/engine/idea")
local rounds = require("@znile/engine/rounds")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function doc(front: string, body: string): string
	return `---\nid: c0002\n{front}rounds: on\n---\n\n# c0002\n\n## Problem\n- p.\n\n{body}`
end

local ASK = "## Ask (verbatim)\n### Message 2026-11-18\n```\nmake it louder\n```\n\n## Interview\n### Q1\nwhich?\nA: this.\n\n"
local REV = "# Idea review NNN\n\n## Findings\n- F1: too big.\n\n## Verdict\nrevise\n"
local ASKREV = "# Idea review NNN\nRound: ask 1, interview 1, idea abc123\n\n## Findings\n- F1: ask: which board?\n\n## Verdict\nrevise\n"

return t.spec("f0417: the idea loop's cap, z-work's idea fact and the guess-mode Confirmation", function(it)
	it("the idea loop's cap is rounds.CAP.idea, five", function()
		t.expect(rounds.CAP.idea).toBe(5)
		t.expect((idea :: any).MAX_ROUNDS).toBe(rounds.CAP.idea)
	end)

	it("the idea stage can run on an unchallenged ticket with its ask, or a loop that takes its next round", function()
		local fresh = doc("capture: required\nidea: unchallenged\n", ASK)
		t.expect((idea.fact(fresh, {}))).toBe("run")
		local agent = doc("capture: required\nidea: unchallenged\n", "## Filed by (agent)\n- c0099.\n\n")
		t.expect((idea.fact(agent, {}))).toBe("run")
		local old = doc("idea: unchallenged\n", "")
		t.expect((idea.fact(old, {}))).toBe("run") -- no capture: required, so no record is needed
		local answered = doc("capture: required\nidea: challenged\n", ASK)
		t.expect((idea.fact(answered, {
			["idea-review-001.md"] = REV,
			["idea-refute-001.md"] = "# Idea refute 001\n\n- F1: revised\n",
		}))).toBe("run")
	end)

	it("an unmarked older ticket is an idea pick too: the guess run marks it", function()
		local older = "---\nid: c0003\ncapture: required\nidea: unchallenged\nstatus: new-x-y-z\n---\n\n# c0003\n\n" .. ASK
		t.expect((idea.fact(older, {}))).toBe("run")
		local before = "---\nid: c0004\nidea: unchallenged\nstatus: new-x-y-z\n---\n\n# c0004\n\n## Problem\n- p.\n"
		t.expect((idea.fact(before, {}))).toBe("run") -- captured before c0260: no record is needed
	end)

	it("the idea fact names what the person must do, every nil with its reason, and a confirmed loop is no idea pick", function()
		local norecord = doc("capture: required\nidea: unchallenged\n", "")
		local r, why = idea.fact(norecord, {})
		t.expect(r).toBe(nil)
		t.expect(has(why, "./zn idea c0002 --record")).toBe(true)
		-- c0260's own open list (no source); the ask waits until the Interview answers it
		local asking = doc("capture: required\nidea: challenged\n", ASK .. "## Open to the human\n- F1: ask: which board?\n")
		local r2, why2 = idea.fact(asking, { ["idea-review-001.md"] = ASKREV })
		t.expect(r2).toBe(nil)
		t.expect(has(why2, "idea-review-001 F1")).toBe(true)
		-- answered with --record (a second ### Q), it runs, though the open line has no Ruled line yet
		local answeredAsk = doc(
			"capture: required\nidea: challenged\n",
			(string.gsub(ASK, "A: this.\n", "A: this.\n### Q2\nwhich board?\nA: the main one.\n"))
				.. "## Open to the human\n- F1: ask: which board?\n"
		)
		t.expect((idea.fact(answeredAsk, { ["idea-review-001.md"] = ASKREV }))).toBe("run")
		-- an ended loop whose open lines are not ruled is no run and no draft: the person rules them, and the skip says which
		local endedOpen = doc("capture: required\nidea: challenged\n", ASK .. "## Open to the human\n- F1: ask: which board?\n")
		local r4, why4 = idea.fact(endedOpen, {
			["idea-review-001.md"] = ASKREV,
			["idea-review-002.md"] = "# Idea review 002\n\n## Findings\n- F1: none\n\n## Verdict\napprove\n",
		})
		t.expect(r4).toBe(nil)
		t.expect(has(why4, "F1")).toBe(true)
		t.expect(has(why4, "ready to design")).toBe(false)
		local approved = { ["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n- F1: none\n\n## Verdict\napprove\n" }
		-- an ended loop with no Confirmation is run once more, for the guess-mode Confirmation alone
		local ended = doc("capture: required\nidea: challenged\n", ASK)
		t.expect((idea.fact(ended, approved))).toBe("run")
		-- with one, it is no idea pick, and says why
		local confirmed = doc(
			"capture: required\nidea: challenged\n",
			ASK .. "## Confirmation\nUnconfirmed (guess mode, 2026-11-20) after round 1: carried by z-work; the person's ./zn approve confirms it\n\n"
		)
		local r3, why3 = idea.fact(confirmed, approved)
		t.expect(r3).toBe(nil)
		t.expect(has(why3, "ready to design")).toBe(true)
	end)

	it("the guess run marks an unmarked ticket once rounds-since is on origin, and refuses before", function()
		local unmarked = "---\nid: c0002\ncapture: required\nidea: unchallenged\nstatus: new-x-y-z\n---\n\n# c0002\n"
		local marked, err = idea.guessPrepare(unmarked, true)
		t.expect(err).toBe(nil)
		t.expect(string.find(marked or "", "\nrounds: on\n", 1, true) ~= nil).toBe(true)
		local already = idea.guessPrepare(marked :: string, true)
		t.expect(already).toBe(marked)
		local none, why = idea.guessPrepare(unmarked, false)
		t.expect(none).toBe(nil)
		t.expect(has(why, "rounds-since")).toBe(true)
	end)

	it("one claim refusal for the claim and for work next: the loop gate and the Confirmation on a born-marked issue, main's answer otherwise", function()
		local rev = { ["idea-review-001.md"] = REV, ["idea-refute-001.md"] = "# Idea refute 001\n\n- F1: revised\n" }
		local challenged = doc("idea: challenged\n", "## Open to the human\nnone\n")
		-- born marked: one answered revise round is not an ended loop
		local mid = idea.claimRefusal(challenged, rev, "c0002", true)
		t.expect(has(mid, "idea-review-002")).toBe(true)
		-- the same ticket marked only by this claim keeps main's answer: claimable
		t.expect(idea.claimRefusal(challenged, rev, "c0002", false)).toBe(nil)
		-- an ended loop on a born-marked capture still needs its Confirmation
		local approved = { ["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n- F1: none\n\n## Verdict\napprove\n" }
		local capture = doc("capture: required\nidea: challenged\n", ASK .. "## Open to the human\nnone\n")
		t.expect(has(idea.claimRefusal(capture, approved, "c0002", true), "Confirmation")).toBe(true)
		local confirmed = doc(
			"capture: required\nidea: challenged\n",
			ASK .. "## Confirmation\nUnconfirmed (guess mode, 2026-11-20) after round 1: carried by z-work; the person's ./zn approve confirms it\n\n## Open to the human\nnone\n"
		)
		t.expect(idea.claimRefusal(confirmed, approved, "c0002", true)).toBe(nil)
		-- with the refusal set, the idea fact runs the stage: z-work never repeats a draft the claim refuses
		t.expect((idea.fact(challenged, rev))).toBe("run")
	end)

	it("the audit's Confirmation rule: Confirmed always, the guess-mode line on a marked issue, done included", function()
		local guess = "Unconfirmed (guess mode, 2026-11-20) after round 3: carried by z-work; the person's ./zn approve confirms it"
		local function withConfirmation(line: string): string
			return `## Problem\n- p.\n\n## Confirmation\n{line}\n`
		end
		t.expect(idea.confirmationOk(withConfirmation(guess), true)).toBe(true)
		t.expect(idea.confirmationOk(withConfirmation(guess), false)).toBe(false)
		t.expect(idea.confirmationOk(withConfirmation('Confirmed (Ada, 2026-11-20) after round 3: "yes"'), false)).toBe(true)
		t.expect(idea.confirmationOk(withConfirmation("Unconfirmed (unattended, 2026-11-20) after round 3: x"), true))
			.toBe(false)
	end)

	it("the guess-mode Confirmation names the round and says the person's approval confirms it", function()
		t.expect(idea.guessLine(3, "2026-11-20")).toBe(
			"Unconfirmed (guess mode, 2026-11-20) after round 3: carried by z-work; the person's ./zn approve confirms it"
		)
	end)
end)
