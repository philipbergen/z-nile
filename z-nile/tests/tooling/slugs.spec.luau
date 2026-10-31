--!strict
-- R0061 code review 001 F3: two rules of c0135's slug reader (z-nile/engine/audit.luau) that its sequestered spec holds
-- no case for: audit reports several clashes sorted by kind, then slug (never in hash order), and a document counts as
-- an item only when it is named after its folder (`issues/c0005/c0005.md`, not `issues/c0005/c0006.md`).
local audit = require("@znile/engine/audit")
local t = require("@tests/lib/t")

local function slugged(kind: string, slug: string, id: string): audit.Slugged
	return { kind = kind, slug = slug, id = id, path = `x/{id}` }
end

return t.spec("c0135 slug reader rules", function(it)
	it("reports several clashes sorted by kind, then slug", function()
		local clashes = audit.slugClashes({
			slugged("raft", "zeta", "R0002"),
			slugged("raft", "zeta", "R0001"),
			slugged("issue", "omega", "c0004"),
			slugged("issue", "omega", "c0003"),
			slugged("issue", "alpha", "c0006"),
			slugged("issue", "alpha", "c0005"),
			slugged("raft", "beta", "R0008"),
			slugged("raft", "beta", "R0007"),
		})
		local order: { string } = {}
		for _, c in clashes do
			table.insert(order, `{c.kind} {c.slug}: {table.concat(c.ids, ", ")}`)
		end
		t.expect(order).toEqual({
			"issue alpha: c0005, c0006",
			"issue omega: c0003, c0004",
			"raft beta: R0007, R0008",
			"raft zeta: R0001, R0002",
		})
	end)

	it("counts a document as an item only when it is named after its folder", function()
		local docs: { [string]: string } = {
			["z/.tracker/issues/c0005/c0005.md"] = "---\nid: c0005\nslug: named\n---\n",
			["z/.tracker/issues/c0007/c0008.md"] = "---\nid: c0008\nslug: misnamed\n---\n",
		}
		local paths: { string } = {}
		for p in docs do
			table.insert(paths, p)
		end
		table.sort(paths)
		local found = audit.sluggedFromTree(paths, { "z/.tracker" }, function(p: string): string?
			return docs[p]
		end)
		t.expect(found).toEqual({
			{ kind = "issue", slug = "named", id = "c0005", path = "z/.tracker/issues/c0005" },
		})
	end)
end)
