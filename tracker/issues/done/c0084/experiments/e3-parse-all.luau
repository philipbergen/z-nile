--!strict
-- E3 (c0084 prep): every spend.md in the tracker parses with the prototype ledger, and its rows sum to its totals.
-- Run from the repository root: lune run tracker/issues/c0084/experiments/e3-parse-all
local fs = require("@lune/fs")
local ledger = require("./ledger")
local process = require("@lune/process")
local files = string.split(
	process.exec("sh", { "-c", "ls tracker/issues/*/spend.md tracker/issues/*/*/spend.md 2>/dev/null" }).stdout,
	"\n"
)
local ok, bad, mismatch, rowsN = 0, 0, 0, 0
for _, f in files do
	if f ~= "" then
		local text = fs.readFile(f)
		local l, err = ledger.parse(text)
		if not l then
			bad += 1
			print("PARSE FAIL", f, err)
		else
			rowsN += #l.rows
			local t = ledger.sum(l.rows)
			local a, r, m, c =
				string.match(text, "totals: added=(%d+) removed=(%d+) minutes=([%d%.]+) commits=(%d+)")
			if
				tonumber(a) ~= t.added
				or tonumber(r) ~= t.removed
				or string.format("%.1f", tonumber(m) :: number) ~= string.format("%.1f", t.minutes)
				or tonumber(c) ~= t.records
			then
				mismatch += 1
				print("TOTALS DIFFER", f, a, r, m, c, "vs", t.added, t.removed, t.minutes, t.records)
			end
			-- round trip: render then parse gives the same rows
			local again = ledger.parse(ledger.render(l.id, l.title, l.rows)) :: any
			assert(#again.rows == #l.rows, `round trip lost rows in {f}`)
			ok += 1
		end
	end
end
print(`files parsed {ok}, failed {bad}, totals mismatches {mismatch}, rows {rowsN}`)
