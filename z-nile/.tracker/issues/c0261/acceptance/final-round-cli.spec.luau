--!strict
-- c0261 ("Commands refuse"): `./zn status <id> prepared` refuses an item whose last design review round was recorded on
-- a model that is not of a final-review kind, and goes on once a row for that round is. The rows are this checkout's
-- (./zn spend commits them in spend.d on the branch; a row the dispatcher published arrives with ./zn sync), the model
-- is judged by kind (a new Opus id passes), and a repository whose base has no root .models.toml holds no round to it. Fixture under .cache/c0261-final-round
-- (tests/lib/trackerfix): a clone with an origin, whose seed commit holds the engine, finalround.luau included.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REVIEW = "# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\n"
	.. "Recommendation: d\n\nVerdict: approve\n"
local MODELS =
	'order = ["claude"]\n[zz-review.claude]\nmodel = "claude-opus-5-5"\nrank = 4\nruntime = "claude-cli"\nmax_tokens = 9\n'

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function designReady(path: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, "\ndesign: draft\n", 1, true)
	assert(s and e, "design: line")
	fs.writeFile(path, string.sub(text, 1, s) .. "design: ready\n" .. string.sub(text, e + 1))
end

return t.spec("c0261 status prepared refuses a last design round not on a final-review model", function(it)
	it(
		"refuses a Sonnet last round, naming the round; a retry row on a new Opus id lets it through (AC11)",
		function()
			local f = trackerfix.new("c0261-final-round", nil)
			-- the base holds a root .models.toml: the repository has final-review models to hold a round to
			fs.writeFile(`{f.main}/.models.toml`, MODELS)
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-q", "-m", "models" })
			fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
			trackerfix.trOk(f, wt, { "sync" })
			local id = string.match(
				trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			trackerfix.trOk(f, wt, { "status", id, "preparing" })
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
			designReady(`{dir}/{id}.md`)
			local function spend(model: string)
				trackerfix.trOk(f, wt, {
					"spend",
					id,
					"--phase",
					"design-review",
					"--model",
					model,
					"--note",
					"design-review-001",
				})
			end
			spend("claude-sonnet-5-5-high")
			t.expect(fs.isDir(`{dir}/spend.d`)).toBe(true) -- the measured row is this branch's: that is where the check reads
			local refused = trackerfix.tr(f, wt, { "status", id, "prepared" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stdout .. refused.stderr, "design-review-001")).toBe(true)
			t.expect(has(refused.stdout .. refused.stderr, "final-review model")).toBe(true)
			t.expect(has(refused.stdout .. refused.stderr, "model claude-sonnet-5-5-high")).toBe(true)
			-- the round re-run on a model of the kind, recorded under the same name: any exact row on one is enough
			spend("claude-opus-6-1-high")
			trackerfix.trOk(f, wt, { "status", id, "prepared" })
			t.expect(string.match(fs.readFile(`{dir}/{id}.md`), "\nstatus: prepared%-%a+%-%a+%-%a+\n") ~= nil)
				.toBe(true)
		end
	)

	it(
		"a row with no model, or only a longer name that contains the round's, is refused; no root .models.toml holds nothing (AC11)",
		function()
			local f = trackerfix.new("c0261-final-round-b", nil)
			fs.writeFile(`{f.main}/.models.toml`, MODELS)
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-q", "-m", "models" })
			fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
			trackerfix.trOk(f, wt, { "sync" })
			local id = string.match(
				trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			trackerfix.trOk(f, wt, { "status", id, "preparing" })
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
			designReady(`{dir}/{id}.md`)
			trackerfix.trOk(f, wt, {
				"spend",
				id,
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
			})
			local none = trackerfix.tr(f, wt, { "status", id, "prepared" })
			t.expect(none.ok).toBe(false)
			t.expect(has(none.stdout .. none.stderr, "no model")).toBe(true)
			-- an Opus row whose note only contains the round's name is not the round's row
			trackerfix.trOk(f, wt, {
				"spend",
				id,
				"--phase",
				"design-review",
				"--model",
				"claude-opus-5-5",
				"--note",
				"design-review-001 answers",
			})
			t.expect(trackerfix.tr(f, wt, { "status", id, "prepared" }).ok).toBe(false)
			-- a repository whose base has no root .models.toml has no final-review models to hold a round to
			local g = trackerfix.new("c0261-final-round-c", nil)
			local wg = trackerfix.trOk(g, g.main, { "worktree", "prep-solo" })
			trackerfix.trOk(g, wg, { "sync" })
			local gid = string.match(
				trackerfix.trOk(g, wg, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			trackerfix.trOk(g, wg, { "status", gid, "preparing" })
			local gdir = `{wg}/pickman/.tracker/issues/{gid}`
			fs.writeFile(`{gdir}/design-review-001.md`, REVIEW)
			designReady(`{gdir}/{gid}.md`)
			trackerfix.trOk(g, wg, { "status", gid, "prepared" })
		end
	)

	it("an issue with no design review round at all is refused when the rule binds (AC11)", function()
		local f = trackerfix.new("c0261-final-round-d", nil)
		fs.writeFile(`{f.main}/.models.toml`, MODELS)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "models" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		trackerfix.trOk(f, wt, { "status", id, "preparing" })
		designReady(`{wt}/pickman/.tracker/issues/{id}/{id}.md`)
		local r = trackerfix.tr(f, wt, { "status", id, "prepared" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "has no design review round")).toBe(true)
	end)

	it(
		"the cutoff reads the rows' own dates: a model-less round dated before the landing passes, one dated after is refused (AC11)",
		function()
			local f = trackerfix.new("c0261-final-round-e", nil)
			fs.writeFile(`{f.main}/.models.toml`, MODELS)
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-q", "-m", "models" })
			fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
			trackerfix.trOk(f, wt, { "sync" })
			local id = string.match(
				trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			trackerfix.trOk(f, wt, { "status", id, "preparing" })
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
			designReady(`{dir}/{id}.md`)
			local function rowDated(when: string): string
				return ledger.render(id, id, {
					{
						when = when,
						subject = "design-review-001",
						added = 0,
						removed = 0,
						minutes = 1,
						how = "x",
						phase = "design-review",
						tokens = 5,
						model = nil,
					} :: any,
				})
			end
			local spendPath = `pickman/.tracker/issues/{id}/spend.md`
			-- reviewed long before the rule landed, with no model recorded: not locked out
			trackerfix.elsewhere(f, { [spendPath] = rowDated("2020-01-01 00:00") }, "old round")
			-- the row is only on origin/main (the dispatcher published it): refused with the sync hint until ./zn sync
			local unsynced = trackerfix.tr(f, wt, { "status", id, "prepared" })
			t.expect(unsynced.ok).toBe(false)
			t.expect(has(unsynced.stdout .. unsynced.stderr, "./zn sync")).toBe(true)
			trackerfix.trOk(f, wt, { "sync" })
			trackerfix.trOk(f, wt, { "status", id, "prepared" })
		end
	)

	it("a model-less round dated after the landing is refused (AC11)", function()
		local f = trackerfix.new("c0261-final-round-f", nil)
		fs.writeFile(`{f.main}/.models.toml`, MODELS)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "models" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		trackerfix.trOk(f, wt, { "status", id, "preparing" })
		local dir = `{wt}/pickman/.tracker/issues/{id}`
		fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
		designReady(`{dir}/{id}.md`)
		local text = ledger.render(id, id, {
			{
				when = "2099-01-01 00:00",
				subject = "design-review-001",
				added = 0,
				removed = 0,
				minutes = 1,
				how = "x",
				phase = "design-review",
				tokens = 5,
				model = nil,
			} :: any,
		})
		trackerfix.elsewhere(f, { [`pickman/.tracker/issues/{id}/spend.md`] = text }, "new round")
		trackerfix.trOk(f, wt, { "sync" })
		local r = trackerfix.tr(f, wt, { "status", id, "prepared" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "no model")).toBe(true)
	end)
end)
