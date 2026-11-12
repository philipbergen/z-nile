-- c0265 split: cases of heartbeat.spec (monolithic version) that belong to c0275. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../heartbeat.spec.orig. They never ran against an implementation.



	it(
		"the lease is the sha this checkout last wrote when it remembers one, else the sha seen, else empty",
		function()
			local seen = { beat(A, NOW) }
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, seen, { [A] = true }, NOW + 300, "mine")))
				.toBe("mine")
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, {}, { [A] = true }, NOW + 300, "mine")))
				.toBe("mine") -- branch gone: rejected
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, seen, { [A] = true }, NOW + 300, nil)))
				.toBe(`sha-{A}-{NOW}`)
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, {}, { [A] = true }, NOW + 300, nil))).toBe("")
		end
	)
