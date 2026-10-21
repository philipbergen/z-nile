--!strict
-- c0115: new skills are invocable, copies that must not drift are byte-equal, the README opens with the flowchart.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)

local function text(path: string): string
	return fs.readFile(`{root}/{path}`)
end

local function field(body: string, key: string): string?
	local block = string.match(body, "^%-%-%-\n(.-)\n%-%-%-")
	if not block then
		return nil
	end
	return string.match(block, key .. ": ([^\n]+)")
end

-- Drop only the frontmatter `name:` line. The rest of the file, including any later `name:` quote, must match.
local function withoutName(s: string): string
	local block, rest = string.match(s, "^(%-%-%-\n.-\n%-%-%-\n)(.*)$")
	if not block or not rest then
		return s
	end
	local kept = {}
	for line in string.gmatch(block, "(.-)\n") do
		if string.match(line, "^name: ") == nil then
			table.insert(kept, line)
		end
	end
	return table.concat(kept, "\n") .. "\n" .. rest
end

local function heading(body: string): string?
	return string.match(body, "\n(# [^\n]+)")
end

local function skillOk(name: string)
	local body = text(`.claude/skills/{name}/SKILL.md`)
	t.expect(field(body, "name")).toBe(name)
	local desc = field(body, "description")
	t.expect(desc ~= nil and desc ~= "").toBe(true)
end

return t.spec("z-nile skill names", function(it)
	it("pipeline names", function()
		for _, name in { "z-ticket", "z-design", "z-raft", "z-ready", "z-run", "z-stop" } do
			skillOk(name)
		end
	end)

	it("internal names", function()
		for _, name in { "zz-review", "zz-rules", "zz-arch", "zz-test", "zz-stats" } do
			skillOk(name)
		end
	end)

	it("README opens with the flowchart", function()
		local body = text("z-nile/README.md")
		local fenceAt = string.find(body, "```mermaid", 1, true)
		t.expect(fenceAt ~= nil).toBe(true)
		local paraAt: number? = nil
		local pos = 1
		local inFence = false
		for line in string.gmatch(body .. "\n", "(.-)\n") do
			local starts = string.sub(line, 1, 3) == "```"
			if starts then
				inFence = not inFence
			elseif not inFence and line ~= "" and string.sub(line, 1, 1) ~= "#" then
				paraAt = pos
				break
			end
			pos += #line + 1
		end
		t.expect(paraAt ~= nil and fenceAt ~= nil and (fenceAt :: number) < (paraAt :: number)).toBe(true)
		for _, word in { "tracker", "skills", "dispatcher", ".models.toml", "board" } do
			t.expect(string.find(body, word, 1, true) ~= nil).toBe(true)
		end
	end)

	it("old tracker skill still readable", function()
		t.expect(fs.isFile(`{root}/.claude/skills/tracker/SKILL.md`)).toBe(true)
		local agents = text("AGENTS.md")
		t.expect(string.find(agents, ".claude/skills/tracker/SKILL.md", 1, true) ~= nil).toBe(true)
		t.expect(string.find(agents, ".claude/skills/z-ticket/SKILL.md", 1, true) ~= nil).toBe(true)
	end)

	it("copies stay equal", function()
		local pairs = {
			{ "z-ticket", "make-issue" },
			{ "z-ready", "ready-raft" },
			{ "z-stop", "stop-raft" },
			{ "zz-review", "review" },
			{ "zz-arch", "architecture" },
			{ "zz-test", "testing" },
			{ "zz-stats", "metrics" },
		}
		for _, pair in pairs do
			local got = text(`.claude/skills/{pair[1]}/SKILL.md`)
			local src = text(`.claude/skills/{pair[2]}/SKILL.md`)
			t.expect(withoutName(got)).toBe(withoutName(src))
		end
	end)

	it("z-run joins both", function()
		local got = text(".claude/skills/z-run/SKILL.md")
		local launch = heading(text(".claude/skills/launch-raft/SKILL.md"))
		local execute = heading(text(".claude/skills/execute-raft/SKILL.md"))
		t.expect(launch ~= nil and string.find(got, launch :: string, 1, true) ~= nil).toBe(true)
		t.expect(execute ~= nil and string.find(got, execute :: string, 1, true) ~= nil).toBe(true)
	end)
end)
