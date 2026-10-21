--!strict
-- RC2: an issue created with --project z-nile is on that view and not on pickman's.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOML = 'id = ["pickman", "z-nile"]\n'

local function idOf(out: string): string
	return string.match(out, "([fcdR]%d%d%d%d)") :: string
end

local function viewsOf(html: string): { any }
	local tag = '<script type="application/json" id="z-nile-view">'
	local start = string.find(html, tag, 1, true)
	t.expect(start ~= nil).toBe(true)
	local from = (start :: number) + #tag
	local stop = string.find(html, "</script>", from, true)
	t.expect(stop ~= nil).toBe(true)
	return serde.decode("json", string.sub(html, from, (stop :: number) - 1))
end

return t.spec("z-nile tab", function(it)
	it("a tooling issue is only on the z-nile view", function()
		local f = trackerfix.new("r0042-tab", { ["z-nile/projects.toml"] = TOML })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-tab" })
		local made = trackerfix.trOk(
			f,
			wt,
			{ "new", "issue", "c", "tooling-tab", "--desc", "Tooling.", "--project", "z-nile" }
		)
		local id = idOf(made)
		local page = `{f.base}/page.html`
		local r = trackerfix.tr(f, wt, { "view", "--out", page, "-O" })
		t.expect(r.ok).toBe(true)
		local built = viewsOf(fs.readFile(page))
		local function has(viewId: string): boolean
			for _, p in built do
				if p.id == viewId then
					for _, card in p.cards do
						if card.id == id then
							return true
						end
					end
				end
			end
			return false
		end
		local pickman = false
		for _, p in built do
			if p.id == "pickman" then
				pickman = true
			end
		end
		t.expect(pickman).toBe(true)
		t.expect(has("z-nile")).toBe(true)
		t.expect(has("pickman")).toBe(false)
	end)
end)
