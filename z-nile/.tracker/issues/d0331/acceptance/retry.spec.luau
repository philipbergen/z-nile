--!strict
-- d0331: what done does when its push of the binding commit is rejected, as a pure decision.
local stack = require("@znile/engine/stack")
local t = require("@tests/lib/t")

return t.spec("d0331 done's answer to a rejected push", function(it)
	it("AC6: main moved and an attempt is left: again; AC7: none left: moved", function()
		t.expect(stack.DONE_ATTEMPTS).toBe(9)
		t.expect(stack.doneRetry(true, 1, true)).toBe("again")
		t.expect(stack.doneRetry(true, 8, true)).toBe("again")
		t.expect(stack.doneRetry(true, 9, true)).toBe("moved")
	end)

	it(
		"AC7: a push rejected for another reason is not retried, and one whose pull request base was not put back is lost, at any attempt",
		function()
			t.expect(stack.doneRetry(false, 1, true)).toBe("failed")
			t.expect(stack.doneRetry(false, 9, true)).toBe("failed")
			t.expect(stack.doneRetry(true, 1, false)).toBe("lost")
			t.expect(stack.doneRetry(true, 9, false)).toBe("lost")
			t.expect(stack.doneRetry(false, 1, false)).toBe("failed")
		end
	)
end)
