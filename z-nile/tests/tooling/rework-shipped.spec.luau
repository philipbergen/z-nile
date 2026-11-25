--!strict
-- f0450: rework counts only defects that ship. A defect names what it fixes (`fixes:`); it counts when any of those
-- was done on or before the day the defect was captured. A defect with no `fixes:` is listed and counted. The pure
-- rules (engine/rework), the printed lines of `./zn metrics` over a fixture with git history, `./zn audit` on a
-- `fixes:` id that names nothing, and `./zn new issue d --fixes`. Fixtures under .cache/f0450-*.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local rework = require("@znile/engine/rework")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local top = engine.TOP

local function write(base: string, rel: string, text: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{base}/{rel}`, text)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local DONE = { f1 = "2026-02-01", R2 = "2026-02-05" }

return t.spec("rework counts shipped defects (f0450)", function(it)
	it("reads the ids a defect fixes from its frontmatter, issues and rafts alike", function()
		t.expect(rework.fixesOf({ fixes = "[f0033, R0044]" })).toEqual({ "f0033", "R0044" })
		t.expect(rework.fixesOf({})).toEqual({})
		t.expect(rework.fixesOf({ fixes = "[]" })).toEqual({})
	end)

	it("dates a fixed id by its issue day, else by its raft's instant (a UTC day)", function()
		local days = rework.doneDays({ f0001 = "2026-02-01" }, { R0002 = 1770249600, f0001 = 1 })
		t.expect(days.f0001).toBe("2026-02-01")
		t.expect(days.R0002).toBe("2026-02-05")
	end)

	it("a defect whose fixed ticket was done on or before its capture day is shipped", function()
		local got = rework.classify({
			{ id = "d1", created = "2026-02-10", fixes = { "f1" } },
			{ id = "d2", created = "2026-02-01", fixes = { "f1" } },
		}, { f1 = "2026-02-01" })
		t.expect(got[1].class).toBe("shipped")
		t.expect(got[2].class).toBe("shipped") -- the same day counts: the stricter reading
	end)

	it("a defect found before the work it fixes was done, or whose work is not done, is open", function()
		local got = rework.classify({
			{ id = "d1", created = "2026-01-31", fixes = { "f1" } },
			{ id = "d2", created = "2026-02-10", fixes = { "f9" } },
		}, DONE)
		t.expect(got[1].class).toBe("open")
		t.expect(got[2].class).toBe("open")
	end)

	it("one fixed ticket done first is enough", function()
		local got = rework.classify({ { id = "d1", created = "2026-02-10", fixes = { "f9", "R2" } } }, DONE)
		t.expect(got[1].class).toBe("shipped")
	end)

	it("a defect that records nothing is unrecorded, and a missing capture day counts", function()
		local got = rework.classify({
			{ id = "d1", created = "2026-02-10", fixes = {} },
			{ id = "d2", fixes = { "f9" } },
		}, DONE)
		t.expect(got[1].class).toBe("unrecorded")
		t.expect(got[2].class).toBe("shipped")
	end)

	it("a ruled defect is dropped, whatever else it records", function()
		local got = rework.classify({
			{ id = "d1", created = "2026-02-10", fixes = { "f1" }, ruled = true },
			{ id = "d2", created = "2026-02-10", fixes = {}, ruled = true },
			{ id = "d3", created = "2026-02-10", fixes = { "f1" }, ruled = false },
		}, DONE)
		t.expect(got[1].class).toBe("ruled")
		t.expect(got[2].class).toBe("ruled")
		t.expect(got[3].class).toBe("shipped")
	end)

	it('shipped: no is honoured only beside a Ruled (user, date): "words" line', function()
		local ruling = '# d\n\nRuled (user, 2026-11-24): "they do not count"\n'
		t.expect(rework.hasRuling(ruling)).toBe(true)
		t.expect(rework.hasRuling('Ruled (user, 2026-11-24): ""\n')).toBe(false)
		t.expect(rework.hasRuling('Ruled (user, 24-11-2026): "x"\n')).toBe(false)
		t.expect(rework.hasRuling('a note: Ruled (user, 2026-11-24): "x" inline\n')).toBe(false)
		t.expect(rework.isRuled({ shipped = "no" }, ruling)).toBe(true)
		t.expect(rework.isRuled({ shipped = "no" }, "# d\n")).toBe(false)
		t.expect(rework.isRuled({}, ruling)).toBe(false)
		t.expect(rework.isRuled({ shipped = "yes" }, ruling)).toBe(false)
		t.expect(rework.keyIgnored({ shipped = "no" }, "# d\n")).toBe(true)
		t.expect(rework.keyIgnored({ shipped = "no" }, ruling)).toBe(false)
		t.expect(rework.keyIgnored({}, "# d\n")).toBe(false)
	end)

	it("with no readable history every defect that records a fix counts", function()
		local got = rework.classify({ { id = "d1", created = "2026-02-10", fixes = { "f9" } } }, nil)
		t.expect(got[1].class).toBe("shipped")
	end)

	it("the lines divide shipped defects by shipped defects plus features and show the old figure", function()
		local rows: { rework.Row } = {
			{ id = "f1", type = "feature", added = 100, minutes = 10 },
			{ id = "f2", type = "feature", added = 100, minutes = 10 },
			{ id = "d1", type = "defect", added = 50, minutes = 5 },
			{ id = "d2", type = "defect", added = 30, minutes = 3 },
			{ id = "d3", type = "defect", added = 20, minutes = 2 },
			{ id = "d4", type = "defect", added = 10, minutes = 1 },
			{ id = "c1", type = "chore", added = 999, minutes = 99 },
		}
		local verdicts: { rework.Verdict } = {
			{ id = "d1", class = "shipped", fixes = { "f1" } },
			{ id = "d2", class = "open", fixes = { "f9" } },
			{ id = "d3", class = "unrecorded", fixes = {} },
			{ id = "d4", class = "ruled", fixes = {} },
		}
		local out = table.concat(rework.lines(rows, verdicts, true), "\n")
		t.expect(has(out, "Rework = shipped defects / (shipped defects + features). Target: under 20%."))
			.toBe(true)
		t.expect(has(out, "Rework counts every phase, capture to deliver.")).toBe(true)
		t.expect(has(out, "by lines added:  25.9%")).toBe(true) -- 70 / 270
		t.expect(has(out, "by issues:       50.0%")).toBe(true) -- 2 / 4
		t.expect(has(out, "by agent time:   25.9%")).toBe(true) -- 7 / 27
		t.expect(has(out, "all defects, shipped or not")).toBe(true)
		t.expect(has(out, "by lines added 35.5%, by issues 66.7%, by agent time 35.5%")).toBe(true)
		t.expect(
			has(
				out,
				"defects not counted, the work they fix was still open when they were captured: 1: d2 (fixes f9)"
			)
		).toBe(true)
		t.expect(has(out, "defects with no fixed ticket recorded: 1: d3")).toBe(true)
	end)

	it("reads the first day of a first-parent log, and nothing from an empty one", function()
		t.expect(rework.firstDay("2026-02-05T12:00:00+00:00\n2026-03-01T01:00:00+00:00\n")).toBe("2026-02-05")
		t.expect(rework.firstDay("")).toBe(nil)
		t.expect(rework.firstDay("\n  \n")).toBe(nil)
	end)

	it("lists none as zero, and says when history could not be read", function()
		local out = table.concat(rework.lines({}, {}, false), "\n")
		t.expect(has(out, "defects with no fixed ticket recorded: 0")).toBe(true)
		t.expect(has(out, "defects not counted by the owner's ruling (shipped: no): 0")).toBe(true)
		t.expect(has(out, "defects not counted, the work they fix was still open when they were captured: 0"))
			.toBe(true)
		t.expect(has(out, "no readable git history")).toBe(true)
		t.expect(has(table.concat(rework.lines({}, {}, true), "\n"), "no readable git history")).toBe(false)
	end)

	it("./zn metrics prints the shipped figure over a tracker with git history", function()
		local base = `{here}/.cache/f0450-metrics`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		engine.copy(top, base)
		engine.roots(base)
		local tr = "pickman/.tracker/issues/done"
		local head = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
			.. "|---|---|---|---|---|---|---|---|---|\n"
		local function item(
			id: string,
			kind: string,
			extra: string,
			added: number,
			minutes: number,
			body: string?
		)
			write(
				base,
				`{tr}/{id}/{id}.md`,
				`---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\nraft: \ncreated: 2026-02-10\n{extra}---\n\n# {id}\n{body or ""}`
			)
			write(
				base,
				`{tr}/{id}/spend.md`,
				`# Spend: {id} {id}\n\n{head}| 1 | 2026-02-10 10:00 | s | {added} | 0 | {minutes} | spend | prep | |\n`
			)
		end
		-- creating the repository needs no check: the path is named here (fixture.lua)
		local made = process.exec("git", { "init", "-q", "-b", "main", base }, { cwd = `{here}/.cache` })
		t.expect(made.ok).toBe(true)
		fixture.git(base, { "config", "user.name", "f0450" })
		fixture.git(base, { "config", "user.email", "f0450@example.invalid" })
		local function commit(day: string, message: string)
			local env =
				{ GIT_COMMITTER_DATE = `{day}T12:00:00+00:00`, GIT_AUTHOR_DATE = `{day}T12:00:00+00:00` }
			fixture.git(base, { "add", "-A" }, { env = env })
			fixture.git(base, { "commit", "-q", "-m", message }, { env = env })
		end
		item("f9001", "feature", "", 100, 10)
		commit("2026-02-01", "f9001 done")
		item("d9001", "defect", "fixes: [f9001]\n", 50, 5)
		item("d9002", "defect", "fixes: [f9002]\n", 30, 3)
		item("d9003", "defect", "", 20, 2)
		commit("2026-02-10", "defects done")
		item("f9002", "feature", "", 100, 10)
		commit("2026-02-20", "f9002 done")
		-- f9003 reaches done/ inside a merge commit (as a raft's `bind` merge does): `git log -p` shows a merge no diff, so
		-- history cannot date it and the day is read from the first-parent line
		fixture.git(base, { "checkout", "-q", "-b", "side" })
		write(base, "side.txt", "side\n")
		commit("2026-02-03", "side work")
		fixture.git(base, { "checkout", "-q", "main" })
		local mergeEnv = {
			GIT_COMMITTER_DATE = "2026-02-05T12:00:00+00:00",
			GIT_AUTHOR_DATE = "2026-02-05T12:00:00+00:00",
		}
		fixture.git(base, { "merge", "-q", "--no-ff", "--no-commit", "side" })
		item("f9003", "feature", "", 100, 10)
		fixture.git(base, { "add", "-A" }, { env = mergeEnv })
		fixture.git(base, { "commit", "-q", "-m", "bind f9003" }, { env = mergeEnv })
		item("d9004", "defect", "fixes: [f9003]\n", 40, 4)
		commit("2026-02-21", "d9004 done")
		item("d9005", "defect", "shipped: no\n", 60, 6, 'Ruled (user, 2026-11-24): "they do not count"\n')
		item("d9006", "defect", "shipped: no\n", 10, 1) -- the key with no ruling line: ignored
		commit("2026-02-22", "d9005 d9006 done")
		local r = fixture.exec(base, "bash", { "zn", "metrics" }, { env = { PICKMAN_PUBLISH = "0" } })
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		t.expect(has(out, "by lines added:  28.6%")).toBe(true) -- 120 / 420
		t.expect(has(out, "by issues:       57.1%")).toBe(true) -- 4 / 7
		t.expect(has(out, "by agent time:   28.6%")).toBe(true) -- 12 / 42
		t.expect(has(out, "by lines added 41.2%, by issues 66.7%, by agent time 41.2%")).toBe(true)
		t.expect(has(out, "(shipped: no): 1: d9005")).toBe(true)
		t.expect(has(out, ": 1: d9002 (fixes f9002)")).toBe(true)
		t.expect(has(out, "defects with no fixed ticket recorded: 2: d9003, d9006")).toBe(true)
		fs.removeDir(base)
	end)

	it("./zn audit errors on a fixes: id that names no item, and is silent on a defect with none", function()
		local base = `{here}/.cache/f0450-audit`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		engine.copy(top, base)
		engine.roots(base)
		local function doc(id: string, extra: string): string
			return `---\nid: {id}\ntype: defect\ntitle: D\nslug: d\nraft: \ncreated: 2026-02-10\n{extra}status: done\n---\n`
		end
		write(base, "pickman/.tracker/issues/done/d9101/d9101.md", doc("d9101", "fixes: [f9999]\n"))
		write(base, "pickman/.tracker/issues/done/d9102/d9102.md", doc("d9102", ""))
		write(base, "pickman/.tracker/issues/done/d9101/check.sh", "true\n")
		write(base, "pickman/.tracker/issues/done/d9102/check.sh", "true\n")
		local r = process.exec("bash", { "zn", "audit" }, { cwd = base, env = { PICKMAN_PUBLISH = "0" } })
		local out = r.stdout .. r.stderr
		t.expect(has(out, "unknown-fixes")).toBe(true)
		t.expect(has(out, "f9999")).toBe(true)
		t.expect(has(out, "d9102")).toBe(false)
		write(base, "pickman/.tracker/issues/done/f9999/f9999.md", doc("f9999", ""))
		write(base, "pickman/.tracker/issues/done/f9999/check.sh", "true\n")
		-- shipped: no with no ruling line is an error; with a Ruled line it is honoured and silent
		write(base, "pickman/.tracker/issues/done/d9103/d9103.md", doc("d9103", "shipped: no\n"))
		write(base, "pickman/.tracker/issues/done/d9103/check.sh", "true\n")
		write(
			base,
			"pickman/.tracker/issues/done/d9104/d9104.md",
			doc("d9104", "shipped: no\n") .. 'Ruled (user, 2026-11-24): "they do not count"\n'
		)
		write(base, "pickman/.tracker/issues/done/d9104/check.sh", "true\n")
		out = process.exec("bash", { "zn", "audit" }, { cwd = base, env = { PICKMAN_PUBLISH = "0" } }).stdout
		t.expect(has(out, "unknown-fixes")).toBe(false)
		t.expect(has(out, "unhonoured-shipped")).toBe(true)
		t.expect(has(out, "d9103")).toBe(true)
		t.expect(has(out, "d9104")).toBe(false)
		fs.removeDir(base)
	end)

	it("./zn new issue d --fixes writes the key, and a feature has none", function()
		local base = `{here}/.cache/f0450-new`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		engine.copy(top, base)
		engine.roots(base)
		write(base, "z-nile/next", "issue 9300 fixture\nraft 1 fixture\n")
		local env = { PICKMAN_PUBLISH = "0" }
		local r = process.exec(
			"bash",
			{ "zn", "new", "issue", "d", "broke", "--project", "pickman", "--fixes", "f0033,R0044" },
			{ cwd = base, env = env }
		)
		t.expect(r.ok).toBe(true)
		local path = string.match(r.stdout, "(%S+%.md)") :: string
		t.expect(has(fs.readFile(`{base}/{path}`), "\nfixes: [f0033, R0044]\n")).toBe(true)
		local f = process.exec(
			"bash",
			{ "zn", "new", "issue", "f", "plain", "--project", "pickman" },
			{ cwd = base, env = env }
		)
		local fpath = string.match(f.stdout, "(%S+%.md)") :: string
		t.expect(has(fs.readFile(`{base}/{fpath}`), "fixes:")).toBe(false)
		fs.removeDir(base)
	end)
end)
