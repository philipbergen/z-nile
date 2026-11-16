--!strict
-- c0257 AC7: fetch.sh turns the board's JSON into the model the app reads, through ./zn only, and fails with its own codes. It
-- runs against a fixture repository under .cache with stub `zn` and `lune` programs (the real ones are never started), HOME
-- and XDG_CACHE_HOME pointing into the fixture so the script writes only there.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`
local DIR = ".cache/c0257-fetch"

local MODEL = {
	issues = {
		{ id = "f0002", type = "feature", title = "Two", stage = "new", dependsOn = { "c0001" }, body = "x" },
		{ id = "c0001", type = "chore", title = "One", stage = "active", raft = "R0001", dependsOn = {} },
	},
	rafts = { { id = "R0001", type = "chore", label = "chore", title = "Raft", stage = "active", issues = { "c0001" } } },
	home = "/home/someone/elsewhere",
}

local SPEND = [[
# Spend
| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-11-01 | abc | 10 | 2 | 7.5 | a | build | 2000 |
| 2 | 2026-11-02 | def | 0 | 0 | 5 | a | code-review | 1000 |
<!-- totals: minutes=12.5 tokens=3000 added=10 removed=2 -->
]]

local function write(path: string, text: string)
	local dir = string.match(path, "^(.*)/[^/]*$") :: string
	fs.writeDir(dir)
	fs.writeFile(path, text)
end

local function build(withJsonFlag: boolean, page: string?)
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	local json = serde.encode("json", MODEL)
	write(`{DIR}/repo/pickman/.tracker/issues/f0002/f0002.md`, "---\nid: f0002\n---\n")
	write(`{DIR}/repo/z-nile/.tracker/issues/active/c0001/c0001.md`, "---\nid: c0001\n---\n")
	write(`{DIR}/repo/z-nile/.tracker/issues/active/c0001/spend.md`, SPEND)
	write(`{DIR}/repo/z-nile/.tracker/rafts/active/R0001/R0001.md`, "---\nid: R0001\n---\n")
	write(`{DIR}/repo/z-nile/engine/main.luau`, if withJsonFlag then "-- board [--json] board --json\n" else "-- board [--out PATH] [-O]\n")
	write(`{DIR}/page.html`, page or `<html><script type="application/json" id="board-data">{json}</script></html>`)
	write(`{DIR}/model.json`, json)
	-- the stub ./zn: writes the page for `board -O --out X`, prints the model for `board --json`
	write(
		`{DIR}/repo/zn`,
		'#!/usr/bin/env bash\ncase "$*" in\n  "board --json") cat "$STUB_MODEL" ;;\n  "board -O --out "*) cp "$STUB_PAGE" "$4" ;;\n  *) echo "unexpected zn $*" >&2; exit 9 ;;\nesac\n'
	)
	write(
		`{DIR}/home/.rokit/bin/lune`,
		'#!/usr/bin/env bash\nif [[ "$*" == "run z-nile/roots -- --projects" ]]; then\n  printf "pickman\\t/h/pickman\\tpickman/.tracker\\nz-nile\\t/h/z-nile\\tz-nile/.tracker\\n"\nelse echo "unexpected lune $*" >&2; exit 9; fi\n'
	)
	process.exec("chmod", { "+x", `{DIR}/repo/zn`, `{DIR}/home/.rokit/bin/lune` })
end

local function fetch(): process.ExecResult
	local abs = (string.gsub(process.exec("pwd", {}).stdout, "%s+$", ""))
	return process.exec("bash", { `{APP}/fetch.sh`, `{abs}/{DIR}/repo` }, {
		env = {
			HOME = `{abs}/{DIR}/home`,
			XDG_CACHE_HOME = `{abs}/{DIR}/home/cache`,
			STUB_MODEL = `{abs}/{DIR}/model.json`,
			STUB_PAGE = `{abs}/{DIR}/page.html`,
		},
	})
end

return t.spec("c0257: fetch.sh builds the app's model", function(it)
	it("AC7: from the board page's embedded JSON: projects, paths, spend, order, repository", function()
		build(false)
		local r = fetch()
		t.expect(r.ok).toBe(true)
		local m = serde.decode("json", r.stdout) :: any
		t.expect(m.projects.f0002).toBe("pickman")
		t.expect(m.projects.c0001).toBe("z-nile")
		t.expect(m.projects.R0001).toBe("z-nile")
		t.expect(m.paths.c0001).toBe("z-nile/.tracker/issues/active/c0001/c0001.md")
		t.expect(m.projectOrder).toEqual({ "pickman", "z-nile" })
		t.expect(m.spend.c0001.minutes).toBe(12.5)
		t.expect(m.spend.c0001.tokens).toBe(3000)
		t.expect(m.spend.c0001.phases.build.minutes).toBe(7.5)
		t.expect(m.spend.c0001.phases["code-review"].tokens).toBe(1000)
		t.expect(#m.issues).toBe(2)
		t.expect(m.home).toBe(nil) -- the machine's own path never rides along
		t.expect(type(m.fetchedAt)).toBe("string")
		t.expect(string.sub(m.repo, -#"/repo")).toBe("/repo")
		-- no remote in a fixture: no web base, so no links
		t.expect(m.webBase).toBe("")
	end)

	it("AC7: from ./zn board --json once the engine has it, with the same enrichment", function()
		build(true)
		local r = fetch()
		t.expect(r.ok).toBe(true)
		local m = serde.decode("json", r.stdout) :: any
		t.expect(m.projects.c0001).toBe("z-nile")
		t.expect(m.spend.c0001.minutes).toBe(12.5)
	end)

	it("AC7: a page without the embedded model fails, and a repository without ./zn exits 2", function()
		build(false, "<html>no data</html>")
		t.expect(fetch().ok).toBe(false)
		build(false)
		fs.removeFile(`{DIR}/repo/zn`)
		local r = fetch()
		t.expect(r.code).toBe(2)
	end)
end)
