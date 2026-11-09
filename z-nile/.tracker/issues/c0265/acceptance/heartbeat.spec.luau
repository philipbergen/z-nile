--!strict
-- c0265: the heartbeat's pure rules (z-nile/engine/heartbeat.luau): the ref a beat is written as, which refs are
-- beats, when a claim is stale, how parked and unknown claims settle, the order lost work is picked in, which PRs park
-- a claim, and which refs a new beat deletes. No I/O, no clock: every case passes `now`.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "active-brisk-amber-otter"
local C = "preparing-lucky-violet-heron"
local D = "preparing-mellow-badger-jolly"
local NOW = 1800000000

local function claim(id: string, stamp: string, since: number?, match: { string }?)
	return {
		since = since or NOW - 99999,
		id = id,
		state = if string.sub(stamp, 1, 6) == "active" then "active" else "preparing",
		stamp = stamp,
		match = match or { id },
	}
end
local function beat(stamp: string, epoch: number)
	return { stamp = stamp, epoch = epoch, ref = heartbeat.branch(stamp), sha = `sha-{stamp}-{epoch}` }
end
local function entry(stamp: string, epoch: number)
	return {
		ref = heartbeat.branch(stamp),
		sha = `sha-{stamp}-{epoch}`,
		subject = heartbeat.subject(stamp, epoch),
	}
end
local function kinds(vs: { heartbeat.Verdict }): { string }
	local out = {}
	for _, v in vs do
		table.insert(out, `{v.id}={v.kind}`)
	end
	return out
end

