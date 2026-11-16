--!strict
-- c0348 AC7: the two promoted specs this chore changes are exactly the changed files, pinned whole.
-- c0084's spend-command.spec said a deliver row for a done item pushes nothing to origin/main; it now says that row is
-- published there as one commit, and nothing else in the file changes. d0333's commit-land.spec gains one last case:
-- after its `./zn done`, `./zn spend R0010 --phase deliver` puts the row on origin's main with no push by hand.
-- Each file is pinned by the SHA-256 of its exact text with only item ids masked (so a compaction cannot break it) and
-- line endings made LF (zz-test/narrowing-pins-the-whole-file; c0177's model). This spec reads the files as text: any
-- later change to one must update its digest here (`exact` the file's text, then `serde.hash("sha256", …)`).
-- That they pass is their own run: commit-land's in the fast tier, spend-command's once by check.sh (it is slow-tier).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- A pin names its spec by its full path, and the owning item's id comes from that path: a compaction renames the item
-- and its tests/acceptance folder and rewrites `tests/acceptance/<id>` paths in this file, but not a bare id.
local SPEND = {
	path = "tests/acceptance/c0084/spend-command.spec.luau",
	sha = "b63eeb34509324999ddeb21b657b73d4f7d346fb1da38eee3af912a203c28e62",
}
local LAND = {
	path = "tests/acceptance/d0333/commit-land.spec.luau",
	sha = "72fd5b5645748c8b2e5fee52da9a5856beb8ee817d9fa70b78d316f9f7e1c861",
}

-- the text with item ids masked and CRLF made LF; nothing else changes. Every read of a pinned file goes through it.
local function exact(text: string): string
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function ownerCheck(path: string): string
	local item = string.match(path, "^tests/acceptance/([^/]+)/") :: string
	return fs.readFile(".tracker/issues/done/" .. item .. "/check.sh")
end

return t.spec("c0348 the two promoted specs it changes, pinned whole", function(it)
	it(`{SPEND.path} is exactly the changed file`, function()
		t.expect(serde.hash("sha256", exact(fs.readFile(SPEND.path)))).toBe(SPEND.sha)
	end)

	it(`{LAND.path} is exactly the changed file`, function()
		t.expect(serde.hash("sha256", exact(fs.readFile(LAND.path)))).toBe(LAND.sha)
	end)

	it(
		"the deliver case no longer says origin's main stays where it was, and says what is published",
		function()
			local text = fs.readFile(SPEND.path)
			local from =
				string.find(text, 'it("records deliver on a done item, in its done directory"', 1, true)
			t.expect(from ~= nil).toBe(true)
			local to = string.find(text, "\n\tend)\n", from :: number, true) :: number
			local case = string.sub(text, from :: number, to)
			t.expect(has(case, "t.expect(tip()).toBe(before)")).toBe(false)
			t.expect(has(case, 't.expect(git(origin, { "rev-parse", "main~1" })).toBe(before)')).toBe(true)
			t.expect(has(case, "`tracker: spend {g} deliver`")).toBe(true)
		end
	)

	it("the landing spec ends with the deliver row published after done", function()
		local text = fs.readFile(LAND.path)
		local landed = string.find(text, 'it("AC4: ./zn done lands that stack"', 1, true)
		local after =
			string.find(text, "after done, ./zn spend --phase deliver puts its row on origin/main", 1, true)
		t.expect(landed ~= nil and after ~= nil and (after :: number) > (landed :: number)).toBe(true)
		t.expect(has(text, 'znOk({ "spend", "R0010", "--phase", "deliver" })')).toBe(true)
	end)

	it("their owners' check.sh files still run them, by the same case names", function()
		local spend = ownerCheck(SPEND.path)
		t.expect(has(spend, 'spec_ok spend-command.spec.luau "publishes one capture row"')).toBe(true)
		t.expect(has(spend, '"records deliver on a done item"')).toBe(true)
		local land = ownerCheck(LAND.path)
		t.expect(has(land, "cases commit-land --run 'sets up a one-ticket raft, finished'")).toBe(true)
		t.expect(has(land, "cases commit-land 'AC4: ./zn done lands that stack'")).toBe(true)
	end)
end)
