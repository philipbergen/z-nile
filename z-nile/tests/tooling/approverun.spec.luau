--!strict
-- f0423 AC4 (the format half) and the safety property of amendment 4: `--ruling` can write only the run's
-- rulings.tsv under `.cache/approve/<run>/`, and a run id or a ticket id that is not of its shape never reaches a path.
local approverun = require("@znile/engine/approverun")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local RUN = "20261120T184000Z-a1b2"

local function queueRow(id: string, state: string): approverun.QueueRow
	return {
		id = id,
		place = "origin/main",
		hash = "abc",
		state = state,
		parts = "-",
		why = "no approval (2 guesses)",
	}
end

local function approve(ticket: string): approverun.Ruling
	return {
		ticket = ticket,
		guess = "-",
		action = "approve",
		stage = "-",
		note = "-",
		lesson = "-",
		ask = "-",
		into = "-",
	}
end

local function change(ticket: string, guess: string, over: { [string]: string }?): approverun.Ruling
	local r: any = {
		ticket = ticket,
		guess = guess,
		action = "change",
		stage = "design",
		note = "keep the old way",
		lesson = "-",
		ask = "-",
		into = "-",
	}
	if over then
		for k, v in over do
			r[k] = v
		end
	end
	return r :: approverun.Ruling
end

local function second(_a: any, b: string?): string?
	return b
end

local QUEUE = { queueRow("c0001", "waits"), queueRow("c0002", "waits"), queueRow("c0003", "working") }

