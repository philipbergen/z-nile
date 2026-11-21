--!strict
-- f0422: the tributary file: its parser, every problem its check names, the counts, and (on the real tracker) that
-- every project's file lists each of its units exactly once, so the gate fails when someone adds a unit and lists it
-- nowhere.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local tributaries = require("@znile/engine/tributaries")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function parsed(text: string): { tributaries.Tributary }
	local list, problem = tributaries.parse(text)
	if not list then
		error(problem or "no list", 0)
	end
	return list
end

local function tr(name: string, units: { string }): tributaries.Tributary
	return { name = name, purpose = "Why.", units = units }
end

local function has(list: { string }, needle: string): boolean
	for _, line in list do
		if string.find(line, needle, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("tributaries", function(it)
	it("parse reads the ordered list with name, purpose and units", function()
		local list = parsed(
			'[[tributary]]\nname = "worker"\npurpose = "Carries work."\nunits = ["R0100", "f0420"]\n\n[[tributary]]\nname = "lessons"\npurpose = "Learns."\nunits = []\n'
		)
		t.expect(#list).toBe(2)
		t.expect(list[1].name).toBe("worker")
		t.expect(list[1].purpose).toBe("Carries work.")
		t.expect(list[1].units).toEqual({ "R0100", "f0420" })
		t.expect(list[2].name).toBe("lessons")
		t.expect(parsed("")).toEqual({})
	end)

	it("parse names an invalid file, an unknown key and a value of the wrong shape", function()
		local _, bad = tributaries.parse("[[tributary")
		t.expect(bad ~= nil and string.find(bad, "not valid TOML", 1, true) ~= nil).toBe(true)
		local _, top = tributaries.parse("stray = 1\n")
		t.expect(top ~= nil and string.find(top, "unknown key stray", 1, true) ~= nil).toBe(true)
		local _, key =
			tributaries.parse('[[tributary]]\nname = "a"\npurpose = "p"\nunits = []\ncolor = "red"\n')
		t.expect(key ~= nil and string.find(key, "unknown key color", 1, true) ~= nil).toBe(true)
		local _, noName = tributaries.parse('[[tributary]]\npurpose = "p"\nunits = []\n')
		t.expect(noName ~= nil and string.find(noName, "needs a name", 1, true) ~= nil).toBe(true)
		local _, units = tributaries.parse('[[tributary]]\nname = "a"\npurpose = "p"\nunits = [1]\n')
		t.expect(units ~= nil and string.find(units, "not a string", 1, true) ~= nil).toBe(true)
		local _, shape = tributaries.parse('tributary = "a"\n')
		t.expect(shape ~= nil and string.find(shape, "list of [[tributary]]", 1, true) ~= nil).toBe(true)
	end)

	it("check passes when every unit is listed once", function()
		t.expect(
			tributaries.check(
				{ tr("a", { "R0010", "c0020" }), tr("b", { "c0030" }) },
				{ "R0010", "c0020", "c0030" }
			)
		).toEqual({})
	end)

	it("check names a unit listed in no tributary, in two, and twice in one", function()
		local problems = tributaries.check(
			{ tr("a", { "R0010", "R0010", "c0020" }), tr("b", { "c0020" }) },
			{ "R0010", "c0020", "c0030" }
		)
		t.expect(has(problems, "c0030 is listed in no tributary")).toBe(true)
		t.expect(has(problems, "c0020 is listed in two tributaries: a and b")).toBe(true)
		t.expect(has(problems, "R0010 is listed twice in tributary a")).toBe(true)
		t.expect(#problems).toBe(3)
	end)

	it("check names an id that is no unit: unknown, or an issue that is in a raft", function()
		local problems = tributaries.check(
			{ tr("a", { "R0010", "c0099", "c0011" }) },
			{ "R0010" },
			{ c0011 = "R0010" }
		)
		t.expect(has(problems, "c0099 is not a raft or raftless issue of this project (tributary a)"))
			.toBe(true)
		t.expect(has(problems, "c0011 is in raft R0010")).toBe(true)
		t.expect(#problems).toBe(2)
	end)

	it(
		"check names a duplicate name, an empty name, a bad name, a list word and a missing purpose",
		function()
			local problems = tributaries.check({
				tr("a", { "R0010" }),
				tr("a", {}),
				tr("", {}),
				tr("Bad Name", {}),
				tr("done", {}),
				{ name = "nope", purpose = "  ", units = {} },
			}, { "R0010" })
			t.expect(has(problems, "tributary a is named twice")).toBe(true)
			t.expect(has(problems, "an empty name")).toBe(true)
			t.expect(has(problems, "tributary Bad Name: a name is lowercase words")).toBe(true)
			t.expect(has(problems, "tributary done is named like a list word")).toBe(true)
			t.expect(has(problems, "tributary nope has no purpose")).toBe(true)
			for _, word in { "backlog", "active", "done", "closed" } do
				t.expect(has(tributaries.check({ tr(word, {}) }, {}), "named like a list word")).toBe(true)
			end
		end
	)

	it(
		"counts sorts each tributary's units into done, in flight, waiting and not started, in file order",
		function()
			local rows = tributaries.counts(
				{ tr("b", { "x1", "x2", "gone" }), tr("a", { "y1", "y2", "y3" }) },
				{ x1 = "done", x2 = "flight", y1 = "waiting", y2 = "open", y3 = "open" }
			)
			t.expect(rows[1])
				.toEqual({ name = "b", purpose = "Why.", done = 1, inFlight = 1, waiting = 0, notStarted = 0 })
			t.expect(rows[2])
				.toEqual({ name = "a", purpose = "Why.", done = 0, inFlight = 0, waiting = 1, notStarted = 2 })
		end
	)

	it("audit.tributaries asks each project root for a tributaries.toml that lists its units once", function()
		local dir = ".cache/tributaries-audit"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/z-nile`)
		fs.writeFile(`{dir}/z-nile/projects.toml`, '[[project]]\nname = "demo"\nroot = "demo/.tracker"\n')
		local function item(path: string, id: string, front: string)
			fs.writeDir(`{dir}/demo/.tracker/{path}`)
			fs.writeFile(
				`{dir}/demo/.tracker/{path}/{id}.md`,
				`---\nid: {id}\nslug: s\n{front}\n---\n\n# {id}\n`
			)
		end
		item("rafts/R0010", "R0010", "type: chore")
		item("issues/c0010", "c0010", "type: chore\nraft: R0010")
		item("issues/c0020", "c0020", "type: chore")
		item("issues/done/c0030", "c0030", "type: chore\nstatus: done")
		local function tribProblems(): { string }
			local out = {}
			for _, p in audit.tributaries(dir) do
				table.insert(out, audit.format(p))
			end
			return out
		end
		local missing = tribProblems()
		t.expect(#missing).toBe(1)
		t.expect(has(missing, "error tributaries-missing demo/.tracker/tributaries.toml")).toBe(true)
		fs.writeFile(
			`{dir}/demo/.tracker/tributaries.toml`,
			'[[tributary]]\nname = "one"\npurpose = "P."\nunits = ["R0010", "c0020"]\n'
		)
		local unlisted = tribProblems()
		t.expect(#unlisted).toBe(1)
		t.expect(has(unlisted, "c0030 is listed in no tributary")).toBe(true) -- a done unit counts; c0010 is R0010's
		fs.writeFile(
			`{dir}/demo/.tracker/tributaries.toml`,
			'[[tributary]]\nname = "one"\npurpose = "P."\nunits = ["R0010", "c0020", "c0030", "c0010"]\n'
		)
		local member = tribProblems()
		t.expect(#member).toBe(1)
		t.expect(has(member, "c0010 is in raft R0010")).toBe(true)
		fs.writeFile(
			`{dir}/demo/.tracker/tributaries.toml`,
			'[[tributary]]\nname = "one"\npurpose = "P."\nunits = ["R0010", "c0020", "c0030"]\n'
		)
		t.expect(tribProblems()).toEqual({})
		fs.removeDir(dir)
	end)

	it(
		"the real tracker's tributary files list every unit once, so an unlisted new unit fails the gate",
		function()
			local found = {}
			for _, p in audit.run(TOP) do
				if string.sub(p.code, 1, 11) == "tributaries" then
					table.insert(found, audit.format(p))
				end
			end
			t.expect(found).toEqual({})
			t.expect(fs.isFile(`{TOP}/z-nile/.tracker/tributaries.toml`)).toBe(true)
		end
	)

	it("list <tributary> prints only that tributary's units, and the old words keep their meaning", function()
		local function list(args: { string }): { string }
			local r = process.exec("scripts/tracker.sh", args, { cwd = TOP })
			local lines = {}
			for line in string.gmatch(r.stdout, "[^\n]+") do
				table.insert(lines, line)
			end
			return lines
		end
		local file = parsed(fs.readFile(`{TOP}/z-nile/.tracker/tributaries.toml`))
		local worker: { string } = {}
		for _, one in file do
			if one.name == "worker" then
				worker = one.units
			end
		end
		t.expect(#worker > 0).toBe(true)
		local inList: { [string]: boolean } = {}
		for _, id in worker do
			inList[id] = true
		end
		local lines = list({ "list", "worker", "--project", "z-nile" })
		t.expect(#lines).toBe(#worker)
		for _, line in lines do
			t.expect(inList[string.match(line, "^(%S+)") or ""]).toBe(true)
		end
		for _, line in list({ "list", "done", "--project", "z-nile" }) do
			t.expect(string.match(line, "^%S+%s+done%s") ~= nil).toBe(true)
		end
		t.expect(#list({ "list", "nonesuch", "--project", "z-nile" })).toBe(0)
	end)
end)
