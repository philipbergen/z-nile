--!strict
-- c0112 AC4: the twelve checks of the author's private memory `design-first-pass-checklist` (the defects R0039's five
-- design reviews kept finding) are seeded as lessons: R0039's harvest has one note per point, `design-first-pass-checklist
-- point N`, naming at least one existing design lesson that one of R0039's own findings is also a source of. Reads the real
-- files, writes nothing.
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- the repository's files, from its top (this spec runs from z-nile/, c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0112 the R0039 checklist is seeded as lessons", function(it)
	it(
		"R0039's harvest has one note per checklist point, each naming a design lesson sourced from R0039",
		function()
			local raft = renamed.id("R0039")
			local tree = lessons.load(TOP)
			local sources = lessons.sources(tree.items)
			local item: lessons.Item? = nil
			for _, candidate in tree.items do
				if candidate.id == raft then
					item = candidate
				end
			end
			t.expect(item ~= nil).toBe(true)
			local harvest = (item :: lessons.Item).harvest
			t.expect(harvest ~= nil).toBe(true)
			local entries = lessons.parseHarvest(raft, harvest :: string)
			local byPoint: { [number]: lessons.Entry } = {}
			for _, e in entries do
				local n = e.note and string.match(e.note, "^design%-first%-pass%-checklist point (%d+)$")
				if n then
					t.expect(byPoint[tonumber(n) :: number]).toBe(nil) -- one note per point
					byPoint[tonumber(n) :: number] = e
				end
			end
			for point = 1, 12 do
				local e = byPoint[point]
				t.expect(e ~= nil).toBe(true)
				local grounded = false
				for _, lid in (e :: lessons.Entry).lessons do
					local l = if tree.lessons[lid] then lessons.parse(lid, tree.lessons[lid]) else nil
					t.expect(l ~= nil).toBe(true)
					t.expect((l :: lessons.Lesson).when ~= "build").toBe(true)
					local list: { string } = sources[lid] or {}
					for _, s in list do
						if
							string.sub(s, 1, #raft + 1) == `{raft} `
							and string.find(s, "design-review-", 1, true)
						then
							grounded = true
						end
					end
				end
				t.expect(grounded).toBe(true)
			end
		end
	)
end)
