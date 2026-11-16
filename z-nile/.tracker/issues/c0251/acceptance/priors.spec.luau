--!strict
-- c0251 AC4: the previous round's reviewers are the stamped reviews of the highest lifecycle rank up to the kind being written
-- (design, coherence, code, final), then the highest round number at that rank; a refused or flagged round counts, an
-- unstamped file is skipped, each folder's newest round counts (round numbers are never compared across folders), and unmarked items count too. Folders under .cache.
local fs = require("@lune/fs")
local process = require("@lune/process")
local reviewmodel = require("@znile/engine/reviewmodel")
local t = require("@tests/lib/t")

local RM: any = reviewmodel
local F: any = require("@znile/engine/reviewfiles")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local BASE = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0251-priors`

local DESIGN, COHERENCE, CODE, FINAL = 1, 2, 3, 4

-- an item folder `<BASE>/<name>` (the folder name is the document's name), marked `reviews: judged` unless `unmarked`
local function folder(name: string, files: { [string]: string }, unmarked: boolean?): string
	local dir = `{BASE}/{name}`
	fs.writeDir(dir)
	fs.writeFile(
		`{dir}/{name}.md`,
		`---\nid: {name}\ntype: chore\ntitle: t\nslug: t\n{if unmarked then "" else "reviews: judged\n"}status: preparing-a-b-c\n---\n\n# {name}\n`
	)
	for file, text in files do
		fs.writeFile(`{dir}/{file}`, text)
	end
	return dir
end

local function stamped(model: string, effort: string?, extra: string?): string
	return `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}{extra or ""}# Review\n\nVerdict: approve\n`
end

local function sorted(list: { string }): { string }
	local out = table.clone(list)
	table.sort(out)
	return out
end

