--!strict
-- c0250 AC9 to AC11: a blocked raft is nobody's to take (work, readycheck), the board's first column holds what
-- waits on the person (boardview, board.collect over a tracker folder under .cache), `./zn list` and `./zn status`
-- print blocked items first (a fixture under .cache), and `.models.toml` reads `quota_cap_hours`.
local board = require("@znile/engine/board")
local boardview = require("@znile/engine/boardview")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local work = require("@znile/engine/work")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BOARD = ".cache/c0250-board/pickman/.tracker"

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function raft(over: { [string]: any }): work.RaftFact
	local r: any = {
		id = "R0010",
		title = "t",
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		blocked = nil,
		issues = { "c0010" },
		layers = {},
		holder = "Ada <ada@example>",
		since = "2026-11-12T00:00:00-08:00",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "",
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

local DOC =
	"---\nid: c0001\ndesign: ready\n---\n\n# c0001\n\n## Problem\nP\n\n## Solution\nS\n\n## Design\nD\n\n## Acceptance criteria\nA\n\n## Test plan\nT\n"

local function readyRaft(over: { [string]: any }): readycheck.Raft
	local r: any = {
		id = "R0001",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0001",
		design = "ready",
		doc = "---\ndesign: ready\n---\n",
		grouped = nil,
		listed = { "c0001" },
		members = {
			{
				id = "c0001",
				design = "ready",
				doc = DOC,
				deps = {},
				files = {
					["c0001.md"] = DOC,
					["check.sh"] = 'check "AC1: holds" true\n',
					["approval.md"] = "",
				},
				specs = {},
				approval = nil,
				approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
			},
		},
		files = { ["check.sh"] = 'check "AC1: holds" true\n' },
		loaded = true,
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

local function note(question: string): string
	return `# Escalation: x\nItem: x\nReason: red-gate\nFrom: preparing\nActor: human:Ada\nWhen: 2026-11-20 03:10\n\n## Question\n{question}\n\n## What was tried\nTwice.\n\n## Open findings or error\nF1.\n\n## Options\n- retry: again (recommended)\n- abort: stop\n\n## Resume\n./zn resolve x retry --answer "<your answer>"\n./zn resolve x abort --answer "<your answer>"\n`
end

local function item(id: string, status: string, extra: string): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: {extra}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: {status}\n{if string.sub(
			status,
			1,
			7
		) == "blocked"
		then "blocked: red-gate\n"
		else ""}---\n\n# {id}\n\n## Problem\nP\n`
end

local function raftDoc(id: string, status: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-10\nstatus: {status}\n{if string.sub(
			status,
			1,
			7
		) == "blocked"
		then "blocked: needs-decision\n"
		else ""}---\n\n# {id}\n\n## Theme\nT\n`
end

-- read through any: the cap is c0250's to add
local function quotaCap(layers: { models.Layer }): number?
	return (models :: any).quotaCapHours(layers)
end

local f: trackerfix.Fixture

return t.spec("c0250 blocked rafts, the board and the cap", function(it)
	it(
		"AC9: a blocked raft is not claimable, whyNone and forRaft say so, and readycheck refuses it",
		function()
			local blocked = raft({ id = "R0010", status = "blocked", blocked = "red-gate" })
			local other = raft({ id = "R0020", block = "" })
			-- not claimable, however ready its design and dependencies look
			t.expect(work.claimable(blocked)).toBe(false)
			t.expect(
				work.claimable(raft({ id = "R0030", status = "blocked", blocked = "quota", block = "" }))
			)
				.toBe(false)
			t.expect(work.claimable(raft({}))).toBe(true)
			-- an unnamed session passes it by and takes the next raft
			local next = work.decide({ rafts = { blocked, other } })
			t.expect(next.raft).toBe("R0020")
			t.expect(next.action).toBe("ready")
			-- with nothing else, it says why
			local none = work.decide({ rafts = { blocked } })
			t.expect(none.action).toBe("none")
			t.expect(has(none.why, "R0010: is blocked (red-gate): a human resolves it with ./zn resolve"))
				.toBe(true)
			t.expect(has(work.whyNone({ blocked }), "R0010: is blocked (red-gate)")).toBe(true)
			t.expect(
				has(
					work.report({ rafts = { blocked } }, none),
					"is blocked (red-gate): a human resolves it with ./zn resolve"
				)
			).toBe(true)
			-- a session that named it ends: its hold is over, a fresh session takes the next raft
			local named = work.decide({ asked = "R0010", rafts = { blocked, other } })
			t.expect(named.action).toBe("end")
			t.expect(named.raft).toBe("R0010")
			t.expect(has(named.why, "R0010 is blocked: start a fresh session")).toBe(true)
			-- the old signal is gone: a raft with no blocked status is claimable whatever else it holds
			t.expect((raft({}) :: any).questions).toBe(nil)
			-- readycheck refuses it before it looks at anything else, naming the command that gets past
			local why, final = readycheck.reason(readyRaft({ status = "blocked" }))
			t.expect(why).toBe("R0001 is blocked: ./zn resolve R0001 <decision> first")
			t.expect(final).toBe(true)
			local prepared = readycheck.reason(readyRaft({}))
			t.expect(has(prepared or "", "is blocked")).toBe(false)
			t.expect(has(prepared or "", "./zn approve c0001 --publish")).toBe(true)
			-- a raft that is active is still refused as "only a prepared raft is readied"
			t.expect(
				has(
					readycheck.reason(readyRaft({ where = "active", status = "active" })) or "",
					"only a prepared raft"
				)
			).toBe(true)
		end
	)

	it(
		"AC10: the board's first column is blocked, each card with its reason and question, and list and status print blocked items first",
		function()
			-- the columns
			t.expect(boardview.COLUMNS)
				.toEqual({ "blocked", "ticket", "design", "raft", "ready", "run", "done" })
			t.expect((boardview.LABELS :: any).blocked).toBe("Blocked")
			t.expect(boardview.column("blocked", false)).toBe("blocked")
			t.expect(boardview.column("blocked", true)).toBe("blocked")
			t.expect(boardview.column("new", false)).toBe("ticket")
			t.expect(boardview.column("active", true)).toBe("run")
			t.expect(function()
				boardview.column("stuck", false)
			end).toThrow("stuck is not an effective status")
			-- the model of a tracker folder: blocked issues, a blocked raft with its members, a blocked draft raft whose
			-- members are not themselves blocked, a note that does not parse, and an item that is not blocked
			if fs.isDir(".cache/c0250-board") then
				fs.removeDir(".cache/c0250-board")
			end
			local long = string.rep("Which library should we take? ", 12)
			local files: { [string]: string } = {
				["issues/c0010/c0010.md"] = item("c0010", "blocked-quiet-copper-falcon", ""),
				["issues/c0010/escalation.md"] = note(long),
				["rafts/R0100/R0100.md"] = raftDoc("R0100", "blocked-quiet-copper-falcon", "c0020, c0030"),
				["rafts/R0100/escalation.md"] = note("The gate is red on c0020."),
				["issues/c0020/c0020.md"] = item("c0020", "blocked-quiet-copper-falcon", "R0100"),
				["issues/c0030/c0030.md"] = item("c0030", "blocked-quiet-copper-falcon", "R0100"),
				["rafts/R0200/R0200.md"] = raftDoc("R0200", "blocked-quiet-copper-falcon", "c0050"),
				["rafts/R0200/escalation.md"] = note("Which members belong together?"),
				["issues/c0050/c0050.md"] = item("c0050", "prepared-quiet-copper-falcon", "R0200"),
				["issues/c0040/c0040.md"] = item("c0040", "blocked-quiet-copper-falcon", ""),
				["issues/c0040/escalation.md"] = "this is not a note\n",
				["issues/c0060/c0060.md"] = item("c0060", "prepared-quiet-copper-falcon", ""),
				["issues/c0070/c0070.md"] = item("c0070", "new-quiet-copper-falcon", ""),
			}
			for path, text in files do
				local full = `{BOARD}/{path}`
				fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
				fs.writeFile(full, text)
			end
			local model = board.collect(BOARD)
			local ids: { string } = {}
			for _, band in model.columns["pickman"]["blocked"] do
				for _, id in band.ids do
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			-- c0050 is not itself blocked, but its raft is: it waits in the blocked column with the raft
			t.expect(ids).toEqual({ "c0010", "c0020", "c0030", "c0040", "c0050" })
			local function issue(id: string): any
				for _, i in model.issues do
					if i.id == id then
						return i
					end
				end
				error(`no issue {id}`)
			end
			t.expect(issue("c0010").column).toBe("blocked")
			t.expect(issue("c0010").blocked.reason).toBe("red-gate")
			-- the question, cut at 200 characters
			t.expect(issue("c0010").blocked.question).toBe(string.sub(long, 1, 200))
			t.expect(#issue("c0010").blocked.question).toBe(200)
			-- members carry their raft's block: the reason of the raft's note and its question
			t.expect(issue("c0020").blocked.question).toBe("The gate is red on c0020.")
			t.expect(issue("c0050").blocked.question).toBe("Which members belong together?")
			t.expect(issue("c0050").blocked.reason).toBe("needs-decision")
			t.expect(issue("c0060").column).toBe("raft")
			t.expect(issue("c0060").blocked).toBe(nil)
			t.expect(issue("c0070").column).toBe("ticket")
			-- the bands: the blocked raft's members sit together
			local banded = false
			for _, band in model.columns["pickman"]["blocked"] do
				if band.raft == "R0100" then
					banded = true
					t.expect(band.ids).toEqual({ "c0020", "c0030" })
				end
			end
			t.expect(banded).toBe(true)
			-- the rafts know their block too
			for _, r in model.rafts do
				if r.id == "R0100" then
					t.expect((r :: any).blocked.reason).toBe("needs-decision")
				end
			end
			-- a note that does not parse goes to problems, and the card shows the reason alone
			local named = false
			for _, p in model.problems do
				if has(p, "issues/c0040/escalation.md does not parse") then
					named = true
				end
			end
			t.expect(named).toBe(true)
			t.expect(issue("c0040").blocked.question).toBe("")
			t.expect(issue("c0040").column).toBe("blocked")
			-- the page carries the column and the card's text
			local page = fs.readFile(`{TOP}/z-nile/engine/board.html`)
			t.expect(has(page, '"blocked", "ticket", "design", "raft", "ready", "run", "done"')).toBe(true)
			t.expect(has(page, 'blocked: "Blocked"')).toBe(true)
			-- list and status: blocked items first, then the order of before
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
					"R0010",
					"prepared-quiet-copper-falcon",
					"c0010"
				),
				["pickman/.tracker/rafts/R0010/check.sh"] = "finish\n",
				["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc(
					"R0020",
					"blocked-quiet-copper-falcon",
					"c0020"
				),
				["pickman/.tracker/rafts/R0020/check.sh"] = "finish\n",
			}
			local statuses: { [string]: string } = {
				c0010 = "prepared-quiet-copper-falcon",
				c0030 = "new-quiet-copper-falcon",
				c0040 = "blocked-quiet-copper-falcon",
				c0050 = "prepared-quiet-copper-falcon",
			}
			for id, status in statuses do
				seed[`pickman/.tracker/issues/{id}/{id}.md`] =
					item(id, status, if id == "c0010" then "R0010" else "")
				seed[`pickman/.tracker/issues/{id}/check.sh`] = "finish\n"
			end
			seed["pickman/.tracker/issues/c0020/c0020.md"] =
				item("c0020", "blocked-quiet-copper-falcon", "R0020")
			seed["pickman/.tracker/issues/c0020/check.sh"] = "finish\n"
			f = trackerfix.new("c0250-work-board", seed)
			local listed = fixture.exec(f.main, "./zn", { "list" })
			t.expect(listed.ok).toBe(true)
			local order: { string } = {}
			for line in string.gmatch(listed.stdout, "[^\n]+") do
				table.insert(order, string.match(line, "^(%S+)") :: string)
			end
			t.expect(order).toEqual({ "R0020", "c0020", "c0040", "R0010", "c0010", "c0030", "c0050" })
			local status = fixture.exec(f.main, "./zn", { "status" })
			t.expect(status.ok).toBe(true)
			local rows: { string } = {}
			for line in string.gmatch(status.stdout, "[^\n]+") do
				table.insert(
					rows,
					(string.match(line, "^(%S+) (%S+)") :: string)
						.. " "
						.. string.match(line, "^%S+ (%S+)") :: string
				)
			end
			t.expect(string.match(rows[1], "^%S+ blocked$") ~= nil).toBe(true)
			t.expect(string.match(rows[2], "^%S+ blocked$") ~= nil).toBe(true)
			t.expect(string.match(rows[3], "^%S+ blocked$") ~= nil).toBe(true)
			for i = 4, #rows do
				t.expect(has(rows[i], "blocked")).toBe(false)
			end
			t.expect(#rows).toBe(7)
		end
	)

	it("AC11: quota_cap_hours is read and a bad value is refused naming the key", function()
		local function layer(text: string, path: string?): models.Layer
			return models.parse(text, path or "a/.models.toml")
		end
		t.expect(quotaCap({})).toBe(nil)
		t.expect(quotaCap({ layer("[dispatch]\nauto_merge = []\n") })).toBe(nil)
		t.expect(quotaCap({ layer("[dispatch]\nquota_cap_hours = 24\n") })).toBe(24)
		-- the closest file that sets it wins, and one that does not set it leaves it
		t.expect(quotaCap({
			layer("[dispatch]\nquota_cap_hours = 24\n", ".models.toml"),
			layer("[dispatch]\nquota_cap_hours = 6\n", "pickman/.models.toml"),
		})).toBe(6)
		t.expect(quotaCap({
			layer("[dispatch]\nquota_cap_hours = 24\n", ".models.toml"),
			layer("[dispatch]\nauto_merge = []\n", "pickman/.models.toml"),
		})).toBe(24)
		-- a value that is not a whole number of at least 1 is refused, naming the key
		for _, bad in { "0", "-3", "1.5", '"24"', "true", "0.5" } do
			local ok, err = pcall(models.parse, `[dispatch]\nquota_cap_hours = {bad}\n`, "x/.models.toml")
			t.expect(ok).toBe(false)
			t.expect(has(tostring(err), "quota_cap_hours")).toBe(true)
			t.expect(has(tostring(err), "x/.models.toml")).toBe(true)
		end
		-- the other settings still read, and the key is listed among them
		local unknown, why = pcall(models.parse, "[dispatch]\nquota_cap = 4\n", "x/.models.toml")
		t.expect(unknown).toBe(false)
		t.expect(has(tostring(why), "quota_cap_hours")).toBe(true)
		local other = models.settings({ layer("[dispatch]\nquota_cap_hours = 24\nstall_seconds = 9\n") })
		t.expect(other.stallSeconds).toBe(9)
		-- the repository's own file still parses
		local own = models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml")
		t.expect(own.roles ~= nil).toBe(true)
		t.expect(HERE ~= "").toBe(true)
	end)
end)
