--!strict
-- c0136 AC3: `./zn lessons --unattributed [<id>...]` lists the harvest entries that name no step (exit 1) and
-- passes when every entry names one (exit 0); `--uncovered` and `--check` see stream and focused reviews; the
-- filing rule and the reviewer's-lines rule fail `--check` by file and finding. Fixture under .cache/c0136-cli
-- (tests/lib/trackerfix): the fixture's own tracker commands run in its own repository; nothing else is written.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end
local function lesson(check: string): string
	return `---\ntitle: A lesson\nwhen: both\ntags: [wiring]\ncheck: {check}\nfrom: a user\n---\nBody.\n`
end
local function review(...: string): string
	local out = "# Review 001\n\n"
	for _, f in { ... } do
		out ..= `### {f} [low] claim\nEvidence: x\n`
		out ..= "Erred: z-design\nUpstream: none\n\n"
	end
	return out .. "Verdict: changes\n"
end
local function plain(...: string): string
	local out = "# Review 001\n\n"
	for _, f in { ... } do
		out ..= `### {f} [low] claim\nEvidence: x\n\n`
	end
	return out .. "Verdict: changes\n"
end

local R10 = "pickman/.tracker/rafts/R0010"
local SEED: { [string]: string } = {
	["z-nile/skills/zz-test/SKILL.md"] = skill("zz-test"),
	["z-nile/skills/z-design/SKILL.md"] = skill("z-design"),
	["z-nile/skills/zz-execute/SKILL.md"] = skill("zz-execute"),
	["z-nile/skills/zz-test/lessons/pin-inputs.md"] = lesson("Are the call site's inputs pinned?"),
	["z-nile/skills/z-design/lessons/lifetimes.md"] = lesson("Which process outlives which?"),
	[`{R10}/design-review-001.md`] = review("F1", "F2"),
	[`{R10}/review-001.md`] = plain("F1"),
	[`{R10}/stream-review-c0010-001.md`] = plain("F1"),
	[`{R10}/focused-review-001.md`] = (
		string.gsub(plain("F1"), "# Review 001", "# Review 001: R0010 (focused mode, build)", 1)
	),
	[`{R10}/harvest.md`] = "# Harvest: R0010\n\n- design-review-001 F1 (erred z-design): z-design/lifetimes\n"
		.. "- design-review-001 F2 (erred z-design): z-design/lifetimes\n"
		.. "- review-001 F1: zz-test/pin-inputs\n" -- written before the group existed
		.. "- note the fixture seeded one state (erred zz-test): zz-test/pin-inputs\n"
		.. "- note told so by the user: z-design/lifetimes\n",
	-- an item whose every entry names its step, one with no reviews, one with an entry for a finding left bare
	["pickman/.tracker/rafts/R0030/design-review-001.md"] = review("F1"),
	["pickman/.tracker/rafts/R0030/harvest.md"] = "- design-review-001 F1 (erred z-design): z-design/lifetimes\n",
	["pickman/.tracker/rafts/R0060/R0060.md"] = "# R0060\n",
}

