--!strict
-- f0464 AC1 (the decision): `lightready.check` is the one decision whether `./zn ready <issue>` readies a
-- prepared ticket in no raft alone, in a single raft it makes in its claim commit. It readies an easy, normal or risky
-- ticket whose depends_on have landed (or are delivered by the raft `--on` names, taken as done), and calls the raft
-- light only when light.luau accepts the ticket. Under ./zn dispatch every member needs an approval that holds.
-- `lightready.claimMessage` is the claim commit's message: `Lands: approved` outside the dispatcher, `On: <R>` for
-- --on, `Light: true` only for a light raft. Pure: a tree snapshot (paths and a reader) in, an answer out.
local lightready = require("@znile/engine/lightready")
local t = require("@tests/lib/t")

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: alpha" lune run tests/run -- pickman/tests/unit/alpha.spec.luau\nfinish\n'
local APPROVED = "# Design review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

type Opts = {
	risk: string?,
	deps: string?,
	guard: string?,
	status: string?,
	raft: string?,
	design: string?,
	note: boolean?,
	noRaftLine: boolean?,
}

local function doc(id: string, o: Opts): string
	local lines = {
		"---",
		`id: {id}`,
		"type: chore",
		`title: {id} module`,
		`slug: {id}`,
		if o.noRaftLine then "tributary:" else `raft: {o.raft or ""}`,
		`depends_on: [{o.deps or ""}]`,
		"emergent: false",
		`design: {o.design or "ready"}`,
		"created: 2026-11-28",
		`status: {o.status or PREPARED}`,
	}
	if o.risk then
		table.insert(lines, `risk: {o.risk}`)
	end
	for _, line in
		{
			"---",
			"",
			`# {id}: module`,
			"",
			"## Problem",
			"Alpha value is not computed.",
			"",
			"## Solution",
			"Add `pickman/src/alpha.luau` returning the alpha table.",
			"",
			"## Design",
			"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
			"",
		}
	do
		table.insert(lines, line)
	end
	if o.note ~= false then
		for _, line in
			{
				"### Short note",
				"- Problem: alpha is not computed",
				"- Change: export the alpha table",
				"- Files: `pickman/src/alpha.luau`",
				"- Test: `pickman/tests/unit/alpha.spec.luau`",
				"- Risk: none",
				"",
			}
		do
			table.insert(lines, line)
		end
	end
	for _, line in
		{
			"## Regression guard",
			o.guard or "Overrides: none",
			"",
			"## Acceptance criteria",
			"- AC1: alpha",
			"",
		}
	do
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

-- A snapshot of origin/main: each ticket's document and check.sh (and a design review unless `bare`), plus extra files.
type Ticket = { id: string, o: Opts, reviewed: boolean?, where: string? }
local function snapshot(tickets: { Ticket }, extra: { [string]: string }?): ({ string }, (string) -> string?)
	local files: { [string]: string } = {}
	for _, tk in tickets do
		local dir = if tk.where then `{ROOT}/issues/{tk.where}/{tk.id}` else `{ROOT}/issues/{tk.id}`
		files[`{dir}/{tk.id}.md`] = doc(tk.id, tk.o)
		files[`{dir}/check.sh`] = CHECK
		if tk.reviewed ~= false then
			files[`{dir}/design-review-001.md`] = APPROVED
		end
	end
	for p, text in (extra or {}) :: { [string]: string } do
		files[p] = text
	end
	local paths: { string } = {}
	for p in files do
		table.insert(paths, p)
	end
	table.sort(paths)
	return paths, function(p: string): string?
		return files[p]
	end
end

local function check(tickets: { Ticket }, id: string, opts: lightready.Opts?, extra: { [string]: string }?)
	local paths, read = snapshot(tickets, extra)
	return lightready.check(id, paths, read, opts)
end

