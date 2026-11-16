--!strict
-- c0251 AC8: the board flags a raft or an issue whose newest review round of a kind carries a `Fallback:` line (`fallbackReviews`,
-- the files' paths) and clears the flag when a later round has none. `boardview.fallbacks` is the pure rule; board.collect reads
-- the files at the edge; the page shows a "fallback review" badge with the command that re-reviews. Fixture under .cache (no git).
local board = require("@znile/engine/board")
local boardview = require("@znile/engine/boardview")
local fs = require("@lune/fs")
local process = require("@lune/process")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local BV: any = boardview

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local dir = `{here}/.cache/c0251-board`
local TRACKER = `{dir}/game/.tracker`
local FACTS = { asOf = stats.seconds("2026-10-21T10:00:00Z"), refs = {}, worktrees = {}, dispatch = {} }

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function item(path: string, id: string, front: string)
	write(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local FLAGGED =
	"Model: claude-opus-5-5\nEffort: xhigh\nFallback: the model that wrote the text ran the review\n# Review\n"
local CLEAN = "Model: claude-fable-5-2\nEffort: xhigh\n# Review\n"
local BARE = "# Review\n"

-- the paths of a list, relative to the tracker folder
local function rel(list: { string }): { string }
	local out = {}
	for _, p in list do
		table.insert(out, (string.gsub(p, "^.*/game/%.tracker/", "")))
	end
	table.sort(out)
	return out
end

local function collect(): any
	local m: any = board.collect(TRACKER, nil, FACTS)
	local byId: { [string]: any } = {}
	for _, r in m.rafts do
		byId[r.id] = r
	end
	for _, i in m.issues do
		byId[i.id] = i
	end
	return byId
end

return t.spec("c0251 the board flags fallback reviews", function(it)
	it(
		"AC8: boardview.fallbacks lists the newest round of each kind that carries Fallback:, per folder",
		function()
			-- design: round 2 is newest and flagged; round 1 flagged too but older, so not listed on its own
			t.expect(BV.fallbacks({
				["a/design-review-001.md"] = FLAGGED,
				["a/design-review-002.md"] = FLAGGED,
			})).toEqual({ "a/design-review-002.md" })
			-- an older flagged round with a clean newer one: nothing
			t.expect(BV.fallbacks({
				["a/design-review-001.md"] = FLAGGED,
				["a/design-review-002.md"] = CLEAN,
			})).toEqual({})
			-- code and final are apart: the newest review and the newest final review
			t.expect(BV.fallbacks({
				["a/review-001.md"] = FLAGGED,
				["a/review-002.md"] = CLEAN,
				["a/final-review-001.md"] = FLAGGED,
			})).toEqual({ "a/final-review-001.md" })
			-- the newest round is the one with the highest number, not the last name
			t.expect(BV.fallbacks({
				["a/review-9.md"] = FLAGGED,
				["a/review-010.md"] = BARE,
				["a/review-002.md"] = FLAGGED,
			})).toEqual({})
			t.expect(BV.fallbacks({})).toEqual({})
		end
	)

	it(
		"AC8: two folders are judged apart, so a clean newest round in one does not hide a flagged one in the other",
		function()
			local got = BV.fallbacks({
				["a/c0011/review-001.md"] = FLAGGED,
				["a/c0012/review-001.md"] = CLEAN,
				["a/c0012/design-review-001.md"] = BARE,
				["a/c0013/review-003.md"] = FLAGGED,
				["a/c0013/review-004.md"] = BARE,
			})
			t.expect(got).toEqual({ "a/c0011/review-001.md" })
			t.expect(BV.fallbacks({
				["notes.md"] = FLAGGED,
				["a/c1/refute-001.md"] = FLAGGED,
				["a/c1/stream-review-c1-001.md"] = FLAGGED,
			})).toEqual({ "a/c1/stream-review-c1-001.md" })
		end
	)

	it("sets up a raft with two members and reviews of every kind", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		write(`{here}/.cache/c0251-board/z-nile-marker`, "fixture\n")
		item(
			`{TRACKER}/rafts/active/R0010`,
			"R0010",
			"type: chore\ntitle: Flagged\ndesign: ready\nstatus: active-a-b-c"
		)
		item(
			`{TRACKER}/issues/active/c0011`,
			"c0011",
			"type: chore\ntitle: One\nraft: R0010\nstatus: active-a-b-c"
		)
		item(
			`{TRACKER}/issues/active/c0012`,
			"c0012",
			"type: chore\ntitle: Two\nraft: R0010\nstatus: active-a-b-c"
		)
		item(`{TRACKER}/issues/active/c0013`, "c0013", "type: chore\ntitle: Alone\nstatus: preparing-a-b-c")
		-- the raft: a coherence review flagged then superseded clean; a final review flagged
		write(`{TRACKER}/rafts/active/R0010/design-review-001.md`, FLAGGED)
		write(`{TRACKER}/rafts/active/R0010/design-review-002.md`, CLEAN)
		write(`{TRACKER}/rafts/active/R0010/final-review-001.md`, FLAGGED)
		-- c0011: a flagged code review (the newest); c0012: an older flagged one with a clean newer round
		write(`{TRACKER}/issues/active/c0011/review-001.md`, FLAGGED)
		write(`{TRACKER}/issues/active/c0012/review-001.md`, FLAGGED)
		write(`{TRACKER}/issues/active/c0012/review-002.md`, CLEAN)
		-- c0013 is in no raft: its design review is flagged
		write(`{TRACKER}/issues/active/c0013/design-review-001.md`, FLAGGED)
		-- stream reviews of the raft's layers: c0011's is flagged; c0012's flagged round has a clean newer one
		write(`{TRACKER}/rafts/active/R0010/stream-review-c0011-001.md`, FLAGGED)
		write(`{TRACKER}/rafts/active/R0010/stream-review-c0012-001.md`, FLAGGED)
		write(`{TRACKER}/rafts/active/R0010/stream-review-c0012-002.md`, CLEAN)
		-- an issue still in the backlog (its prep worktree is where it is worked): a flagged idea challenge and design review
		item(
			`{TRACKER}/issues/c0014`,
			"c0014",
			"type: chore\ntitle: Backlog\nslug: backlog-thing\nstatus: preparing-a-b-c"
		)
		write(`{TRACKER}/issues/c0014/idea-review-001.md`, FLAGGED)
		write(`{TRACKER}/issues/c0014/design-review-001.md`, FLAGGED)
		-- landed work: a done raft with a flagged final review, and its done member
		item(`{TRACKER}/rafts/done/R0011`, "R0011", "type: chore\ntitle: Landed\nstatus: done")
		item(
			`{TRACKER}/issues/done/c0015`,
			"c0015",
			"type: chore\ntitle: Landed one\nraft: R0011\nstatus: done"
		)
		write(`{TRACKER}/rafts/done/R0011/final-review-001.md`, FLAGGED)
		write(`{TRACKER}/issues/done/c0015/review-001.md`, FLAGGED)
	end)

	it(
		"AC8: a raft carries fallbackReviews for its own and its members' newest flagged rounds only",
		function()
			local all = collect()
			t.expect(rel(all.R0010.fallbackReviews)).toEqual({
				"issues/active/c0011/review-001.md",
				"rafts/active/R0010/final-review-001.md",
				"rafts/active/R0010/stream-review-c0011-001.md",
			})
		end
	)

	it("AC8: an issue carries fallbackReviews for its own newest flagged round, in a raft or not", function()
		local all = collect()
		t.expect(rel(all.c0011.fallbackReviews)).toEqual({ "issues/active/c0011/review-001.md" })
		t.expect(rel(all.c0012.fallbackReviews)).toEqual({})
		t.expect(rel(all.c0013.fallbackReviews)).toEqual({ "issues/active/c0013/design-review-001.md" })
	end)

	it("AC8: idea challenges and stream reviews are flagged too, a stream review per layer", function()
		local all = collect()
		t.expect(rel(all.c0014.fallbackReviews)).toEqual({
			"issues/c0014/design-review-001.md",
			"issues/c0014/idea-review-001.md",
		})
		-- c0012's stream review has a clean newer round, c0011's does not
		local streams = {}
		for _, f in rel(all.R0010.fallbackReviews) do
			if string.find(f, "stream-review", 1, true) then
				table.insert(streams, f)
			end
		end
		t.expect(streams).toEqual({ "rafts/active/R0010/stream-review-c0011-001.md" })
		t.expect(BV.fallbacks({
			["a/idea-review-001.md"] = FLAGGED,
			["a/idea-review-002.md"] = CLEAN,
			["b/idea-review-001.md"] = FLAGGED,
		})).toEqual({ "b/idea-review-001.md" })
		t.expect(BV.reviewPaths({
			"a/idea-review-001.md",
			"a/stream-review-c0011-001.md",
			"a/notes.md",
			"a/refute-001.md",
		})).toEqual({ "a/idea-review-001.md", "a/stream-review-c0011-001.md" })
	end)

	it(
		"AC8: the re-review command is the route that works where the item is worked, and none for landed work",
		function()
			local all = collect()
			-- a backlog issue is worked in its prep worktree
			local backlog = all.c0014.rereview
			t.expect(backlog[`{TRACKER}/issues/c0014/design-review-001.md`])
				.toBe('cd "$(./zn worktree prep-backlog-thing)" && ./zn dispatch zz-review c0014 --mode design')
			t.expect(backlog[`{TRACKER}/issues/c0014/idea-review-001.md`])
				.toBe('cd "$(./zn worktree prep-backlog-thing)" && ./zn idea c0014')
			-- an issue and a stream review of a launched raft are worked in the raft's worktree
			t.expect(all.c0011.rereview[`{TRACKER}/issues/active/c0011/review-001.md`])
				.toBe('cd "$(./zn worktree R0010)" && ./zn dispatch zz-review c0011 --mode code')
			t.expect(all.R0010.rereview[`{TRACKER}/rafts/active/R0010/final-review-001.md`])
				.toBe('cd "$(./zn worktree R0010)" && ./zn dispatch zz-review R0010 --mode final')
			t.expect(all.R0010.rereview[`{TRACKER}/rafts/active/R0010/stream-review-c0011-001.md`])
				.toBe('cd "$(./zn worktree R0010)" && ./zn dispatch zz-review c0011 --mode stream')
			-- an issue in no raft that is no longer a backlog issue has no worktree to name
			t.expect(next(all.c0013.rereview)).toBe(nil)
			-- landed work is flagged as history: a flag, and no command
			t.expect(rel(all.R0011.fallbackReviews)).toEqual({
				"issues/done/c0015/review-001.md",
				"rafts/done/R0011/final-review-001.md",
			})
			t.expect(next(all.R0011.rereview)).toBe(nil)
			t.expect(rel(all.c0015.fallbackReviews)).toEqual({ "issues/done/c0015/review-001.md" })
			t.expect(next(all.c0015.rereview)).toBe(nil)
			-- the pure rule: a raft's coherence review is raft mode
			t.expect(
				BV.rereview(
					{ kind = "raft", state = "active", id = "R0010", slug = "", raft = nil },
					"x/design-review-002.md"
				)
			).toBe('cd "$(./zn worktree R0010)" && ./zn dispatch zz-review R0010 --mode raft')
			t.expect(
				BV.rereview(
					{ kind = "raft", state = "backlog", id = "R0010", slug = "", raft = nil },
					"x/design-review-002.md"
				)
			).toBe(nil)
		end
	)

	it("AC8: the flag clears when a later round has no Fallback: line", function()
		write(`{TRACKER}/issues/active/c0011/review-002.md`, CLEAN)
		write(`{TRACKER}/rafts/active/R0010/final-review-002.md`, BARE)
		write(`{TRACKER}/rafts/active/R0010/stream-review-c0011-002.md`, CLEAN)
		local all = collect()
		t.expect(rel(all.c0011.fallbackReviews)).toEqual({})
		t.expect(rel(all.R0010.fallbackReviews)).toEqual({})
		-- and a later flagged round raises it again
		write(`{TRACKER}/issues/active/c0011/review-003.md`, FLAGGED)
		local again = collect()
		t.expect(rel(again.c0011.fallbackReviews)).toEqual({ "issues/active/c0011/review-003.md" })
		t.expect(rel(again.R0010.fallbackReviews)).toEqual({ "issues/active/c0011/review-003.md" })
	end)

	it("AC8: the page names the flag and the command that asks for the cross-model re-review", function()
		local page = board.build(TRACKER, nil, FACTS)
		t.expect(has(page, "fallback review")).toBe(true)
		t.expect(has(page, "ask for a cross-model re-review")).toBe(true)
		t.expect(has(page, "./zn dispatch zz-review")).toBe(true)
		t.expect(has(page, "fallbackReviews")).toBe(true)
		t.expect(has(page, "kept as history")).toBe(true)
		t.expect(has(page, "./zn worktree prep-backlog-thing")).toBe(true)
		-- the model it embeds carries the file for the flagged issue
		t.expect(has(page, "issues/active/c0013/design-review-001.md")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(dir)
	end)
end)
