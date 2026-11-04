--!strict
-- c0165 AC10: the words for the core. zz-test describes fingerprints, reuse, declared inputs and the db writer;
-- AGENTS.md names the db among what writes the main checkout; .gitignore ignores it. Which step runs the affected or
-- the full gate is c0239's wording, not pinned here. The sentences are the Design's "Wording" list. Read from the
-- checkout's top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function says(rel: string, line: string)
	if string.find(read(rel), line, 1, true) == nil then
		error(`{rel} does not say: {line}`)
	end
end

return t.spec("c0165 reuse wording", function(it)
	it("AC10: zz-test describes reuse, declared inputs, --fresh and the db writer", function()
		local f = "z-nile/skills/zz-test/SKILL.md"
		says(f, "| `z-nile/check.sh --affected --fresh` | the affected gate without reuse |")
		says(
			f,
			"**Reuse**: in an affected run, a spec file whose fingerprint (its own content, everything it can reach, the tools and the gate mode) already passed is skipped and reported `reused <spec>`, and a whole affected gate that passed on the same content is skipped with its stored static report. `--fresh` reuses nothing and `--full` runs every spec. Passes are kept in `.claude/.znile_tests.sqlite`; deleting it only costs reruns."
		)
		says(
			f,
			"**Declared inputs**: a spec that reads files or git state outside its requires declares them in its home's `tests/inputs.tsv`, one `<spec>\\t<file, folder/, *, or ref:refs/...>` line each; `*` covers every blob plus HEAD and `ref:` adds one named ref. A path under a project root is allowed only below it, never the root itself or a `spend.md`. A spec that reads the files of every registered project (it loops the registry, itself or through a spec, wrapper or helper it runs) declares `*`, or, when it takes over 2 s idle, a line for each registered project; registering a project adds those lines."
		)
		says(
			f,
			"the gate's results db (`.claude/.znile_tests.sqlite` in the main checkout, written by `z-nile/specs` outside the jail)"
		)
	end)

	-- R73: the rule is a rule, not today's set of projects. The two registry specs that take over 2 s keep a line per
	-- registered project; registering a project without adding its two lines turns this red.
	it(
		"AC10: z-nile's inputs.tsv holds both tracker folders of every registered project for the two slow registry specs",
		function()
			local reg = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" }, { cwd = root })
			t.expect(reg.ok).toBe(true)
			local have: { [string]: boolean } = {}
			for line in string.gmatch(read("z-nile/tests/inputs.tsv"), "[^\n]+") do
				have[line] = true
			end
			local missing: { string } = {}
			local projects = 0
			for line in string.gmatch(reg.stdout, "[^\n]+") do
				local trackerRoot = string.match(line, "^[^\t]+\t[^\t]+\t([^\t]+)$")
				if trackerRoot then
					projects += 1
					for _, spec in { "c0114/classified", "c0042/cli" } do
						for _, kind in { "issues/", "rafts/" } do
							local want = `tests/acceptance/{spec}.spec.luau\t{trackerRoot}/{kind}`
							if not have[want] then
								table.insert(missing, want)
							end
						end
					end
				end
			end
			t.expect(projects > 1).toBe(true)
			t.expect(table.concat(missing, "\n")).toBe("")
		end
	)

	it("AC10: AGENTS.md names the db and .gitignore ignores it", function()
		-- AGENTS.md names the db in its list of what writes the main checkout
		local agents = read("AGENTS.md")
		local line = string.match(agents, "[^\n]*the main checkout is never edited[^\n]*") or ""
		t.expect(
			string.find(line, "and the gate writes its results db, `.claude/.znile_tests.sqlite`", 1, true)
				~= nil
		).toBe(true)
		-- ignored, sidecars included, and git agrees
		local ignore = read(".gitignore")
		t.expect(string.find(ignore, "\n/.claude/.znile_tests.sqlite*\n", 1, true) ~= nil).toBe(true)
		for _, name in
			{
				".claude/.znile_tests.sqlite",
				".claude/.znile_tests.sqlite-wal",
				".claude/.znile_tests.sqlite-shm",
			}
		do
			local r = process.exec("git", { "check-ignore", "-q", "--no-index", name }, { cwd = root })
			t.expect(r.ok).toBe(true)
		end
	end)
end)
