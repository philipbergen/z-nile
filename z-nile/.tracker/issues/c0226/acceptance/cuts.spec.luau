--!strict
-- c0226 AC2: `trail.cuts` lists the commits c0118's history counts as compactions, judged by the one rule both use
-- (`ids.cutFile`, pinned by rule.spec) over a log without rename detection: a map added, changed in place, moved and
-- changed in one commit (even when git's `-M` pairs the two files, the shape the old `-M --diff-filter=AM` log listed
-- as no cut, so the trail followed renamed ids across it), or moved with its lines reordered; never a plain move or a
-- deletion, nor a move that only drops the map's final newline (the patch's lines are compared, as history compares
-- them, not blob ids). Each is named by the map file that makes it one, and history counts exactly the same commits as
-- compactions. Over a real repository under .cache/c0226-cuts (git runs through @tests/lib/fixture; `trail.cuts` only
-- reads it, at the `dir` it is given).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local history = require("@znile/engine/history")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- fixtures live under the home's .cache, where the spec runs (the jail refuses the checkout top's when they differ)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local repo = `{here}/.cache/c0226-cuts`

local OLD, NEW = "tracker/compaction.txt", "z-nile/compaction.txt"
-- a map long enough that changing one pair and its header leaves it over git's 50% rename similarity
local function map(header: string, last: string): string
	local out = { `# {header}` }
	for n = 1, 11 do
		table.insert(out, string.format("c%04d c%04d", 900 + n, 100 + n))
	end
	table.insert(out, last)
	return table.concat(out, "\n") .. "\n"
end

local SHA: { [string]: string } = {}
local function write(path: string, text: string)
	local full = `{repo}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function move(from: string, to: string)
	fs.writeDir(string.match(`{repo}/{to}`, "^(.*)/[^/]+$") :: string)
	fixture.git(repo, { "mv", from, to })
end
local function commit(key: string, message: string)
	fixture.git(repo, { "add", "-A" })
	fixture.git(repo, { "commit", "-q", "-m", message })
	SHA[key] = fixture.git(repo, { "rev-parse", "HEAD" })
end

return t.spec("c0226 trail.cuts counts a map moved and changed", function(it)
	it(
		"sets up a repository whose map is added, moved, moved and changed, changed, reordered, deleted, re-added and moved without its final newline",
		function()
			if fs.isDir(repo) then
				fs.removeDir(repo)
			end
			fs.writeDir(repo)
			process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
			fixture.git(repo, { "config", "user.name", "c0226-cuts" })
			fixture.git(repo, { "config", "user.email", "c0226-cuts@example.invalid" })
			write("z-nile/.tracker/issues/c0300/c0300.md", "# c0300\n")
			commit("seed", "seed: no map")
			write(OLD, map("compaction map A", "c0300 c0030"))
			commit("add", "tracker: compact ids")
			move(OLD, NEW)
			write("z-nile/.tracker/issues/c0300/c0300.md", "# c0300, moved with the map\n")
			commit("move", "c0114: move the map, unchanged")
			move(NEW, OLD)
			write(OLD, map("compaction map B", "c0300 c0031"))
			commit("movechange", "tracker: compact ids, the map moved and rewritten")
			write(OLD, map("compaction map C", "c0300 c0031"))
			commit("change", "tracker: compact ids in place")
			move(OLD, NEW)
			local lines = string.split(trim(map("compaction map C", "c0300 c0031")), "\n")
			lines[2], lines[3] = lines[3], lines[2]
			write(NEW, table.concat(lines, "\n") .. "\n")
			commit("reorder", "the map moved with two lines swapped")
			fixture.git(repo, { "rm", "-q", NEW })
			commit("delete", "the map deleted")
			write(NEW, map("compaction map D", "c0400 c0040"))
			commit("readd", "tracker: compact ids anew")
			-- a move that only drops the final newline: the patch's lines are the same, so no compaction (history's reading)
			move(NEW, OLD)
			write(OLD, trim(map("compaction map D", "c0400 c0040")))
			commit("nlmove", "the map moved, its final newline dropped")
			write("z-nile/.tracker/issues/c0300/c0300.md", "# c0300, no map touched\n")
			commit("other", "an item changed alone")
		end
	)

	it(
		"AC2: the move-and-change commit is one git's rename detection pairs (the shape the -M log missed)",
		function()
			local status = fixture.git(repo, { "diff", "-M", "--name-status", SHA.move, SHA.movechange })
			t.expect(string.match(status, "^R%d+\t") ~= nil).toBe(true)
		end
	)

	it(
		"AC2: trail.cuts lists every add, change, move-and-change and reordered move, and no plain move, deletion or move that only drops the final newline",
		function()
			fixture.check(repo)
			t.expect(trail.cuts("HEAD", repo)).toEqual({
				[SHA.add] = OLD,
				[SHA.movechange] = OLD,
				[SHA.change] = OLD,
				[SHA.reorder] = NEW,
				[SHA.readd] = NEW,
			})
		end
	)

	it("AC2: trail.cuts reads the history of the head it is given", function()
		fixture.check(repo)
		t.expect(trail.cuts(SHA.movechange, repo)).toEqual({ [SHA.add] = OLD, [SHA.movechange] = OLD })
	end)

	it(
		"AC2: history counts as compactions exactly the commits trail.cuts lists, over the same repository",
		function()
			-- history reads a compaction's map (readMap) for every commit it counts as one, and for no other commit
			local seen: { [string]: boolean } = {}
			local roots = { "z-nile/.tracker" }
			history.parse(
				fixture.git(repo, history.logArgs(roots)),
				roots,
				function(sha: string, _path: string): string?
					seen[sha] = true
					return nil
				end
			)
			local listed: { [string]: boolean } = {}
			for sha in trail.cuts("HEAD", repo) do
				listed[sha] = true
			end
			t.expect(seen).toEqual(listed)
			t.expect(seen[SHA.movechange]).toBe(true)
			t.expect(seen[SHA.nlmove]).toBe(nil)
		end
	)

	it("AC2: the log trail.cuts runs, parsed alone, gives the same table", function()
		local log = fixture.git(repo, trail.cutsArgs("HEAD"))
		t.expect(trail.parseCuts(log)).toEqual(trail.cuts("HEAD", repo))
	end)
end)
