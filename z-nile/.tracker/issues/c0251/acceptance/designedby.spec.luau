--!strict
-- c0251 AC8 (the pure half): `designedby` reads the `designed-by: <model id>` front-matter line of an issue's or a raft's document
-- (one id, or a list `[a, b]` once another model revised it), adds a model to it without a duplicate, and gives the refusal text
-- for a document without the line. Pure: document texts in, ids or texts out.
local t = require("@tests/lib/t")

local designedby: any = require("@znile/engine/designedby")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local function doc(line: string?, body: string?): string
	return `---\nid: c0010\ntype: chore\ntitle: demo\n{if line then line .. "\n" else ""}status: prepared-a-b-c\n---\n\n# c0010\n{body or ""}`
end

return t.spec("c0251 the designed-by line", function(it)
	it("AC8: of reads one id, a list, and nothing for a missing or empty line", function()
		t.expect(designedby.KEY).toBe("designed-by")
		t.expect(designedby.of(doc("designed-by: claude-opus-5-5"))).toEqual({ "claude-opus-5-5" })
		t.expect(designedby.of(doc("designed-by: [claude-opus-5-5, claude-fable-5-2]"))).toEqual({
			"claude-opus-5-5",
			"claude-fable-5-2",
		})
		t.expect(designedby.of(doc("designed-by:   [ claude-opus-5-5 ,claude-fable-5-2 ]  "))).toEqual({
			"claude-opus-5-5",
			"claude-fable-5-2",
		})
		t.expect(designedby.of(doc(nil))).toEqual({})
		t.expect(designedby.of(doc("designed-by:"))).toEqual({})
		t.expect(designedby.of(doc("designed-by: []"))).toEqual({})
		t.expect(designedby.of("# no front matter\n")).toEqual({})
	end)

	it(
		"AC8: of reads a bare id (a context marker cut) once each, and only the front matter, never the body",
		function()
			t.expect(designedby.of(doc("designed-by: [claude-opus-5-5[1m], claude-opus-5-5]")))
				.toEqual({ "claude-opus-5-5" })
			t.expect(designedby.of(doc(nil, "\ndesigned-by: claude-fable-5-2\n"))).toEqual({})
			t.expect(designedby.of(doc("designed-by: claude-opus-5-5", "\ndesigned-by: claude-fable-5-2\n")))
				.toEqual({
					"claude-opus-5-5",
				})
		end
	)

	it(
		"AC8: add writes the line when there is none, in the front matter only, and leaves the body alone",
		function()
			local out = designedby.add(doc(nil, "\nbody designed-by: x\n"), "claude-opus-5-5") :: string
			t.expect(designedby.of(out)).toEqual({ "claude-opus-5-5" })
			t.expect(has(out, "\ndesigned-by: claude-opus-5-5\nstatus: prepared-a-b-c\n---\n")).toBe(false)
			t.expect(has(out, "designed-by: claude-opus-5-5\n---\n")).toBe(true)
			t.expect(has(out, "\n# c0010\n\nbody designed-by: x\n")).toBe(true)
			t.expect(has(out, "id: c0010\ntype: chore\ntitle: demo\nstatus: prepared-a-b-c\n")).toBe(true)
		end
	)

	it("AC8: add keeps the same model once, and a second model that revises makes it a list", function()
		local one = doc("designed-by: claude-opus-5-5")
		t.expect(designedby.add(one, "claude-opus-5-5")).toBe(one)
		t.expect(designedby.add(one, "claude-opus-5-5[1m]")).toBe(one)
		local two = designedby.add(one, "claude-fable-5-2") :: string
		t.expect(has(two, "designed-by: [claude-opus-5-5, claude-fable-5-2]\n")).toBe(true)
		t.expect(select(2, string.gsub(two, "designed%-by:", ""))).toBe(1)
		t.expect(designedby.add(two, "claude-fable-5-2")).toBe(two)
		local three = designedby.add(two, "kimi-code-k3.1-pro") :: string
		t.expect(designedby.of(three))
			.toEqual({ "claude-opus-5-5", "claude-fable-5-2", "kimi-code-k3.1-pro" })
	end)

	it(
		"AC8: add gives nil for a document with no front matter, and the refusal names the item, the document and the line",
		function()
			t.expect(designedby.add("# no front matter\n", "claude-opus-5-5")).toBe(nil)
			local why = designedby.refusal("c0010", "pickman/.tracker/issues/c0010/c0010.md")
			t.expect(has(why, "c0010")).toBe(true)
			t.expect(has(why, "pickman/.tracker/issues/c0010/c0010.md")).toBe(true)
			t.expect(has(why, "designed-by")).toBe(true)
			t.expect(has(why, "--author")).toBe(false)
		end
	)
end)
