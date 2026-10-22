--!strict
-- c0830: every line in scripts/ that names a .cache path is on a reviewed list (cachepaths.ALLOWED, with a reason
-- each), so a new writer under .cache can't land without a reviewer seeing how it writes. The scan is a pure
-- function: tested here on planted text, then run on the real scripts/.
local cachepaths = require("@tests/lib/cachepaths")
local t = require("@tests/lib/t")

local function has(list: { string }, part: string): boolean
	for _, line in list do
		if string.find(line, part, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0830 every .cache path in scripts/ is reviewed", function(it)
	it("a new .cache mention in a Luau or a shell file is flagged", function()
		local found = cachepaths.scan({
			["scripts/a.luau"] = 'local x = 1\nfs.writeFile(".cache/new-file", text)\n',
			["scripts/b.sh"] = "echo hi\nprintf x > .cache/other\n",
		}, {})
		t.expect(#found).toBe(2)
		t.expect(has(found, 'scripts/a.luau: fs.writeFile(".cache/new-file", text)')).toBe(true)
		t.expect(has(found, "scripts/b.sh: printf x > .cache/other")).toBe(true)
	end)

	it("a commented mention is not flagged, and a listed one passes", function()
		local found = cachepaths.scan({
			["scripts/a.luau"] = '  -- writes .cache/x through replace-file\n\tsh.writeReplacing(".cache/focus", id)\n',
			["scripts/b.sh"] = "  # .cache must be a plain folder\nmkdir -p .cache\n",
		}, {
			["scripts/a.luau"] = { ['sh.writeReplacing(".cache/focus", id)'] = "through replace-file" },
			["scripts/b.sh"] = { ["mkdir -p .cache"] = "a plain folder the fence checks" },
		})
		t.expect(#found).toBe(0)
	end)

	it("a listed line that is gone is reported", function()
		local found = cachepaths.scan({ ["scripts/a.luau"] = "local x = 1\n" }, {
			["scripts/a.luau"] = { ['fs.writeFile(".cache/old", x)'] = "was reviewed once" },
			["scripts/gone.sh"] = { ["mkdir -p .cache"] = "a file that no longer exists" },
		})
		t.expect(#found).toBe(2)
		t.expect(has(found, 'scripts/a.luau: listed but missing: fs.writeFile(".cache/old", x)')).toBe(true)
		t.expect(has(found, "scripts/gone.sh: listed but missing: mkdir -p .cache")).toBe(true)
	end)

	-- c0114 override: the gate and the engine moved to z-nile/, so the scan covers cachepaths.ROOTS (scripts/, z-nile/)
	it(
		"every .cache line in scripts/ and z-nile/ is on the reviewed list, and every listed line exists",
		function()
			-- c0120 override: the spec runs from z-nile/, so the walk reads the checkout from its top (cachepaths.files)
			local files = cachepaths.files()
			t.expect(files["z-nile/check.sh"] ~= nil).toBe(true) -- the walk found the gate
			t.expect(files["z-nile/lib/sh.luau"] ~= nil).toBe(true)
			local found = cachepaths.scan(files, cachepaths.ALLOWED)
			if #found > 0 then
				error(
					"not on the reviewed list (tests/lib/cachepaths.luau ALLOWED):\n"
						.. table.concat(found, "\n")
				)
			end
			-- every entry carries a reason
			for path, lines in cachepaths.ALLOWED do
				for line, why in lines do
					t.expect(#why > 0).toBe(true)
					t.expect(string.find(line, ".cache", 1, true) ~= nil).toBe(true)
					t.expect(string.sub(path, 1, 8) == "scripts/" or string.sub(path, 1, 7) == "z-nile/")
						.toBe(true)
				end
			end
		end
	)
end)
