--!strict
-- The fail-closed step of a scanning loop (zz-arch skill, lesson scanning-loops-advance). A loop that takes its next
-- position from a helper or an expression writes `i = scan.advance(i, next)`, so a pass that would leave the position
-- where it was, or move it back, raises instead of spinning forever. A step by a literal at the loop's top level
-- (`i += 1`) needs no call: tests/lib/loops.luau accepts both.
local scan = {}

-- `to` when it is past `from`; otherwise an error naming both, raised at the caller's line. A NaN is not past anything.
function scan.advance(from: number, to: number): number
	if not (to > from) then
		error(`scanner did not advance: from {from} to {to}`, 2)
	end
	return to
end

return scan
