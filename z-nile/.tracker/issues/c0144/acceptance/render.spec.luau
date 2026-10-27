--!strict
-- c0144 AC1: each command's look (z-nile/engine/look.luau), pure: what it adds to the plain lines (groups, order,
-- columns, glyphs, bars, colors, links) and that any line it does not recognise passes through unchanged, so a later
-- change to a command's text loses no fact (the renderers read only the lines their own command printed).
local look = require("@znile/engine/look")
local t = require("@tests/lib/t")
local term = require("@znile/engine/term")

local M: term.Mode = { rich = true, color = true, links = true, unicode = true, width = 100 }

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function plain(lines: { string }): { string }
	local out: { string } = {}
	for _, l in lines do
		table.insert(out, term.strip(l))
	end
	return out
end

local function row(id: string, state: string, project: string, extra: { [string]: any }?): look.StatusRow
	local r: look.StatusRow = {
		id = id,
		state = state,
		kind = if string.sub(id, 1, 1) == "R" then "chore" else term.kindOf(id),
		title = `title of {id}`,
		raft = "",
		claim = "",
		project = project,
		url = `file:///x/{id}.md`,
	}
	for k, v in (extra or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

return t.spec("c0144 each command's look", function(it)
	it(
		"status orders states active, preparing, prepared, new, shows any other state last, and counts them all",
		function()
			local out = plain(look.status(M, {
				row("f0001", "new", "pickman"),
				row("d0002", "prepared", "pickman"),
				row("c0003", "preparing", "pickman"),
				row("R0004", "active", "pickman", { pr = "https://github.com/o/r/pulls?q=x" }),
				row("c0005", "waiting", "pickman"),
				row("c0006", "new", "z-nile"),
			}))
			local text = table.concat(out, "\n")
			local order = {}
			for _, h in
				{ "ACTIVE (1)", "PREPARING (1)", "PREPARED (1)", "NEW (1)", "c0005", "z-nile", "NEW (1)" }
			do
				table.insert(
					order,
					(string.find(text, h, if #order > 0 then order[#order] else 1, true)) or 0
				)
			end
			for i = 2, #order do
				t.expect({ i = i, after = order[i] > order[i - 1] }).toEqual({ i = i, after = true })
			end
			t.expect(out[#out]).toBe("6 items: 1 active · 1 preparing · 1 prepared · 2 new · 1 waiting")
		end
	)

	it(
		"status links an active raft's id and its members' raft cells to the pull request, other ids to their files",
		function()
			local out = table.concat(
				look.status(M, {
					row("R0004", "active", "p", { pr = "https://pr.example/R0004" }),
					row("c0007", "active", "p", { raft = "R0004" }),
					row("c0008", "new", "p"),
				}),
				"\n"
			)
			local _, prs = string.gsub(out, "\27%]8;;https://pr%.example/R0004\27\\", "")
			t.expect(prs).toBe(2)
			t.expect(has(out, "\27]8;;file:///x/c0008.md\27\\")).toBe(true)
		end
	)

	it("list paints each state, done and retired dim, and links ids", function()
		local out = look.list(M, {
			{
				id = "R0001",
				state = "done",
				kind = "chore",
				raft = "",
				title = "Old",
				url = "file:///x/R0001.md",
			},
			{ id = "R0002", state = "retired", kind = "chore", raft = "", title = "Gone" },
			{ id = "f0003", state = "backlog", kind = "feature", raft = "R0009", title = "New thing" },
		})
		t.expect(has(out[1], "\27[2mdone\27[0m")).toBe(true)
		t.expect(has(out[2], "\27[2mretired\27[0m")).toBe(true)
		t.expect(has(out[1], "\27]8;;file:///x/R0001.md")).toBe(true)
		t.expect(plain(out)[3]).toBe("f0003  backlog  feature  R0009  New thing")
	end)

	it("audit marks each problem by severity and colors the summary by its counts", function()
		local out = look.audit(M, {
			"error dead-raft z-nile/.tracker/issues/c0001: raft R0009 is missing",
			"warning orphan-raft z-nile/.tracker/rafts/R0002: no member",
			"something the audit never printed",
		}, "audit: 1 errors, 1 warnings")
		t.expect(out[1]).toBe("\27[31;1m✖ error\27[0m  \27[1mdead-raft\27[0m")
		t.expect(has(out[3], "▲ warning")).toBe(true)
		t.expect(out[5]).toBe("something the audit never printed")
		t.expect(has(out[6], "\27[31;1m1 errors\27[0m")).toBe(true)
		local clean = look.audit(M, {}, "audit: 0 errors, 0 warnings")
		t.expect(clean[1]).toBe("\27[1maudit:\27[0m \27[32m0 errors\27[0m, \27[32m0 warnings\27[0m")
	end)

	it("workstreams puts each wave on one line in order, parallel yes green and no yellow", function()
		local out = plain(
			look.workstreams(
				M,
				"raft R0001: 3 issues\nc0003 wave 2\nc0001 wave 1\nc0002 wave 1\nparallel: no"
			)
		)
		t.expect(out).toEqual({
			"raft R0001: 3 issues",
			"  wave 1 → c0001  c0002",
			"  wave 2 → c0003",
			"parallel: no",
		})
		local raw = look.workstreams(M, "parallel: yes (wave 1: c0001)")
		t.expect(raw[1]).toBe("\27[32mparallel: yes (wave 1: c0001)\27[0m")
	end)

	it(
		"lessons shows a bar of sources against the most cited, keeps (when, n sources) and wraps the check",
		function()
			local out = plain(
				look.lessons(
					{ rich = true, color = false, links = false, unicode = true, width = 40 },
					"- a/one (design, 8 sources): Is the first question long enough to wrap at forty columns?\n"
						.. "- b/two (both, 1 source): Short?\nanything else"
				)
			)
			t.expect(out[1]).toBe("a/one  ████████ (design, 8 sources)")
			t.expect(out[2]).toBe("    Is the first question long enough to")
			t.expect(out[4]).toBe("b/two  █        (both, 1 source)")
			t.expect(out[#out]).toBe("anything else")
		end
	)

	it(
		"metrics boxes its tables, aligns numbers right, and bars each rework rate against the 20% target",
		function()
			local out = plain(
				look.markdown(
					M,
					"Totals by type.\n| type | issues |\n|---|---|\n| chore | 7 |\n| defect | 12 |\n  by issues:       25.0%"
				)
			)
			t.expect(out[1]).toBe("Totals by type.")
			t.expect(out[2]).toBe("type   │ issues")
			t.expect({ rest = (string.gsub(out[3], "─", "")), drawn = #out[3] > 0 })
				.toEqual({ rest = "", drawn = true })
			t.expect(out[4]).toBe("chore  │      7")
			local rework = look.markdown(M, "  by issues:       25.0%")[1]
			t.expect(has(rework, "\27[31;1m")).toBe(true) -- over the target: red
			local under = look.markdown(M, "  by issues:       5.0%")[1]
			t.expect(has(under, "\27[32m")).toBe(true)
		end
	)

	it("capture tells its header's parts apart and leaves the document as it is", function()
		local out = look.capture(M, "capture abc123 z/c0001.md tracker: new c0001 X\n---\nid: c0001\n")
		t.expect(out[1])
			.toBe("\27[1mcapture\27[0m \27[2mabc123\27[0m z/c0001.md tracker: new \27[34mc0001\27[0m X")
		t.expect({ out[2], out[3] }).toEqual({ "---", "id: c0001" })
	end)

	it(
		"spend colors additions green and removals red; members, busy, headings and results get their marks",
		function()
			t.expect(look.spend(M, "c0001 deliver +12/-3 4.0 min")[1])
				.toBe("\27[34mc0001\27[0m \27[2mdeliver\27[0m \27[32m+12\27[0m/\27[31m-3\27[0m 4.0 min")
			t.expect(look.spend(M, "an odd line")[1]).toBe("an odd line")
			t.expect(plain(look.members(M, { "z/.tracker/issues/c0001" }, function()
				return nil
			end))[1]).toBe("• c0001  z/.tracker/issues/c0001")
			t.expect(plain(look.busy(M, { "raft R0001 is active" }))[1]).toBe("▲ raft R0001 is active")
			local rule = term.strip(look.heading(M, "=== c0001 check.sh"))
			t.expect(string.sub(rule, 1, #"── c0001 check.sh ")).toBe("── c0001 check.sh ")
			t.expect((string.gsub(string.sub(rule, #"── c0001 check.sh " + 1), "─", ""))).toBe("")
			t.expect(term.width(rule)).toBe(100)
			t.expect(term.strip(look.ok(M, "promote-check OK"))).toBe("✔ promote-check OK")
		end
	)

	it("the usage text shows command names bold and descriptions dim", function()
		local out = look.usage(
			M,
			"usage: ./zn <command> ...\n  find <id>         print an item's folder\n                    more of it"
		)
		t.expect(out[1]).toBe("\27[1musage: ./zn <command> ...\27[0m")
		t.expect(out[2]).toBe("  \27[1mfind\27[0m <id>\27[2m         print an item's folder\27[0m")
		t.expect(out[3]).toBe("\27[2m                    more of it\27[0m")
	end)
end)
