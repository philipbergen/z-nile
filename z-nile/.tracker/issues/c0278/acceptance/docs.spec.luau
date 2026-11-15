--!strict
-- c0278 AC10: the rules restate closing an issue as won't do wherever the statuses, the published changes and the
-- commands are listed (zz-rules and the usage text), and close joins neither the read-only set nor the main checkout's
-- allowed list.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- specs run from z-nile's home: the checkout's files are read from the top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function rules(): string
	return read("z-nile/skills/zz-rules/SKILL.md")
end
local function bullet(text: string, prefix: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	error(`no line starting {prefix}`, 2)
end
local function says(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0278 docs", function(it)
	it("zz-rules' Statuses, Published or carried, direct-push and Paths bullets name closed", function()
		local text = rules()
		local statuses = bullet(text, "- **Statuses**")
		t.expect(says(statuses, "`new -> preparing -> prepared -> active -> done`")).toBe(true)
		t.expect(says(statuses, "`closed` (won't do)")).toBe(true)
		t.expect(says(statuses, "set only by `./zn close`")).toBe(true)
		t.expect(says(statuses, "nothing moves a closed issue")).toBe(true)
		local published = bullet(text, "- **Published or carried.**")
		t.expect(says(published, "`close`")).toBe(true)
		t.expect(says(published, "`close --carry`")).toBe(true)
		local push = bullet(text, "- **The direct-push exception.**")
		t.expect(says(push, "one added `wont_do:` line (what `close` publishes)")).toBe(true)
		t.expect(says(push, "never again once closed")).toBe(true)
		-- what c0081 pins stays
		t.expect(says(push, "`z-nile/next`")).toBe(true)
		t.expect(says(push, "only go up")).toBe(true)
		local paths = bullet(text, "- **Paths**")
		t.expect(says(paths, "a closed issue stays in its backlog folder with status `closed`")).toBe(true)
	end)

	it("zz-rules' commands table has a close row and Other commands lists close and list closed", function()
		local text = rules()
		local row = bullet(text, '| close | `./zn close <issue> --reason "<why>" [--carry]` |')
		for _, needle in
			{
				"`wont_do: <why>`",
				"`closed-…`",
				"in a worktree",
				"`--carry`",
				"`./zn list closed`",
				"`./zn find`",
				"preparing",
				"`depends_on`",
				"`./zn unfold",
			}
		do
			if not says(row, needle) then
				error(`the close row lacks {needle}: {row}`)
			end
		end
		local other = string.match(text, "## Other commands\n(.-)\n## ") :: string
		t.expect(other ~= nil).toBe(true)
		t.expect(says(other, '- `./zn close <issue> --reason "<why>" [--carry]`')).toBe(true)
		t.expect(says(other, "- `./zn list [backlog|active|done|closed]`")).toBe(true)
		t.expect(says(other, "- `./zn list [backlog|active|done]`\n")).toBe(false)
	end)

	it(
		"usage names close and list closed, and close is neither read-only nor allowed in the main checkout",
		function()
			local main = read("z-nile/engine/main.luau")
			local usage = string.match(main, "local USAGE = %[%[(.-)%]%]") :: string
			t.expect(usage ~= nil).toBe(true)
			t.expect(says(usage, '\n  close <issue> --reason "<why>" [--carry]')).toBe(true)
			t.expect(says(usage, "\n  list [backlog|active|done|closed]")).toBe(true)
			local readOnly =
				string.match(main, "local READ_ONLY: { %[string%]: boolean } = {(.-)\n}") :: string
			t.expect(readOnly ~= nil).toBe(true)
			t.expect(says(readOnly, "close")).toBe(false)
			local allowed =
				string.match(rules(), "The complete list of commands that may run there:([^\n]+)") :: string
			t.expect(allowed ~= nil).toBe(true)
			t.expect(says(allowed, "`close`")).toBe(false)
			-- --carry is a flag that takes no value
			local flags = string.match(main, 'local function flags%(.-opts%[a%] = { "true" }') :: string
			t.expect(says(flags, 'a == "--carry"')).toBe(true)
		end
	)
end)
