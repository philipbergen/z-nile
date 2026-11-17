--!strict
-- c0257 AC8: the board page's embedded model, built by the engine from a fixture tracker, is what the app's model reads.
-- The app is a second view of the served board's data (c0121's page loads the same model), so a rename or removal of a key
-- the app reads fails here, and a key added to the page (c0276's heartbeat marks, c0249's rank) changes nothing the app shows.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`
local DIR = ".cache/c0257-contract"

local FILES: { { any } } = {
	{
		"rafts/active/R0020/R0020.md",
		{ "id: R0020", "type: feature", "title: Beta", "design: ready" },
		"# R0020: Beta\n",
	},
	{
		"issues/done/c0010/c0010.md",
		{ "id: c0010", "type: chore", "title: First", "raft: ", "depends_on: []" },
		"# c0010: First\n",
	},
	{
		"issues/active/f0020/f0020.md",
		{ "id: f0020", "type: feature", "title: Second", "raft: R0020", "depends_on: [c0010]" },
		"# f0020: Second\n\nBody text.\n",
	},
	{
		"issues/f0030/f0030.md",
		{ "id: f0030", "type: feature", "title: Third", "raft: ", "depends_on: [f0020]" },
		"# f0030: Third\n",
	},
}

local PROBE = [==[
const fs = process.getBuiltinModule("fs");
const src = fs.readFileSync(process.argv[2] + "/Model.js", "utf8").replace(/^\.pragma library\s*$/m, "");
const names = [...src.matchAll(/^function (\w+)/gm)].map(m => m[1]);
const M = new Function(src + "\nreturn { " + names.join(", ") + " }")();
const raw = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const m = M.normalize(raw);
console.log(JSON.stringify({
  issues: m.issues.map(i => [i.id, i.stage, i.blockedBy, i.title, i.command || ""]),
  rafts: m.rafts.map(r => [r.id, r.stage, r.issues, r.command || ""]),
}));
]==]

local STATS_PROBE = [==[
const fs = process.getBuiltinModule("fs");
const src = fs.readFileSync(process.argv[2] + "/Model.js", "utf8").replace(/^\.pragma library\s*$/m, "");
const names = [...src.matchAll(/^function (\w+)/gm)].map(m => m[1]);
const M = new Function(src + "\nreturn { " + names.join(", ") + " }")();
const stats = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const days = M.activity(stats), week = M.weekSummary(stats);
console.log(JSON.stringify({ days: days.length, label: days.length ? days[0].label : "", week: week !== null }));
]==]

return t.spec("c0257: the board page's model is the app's input", function(it)
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	for _, f in FILES do
		local path = `{DIR}/tracker/{f[1]}`
		fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
		fs.writeFile(path, "---\n" .. table.concat(f[2] :: any, "\n") .. "\n---\n\n" .. (f[3] :: string))
	end
	local page = board.render(
		board.collect(`{DIR}/tracker`, nil, { asOf = 1794000000, refs = {}, worktrees = {}, dispatch = {} }),
		fs.readFile(`{TOP}/{board.MARKED_PATH}`)
	)
	local json = string.match(page, '<script type="application/json" id="board%-data">(.-)</script>')
	local model = if json then serde.decode("json", json) :: any else nil

	it("AC8: the page embeds the model, and every key the app reads is on the items", function()
		t.expect(model ~= nil).toBe(true)
		local byId: { [string]: any } = {}
		for _, i in model.issues do
			byId[i.id] = i
		end
		for _, r in model.rafts do
			byId[r.id] = r
		end
		for _, id in { "f0020", "f0030", "c0010", "R0020" } do
			local item = byId[id]
			t.expect(`{id}:{item ~= nil}`).toBe(`{id}:true`)
			for _, key in
				{
					"id",
					"type",
					"title",
					"stage",
					"status",
					"design",
					"body",
					"dependsOn",
					"dependents",
					"label",
				}
			do
				t.expect(`{id}.{key}:{item[key] ~= nil}`).toBe(`{id}.{key}:true`)
			end
		end
		t.expect(type(byId.R0020.issues)).toBe("table")
		t.expect(byId.f0020.raft).toBe("R0020")
		t.expect(byId.f0030.dependsOn).toEqual({ "f0020" })
		t.expect(type(model.stats)).toBe("table")
	end)

	it("AC8: the app's normalize takes the real model: every card, its stage and its blockers", function()
		fs.writeFile(`{DIR}/probe.js`, PROBE)
		fs.writeFile(`{DIR}/model.json`, json or "{}")
		local r = process.exec("node", { `{DIR}/probe.js`, APP, `{DIR}/model.json` })
		t.expect(r.ok).toBe(true)
		local out = serde.decode("json", r.stdout) :: any
		local stages: { [string]: string } = {}
		local blocked: { [string]: { string } } = {}
		for _, i in out.issues do
			stages[i[1]] = i[2]
			blocked[i[1]] = i[3]
		end
		t.expect(stages).toEqual({ c0010 = "done", f0020 = "active", f0030 = "new" })
		t.expect(blocked.f0030).toEqual({ "f0020" })
		t.expect(blocked.f0020).toEqual({})
		t.expect(out.rafts[1][1]).toBe("R0020")
		t.expect(out.rafts[1][3]).toEqual({ "f0020" })
		-- the next command rides on every card that has a next step (not on done work). The chart and the week summary read
		-- stats.views.month and stats.periods.week, which the page computes from git history that a fixture tracker has no
		-- repository for: those keys are proved against the real tree (E2) and by OC1, not here
		for _, i in out.issues do
			t.expect(`{i[1]} command:{i[5] ~= ""}`).toBe(`{i[1]} command:{i[2] ~= "done"}`)
		end
		t.expect(out.rafts[1][4] ~= "").toBe(true)
	end)

	it(
		"AC8: the chart and the week summary read the engine's stats: a month of days, a labelled bucket, a week",
		function()
			-- stats.compute is the engine's pure source of the page's `stats`; the page embeds its result as it is
			local computed = stats.compute({}, {}, "2026-11-15", true)
			fs.writeFile(`{DIR}/stats.json`, serde.encode("json", computed))
			fs.writeFile(`{DIR}/stats-probe.js`, STATS_PROBE)
			local r = process.exec("node", { `{DIR}/stats-probe.js`, APP, `{DIR}/stats.json` })
			t.expect(r.ok).toBe(true)
			local out = serde.decode("json", r.stdout) :: any
			t.expect(out.days >= 28).toBe(true)
			t.expect(out.label ~= "").toBe(true)
			t.expect(out.week).toBe(true)
		end
	)
end)
