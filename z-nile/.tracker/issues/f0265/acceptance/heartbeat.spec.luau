--!strict
-- f0265: the heartbeat's pure rules (z-nile/engine/heartbeat.luau): the ref a beat is written as, which refs are
-- beats, when a claim is lost, the order lost work is picked in, and which refs a new beat deletes. No I/O, no clock:
-- every case passes `now`.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "active-brisk-amber-otter"
local C = "preparing-lucky-violet-heron"
local NOW = 1800000000

local function claim(id: string, stamp: string, since: number)
	return {
		id = id,
		state = if string.sub(stamp, 1, 6) == "active" then "active" else "preparing",
		stamp = stamp,
		since = since,
	}
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
		"the interval is five minutes and a claim is lost only after strictly more than the stale limit",
		function()
			t.expect(heartbeat.INTERVAL).toBe(300)
			local stale = heartbeat.STALE
			t.expect(stale > heartbeat.INTERVAL).toBe(true) -- at least one missed beat is forgiven
			local claims = { claim("f0010", A, NOW - 99999) }
			local beats = { { stamp = A, epoch = NOW - stale, ref = heartbeat.refName(A, NOW - stale) } }
			t.expect(heartbeat.judge(claims, beats, NOW)[1].lost).toBe(false) -- exactly the limit is still live
			t.expect(heartbeat.judge(claims, beats, NOW + 1)[1].lost).toBe(true)
			t.expect(heartbeat.judge(claims, beats, NOW + 1)[1].silent).toBe(stale + 1)
		end
	)

	it("only the newest beat of the claim's own stamp counts", function()
		local claims = { claim("f0010", A, NOW - 99999) }
		local beats = {
			{ stamp = A, epoch = NOW - 5000, ref = heartbeat.refName(A, NOW - 5000) },
			{ stamp = A, epoch = NOW - 10, ref = heartbeat.refName(A, NOW - 10) },
			{ stamp = C, epoch = NOW - 1, ref = heartbeat.refName(C, NOW - 1) }, -- another claim's beat
		}
		local v = heartbeat.judge(claims, beats, NOW)[1]
		t.expect(v.lost).toBe(false)
		t.expect(v.silent).toBe(10)
		-- a beat of an earlier claim of the same item (its old stamp) keeps nothing alive
		local old = { { stamp = C, epoch = NOW, ref = heartbeat.refName(C, NOW) } }
		t.expect(heartbeat.judge(claims, old, NOW)[1].lost).toBe(true)
	end)

	it("a claim nobody ever beat is silent since it landed, so it turns lost on the same clock", function()
		local fresh = heartbeat.judge({ claim("f0010", A, NOW - 60) }, {}, NOW)[1]
		t.expect(fresh.lost).toBe(false)
		t.expect(fresh.silent).toBe(60)
		local old = heartbeat.judge({ claim("f0010", A, NOW - heartbeat.STALE - 1) }, {}, NOW)[1]
		t.expect(old.lost).toBe(true)
	end)

	it("a beat dated past the skew allowance is ignored, not trusted", function()
		local claims = { claim("f0010", A, NOW - 99999) }
		local beats = { { stamp = A, epoch = NOW + heartbeat.SKEW + 1, ref = "x" } }
		t.expect(heartbeat.judge(claims, beats, NOW)[1].lost).toBe(true)
		local near = { { stamp = A, epoch = NOW + heartbeat.SKEW, ref = "x" } }
		local v = heartbeat.judge(claims, near, NOW)[1]
		t.expect(v.lost).toBe(false)
		t.expect(v.silent).toBe(0) -- a slightly future beat reads as now, never negative
	end)

	it("lost work is picked first, the longest silent first, and the rest keep their order", function()
		local verdicts = heartbeat.judge({
			claim("c0030", A, NOW - 100),
			claim("c0040", B, NOW - 5000),
			claim("c0020", C, NOW - 9000),
			claim("c0010", "preparing-mellow-badger-jolly", NOW - 200),
		}, {}, NOW)
		local ids = {}
		for _, v in heartbeat.order(verdicts) do
			table.insert(ids, v.id)
		end
		t.expect(ids).toEqual({ "c0020", "c0040", "c0030", "c0010" })
	end)

	it(
		"a new beat deletes the older beats of its stamp and of stamps no claim holds, and nothing else",
		function()
			local beats = {
				{ stamp = A, epoch = NOW - 600, ref = heartbeat.refName(A, NOW - 600) },
				{ stamp = A, epoch = NOW - 300, ref = heartbeat.refName(A, NOW - 300) },
				{ stamp = B, epoch = NOW - 300, ref = heartbeat.refName(B, NOW - 300) }, -- another live claim
				{ stamp = C, epoch = NOW - 300, ref = heartbeat.refName(C, NOW - 300) }, -- its claim is gone
			}
			local plan = heartbeat.plan(A, NOW, beats, { [A] = true, [B] = true })
			t.expect(plan.write).toBe(heartbeat.refName(A, NOW))
			local want = {
				heartbeat.refName(A, NOW - 600),
				heartbeat.refName(A, NOW - 300),
				heartbeat.refName(C, NOW - 300),
			}
			table.sort(plan.delete)
			table.sort(want)
			t.expect(plan.delete).toEqual(want)
		end
	)

	it(
		"a beat at the same second as one already there writes nothing, and a newer beat is never deleted",
		function()
			local beats = {
				{ stamp = A, epoch = NOW, ref = heartbeat.refName(A, NOW) },
				{ stamp = A, epoch = NOW + 5, ref = heartbeat.refName(A, NOW + 5) }, -- another beater's, a little ahead
			}
			local plan = heartbeat.plan(A, NOW, beats, { [A] = true })
			t.expect(plan.write).toBe(nil)
			t.expect(plan.delete).toEqual({})
			local ahead = heartbeat.plan(A, NOW + 1, beats, { [A] = true })
			t.expect(ahead.write).toBe(heartbeat.refName(A, NOW + 1))
			t.expect(ahead.delete).toEqual({ heartbeat.refName(A, NOW) })
		end
	)
end)
