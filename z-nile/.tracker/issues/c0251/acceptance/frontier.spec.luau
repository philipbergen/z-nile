--!strict
-- c0251 AC19 and AC20 (the pure half): the frontier floor. `frontier.check` says whether the landed code has a review by a model
-- on the `[review] frontier` list, with a named problem c0252's `landcheck` can call; `models.parse` reads the list; the root
-- `.models.toml` seeds it; and any model may run any review (`reviewmodel.ok` refuses no recorded model). Files under .cache.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local frontier: any = require("@znile/engine/frontier")
local reviewfiles: any = require("@znile/engine/reviewfiles")
local reviewmodel: any = require("@znile/engine/reviewmodel")
local M: any = models

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function errorOf(f: () -> ()): string
	local ok, e = pcall(f :: any)
	return if ok then "" else tostring(e)
end

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local BASE = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/c0251-frontier`

local LIST =
	{ "claude-opus-5-5", "claude-fable-5-2", "kimi-code-k3.1-pro", "grok-4.7@xhigh", "gemini-4-argon" }

local function stamped(model: string?, effort: string?): string
	local head = if model then `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}` else ""
	return `{head}# Review\n\nVerdict: approve\n`
end

return t.spec("c0251 the frontier floor", function(it)
	it(
		"AC19: listed matches a bare model id, ignores a context marker, and an @effort entry needs that effort",
		function()
			t.expect(frontier.listed("claude-opus-5-5", nil, LIST)).toBe(true)
			t.expect(frontier.listed("claude-opus-5-5[1m]", "low", LIST)).toBe(true)
			t.expect(frontier.listed("claude-fable-5-2", "medium", LIST)).toBe(true)
			t.expect(frontier.listed("kimi-code-k3.1-pro", "high", LIST)).toBe(true)
			t.expect(frontier.listed("gemini-4-argon", "high", LIST)).toBe(true)
			-- grok-4.7@xhigh: the effort must be that one
			t.expect(frontier.listed("grok-4.7", "xhigh", LIST)).toBe(true)
			t.expect(frontier.listed("grok-4.7", "high", LIST)).toBe(false)
			t.expect(frontier.listed("grok-4.7", nil, LIST)).toBe(false)
			-- a model line is not a model: only the ids listed count
			t.expect(frontier.listed("claude-opus-5-4", "xhigh", LIST)).toBe(false)
			t.expect(frontier.listed("claude-sonnet-5-5", "xhigh", LIST)).toBe(false)
			t.expect(frontier.listed("claude-opus-5-5-high", "xhigh", LIST)).toBe(false)
			t.expect(frontier.listed("kimi-code-k3.1-pro-highspeed", nil, LIST)).toBe(false)
			-- no record counts for nothing
			t.expect(frontier.listed(nil, nil, LIST)).toBe(false)
			t.expect(frontier.listed("", "xhigh", LIST)).toBe(false)
			t.expect(frontier.listed("claude-opus-5-5", nil, {})).toBe(false)
		end
	)

	it(
		"AC19: check is met by one listed review anywhere, and unmet it names the code, each review found and the list",
		function()
			local seen = {
				{ file = "review-001.md", model = "claude-sonnet-5-5", effort = "high" },
				{ file = "final-review-001.md", model = "claude-fable-5-2", effort = "xhigh" },
			}
			local met = frontier.check(seen, LIST)
			t.expect(met.met).toBe(true)
			t.expect(met.code).toBe(nil)
			t.expect(met.problem).toBe(nil)
			local unmet = frontier.check(
				{ seen[1], { file = "review-002.md", model = "grok-4.7", effort = "high" } },
				LIST
			)
			t.expect(unmet.met).toBe(false)
			t.expect(unmet.code).toBe("no-frontier-review")
			t.expect(frontier.CODE).toBe("no-frontier-review")
			t.expect(has(unmet.problem, "no-frontier-review")).toBe(true)
			t.expect(has(unmet.problem, "review-001.md on claude-sonnet-5-5 at high")).toBe(true)
			t.expect(has(unmet.problem, "review-002.md on grok-4.7 at high")).toBe(true)
			t.expect(has(unmet.problem, "grok-4.7@xhigh")).toBe(true)
			t.expect(unmet.listed).toEqual(LIST)
			-- no review at all, and one that records no model, are named
			local none = frontier.check({}, LIST)
			t.expect(none.met).toBe(false)
			t.expect(has(none.problem, "no code or final review")).toBe(true)
			local blank = frontier.check({ { file = "review-001.md", model = nil, effort = nil } }, LIST)
			t.expect(blank.met).toBe(false)
			t.expect(has(blank.problem, "no recorded model")).toBe(true)
		end
	)

	it("AC19: an empty list sets no floor", function()
		t.expect(frontier.check({}, {}).met).toBe(true)
		t.expect(frontier.check({ { file = "review-001.md", model = "claude-sonnet-5-5" } }, {}).met)
			.toBe(true)
	end)

	it("AC19: seenIn keeps the code and final reviews only, with their record", function()
		local seen = frontier.seenIn({
			["design-review-001.md"] = stamped("claude-fable-5-2", "xhigh"),
			["review-001.md"] = stamped("claude-sonnet-5-5", "high"),
			["final-review-001.md"] = stamped("kimi-code-k3.1-pro", nil),
			["review-002.md"] = stamped(nil, nil),
			["stream-review-c0010-001.md"] = stamped("claude-fable-5-2", "xhigh"),
			["idea-review-001.md"] = stamped("claude-fable-5-2", "xhigh"),
		})
		local names = {}
		for _, s in seen do
			table.insert(names, s.file)
		end
		t.expect(names).toEqual({ "final-review-001.md", "review-001.md", "review-002.md" })
		t.expect(seen[1].model).toBe("kimi-code-k3.1-pro")
		t.expect(seen[1].effort).toBe(nil)
		t.expect(seen[3].model).toBe(nil)
		-- a design review, a stream review and an idea review on Fable do not meet the floor
		local only = frontier.seenIn({
			["design-review-001.md"] = stamped("claude-fable-5-2", "xhigh"),
			["stream-review-c0010-001.md"] = stamped("claude-fable-5-2", "xhigh"),
		})
		t.expect(frontier.check(only, LIST).met).toBe(false)
	end)

	it(
		"AC19: models.parse reads [review] frontier, a closer file replaces the list whole, and bad entries are refused",
		function()
			local root =
				M.parse('[review]\nfrontier = ["claude-opus-5-5", "grok-4.7@xhigh"]\n', ".models.toml")
			t.expect(root.frontier).toEqual({ "claude-opus-5-5", "grok-4.7@xhigh" })
			t.expect(M.parse("[dispatch]\nstall_seconds = 60\n", ".models.toml").frontier).toBe(nil)
			local closer = M.parse('[review]\nfrontier = ["kimi-code-k3.1-pro"]\n', "pickman/.models.toml")
			t.expect(M.frontier({ root, closer })).toEqual({ "kimi-code-k3.1-pro" })
			t.expect(M.frontier({ root, M.parse("[dispatch]\nstall_seconds = 9\n", "pickman/.models.toml") }))
				.toEqual({ "claude-opus-5-5", "grok-4.7@xhigh" })
			t.expect(M.frontier({})).toEqual({})
			for _, bad in
				{
					"[review]\nfrontier = []\n",
					'[review]\nfrontier = "claude-opus-5-5"\n',
					'[review]\nfrontier = ["claude-opus-5-5", "claude-opus-5-5"]\n',
					'[review]\nfrontier = ["a b"]\n',
					"[review]\nfrontier = [5]\n",
					"[review]\nother = 1\n",
					'review = "x"\n',
				}
			do
				t.expect(errorOf(function()
					M.parse(bad, ".models.toml")
				end) ~= "").toBe(true)
			end
		end
	)

	it(
		"AC19: the root .models.toml seeds the list: Opus, Fable, kimi k3.1 pro, grok 4.7 at xhigh and Gemini 4 Argon",
		function()
			local layers = { M.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			t.expect(M.frontier(layers)).toEqual({
				"claude-opus-5-5",
				"claude-fable-5-2",
				"kimi-code-k3.1-pro",
				"grok-4.7@xhigh",
				"gemini-4-argon",
			})
		end
	)

	it(
		"AC20: any model may run any review: ok refuses no recorded model and problem names only a missing record",
		function()
			for _, id in { "claude-sonnet-5-5", "claude-haiku-5-5", "grok-4.6", "composer-2.5", "mystery-1" } do
				t.expect(reviewmodel.ok(id, nil)).toBe(true)
				t.expect(reviewmodel.ok(id, "low")).toBe(true)
			end
			t.expect(reviewmodel.ok("", "xhigh")).toBe(false)
			t.expect(reviewmodel.KINDS).toBe(nil)
			t.expect(reviewmodel.describe).toBe(nil)
			-- a grok review at high, a Sonnet review and a Haiku review are all fine records
			local files = {
				["design-review-001.md"] = stamped("claude-sonnet-5-5", "low"),
				["review-001.md"] = stamped("grok-4.7", "high"),
				["final-review-001.md"] = stamped("claude-haiku-5-5", nil),
			}
			for _, kind in { "design", "code" } do
				t.expect(reviewmodel.problem(files, kind, "c0010")).toBe(nil)
			end
			-- a review that records no model, or an empty one, is still named
			local bare = reviewmodel.problem({ ["review-001.md"] = stamped(nil, nil) }, "code", "c0010")
			t.expect(has(bare, "no `Model:` line")).toBe(true)
			t.expect(has(bare, "not a review model")).toBe(false)
			local empty = reviewmodel.problem({ ["review-001.md"] = "Model:\n# Review\n" }, "code", "c0010")
			t.expect(has(empty, "empty `Model:` line")).toBe(true)
			t.expect(reviewmodel.refused(stamped("claude-haiku-5-5", nil))).toBe(false)
			t.expect(reviewmodel.refused(stamped(nil, nil))).toBe(true)
		end
	)

	it(
		"AC20: frontierVerdict reads the code and final reviews of every folder of a landing, one listed review meeting the floor",
		function()
			if fs.isDir(BASE) then
				fs.removeDir(BASE)
			end
			for _, d in { "raft", "m1", "m2" } do
				fs.writeDir(`{BASE}/{d}`)
			end
			fs.writeFile(`{BASE}/raft/final-review-001.md`, stamped("claude-sonnet-5-5", "high"))
			fs.writeFile(`{BASE}/raft/design-review-001.md`, stamped("claude-fable-5-2", "xhigh"))
			fs.writeFile(`{BASE}/m1/review-001.md`, stamped("claude-haiku-5-5", "low"))
			fs.writeFile(`{BASE}/m2/stream-review-m2-001.md`, stamped("claude-fable-5-2", "xhigh"))
			local dirs = { `{BASE}/raft`, `{BASE}/m1`, `{BASE}/m2` }
			local unmet = reviewfiles.frontierVerdict(dirs, LIST)
			t.expect(unmet.met).toBe(false)
			t.expect(has(unmet.problem, "final-review-001.md on claude-sonnet-5-5")).toBe(true)
			t.expect(has(unmet.problem, "review-001.md on claude-haiku-5-5")).toBe(true)
			-- a layer's code review on Fable, in a member's folder, meets it for the whole landing
			fs.writeFile(`{BASE}/m2/review-001.md`, stamped("claude-fable-5-2", "high"))
			t.expect(reviewfiles.frontierVerdict(dirs, LIST).met).toBe(true)
			-- a prefix landing passes only the folders it lands: the folders without that review do not meet it
			t.expect(reviewfiles.frontierVerdict({ `{BASE}/raft`, `{BASE}/m1` }, LIST).met).toBe(false)
			-- a missing folder is empty, and an empty list sets no floor
			t.expect(reviewfiles.frontierVerdict({ `{BASE}/none` }, LIST).met).toBe(false)
			t.expect(reviewfiles.frontierVerdict({ `{BASE}/none` }, {}).met).toBe(true)
			fs.removeDir(BASE)
		end
	)
end)
