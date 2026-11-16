--!strict
-- c0118 AC6: the real tracker's board: one tab per registered project in registry order, and every issue on exactly
-- one column of its own project's board. No counts of live items: only that each item found behaves.
local board = require("@znile/engine/board")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

return t.spec("c0118 real board", function(it)
	-- the spec runs from its project's home: the tracker is read from the checkout's top (c0120)
	local top = (
		string.gsub(
			require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout,
			"%s+$",
			""
		)
	)
	local m = board.collect(nil, top)

	it("has one tab per project in z-nile/projects.toml, in its order", function()
		local want = {}
		for _, p in projects.load(top).projects do
			table.insert(want, { name = p.name, root = p.root })
		end
		t.expect(m.projects).toEqual(want)
	end)

	it("puts every issue on exactly one column of its own project", function()
		local seen: { [string]: number } = {}
		for project, columns in m.columns do
			for _, bands in columns do
				for _, band in bands do
					for _, id in band.ids do
						seen[id] = (seen[id] or 0) + 1
						for _, issue in m.issues do
							if issue.id == id and issue.project ~= project then
								error(`{id} is on {project}'s board but belongs to {issue.project}`)
							end
						end
					end
				end
			end
		end
		for _, issue in m.issues do
			if seen[issue.id] ~= 1 then
				error(`{issue.id} is on {seen[issue.id] or 0} columns`)
			end
		end
	end)
end)
