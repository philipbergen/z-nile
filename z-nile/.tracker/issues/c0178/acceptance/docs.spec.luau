--!strict
-- c0178 AC9: the skills that restate how a fixture is built say that it comes from an image, and where the image's key
-- is computed (zz-test, "Speed"; zz-arch, "Layout"). Reads the real skill files at the checkout's top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0178 skills name the fixture images", function(it)
	it(
		"zz-test's Speed section has a Fixture images bullet that names the store, its users, the sweep, the tally and the git template",
		function()
			local text = fs.readFile(`{TOP}/z-nile/skills/zz-test/SKILL.md`)
			local speed = string.match(text, "\n## Speed\n(.-)\n## ") or ""
			t.expect(speed ~= "").toBe(true)
			for _, needle in
				{
					"**Fixture images**",
					"@tests/lib/images",
					"images.dir()",
					"engine.seed",
					"engine.image",
					"trackerfix.new",
					"engine.copy",
					"clone.isolated",
					"pruning",
					"@tests/lib/swept",
					"@tests/lib/tally",
					"GIT_TEMPLATE_DIR",
					"fixtures: N files written",
				}
			do
				if not has(speed, needle) then
					error(`zz-test's Speed section lacks {needle}`, 2)
				end
			end
		end
	)

	it("zz-arch's Layout row for z-nile/lib names image-key.pl", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-arch/SKILL.md`)
		local layout = string.match(text, "\n## Layout\n(.-)\n## ") or ""
		local row = ""
		for line in string.gmatch(layout, "[^\n]+") do
			if has(line, "`z-nile/lib/`") then
				row = line
			end
		end
		t.expect(row ~= "").toBe(true)
		t.expect(has(row, "image-key.pl")).toBe(true)
	end)
end)
