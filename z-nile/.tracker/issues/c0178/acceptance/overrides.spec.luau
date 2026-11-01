--!strict
-- c0178 AC8: the promoted specs this chore edits (its Overrides) use the shared helpers where they used to do the work
-- by hand: the thirteen that clone the repository clone only the paths they read (clone.isolated with paths), the ten
-- that built their own four-repository fixture call trackerfix.new, and c0116/claims makes its twenty worktrees with
-- trackerfix.worktrees. Reads the real spec files at the checkout's top. The edits replace setup only; every case of
-- those specs is the promoted text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local TESTS = "z-nile/" .. "tests" -- two parts: a compaction rewrites a literal path

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function read(path: string): string
	return fs.readFile(`{TOP}/{TESTS}/{path}`)
end

-- the specs that clone the repository: each calls clone.isolated(root, <dest>, { paths = ... }) and no raw clone of root
local CLONING = {
	"acceptance/c0001/tracker-lifecycle",
	"acceptance/c0005/worktree",
	"acceptance/c0008/done-order",
	"acceptance/c0038/deferred",
	"acceptance/c0044/naming",
	"acceptance/c0045/workstreams",
	"acceptance/c0046/launch",
	"acceptance/c0050/start-depends",
	"acceptance/c0074/done-gate",
	"acceptance/c0080/consequences",
	"acceptance/c0116/promote",
	"acceptance/c0120/promote-home",
	"tooling/worktree-fetch",
}

-- the specs that built a four-repository fixture by hand: each calls trackerfix.new and no longer makes a seed folder
local BUILDING = {
	"acceptance/c0067/ready",
	"acceptance/c0068/stop",
	"acceptance/c0069/prompt",
	"acceptance/c0070/board-refresh",
	"acceptance/c0072/land",
	"acceptance/c0081/allocate",
	"acceptance/c0081/compact",
	"acceptance/c0081/remap",
	"acceptance/c0084/spend-command",
	"tooling/remap-once",
}

return t.spec("c0178 the specs it edits", function(it)
	it("the thirteen specs that clone the repository clone only the paths they read", function()
		for _, spec in CLONING do
			local text = read(`{spec}.spec.luau`)
			if not has(text, "clone.isolated(root, ") or not has(text, "paths = {") then
				error(`{spec} does not call clone.isolated with paths`)
			end
			if not has(text, "require" .. '("@tests/lib/clone")') then
				error(`{spec} does not require @tests/lib/clone`)
			end
			if has(text, '"--no-hardlinks", root') then
				error(`{spec} still clones the repository with a raw git clone`)
			end
		end
	end)

	it("the ten specs that built their own four-repository fixture call trackerfix.new", function()
		for _, spec in BUILDING do
			local text = read(`{spec}.spec.luau`)
			if not has(text, "trackerfix.new(") then
				error(`{spec} does not call trackerfix.new`)
			end
			if has(text, '"clone", "-q", "--bare"') or has(text, "engine.copy(root, seed)") then
				error(`{spec} still builds its own seed and origin`)
			end
		end
	end)

	it(
		"the specs whose reset or rollback deletes what is outside the sparse set carry the tooling the engine runs",
		function()
			for _, spec in { "acceptance/c0038/deferred", "acceptance/c0120/promote-home", "acceptance/c0116/promote" } do
				if not has(read(`{spec}.spec.luau`), "tooling = true") then
					error(`{spec} does not take tooling = true`)
				end
			end
		end
	)

	it(
		"the specs that list their own tooling list its folders, so a module the engine newly requires survives a reset",
		function()
			for _, spec in
				{ "acceptance/c0008/done-order", "acceptance/c0074/done-gate", "acceptance/c0080/consequences" }
			do
				local text = read(`{spec}.spec.luau`)
				for _, folder in { '"zn"', '"scripts/"', '"z-nile/engine/"', '"z-nile/lib/"' } do
					if not has(text, folder) then
						error(`{spec} does not list {folder}`)
					end
				end
			end
		end
	)

	it("c0116/claims makes its twenty worktrees with trackerfix.worktrees, none by hand", function()
		local text = read("acceptance/c0116/claims.spec.luau")
		t.expect(has(text, "trackerfix.worktrees(")).toBe(true)
		local direct = 0
		for _ in string.gmatch(text, '{ "worktree", "raft%-') do
			direct += 1
		end
		for _ in string.gmatch(text, '{ "worktree", "prep%-') do
			direct += 1
		end
		t.expect(direct).toBe(0)
	end)
end)