local f: trackerfix.Fixture
local function run(args: { string }): (number, string, string)
	local argv = { "lessons" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = trackerfix.tr(f, f.main, argv)
	return r.code, r.stdout, r.stderr
end
local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0136 tracker lessons --unattributed", function(it)
	it("sets up a tracker fixture with attributed and legacy entries", function()
		f = trackerfix.new("c0136-cli", SEED, { noLessons = true })
	end)

	it("lists every entry and note that names no step, and exits 1", function()
		local code, out = run({ "--unattributed" })
		t.expect(code).toBe(1)
		t.expect(lines(out)).toEqual({ "R0010 review-001 F1", "R0010 note told so by the user" })
	end)

	it("takes item ids like --uncovered does", function()
		local one, oneOut = run({ "--unattributed", "R0010" })
		t.expect(one).toBe(1)
		t.expect(lines(oneOut)).toEqual({ "R0010 review-001 F1", "R0010 note told so by the user" })
		local ok, okOut = run({ "--unattributed", "R0030" })
		t.expect(ok).toBe(0)
		t.expect(has(okOut, "harvest: every entry names its step")).toBe(true)
		local bare, bareOut = run({ "--unattributed", "R0060" })
		t.expect(bare).toBe(0)
		t.expect(has(bareOut, "R0060: no reviews")).toBe(true)
		local missing, _, missingErr = run({ "--unattributed", "R0099" })
		t.expect(missing).toBe(2)
		t.expect(has(missingErr, "R0099: no such item")).toBe(true)
	end)

	it("refuses to mix with another mode or option, with exit 2 and the usage line", function()
		for _, args in
			{
				{ "--unattributed", "--full" },
				{ "--unattributed", "--check" },
				{ "--unattributed", "--uncovered" },
				{ "--unattributed", "--tag", "x" },
			}
		do
			local code, _, err = run(args)
			if code ~= 2 then
				error(`lessons {table.concat(args, " ")} exited {code}`)
			end
			t.expect(has(err, "--unattributed")).toBe(true)
		end
	end)

	it("--uncovered lists the stream review's and the focused review's findings", function()
		local code, out = run({ "--uncovered", "R0010" })
		t.expect(code).toBe(1)
		t.expect(lines(out)).toEqual({ "R0010 focused-review-001 F1", "R0010 stream-review-c0010-001 F1" })
	end)

	it("--check passes the tree (attributed and legacy entries together)", function()
		local code, out = run({ "--check" })
		t.expect(code).toBe(0)
		t.expect(has(out, "ok")).toBe(true)
	end)

	it(
		"--check names a lesson filed under a step the line does not name, and a line the reviewer contradicts",
		function()
			local h = `{f.main}/{R10}/harvest.md`
			local before = fs.readFile(h)
			fs.writeFile(h, before .. "- focused-review-001 F1 (erred z-design): zz-test/pin-inputs\n")
			local code, out = run({ "--check" })
			t.expect(code).toBe(1)
			t.expect(
				has(
					out,
					"R0010/harvest.md: focused-review-001 F1: lesson zz-test/pin-inputs is filed under zz-test"
				)
			).toBe(true)
			fs.writeFile(h, before .. "- stream-review-c0010-001 F1 (erred zz-test): zz-test/pin-inputs\n")
			local ok = run({ "--check" })
			t.expect(ok).toBe(0) -- a stream review that gives no lines has nothing to contradict
			local swapped = string.gsub(
				before,
				"design%-review%-001 F2 %(erred z%-design%)",
				"design-review-001 F2 (erred zz-test)"
			)
			fs.writeFile(h, swapped)
			local bad, badOut = run({ "--check" })
			t.expect(bad).toBe(1)
			t.expect(
				has(
					badOut,
					"design-review-001 F2: the line says (erred zz-test) but design-review-001.md F2 says Erred: z-design"
				)
			).toBe(true)
			fs.writeFile(h, before)
		end
	)
	it(
		"--check-review reads one review file wherever it is, names each problem and writes nothing",
		function()
			local dir = `{f.base}/dispatch-state` -- outside the fixture's checkout, as a dispatcher's state folder is
			fs.writeDir(dir)
			local function write(name: string, body: string): string
				local path = `{dir}/{name}`
				fs.writeFile(
					path,
					`# Review 001\n\n### F1 [low] a claim\nEvidence: x\n{body}\nVerdict: changes\n`
				)
				return path
			end
			local good = write("review-001.md", "Erred: z-design\nUpstream: none\n")
			local code, out = run({ "--check-review", good })
			t.expect(code).toBe(0)
			t.expect(has(out, "step lines ok")).toBe(true)
			local typo = write("review-002.md", "Erred: z-desgin\nUpstream: none\n")
			local c2, o2 = run({ "--check-review", typo })
			t.expect(c2).toBe(1)
			t.expect(has(o2, `{typo} F1: Erred: no skill z-desgin`)).toBe(true)
			local half = write("review-003.md", "Erred: z-design\n")
			local c3, o3 = run({ "--check-review", half })
			t.expect(c3).toBe(1)
			t.expect(has(o3, "F1: write both Erred: and Upstream:")).toBe(true)
			local focused = write("focused-review-001.md", "Erred: z-design\nUpstream: none\n")
			local c4, o4 = run({ "--check-review", focused })
			t.expect(c4).toBe(1)
			t.expect(has(o4, "the heading must say (focused mode, design)")).toBe(true)
			-- a new review with a finding and no step lines is refused, bolded lines included; an approving round passes
			local lineless = write("review-004.md", "")
			local c6, o6 = run({ "--check-review", lineless })
			t.expect(c6).toBe(1)
			t.expect(has(o6, "no step lines")).toBe(true)
			local bold = write("review-005.md", "**Erred:** z-design\n- Upstream: none\n")
			t.expect((run({ "--check-review", bold }))).toBe(1)
			fs.writeFile(`{dir}/review-006.md`, "# Review 006\n\nVerdict: approve\n")
			t.expect((run({ "--check-review", `{dir}/review-006.md` }))).toBe(0)
			-- a focused text saved under the dispatcher's name is judged by its own heading
			fs.writeFile(
				`{dir}/review.md`,
				"# Review 001: c0010 (focused mode)\n\n### F1 [low] c\nErred: z-design\nUpstream: none\n"
			)
			local c7, o7 = run({ "--check-review", `{dir}/review.md` })
			t.expect(c7).toBe(1)
			t.expect(has(o7, "the heading must say (focused mode, design)")).toBe(true)
			local before = fs.readFile(typo)
			local c5, _, e5 = run({ "--check-review", `{dir}/gone.md` })
			t.expect(c5).toBe(2)
			t.expect(has(e5, "no such file")).toBe(true)
			for _, args in
				{
					{ "--check-review", good, "--check" },
					{ "--check-review", good, "--full" },
					{ "--check-review" },
				}
			do
				local c = run(args)
				if c ~= 2 then
					error(`lessons {table.concat(args, " ")} exited {c}`)
				end
			end
			t.expect(fs.readFile(typo)).toBe(before)
		end
	)
end)