return t.spec("approverun: the run folder", function(it)
	it("a run id and a ticket id have exactly one shape", function()
		t.expect(approverun.runId("20261120T184000Z", "a1b2")).toBe(RUN)
		t.expect(approverun.runId("20261120T184000Z", "xyz1")).toBe(nil)
		for _, bad in
			{ "../x", "20261120T184000Z-a1b2/..", "/abs/path", "20261120T184000Z-a1b", "", "a/../../b" }
		do
			t.expect(approverun.validRun(bad)).toBe(false)
			t.expect(approverun.dir("/root", bad)).toBe(nil)
		end
		t.expect(approverun.dir("/root", RUN)).toBe(`/root/.cache/approve/{RUN}`)
		t.expect(approverun.validTicket("c0001")).toBe(true)
		for _, bad in { "../../etc", "c001", "R0001", "c0001/x", "c00011" } do
			t.expect(approverun.validTicket(bad)).toBe(false)
		end
	end)

	it("the queue and the rulings render and parse back; a bad file is refused", function()
		local text = approverun.renderQueue(QUEUE)
		t.expect((approverun.parseQueue(text))).toEqual(QUEUE)
		t.expect(second(approverun.parseQueue("nope\n")))
			.toBe(`queue.tsv: the first line is not "id place hash state parts why"`)
		local twice = approverun.renderQueue({ queueRow("c0001", "waits"), queueRow("c0001", "waits") })
		t.expect(second(approverun.parseQueue(twice))).toBe("queue.tsv: c0001 is listed twice")
		local rulings =
			{ approve("c0001"), change("c0002", "G1", { lesson = "ask first", ask = "Did you ask?" }) }
		t.expect((approverun.parseRulings(approverun.renderRulings(rulings)))).toEqual(rulings)
		-- a tab or a line break in the owner's words cannot split a row
		local words = approverun.renderRulings({ change("c0002", "-", { note = "a\tb\nc" }) })
		local parsed = approverun.parseRulings(words) :: { approverun.Ruling }
		t.expect(parsed[1].note).toBe("a b c")
	end)

	it(
		"a ruling is refused for a ticket not in the queue, one not waiting, a repeat and an ask with no question",
		function()
			t.expect(approverun.refusal(QUEUE, {}, approve("c0001"))).toBe(nil)
			t.expect(approverun.refusal(QUEUE, {}, approve("c0009")))
				.toBe("c0009 is not in this run's queue: ./zn approve --queue lists what was walked")
			t.expect(approverun.refusal(QUEUE, {}, approve("c0003")))
				.toBe("c0003 does not wait for approval in this run (working): there is nothing to rule on")
			t.expect(approverun.refusal(QUEUE, { approve("c0001") }, approve("c0001")))
				.toBe("c0001 already has a ruling in this run")
			t.expect(approverun.refusal(QUEUE, { change("c0002", "G1") }, change("c0002", "G1")))
				.toBe("c0002 G1 already has a ruling in this run")
			t.expect(
				approverun.refusal(QUEUE, {}, change("c0002", "G1", { lesson = "r", ask = "no question" }))
			)
				.toBe('the ask of the change to c0002 must be a question (it has no "?")')
			t.expect(approverun.refusal(QUEUE, {}, change("c0002", "G1", { lesson = "r" })))
				.toBe("the change to c0002 needs --lesson and --ask together")
			t.expect(approverun.refusal(QUEUE, {}, change("c0002", "G1", { note = "-" })))
				.toBe("the change to c0002 needs --note with the owner's own words")
			t.expect(approverun.refusal(QUEUE, {}, change("c0002", "G1", { stage = "ui" })))
				.toBe("the change to c0002 needs --stage idea, design or code")
			-- two changes to different guesses are fine; an approval and a change are not
			t.expect(approverun.refusal(QUEUE, { change("c0002", "G1") }, change("c0002", "G2"))).toBe(nil)
			t.expect(approverun.refusal(QUEUE, { approve("c0002") }, change("c0002", "G2")))
				.toBe(
					"c0002 already has a ruling that conflicts with change: approve and change exclude each other"
				)
		end
	)

	it("the brief lists the waiting tickets in queue order, then the ones still being worked", function()
		local function entry(id: string, state: string): approverun.Entry
			return {
				id = id,
				title = `Title of {id}`,
				unit = "R0050",
				state = state,
				why = "no approval (1 guesses)",
				stage = "designed",
				doc = `z-nile/.tracker/issues/{id}/{id}.md`,
				place = "origin/main",
				hash = "abc",
				guesses = { "G1 (design, 2026-11-16): open. Chose: x. Why: y." },
				places = {},
				layer = nil,
				rework = {},
				lessons = {},
			}
		end
		local text = approverun.brief(
			RUN,
			"R0050",
			{ entry("c0002", "waits"), entry("c0001", "waits"), entry("c0003", "working") }
		)
		local a, b, c =
			string.find(text, "### 1. c0002", 1, true),
			string.find(text, "### 2. c0001", 1, true),
			string.find(text, "c0003: Title of c0003", 1, true)
		t.expect(
			a ~= nil
				and b ~= nil
				and c ~= nil
				and (a :: number) < (b :: number)
				and (b :: number) < (c :: number)
		).toBe(true)
		t.expect(string.find(text, "G1 (design, 2026-11-16): open. Chose: x. Why: y.", 1, true) ~= nil)
			.toBe(true)
	end)

	it(
		"--ruling writes only rulings.tsv in the run's folder, and a traversing run or ticket id writes nothing",
		function()
			local root = fixture.physical(".") :: string
			local base = `{root}/.cache/approverun-spec`
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			fs.writeFile(`{base}/outside.txt`, "untouched")
			local checkout = `{base}/checkout`
			fs.writeDir(checkout)
			t.expect(approverun.write(checkout, RUN, QUEUE, "brief")).toBe(nil)
			local dir = `{checkout}/.cache/approve/{RUN}`
			local function snapshot(): { string }
				local out: { string } = {}
				local function walk(path: string, rel: string)
					for _, name in fs.readDir(path) do
						local full = `{path}/{name}`
						if fs.isDir(full) then
							walk(full, `{rel}{name}/`)
						else
							table.insert(out, `{rel}{name}={fs.readFile(full)}`)
						end
					end
				end
				walk(base, "")
				table.sort(out)
				return out
			end
			local before = snapshot()
			t.expect(approverun.addRuling(checkout, RUN, approve("c0001"))).toBe(nil)
			-- exactly one file changed, and it is rulings.tsv
			local after = snapshot()
			local changed: { string } = {}
			for _, line in after do
				if not table.find(before, line) then
					table.insert(changed, (string.match(line, "^([^=]+)=")) :: string)
				end
			end
			t.expect(changed).toEqual({ `checkout/.cache/approve/{RUN}/rulings.tsv` })
			t.expect(#after).toBe(#before)
			t.expect(fs.readFile(`{base}/outside.txt`)).toBe("untouched")

			local settled = snapshot()
			for _, run in
				{ "../approverun-spec/checkout/.cache/approve/" .. RUN, `{RUN}/..`, "../../x", "/etc/passwd" }
			do
				t.expect(approverun.addRuling(checkout, run, approve("c0002")))
					.toBe(`{run} is not a run id (YYYYMMDDTHHMMSSZ-xxxx)`)
			end
			for _, ticket in { "../../outside", "c0002/../c0001", "c0001\nc0002" } do
				t.expect(approverun.addRuling(checkout, RUN, approve(ticket)) ~= nil).toBe(true)
			end
			t.expect(snapshot()).toEqual(settled)
			t.expect(fs.isFile(`{dir}/rulings.tsv`)).toBe(true)
			fs.removeDir(base)
		end
	)
end)
