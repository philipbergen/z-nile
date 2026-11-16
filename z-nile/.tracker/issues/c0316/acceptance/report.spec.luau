--!strict
-- c0316 AC7: `./zn metrics` prints the escapes table (made in which stage, found at which) before the Rework lines,
-- with the target of none after a merge. A tracker fixture under .cache/c0316-report (tests/lib/trackerfix) holds
-- four done issues carrying a known set of escapes; metrics only reads.
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- the position of a whole line of the output, or nil
local function lineAt(text: string, line: string): number?
	local at = string.find("\n" .. text .. "\n", "\n" .. line .. "\n", 1, true)
	return if at then at else nil
end

-- a review with one finding per (id, stage) pair: the stage is the `Stage:` line (nil leaves it out)
local function review(findings: { { string } }): string
	local out = "# Review 001\n\n"
	for _, f in findings do
		out ..= `### {f[1]} [low] a claim\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\n` .. `Recommendation: d\nStage: {f[2]}\n\n`
	end
	return out .. "Verdict: approve\n"
end

local function doc(id: string, extra: string): string
	return (
		string.gsub(trackerfix.stub(id, id, "new-a-b-c"), "depends_on: %[%]\n", `depends_on: []\n{extra}`)
	)
end

local function hex(c: string): string
	return string.rep(c, 64)
end

local DONE = "pickman/.tracker/issues/done"

return t.spec("c0316 metrics prints the escapes table before the Rework lines", function(it)
	it(
		"AC7: metrics prints the escapes table before the Rework lines, with the counts of a fixture and the after-the-merge line",
		function()
			local f = trackerfix.new("c0316-report", {
				-- c0010: a design review that finds a hole in the idea (an escape found at design) and one in the
				-- design itself (the same stage: no escape). Both are harvested.
				[`{DONE}/c0010/c0010.md`] = doc("c0010", ""),
				[`{DONE}/c0010/design-review-001.md`] = review({ { "F1", "idea" }, { "F2", "design" } }),
				[`{DONE}/c0010/harvest.md`] = "# Harvest: c0010\n\n- design-review-001 F1: one-off: the idea left it open\n"
					.. "- design-review-001 F2: one-off: a typo\n",
				-- c0020: a code review that finds a hole in the design (found at implementation) and one in the code
				-- (the same stage: no escape). Both are harvested.
				[`{DONE}/c0020/c0020.md`] = doc("c0020", ""),
				[`{DONE}/c0020/review-001.md`] = review({ { "F1", "design" }, { "F2", "implementation" } }),
				[`{DONE}/c0020/harvest.md`] = "# Harvest: c0020\n\n- review-001 F1: one-off: the design left it open\n"
					.. "- review-001 F2: one-off: a typo\n",
				-- c0030: corrects c0010 after its merge; its entry says the mistake was made in implementation
				[`{DONE}/c0030/c0030.md`] = doc("c0030", "reworks: c0010\n"),
				[`{DONE}/c0030/harvest.md`] = "# Harvest: c0030\n\n- escape rework 1 (implementation): one-off: a missed case\n",
				-- c0040: approved twice (a redesign after approval) and no entry for it: not harvested yet
				[`{DONE}/c0040/c0040.md`] = doc("c0040", ""),
				[`{DONE}/c0040/approval.md`] = "# approval\nwhen\twho\thash\tparts\n"
					.. `2026-11-01T10:00:00Z\tann\t{hex("a")}\tdesign={hex("a")}\n`
					.. `2026-11-02T10:00:00Z\tann\t{hex("b")}\tdesign={hex("b")}\n`,
			})
			local r = trackerfix.tr(f, f.main, { "metrics" })
			if not r.ok then
				error(`./zn metrics failed ({r.code}): {r.stderr}{r.stdout}`)
			end
			local out = r.stdout
			local head = lineAt(
				out,
				"Escapes: a mistake found at a later stage than the one that made it. Target: none after a merge."
			)
			t.expect(head ~= nil).toBe(true)
			local header =
				lineAt(out, "| made in | found at design | found at implementation | found after the merge |")
			t.expect(header ~= nil).toBe(true)
			t.expect(lineAt(out, "|---|---|---|---|")).toBeTruthy()
			-- idea: the c0010 design-review F1; design: the c0020 review F1; implementation: the c0030 rework;
			-- not harvested: the c0040 redesign, found at implementation. The same-stage findings count nowhere.
			local rows = {
				lineAt(out, "| idea | 1 | 0 | 0 |"),
				lineAt(out, "| design | - | 1 | 0 |"),
				lineAt(out, "| implementation | - | - | 1 |"),
				lineAt(out, "| not harvested | 0 | 1 | 0 |"),
			}
			for i = 1, 4 do
				t.expect(rows[i] ~= nil).toBe(true)
			end
			local after = lineAt(out, "After the merge: 1 (target 0).")
			t.expect(after ~= nil).toBe(true)
			-- in the order of the design: heading, table, after-the-merge line, and all before the Rework lines
			local rework = string.find("\n" .. out, "\nRework = ", 1, true)
			t.expect(rework ~= nil).toBe(true)
			if head and header and after and rework then
				t.expect(head < header).toBe(true)
				t.expect(header < (rows[1] :: number)).toBe(true)
				t.expect((rows[1] :: number) < (rows[2] :: number)).toBe(true)
				t.expect((rows[2] :: number) < (rows[3] :: number)).toBe(true)
				t.expect((rows[3] :: number) < (rows[4] :: number)).toBe(true)
				t.expect((rows[4] :: number) < after).toBe(true)
				t.expect(after < rework).toBe(true)
			end
			-- the report says the 20% figure is history (the Rework block's first line, c0316.md section 5)
			t.expect(has(out, "The 20% target is history: the target is no escape after a merge.")).toBe(true)
		end
	)
end)