return t.spec("c0251 the previous round's reviewers", function(it)
	it("sets up the folders", function()
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		fs.writeDir(BASE)
	end)

	it("AC4: the highest lifecycle rank decides, not the file number", function()
		-- design round 5 is the highest NNN, but a code review is later in the lifecycle
		local dir = folder("c0100", {
			["design-review-005.md"] = stamped("claude-opus-5-5", "xhigh"),
			["review-001.md"] = stamped("claude-sonnet-5-5", "high"),
		})
		t.expect(F.priors({ { kind = "design", dir = dir }, { kind = "code", dir = dir } }, CODE))
			.toEqual({ "claude-sonnet-5-5" })
		-- a final review is later still
		local both = folder("c0101", {
			["review-009.md"] = stamped("claude-opus-5-5", "xhigh"),
			["final-review-001.md"] = stamped("claude-fable-5-2"),
		})
		t.expect(F.priors({ { kind = "code", dir = both } }, FINAL)).toEqual({ "claude-fable-5-2" })
	end)

	it("AC4: only the ranks up to the kind being written count", function()
		local dir = folder("c0102", {
			["design-review-001.md"] = stamped("claude-opus-5-5", "xhigh"),
			["review-001.md"] = stamped("claude-sonnet-5-5", "high"),
			["final-review-001.md"] = stamped("claude-fable-5-2"),
		})
		local folders = { { kind = "design", dir = dir }, { kind = "code", dir = dir } }
		t.expect(F.priors(folders, DESIGN)).toEqual({ "claude-opus-5-5" })
		t.expect(F.priors(folders, CODE)).toEqual({ "claude-sonnet-5-5" })
		t.expect(F.priors(folders, FINAL)).toEqual({ "claude-fable-5-2" })
		-- a raft's own design-review files are the coherence rank: a design review of a member does not outrank it
		local raft = folder("R0100", { ["design-review-001.md"] = stamped("kimi-code-k3.1-pro", "high") })
		local member = folder("c0103", { ["design-review-004.md"] = stamped("claude-opus-5-5", "xhigh") })
		t.expect(
			F.priors({ { kind = "coherence", dir = raft }, { kind = "design", dir = member } }, COHERENCE)
		)
			.toEqual({
				"kimi-code-k3.1-pro",
			})
		-- a design review being written sees no coherence review of the raft
		t.expect(F.priors({ { kind = "coherence", dir = raft }, { kind = "design", dir = member } }, DESIGN))
			.toEqual({
				"claude-opus-5-5",
			})
	end)

	it("AC4: inside one rank the highest round number decides", function()
		local dir = folder("c0104", {
			["review-001.md"] = stamped("claude-opus-5-5", "xhigh"),
			["review-002.md"] = stamped("claude-fable-5-2"),
			["review-003.md"] = stamped("kimi-code-k3.1-pro", "high"),
		})
		t.expect(F.priors({ { kind = "code", dir = dir } }, CODE)).toEqual({ "kimi-code-k3.1-pro" })
	end)

	it("AC4: a refused round counts (an off-model record), and so does a flagged one", function()
		local cheap = folder("c0105", { ["review-001.md"] = stamped("claude-sonnet-5-5", "high") })
		t.expect(F.priors({ { kind = "code", dir = cheap } }, CODE)).toEqual({ "claude-sonnet-5-5" })
		local flagged = folder("c0106", {
			["design-review-001.md"] = stamped(
				"claude-opus-5-5",
				"xhigh",
				"Fallback: the exact model ran it\n"
			),
		})
		t.expect(F.priors({ { kind = "design", dir = flagged } }, DESIGN)).toEqual({ "claude-opus-5-5" })
		-- a round that records an empty Model: line is no record
		local empty = folder("c0107", { ["review-001.md"] = "Model:\n# Review\n" })
		t.expect(F.priors({ { kind = "code", dir = empty } }, CODE)).toEqual({})
	end)

	it("AC4: unstamped files are skipped and the next stamped one is the previous round", function()
		local dir = folder("c0108", {
			["review-001.md"] = stamped("claude-opus-5-5", "xhigh"),
			["review-002.md"] = "# Review\n\nVerdict: approve\n", -- no record
		})
		t.expect(F.priors({ { kind = "code", dir = dir } }, CODE)).toEqual({ "claude-opus-5-5" })
		local none = folder("c0109", { ["review-001.md"] = "# Review\n\nVerdict: approve\n" })
		t.expect(F.priors({ { kind = "code", dir = none } }, CODE)).toEqual({})
		t.expect(F.priors({ { kind = "code", dir = `{BASE}/missing` } }, CODE)).toEqual({})
	end)

	it("AC4: ties across a raft's member folders all count, each model once, with a bare id", function()
		local a = folder("c0110", { ["review-001.md"] = stamped("claude-opus-5-5[1m]", "xhigh") })
		local b = folder("c0111", { ["review-001.md"] = stamped("kimi-code-k3.1-pro", "high") })
		local c = folder("c0112", { ["review-001.md"] = stamped("claude-opus-5-5", "xhigh") })
		local d = folder("c0113", {
			["review-001.md"] = stamped("grok-4.7", "xhigh"),
			["design-review-009.md"] = stamped("claude-fable-5-2"),
		})
		local got = F.priors({
			{ kind = "code", dir = a },
			{ kind = "code", dir = b },
			{ kind = "code", dir = c },
			{ kind = "code", dir = d },
			{ kind = "design", dir = d },
		}, CODE)
		t.expect(sorted(got)).toEqual({ "claude-opus-5-5", "grok-4.7", "kimi-code-k3.1-pro" })
		-- round numbers are never compared between folders: a member's review-002 does not hide the others' review-001
		local newer = folder("c0114", { ["review-002.md"] = stamped("claude-fable-5-2") })
		t.expect(sorted(F.priors({ { kind = "code", dir = a }, { kind = "code", dir = newer } }, CODE)))
			.toEqual({ "claude-fable-5-2", "claude-opus-5-5" })
	end)

	it(
		"AC4: inside one folder only the newest round at the top rank counts, and each folder contributes its own",
		function()
			-- layer 1 was reviewed twice (Opus, then Fable); layers 2 and 3 once each: c0248 numbers each folder from 001
			local one = folder("c0118", {
				["review-001.md"] = stamped("claude-opus-5-5", "xhigh"),
				["review-002.md"] = stamped("claude-fable-5-2"),
			})
			local two = folder("c0119", { ["review-001.md"] = stamped("kimi-code-k3.1-pro", "high") })
			local three = folder("c0120", { ["review-001.md"] = stamped("grok-4.7", "xhigh") })
			local got = F.priors(
				{ { kind = "code", dir = one }, { kind = "code", dir = two }, { kind = "code", dir = three } },
				FINAL
			)
			t.expect(sorted(got)).toEqual({ "claude-fable-5-2", "grok-4.7", "kimi-code-k3.1-pro" })
			-- a final review outranks the layer reviews of the other folders
			local final = folder("c0121", { ["final-review-001.md"] = stamped("claude-sonnet-5-5", "high") })
			t.expect(F.priors({ { kind = "code", dir = one }, { kind = "code", dir = final } }, FINAL))
				.toEqual({ "claude-sonnet-5-5" })
		end
	)

	it("AC4: an unmarked item's stamped rounds count too: c0306 stamps every review it files", function()
		local dir = folder("c0115", { ["review-001.md"] = stamped("claude-opus-5-5", "xhigh") }, true)
		t.expect(F.priors({ { kind = "code", dir = dir } }, CODE)).toEqual({ "claude-opus-5-5" })
		local marked = folder("c0116", { ["review-001.md"] = stamped("claude-fable-5-2") })
		t.expect(sorted(F.priors({ { kind = "code", dir = dir }, { kind = "code", dir = marked } }, CODE)))
			.toEqual({ "claude-fable-5-2", "claude-opus-5-5" })
		-- an unmarked item with no stamped file has none
		local bare = folder("c0122", { ["review-001.md"] = "# Review\n" }, true)
		t.expect(F.priors({ { kind = "code", dir = bare } }, CODE)).toEqual({})
	end)

	it(
		"AC4: a stream review reads none (rank 0 admits no file), and the pure ranking agrees with the reader",
		function()
			local dir = folder("c0117", { ["review-001.md"] = stamped("claude-opus-5-5", "xhigh") })
			t.expect(F.priors({ { kind = "code", dir = dir } }, 0)).toEqual({})
			local mixed: { { kind: string, files: { [string]: string } } } = {
				{ kind = "design", files = { ["design-review-001.md"] = stamped("claude-opus-5-5") } },
				{
					kind = "code",
					files = {
						["review-001.md"] = stamped("kimi-code-k3.1-pro"),
						["notes.md"] = stamped("grok-4.7"),
					},
				},
			}
			t.expect(RM.priorsOf(mixed, CODE)).toEqual({ "kimi-code-k3.1-pro" })
			t.expect(RM.priorsOf({}, CODE)).toEqual({})
		end
	)

	it("cleans up", function()
		fs.removeDir(BASE)
	end)
end)
