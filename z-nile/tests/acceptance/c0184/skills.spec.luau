--!strict
-- c0184 AC6: a skill's `extends:` key is read, checked and put in the prompt's order. Pure over skill entries, so it
-- needs no tree; the prompt rendered for a raft is generic.spec's. (The text of each project's skills is check.sh's AC6.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local THREE = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n[[project]]\nname = "snake"\nroot = "snake/.tracker"\n'
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local function skillDoc(name: string, extends: string?, body: string): string
	local ext = if extends then `extends: {extends}\n` else ""
	return `---\nname: {name}\n{ext}description: d\n---\n\n# {body}\n`
end

return t.spec("c0184 a skill's extends", function(it)
	it("AC6: a skill's extends is read, checked, and inlined after the project's own skills", function()
		local function entry(name: string, extends: string?): skills.Entry
			local front = `---\nname: {name}\n{if extends then `extends: {extends}\n` else ""}---\n# x\n`
			return { name = name, text = front }
		end
		local found: { skills.Found } = {
			{
				folder = { project = "z-nile", path = "z-nile/skills" },
				entries = { entry("zz-execute", nil), entry("zz-rules", nil) },
			},
			{
				folder = { project = "pickman", path = "pickman/skills" },
				entries = { entry("pickman-arch", nil), entry("pickman-test", nil) },
			},
			{
				folder = { project = "snake", path = "snake/skills" },
				entries = { entry("snake-arch", "pickman-arch"), entry("snake-test", "pickman-test") },
			},
		}
		local list, problems = skills.plan(found)
		t.expect(problems).toEqual({})
		local byName: { [string]: skills.Skill } = {}
		for _, sk in list do
			byName[sk.name] = sk
		end
		t.expect(byName["snake-arch"].extends).toBe("pickman-arch")
		t.expect(byName["pickman-arch"].extends).toBe(nil)
		-- the raft's prompt: z-nile's, snake's own, then the bases (pickman's own skills are not inlined for snake otherwise)
		local inlined = skills.inlined(list, "snake")
		t.expect(inlined[#inlined - 3]).toBe("snake/skills/snake-arch/SKILL.md")
		t.expect(inlined[#inlined - 2]).toBe("snake/skills/snake-test/SKILL.md")
		t.expect(inlined[#inlined - 1]).toBe("pickman/skills/pickman-arch/SKILL.md")
		t.expect(inlined[#inlined]).toBe("pickman/skills/pickman-test/SKILL.md")
		-- pickman's own raft inlines each of its skills once, and z-nile's inlines no project's
		local own = skills.inlined(list, "pickman")
		t.expect(own[#own]).toBe("pickman/skills/pickman-test/SKILL.md")
		t.expect(table.find(skills.inlined(list, "z-nile"), "pickman/skills/pickman-arch/SKILL.md")).toBe(nil)
		-- a base that is no skill, or the skill itself, is a problem naming the file, and the skill is left out
		found[3].entries = { entry("snake-arch", "nowhere"), entry("snake-test", "snake-test") }
		local kept, bad = skills.plan(found)
		t.expect(#bad).toBe(2)
		t.expect(bad[1]).toBe("snake/skills/snake-arch/SKILL.md: extends nowhere, which is no other skill")
		t.expect(bad[2]).toBe("snake/skills/snake-test/SKILL.md: extends snake-test, which is no other skill")
		for _, sk in kept do
			t.expect(string.find(sk.name, "snake", 1, true) == nil).toBe(true)
		end
		-- a z-nile skill extends nothing, and a base that extends is refused (one level)
		found[3].entries = { entry("snake-arch", "pickman-arch") }
		found[2].entries = { entry("pickman-arch", "pickman-test"), entry("pickman-test", nil) }
		found[1].entries = { entry("zz-execute", "pickman-arch"), entry("zz-rules", nil) }
		local _, more = skills.plan(found)
		t.expect(table.find(more, "z-nile/skills/zz-execute/SKILL.md: a z-nile skill extends nothing") ~= nil)
			.toBe(true)
		t.expect(
			table.find(
				more,
				"snake/skills/snake-arch/SKILL.md: extends pickman-arch, which itself extends pickman-test: one level only"
			) ~= nil
		).toBe(true)
	end)

	it(
		"AC6: only the raft's own project's bases are inlined, never another project's, and none for z-nile",
		function()
			local function entry(name: string, extends: string?): skills.Entry
				return {
					name = name,
					text = `---\nname: {name}\n{if extends then `extends: {extends}\n` else ""}---\n# x\n`,
				}
			end
			local list = skills.plan({
				{
					folder = { project = "pickman", path = "pickman/skills" },
					entries = { entry("pickman-arch", nil) },
				},
				{
					folder = { project = "snake", path = "snake/skills" },
					entries = { entry("snake-arch", "pickman-arch") },
				},
			})
			t.expect(skills.bases(list, "snake")).toEqual({ ["pickman-arch"] = true })
			t.expect(skills.bases(list, "pickman")).toEqual({})
			t.expect(skills.bases(list, "z-nile")).toEqual({})
			t.expect(skills.bases(list, nil)).toEqual({})
			t.expect(table.find(skills.inlined(list, "z-nile"), "pickman/skills/pickman-arch/SKILL.md"))
				.toBe(nil)
			t.expect(table.find(skills.inlined(list, "pickman"), "snake/skills/snake-arch/SKILL.md"))
				.toBe(nil)
		end
	)

	it(
		"AC6: the prompt of a raft in a project whose skill extends another names that skill and its base",
		function()
			-- a third project, snake, whose skill extends a pickman skill: the fixture's registry names it (trackerfix seeds
			-- last), and `ready` renders the raft's prompt with the real engine
			local reg = THREE .. "\n"
			local f = trackerfix.new("c0184-prompt", {
				["z-nile/projects.toml"] = reg,
				["snake/.tracker/architecture.md"] = "# map\n",
				["snake/.tracker/rafts/R0030/R0030.md"] = `---\nid: R0030\ntype: chore\ntitle: R0030\nslug: r0030\nsingle: true\nissues: [c0030]\ndesign: ready\ncreated: 2026-10-21\nstatus: {PREPARED}\n---\n\n# R0030\n`,
				["snake/.tracker/rafts/R0030/check.sh"] = CHECK,
				["snake/.tracker/issues/c0030/c0030.md"] = `---\nid: c0030\ntype: chore\ntitle: c0030\nslug: c0030\nraft: R0030\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-21\nstatus: {PREPARED}\n---\n\n# c0030\n`,
				["snake/.tracker/issues/c0030/check.sh"] = CHECK,
				["snake/skills/snake-arch/SKILL.md"] = skillDoc("snake-arch", "pickman-play", "SNAKE-RULES"),
				["pickman/skills/pickman-play/SKILL.md"] = skillDoc("pickman-play", nil, "PLAY-RULES"),
				["pickman/skills/pickman-play/lessons/feel.md"] = "---\ntitle: Feel lesson\nwhen: build\ntags: [x]\ncheck: Does it feel fair?\nfrom: user 2026-10-21: said so\n---\nBody.\n",
				["pickman/skills/pickman-other/SKILL.md"] = skillDoc("pickman-other", nil, "OTHER-RULES"),
				["pickman/skills/pickman-other/lessons/other.md"] = "---\ntitle: Other lesson\nwhen: build\ntags: [x]\ncheck: Is it another?\nfrom: user 2026-10-21: said so\n---\nBody.\n",
			})
			local r = trackerfix.tr(f, f.main, { "ready", "R0030" })
			t.expect(r.ok).toBe(true)
			local prompt = fs.readFile(`{f.main}/snake/.tracker/rafts/active/R0030/prompt.md`)
			local order: { string } = {}
			local from = string.find(prompt, "\n## Skills", 1, true) :: number
			for path in string.gmatch(string.sub(prompt, from), "`([^`]+)`") do
				if string.find(path, "/SKILL.md", 1, true) then
					table.insert(order, path)
				end
			end
			-- z-nile's five, then snake's own, then the base: pickman-play, once, and not pickman's other skill
			t.expect(order[#order - 1]).toBe("snake/skills/snake-arch/SKILL.md")
			t.expect(order[#order]).toBe("pickman/skills/pickman-play/SKILL.md")
			t.expect(#order).toBe(7)
			t.expect(string.find(prompt, "PLAY-RULES", 1, true) == nil).toBe(true) -- the skill is named, not pasted
			t.expect(string.find(prompt, "pickman-play/feel", 1, true) == nil).toBe(true) -- lessons are not listed
			t.expect(string.find(prompt, "pickman-other", 1, true) == nil).toBe(true) -- another pickman skill is not named
			fs.removeDir(`{HERE}/.cache/c0184-prompt`)
		end
	)
end)
