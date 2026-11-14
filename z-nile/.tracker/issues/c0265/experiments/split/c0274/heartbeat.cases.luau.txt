-- c0265 split: cases of heartbeat.spec (monolithic version) that belong to c0274. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../heartbeat.spec.orig. They never ran against an implementation.



	it(
		"a takeover creates the taker's branch and deletes the old owner's with a lease, in one plan",
		function()
			local plan = heartbeat.takeoverPlan(A, C, NOW, { beat(A, NOW - 2000), beat(B, NOW - 5) })
			t.expect(plan.write)
				.toEqual({ ref = heartbeat.branch(C), subject = heartbeat.subject(C, NOW), lease = "" })
			t.expect(plan.delete).toEqual({ { ref = heartbeat.branch(A), lease = `sha-{A}-{NOW - 2000}` } })
			t.expect(heartbeat.takeoverPlan(A, C, NOW, {}).delete).toEqual({}) -- an old owner that never beat has no branch
		end
	)

	it("a takeover needs an explicit lost verdict judged for the stamp origin still holds", function()
		t.expect(heartbeat.canTakeOver("lost", A, A)).toBe(true)
		t.expect(heartbeat.canTakeOver("lost", A, C)).toBe(false) -- restamped since the verdict
		for _, kind in { "live", "stale", "parked" } do
			t.expect(heartbeat.canTakeOver(kind, A, A)).toBe(false)
		end
	end)
