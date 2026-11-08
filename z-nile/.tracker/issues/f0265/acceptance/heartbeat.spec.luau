--!strict
-- f0265: the heartbeat's pure rules (z-nile/engine/heartbeat.luau): the ref a beat is written as, which refs are
-- beats, when a claim is stale, how parked and unknown claims settle, the order lost work is picked in, which PRs park
-- a claim, and which refs a new beat deletes. No I/O, no clock: every case passes `now`.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "active-brisk-amber-otter"
local C = "preparing-lucky-violet-heron"
local D = "preparing-mellow-badger-jolly"
local NOW = 1800000000

local function claim(id: string, stamp: string, match: { string }?)
	return {
		id = id,
		state = if string.sub(stamp, 1, 6) == "active" then "active" else "preparing",
		stamp = stamp,
		match = match or { id },
	}
end
local function beat(stamp: string, epoch: number)
	return { stamp = stamp, epoch = epoch, ref = heartbeat.refName(stamp, epoch) }
end
local function kinds(vs: { heartbeat.Verdict }): { string }
	local out = {}
	for _, v in vs do
		table.insert(out, `{v.id}={v.kind}`)
	end
	return out
end

return t.spec("f0265 heartbeat rules", function(it)
	it("a beat is the ref refs/zn/hb/<stamp>/<epoch>, and parse reads it back", function()
		local name = heartbeat.refName(A, NOW)
		t.expect(name).toBe(`refs/zn/hb/{A}/{NOW}`)
		local beats, problems = heartbeat.parse({ name, "refs/heads/main" })
		t.expect(#problems).toBe(0)
		t.expect(#beats).toBe(1)
		t.expect(beats[1].stamp).toBe(A)
		t.expect(beats[1].epoch).toBe(NOW)
		t.expect(beats[1].ref).toBe(name)
	end)

	it("a ref under the prefix that is not a beat is a problem naming it; other refs are ignored", function()
		local beats, problems = heartbeat.parse({
			`refs/zn/hb/{A}/soon`,
			"refs/zn/hb/new/1800000000",
			`refs/zn/hb/{A}/{NOW}/extra`,
			"refs/zn/other/x",
			"refs/tags/v1",
		})
		t.expect(#beats).toBe(0)
		t.expect(#problems).toBe(3)
		for _, p in problems do
			t.expect(string.find(p, "refs/zn/hb/", 1, true) ~= nil).toBe(true)
		end
	end)

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
		-- a beat of an earlier claim of the same item (its old stamp) keeps nothing alive, and proves nothing either
		t.expect(heartbeat.judge(claims, { beat(C, NOW) }, NOW)[1].kind).toBe("unbeaten")
	end)

	it("a claim that never had a beat is unbeaten, never stale, however old", function()
		local v = heartbeat.judge({ claim("f0010", A) }, {}, NOW + 10 * heartbeat.STALE)[1]
		t.expect(v.kind).toBe("unbeaten")
		t.expect(v.silent).toBe(nil)
		t.expect(heartbeat.settle({ v }, {})[1].kind).toBe("unbeaten") -- settling does not turn it lost
	end)

	it("a beat dated past the skew allowance is ignored, one near it reads as now", function()
		local claims = { claim("f0010", A) }
		t.expect(heartbeat.judge(claims, { beat(A, NOW + heartbeat.SKEW + 1) }, NOW)[1].kind).toBe("unbeaten")
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
			claim("R0010", B, { "R0010", "c0040", "c0050" }),
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
		t.expect(ids).toEqual({ "c0020", "c0040", "c0030", "c0010", "c0050" })
	end)

	it("a new beat deletes the older beats of its stamp and long-unclaimed ones, and nothing else", function()
		local beats = {
			beat(A, NOW - 600),
			beat(A, NOW - 300),
			beat(B, NOW - 300), -- another live claim
			beat(C, NOW - heartbeat.STALE - 1), -- its claim is gone, and has been for longer than the limit
			beat(D, NOW - 60), -- unclaimed here, but young: this checkout may simply not have fetched its claim yet
		}
		local plan = heartbeat.plan(A, NOW, beats, { [A] = true, [B] = true }, NOW)
		t.expect(plan.write).toBe(heartbeat.refName(A, NOW))
		local want = {
			heartbeat.refName(A, NOW - 600),
			heartbeat.refName(A, NOW - 300),
			heartbeat.refName(C, NOW - heartbeat.STALE - 1),
		}
		table.sort(plan.delete)
		table.sort(want)
		t.expect(plan.delete).toEqual(want)
	end)

	it(
		"a beat at the same second as one already there writes nothing, and a newer beat is never deleted",
		function()
			local beats = { beat(A, NOW), beat(A, NOW + 5) }
			local plan = heartbeat.plan(A, NOW, beats, { [A] = true }, NOW)
			t.expect(plan.write).toBe(nil)
			t.expect(plan.delete).toEqual({})
			local ahead = heartbeat.plan(A, NOW + 1, beats, { [A] = true }, NOW + 1)
			t.expect(ahead.write).toBe(heartbeat.refName(A, NOW + 1))
			t.expect(ahead.delete).toEqual({ heartbeat.refName(A, NOW) })
		end
	)
end)