return t.spec("c0265 heartbeat rules", function(it)
	it(
		"a beat is the branch refs/heads/hb/<stamp> whose commit subject is 'hb <stamp> <epoch>'; parse reads it back",
		function()
			t.expect(heartbeat.branch(A)).toBe(`refs/heads/hb/{A}`)
			t.expect(heartbeat.subject(A, NOW)).toBe(`hb {A} {NOW}`)
			local beats, problems =
				heartbeat.parse({ entry(A, NOW), { ref = "refs/heads/main", sha = "x", subject = "m" } })
			t.expect(#problems).toBe(0)
			t.expect(#beats).toBe(1)
			t.expect(beats[1].stamp).toBe(A)
			t.expect(beats[1].epoch).toBe(NOW)
			t.expect(beats[1].ref).toBe(`refs/heads/hb/{A}`)
			t.expect(beats[1].sha).toBe(`sha-{A}-{NOW}`)
		end
	)

	it(
		"a branch under the prefix that is not a beat is a problem naming it and its cure; other branches are ignored",
		function()
			local beats, problems = heartbeat.parse({
				{ ref = "refs/heads/hb/garbage", sha = "1", subject = "just a commit" },
				{ ref = `refs/heads/hb/{A}`, sha = "2", subject = `hb {C} {NOW}` }, -- the subject names another stamp
				{ ref = `refs/heads/hb/{A}`, sha = "3", subject = `hb {A} soon` },
				{ ref = "refs/heads/prep-x", sha = "4", subject = "work" },
				{ ref = "refs/heads/hb/preparing-a-b", sha = "5", subject = "hb preparing-a-b 1" }, -- two words, not three
				{ ref = "refs/heads/hb/preparing-a-b-c-d", sha = "6", subject = "hb preparing-a-b-c-d 1" }, -- four
				{ ref = "refs/heads/hb/waiting-a-b-c", sha = "7", subject = "hb waiting-a-b-c 1" }, -- not a claim state
			})
			t.expect(#beats).toBe(0)
			t.expect(#problems).toBe(6)
			for _, p in problems do
				t.expect(string.find(p, "git push origin :refs/heads/hb/", 1, true) ~= nil).toBe(true)
			end
		end
	)

	it(
		"the interval is five minutes, the limit three beats, and a claim is stale only strictly past it",
		function()
			t.expect(heartbeat.INTERVAL).toBe(300)
			t.expect(heartbeat.STALE).toBe(900)
			local claims = { claim("f0010", A) }
			local beats = { beat(A, NOW - heartbeat.STALE) }
			t.expect(heartbeat.judge(claims, beats, NOW)[1].kind).toBe("live") -- exactly the limit is still live
			local v = heartbeat.judge(claims, beats, NOW + 1)[1]
			t.expect(v.kind).toBe("stale")
			t.expect(v.silent).toBe(heartbeat.STALE + 1)
		end
	)

	it("only the newest beat of the claim's own stamp counts", function()
		local claims = { claim("f0010", A) }
		local beats = { beat(A, NOW - 5000), beat(A, NOW - 10), beat(C, NOW - 1) }
		local v = heartbeat.judge(claims, beats, NOW)[1]
		t.expect(v.kind).toBe("live")
		t.expect(v.silent).toBe(10)
		-- a beat of an earlier claim of the same item (its old stamp) keeps nothing alive
		t.expect(heartbeat.judge(claims, { beat(C, NOW) }, NOW)[1].kind).toBe("stale")
	end)

	it(
		"a claim nobody ever beat is silent since it landed, so it turns lost on the same clock (flatline)",
		function()
			local fresh = heartbeat.judge({ claim("f0010", A, NOW - 60) }, {}, NOW)[1]
			t.expect(fresh.kind).toBe("live")
			t.expect(fresh.silent).toBe(60)
			local old = heartbeat.judge({ claim("f0010", A, NOW - heartbeat.STALE - 1) }, {}, NOW)[1]
			t.expect(old.kind).toBe("stale")
			t.expect(heartbeat.settle({ old }, {})[1].kind).toBe("lost")
		end
	)

	it("a claim with neither a beat nor a readable landing time is unknown, never lost", function()
		local v = heartbeat.judge(
			{ { id = "f0010", state = "preparing", stamp = A, match = { "f0010" } } },
			{},
			NOW
		)[1]
		t.expect(v.kind).toBe("unknown")
		t.expect(heartbeat.settle({ v }, {})[1].kind).toBe("unknown")
		-- a beat is still a sign of life for it
		local alive = heartbeat.judge(
			{ { id = "f0010", state = "preparing", stamp = A, match = { "f0010" } } },
			{ beat(A, NOW - 5) },
			NOW
		)[1]
		t.expect(alive.kind).toBe("live")
	end)

	it("a beat dated past the skew allowance is ignored, one near it reads as now", function()
		local claims = { claim("f0010", A) }
		t.expect(heartbeat.judge(claims, { beat(A, NOW + heartbeat.SKEW + 1) }, NOW)[1].kind).toBe("stale")
		local v = heartbeat.judge(claims, { beat(A, NOW + heartbeat.SKEW) }, NOW)[1]
		t.expect(v.kind).toBe("live")
		t.expect(v.silent).toBe(0)
	end)

	it("settle: a stale claim is lost only when the PR list was read and no PR parks it", function()
		local stale = heartbeat.judge(
			{ claim("c0010", A), claim("c0020", C), claim("c0030", D) },
			{ beat(A, NOW - 5000), beat(C, NOW - 5000), beat(D, NOW - 5) },
			NOW
		)
		t.expect(kinds(heartbeat.settle(stale, { c0020 = true }))).toEqual({
			"c0010=lost",
			"c0020=parked",
			"c0030=live",
		})
		-- the PR list could not be read: stale stays stale (unknown), never lost
		t.expect(kinds(heartbeat.settle(stale, nil))).toEqual({
			"c0010=stale",
			"c0020=stale",
			"c0030=live",
		})
	end)

	it("a PR parks the claims whose item id it names, in its title or its branch, whole ids only", function()
		local claims = {
			claim("c0010", A),
			claim("R0010", B, nil, { "R0010", "c0040", "c0050" }),
			claim("c0060", C),
			claim("c0070", D),
		}
		local parked = heartbeat.parkedBy({
			{ title = "tracker: prep c0010 Something", head = "prep-something" },
			{ title = "raft R0010", head = "R0010-thing" },
			{ title = "c00600 is another id", head = "x-c0060x" },
			{ title = "touches c0050", head = "other" },
		}, claims)
		t.expect(parked.c0010).toBe(true)
		t.expect(parked.R0010).toBe(true) -- named by its own id
		t.expect(parked.c0060).toBe(nil) -- c00600 and c0060x are not c0060
		t.expect(parked.c0070).toBe(nil)
		local viaMember = heartbeat.parkedBy({ { title = "x", head = "b-c0050" } }, { claims[2] })
		t.expect(viaMember.R0010).toBe(true) -- named through a member of its raft
	end)

	it("lost work is picked first, the longest silent first, and the rest keep their order", function()
		local verdicts = heartbeat.settle(
			heartbeat.judge({
				claim("c0030", A),
				claim("c0040", B),
				claim("c0020", C),
				claim("c0010", D),
				claim("c0050", "preparing-sunny-heron-lynx"),
			}, { beat(A, NOW - 100), beat(B, NOW - 5000), beat(C, NOW - 9000), beat(D, NOW - 200) }, NOW),
			{}
		)
		local ids = {}
		for _, v in heartbeat.order(verdicts) do
			table.insert(ids, v.id)
		end
		t.expect(ids).toEqual({ "c0050", "c0020", "c0040", "c0030", "c0010" }) -- c0050 never beat: silent longest
	end)

	it(
		"a beat replaces the claim's branch with a lease on the sha seen, creates it with an empty lease, never goes backwards",
		function()
			local first = heartbeat.plan(A, NOW, {}, { [A] = true }, NOW)
			t.expect(first.write)
				.toEqual({ ref = heartbeat.branch(A), subject = heartbeat.subject(A, NOW), lease = "" })
			local again = heartbeat.plan(A, NOW + 300, { beat(A, NOW) }, { [A] = true }, NOW + 300)
			t.expect(again.write).toEqual({
				ref = heartbeat.branch(A),
				subject = heartbeat.subject(A, NOW + 300),
				lease = `sha-{A}-{NOW}`,
			})
			t.expect(heartbeat.plan(A, NOW, { beat(A, NOW) }, { [A] = true }, NOW).write).toBe(nil) -- the same second
			t.expect(heartbeat.plan(A, NOW, { beat(A, NOW + 5) }, { [A] = true }, NOW).write).toBe(nil) -- another beater's, ahead
		end
	)

	it(
		"a beat also deletes the branches of long-unclaimed stamps, each with its lease, and nothing else",
		function()
			local beats = {
				beat(A, NOW - 300),
				beat(B, NOW - 300), -- another live claim
				beat(C, NOW - heartbeat.STALE - 1), -- its claim is gone, and has been for longer than the limit
				beat(D, NOW - 60), -- unclaimed here, but young: this checkout may simply not have fetched its claim yet
				beat("preparing-mild-mild-mild", NOW - 600), -- unclaimed, older than an interval but inside the limit: kept
				beat("preparing-sunny-heron-lynx", NOW - 5000), -- a LOST claim: still claimed, so its branch is kept as evidence
			}
			local plan = heartbeat.plan(
				A,
				NOW,
				beats,
				{ [A] = true, [B] = true, ["preparing-sunny-heron-lynx"] = true },
				NOW
			)
			t.expect(plan.delete)
				.toEqual({ { ref = heartbeat.branch(C), lease = `sha-{C}-{NOW - heartbeat.STALE - 1}` } })
		end
	)

	it(
		"a rejected beat learns whether it lost the claim: ended, taken over, or retries on what is there",
		function()
			local lost = heartbeat.rejected(A, C, { beat(C, NOW) })
			t.expect(lost.action).toBe("lost")
			t.expect(string.find(lost.why or "", C, 1, true) ~= nil).toBe(true) -- names the new stamp
			t.expect(heartbeat.rejected(A, nil, {}).action).toBe("lost")
			t.expect(heartbeat.rejected(A, nil, {}).why).toBe("ended")
			local retry = heartbeat.rejected(A, A, { beat(A, NOW) })
			t.expect(retry.action).toBe("retry")
			t.expect(retry.lease).toBe(`sha-{A}-{NOW}`)
			local create = heartbeat.rejected(A, A, {}) -- the claim stands, its branch is gone (pruned by mistake)
			t.expect(create.action).toBe("create")
			t.expect(create.lease).toBe("")
		end
	)

	it("a PR parks a stamp: every item holding it is parked, from a PR that names only the raft", function()
		local raft = claim("R0010", B, nil, { "R0010", "c0040" })
		local member = claim("c0040", B, nil, { "c0040" })
		local other = claim("c0070", A)
		local parked = heartbeat.parkedBy(
			{ { title = "R0010: the raft", head = "R0010-thing" } },
			{ raft, member, other }
		)
		t.expect(parked.R0010).toBe(true)
		t.expect(parked.c0040).toBe(true) -- shares the raft's stamp
		t.expect(parked.c0070).toBe(nil)
		-- a dispatcher run state under the raft's id parks the same stamp
		local viaRun = heartbeat.parkedBy({}, { raft, member }, { R0010 = true })
		t.expect(viaRun.c0040).toBe(true)
	end)

	it("the clock is ZN_NOW only inside a spec run", function()
		t.expect(heartbeat.clock({ ZN_NOW = "5" }, 100, true)).toBe(5)
		t.expect(heartbeat.clock({ ZN_NOW = "5" }, 100, false)).toBe(100)
		t.expect(heartbeat.clock({ ZN_NOW = "soon" }, 100, true)).toBe(100)
		t.expect(heartbeat.clock({}, 100, true)).toBe(100)
	end)

	it("watch beats until the claim's stamp changes or the next tick would pass the bound", function()
		t.expect(heartbeat.watch(A, A, NOW, NOW + 100, 5)).toBe("beat")
		t.expect(heartbeat.watch(A, C, NOW, NOW + 100, 5)).toBe("stop-restamped")
		t.expect(heartbeat.watch(A, nil, NOW, NOW + 100, 5)).toBe("stop-restamped") -- the claim ended
		t.expect(heartbeat.watch(A, A, NOW + 95, NOW + 100, 5)).toBe("stop-bound")
		t.expect(heartbeat.watch(A, A, NOW + 94, NOW + 100, 5)).toBe("beat")
	end)

	it("tuning settings are honoured only inside a spec run, and only as positive whole numbers", function()
		t.expect(heartbeat.setting({ ZN_BEAT_EVERY = "1" }, "ZN_BEAT_EVERY", 300, true)).toBe(1)
		t.expect(heartbeat.setting({ ZN_BEAT_EVERY = "1" }, "ZN_BEAT_EVERY", 300, false)).toBe(300)
		for _, bad in { "0", "-3", "1.5", "soon", "" } do
			t.expect(heartbeat.setting({ ZN_NET_SECONDS = bad }, "ZN_NET_SECONDS", 10, true)).toBe(10)
		end
	end)

	it(
		"a claim made at or before the heartbeat's landing that never beat is nobeat, not lost, until it beats once",
		function()
			local LANDED = NOW - 50000
			local old = claim("c0010", A, LANDED - 10) -- made before the landing
			local atLanding = claim("c0020", C, LANDED) -- the landing's own second counts as before
			local after = claim("c0030", D, LANDED + 1) -- made after: flatlined as ever
			local vs = heartbeat.judge({ old, atLanding, after }, {}, NOW, nil, LANDED)
			t.expect(kinds(vs)).toEqual({ "c0010=nobeat", "c0020=nobeat", "c0030=stale" })
			t.expect(kinds(heartbeat.settle(vs, {})))
				.toEqual({ "c0010=nobeat", "c0020=nobeat", "c0030=lost" })
			-- once it has beaten, the ordinary rules apply to it, even a stale beat
			t.expect(kinds(heartbeat.judge({ old }, { beat(A, NOW - 5000) }, NOW, nil, LANDED)))
				.toEqual({ "c0010=stale" })
			t.expect(kinds(heartbeat.judge({ old }, { beat(A, NOW - 5) }, NOW, nil, LANDED)))
				.toEqual({ "c0010=live" })
			-- no landing rule given: every beatless claim is flatlined
			t.expect(kinds(heartbeat.judge({ old }, {}, NOW, nil, nil))).toEqual({ "c0010=stale" })
			-- an unreadable landing time of the claim is unknown, as before
			local blind = heartbeat.judge(
				{ { id = "c0040", state = "preparing", stamp = B, match = { "c0040" } } },
				{},
				NOW,
				nil,
				LANDED
			)
			t.expect(kinds(blind)).toEqual({ "c0040=unknown" })
		end
	)

	it("a branch dated past the skew allowance does not stop a beat: it is replaced", function()
		local far = beat(A, NOW + heartbeat.SKEW + 1000)
		local plan = heartbeat.plan(A, NOW, { far }, { [A] = true }, NOW)
		t.expect(plan.write ~= nil).toBe(true)
		t.expect(if plan.write then plan.write.lease else "").toBe(far.sha)
		-- one inside the allowance is still "not backwards"
		t.expect(heartbeat.plan(A, NOW, { beat(A, NOW + 5) }, { [A] = true }, NOW).write).toBe(nil)
	end)

	it("a pull request parks an id only when it stands alone on both sides", function()
		local parked = heartbeat.parkedBy(
			{ { title = "xc0010", head = "ac0010" }, { title = "c0010y", head = "b" } },
			{ claim("c0010", A) }
		)
		t.expect(parked.c0010).toBe(nil)
	end)

	it(
		"the heartbeat's landing is read on main's first-parent line, newest add, not at a PR branch's commit",
		function()
			local args = heartbeat.landingArgs()
			t.expect(table.find(args, "--first-parent") ~= nil).toBe(true) -- a merge-commit PR is read at the merge
			t.expect(table.find(args, "--diff-filter=A") ~= nil).toBe(true)
			t.expect(table.find(args, "-1") ~= nil).toBe(true) -- the newest add: a revert and a re-land restart it
			t.expect(args[#args]).toBe("z-nile/engine/heartbeat.luau")
			t.expect(table.find(args, "origin/main") ~= nil).toBe(true)
		end
	)
end)