return t.spec("f0464 ready readies a ticket in no raft alone", function(it)
	it(
		"AC1: a prepared normal or risky ticket in no raft whose depends_on landed is readied, not light",
		function()
			for _, risk in { "normal", "risky" } do
				local got = check({ { id = "c0010", o = { risk = risk, note = false } } }, "c0010")
				t.expect(got.why).toBe(nil)
				t.expect(got.light).toBe(false)
				t.expect(got.lightWhy ~= nil).toBe(true)
			end
			-- no risk: line is normal
			local plain = check({ { id = "c0010", o = { note = false } } }, "c0010")
			t.expect(plain.why).toBe(nil)
			t.expect(plain.light).toBe(false)
			-- a landed dependency is met
			local landed = check({
				{ id = "c0010", o = { risk = "normal", deps = "c0009", note = false } },
				{ id = "c0009", o = { status = "done-quiet-copper-falcon" }, where = "done" },
			}, "c0010")
			t.expect(landed.why).toBe(nil)
		end
	)

	it("AC1: light stays limited to what light.luau accepts", function()
		-- an easy ticket with the short note and a plain Overrides: none is light (f0420)
		local easy = check({ { id = "c0011", o = { risk = "easy" }, reviewed = false } }, "c0011")
		t.expect(easy.why).toBe(nil)
		t.expect(easy.light).toBe(true)
		t.expect(easy.lightWhy).toBe(nil)
		-- an easy ticket with an Overrides entry and a design review is readied, but not light
		local entry = check({
			{
				id = "c0012",
				o = {
					risk = "easy",
					guard = "Overrides:\n- `z-nile/tests/" .. "acceptance/d0415/dispatch.spec.luau`",
				},
			},
		}, "c0012")
		t.expect(entry.why).toBe(nil)
		t.expect(entry.light).toBe(false)
		t.expect(has(entry.lightWhy, "Overrides")).toBe(true)
		-- a normal ticket is never light, even with a short note
		local normal = check({ { id = "c0013", o = { risk = "normal" } } }, "c0013")
		t.expect(normal.why).toBe(nil)
		t.expect(normal.light).toBe(false)
	end)

	it("AC1: what ready refuses stays refused, for every level", function()
		for _, risk in { "easy", "normal", "risky" } do
			local unmet = check({
				{ id = "c0020", o = { risk = risk, deps = "c0021" } },
				{ id = "c0021", o = {} },
			}, "c0020")
			t.expect(has(unmet.why, "c0020 depends on c0021")).toBe(true)
			local draft = check({ { id = "c0022", o = { risk = risk, design = "draft" } } }, "c0022")
			t.expect(draft.why ~= nil).toBe(true)
			local newer =
				check({ { id = "c0023", o = { risk = risk, status = "new-amber-otter-marble" } } }, "c0023")
			t.expect(has(newer.why, "not prepared in the backlog")).toBe(true)
			local inRaft = check({ { id = "c0024", o = { risk = risk, raft = "R0001" } } }, "c0024")
			t.expect(has(inRaft.why, "already belongs to R0001")).toBe(true)
		end
		-- f0464 review 001 F3: light.reason refused a document with no raft: line in front of readycheck; now this does
		local noLine =
			check({ { id = "c0029", o = { risk = "normal", note = false, noRaftLine = true } } }, "c0029")
		t.expect(has(noLine.why, "c0029: its document has no raft: line: add an empty one")).toBe(true)
		local bad = check({ { id = "c0025", o = { risk = "hard" } } }, "c0025")
		t.expect(has(bad.why, "easy, normal or risky")).toBe(true)
		-- listed by a raft that is not done: z-raft is grouping it
		local listed = check({ { id = "c0026", o = { risk = "normal" } } }, "c0026", nil, {
			[`{ROOT}/rafts/R0007/R0007.md`] = "---\nid: R0007\ntype: chore\nissues: [c0026]\nstatus: "
				.. PREPARED
				.. "\n---\n",
		})
		t.expect(has(listed.why, "c0026 is listed by R0007")).toBe(true)
		t.expect(listed.groupedBy).toBe("R0007")
	end)

	it("AC1: under ./zn dispatch every member needs an approval that holds", function()
		local tickets: { Ticket } = { { id = "c0030", o = { risk = "normal", note = false } } }
		t.expect(check(tickets, "c0030", { dispatched = false }).why).toBe(nil)
		local d = check(tickets, "c0030", { dispatched = true })
		t.expect(has(d.why, "c0030 has no approval")).toBe(true)
		-- the light ticket too: the dispatcher's rule is not the light path's
		local easy: { Ticket } = { { id = "c0031", o = { risk = "easy" }, reviewed = false } }
		t.expect(has(check(easy, "c0031", { dispatched = true }).why, "c0031 has no approval")).toBe(true)
	end)

	it("AC1: --on takes the base raft's members as done, and a ticket built on it is never light", function()
		local tickets: { Ticket } = {
			{ id = "c0040", o = { risk = "easy", deps = "c0041" } },
			{ id = "c0041", o = { status = "active-quiet-copper-falcon", raft = "R0041" }, where = "active" },
			{ id = "c0042", o = { risk = "normal", deps = "c0041, c0043", note = false } },
			{ id = "c0043", o = {} },
		}
		t.expect(has(check(tickets, "c0040").why, "c0040 depends on c0041")).toBe(true)
		local on = check(tickets, "c0040", { onMembers = { "c0041" } })
		t.expect(on.why).toBe(nil)
		t.expect(on.light).toBe(false)
		-- a dependency the base does not deliver still refuses
		t.expect(has(check(tickets, "c0042", { onMembers = { "c0041" } }).why, "c0042 depends on c0043"))
			.toBe(true)
	end)

	it("AC1: the claim commit's message carries the trailers for how it was readied", function()
		t.expect(lightready.claimMessage("R0050", "c0010", { dispatched = false, light = false }))
			.toBe("tracker: ready R0050 c0010\n\nLands: approved")
		t.expect(lightready.claimMessage("R0050", "c0010", { dispatched = false, light = true }))
			.toBe("tracker: ready R0050 c0010\n\nLands: approved\nLight: true")
		t.expect(
			lightready.claimMessage("R0050", "c0010", { dispatched = false, on = "R0041", light = false })
		)
			.toBe("tracker: ready R0050 c0010\n\nLands: approved\nOn: R0041")
		t.expect(lightready.claimMessage("R0050", "c0010", { dispatched = true, light = false }))
			.toBe("tracker: ready R0050 c0010")
		t.expect(lightready.claimMessage("R0050", "c0010", { dispatched = true, light = true }))
			.toBe("tracker: ready R0050 c0010\n\nLight: true")
	end)
end)
