-- c0265 split: cases of heartbeat.spec (monolithic version) that belong to c0277. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../heartbeat.spec.orig. They never ran against an implementation.



	it("a discarded worktree is named with the smallest free numeric suffix", function()
		t.expect(heartbeat.nextSuffix("R0010", {})).toBe("R0010-1")
		t.expect(heartbeat.nextSuffix("R0010", { "R0010", "R0010-1" })).toBe("R0010-2")
		t.expect(heartbeat.nextSuffix("R0010", { "R0010-1", "R0010-3" })).toBe("R0010-2") -- the smallest free
		t.expect(heartbeat.nextSuffix("prep-x", { "prep-xy-1" })).toBe("prep-x-1") -- another name's suffix is not ours
	end)
