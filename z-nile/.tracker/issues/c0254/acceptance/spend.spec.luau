--!strict
-- c0254 AC4: spend rows record the host, the CLI and the model that spent them. The tsv a fold writes gains two cells; an
-- old file (12 cells, the old header) still reads, and a row of either shape reads back. The fold stamps every row it writes
-- with this machine's host and the CLI of the step (ZN_CLI, set by the dispatcher for each attempt), next to the model
-- cell (ZN_MODEL). Fixture folders under .cache/c0254-spend; the environment is set for the case and put back.
local buffer = require("@znile/engine/buffer")
local costrow = require("@znile/engine/costrow")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local BASE = (fixture.physical(".") :: string) .. "/.cache/c0254-spend"

local function row(phase: string, model: string?, host: string?, cli: string?): ledger.Row
	return {
		when = "2026-11-16 10:00",
		subject = "s",
		added = 3,
		removed = 1,
		minutes = 0,
		how = "measured",
		phase = phase,
		tokens = 100,
		model = model,
		host = host,
		cli = cli,
		wall = 1,
		cpu = 1,
		ai = 1,
		test = nil,
		unmeasured = "test",
	}
end

-- Sets `vars` and removes every name in `unset` for the body, then puts all of them back (a nil in a table constructor
-- is no key, so the names to remove are a list of their own).
local function withEnv(vars: { [string]: string }, unset: { string }, body: () -> ())
	local names: { string } = table.clone(unset)
	for k in vars do
		table.insert(names, k)
	end
	local saved: { [string]: string? } = {}
	for _, k in names do
		saved[k] = process.env[k]
	end
	for _, k in unset do
		process.env[k] = nil
	end
	for k, v in vars do
		process.env[k] = v
	end
	local ok, err = pcall(body)
	for _, k in names do
		process.env[k] = saved[k]
	end
	if not ok then
		error(err, 0)
	end
end

return t.spec("c0254 spend rows say who spent them", function(it)
	it("AC4: a row with a host and a CLI is written with two more cells and reads back whole", function()
		local text = buffer.appendTsv(nil, { row("build", "claude-opus-5-5", "m5-max.local", "claude") })
		local lines = string.split(text, "\n")
		t.expect(lines[1]).toBe(buffer.HEADER_WHO)
		t.expect(#string.split(lines[2] :: string, "\t")).toBe(14)
		local rows = buffer.parseTsv(text) :: { ledger.Row }
		t.expect(rows[1].host).toBe("m5-max.local")
		t.expect(rows[1].cli).toBe("claude")
		t.expect(rows[1].model).toBe("claude-opus-5-5")
	end)

	it("AC4: a file with the old header still reads, and takes new rows without losing their host and CLI", function()
		local old = buffer.appendTsv(nil, { row("build", "m1", nil, nil) })
		t.expect(string.split(old, "\n")[1]).toBe(buffer.HEADER)
		local rows = buffer.parseTsv(old) :: { ledger.Row }
		t.expect(rows[1].host).toBe(nil)
		t.expect(rows[1].cli).toBe(nil)
		local grown = buffer.appendTsv(old, { row("build", "m2", "h2", "grok") })
		local both = buffer.parseTsv(grown) :: { ledger.Row }
		t.expect(#both).toBe(2)
		t.expect(both[1].host).toBe(nil)
		t.expect(both[2].host).toBe("h2")
		t.expect(both[2].cli).toBe("grok")
		-- the rows already in the file are byte for byte as they were
		t.expect(string.sub(grown, 1, #old)).toBe(old)
	end)

	it("AC4: the fold stamps every row it writes with this host and the step's CLI, next to its model", function()
		local root = `{BASE}/fold`
		if fs.isDir(root) then
			fs.removeDir(root)
		end
		fs.writeDir(`{root}/item`)
		withEnv({ ZN_CLI = "grok", ZN_MODEL = "grok-4.7" }, { "CLAUDECODE" }, function()
			local planned = costrow.plan(
				root,
				{ c0010 = `{root}/item` },
				{ c0010 = { row("build", "grok-4.7", nil, nil) } },
				false
			)
			t.expect(#planned.files).toBe(1)
			local file = planned.files[1]
			t.expect(string.find(file.path, "/item/spend.d/", 1, true) ~= nil).toBe(true)
			local rows = buffer.parseTsv(file.text) :: { ledger.Row }
			t.expect(rows[1].cli).toBe("grok")
			t.expect(rows[1].model).toBe("grok-4.7")
			-- the host is the machine's, the same word the file name starts with
			local host = rows[1].host :: string
			t.expect(host ~= "").toBe(true)
			t.expect(string.sub(string.match(file.path, "([^/]+)%.tsv$") :: string, 1, #host)).toBe(host)
		end)
	end)

	it("AC4: a row that already says its host and CLI keeps them", function()
		local root = `{BASE}/keep`
		if fs.isDir(root) then
			fs.removeDir(root)
		end
		fs.writeDir(`{root}/item`)
		withEnv({ ZN_CLI = "grok" }, {}, function()
			local planned = costrow.plan(
				root,
				{ c0010 = `{root}/item` },
				{ c0010 = { row("prep", "m", "elsewhere", "kimi") } },
				false
			)
			local rows = buffer.parseTsv(planned.files[1].text) :: { ledger.Row }
			t.expect(rows[1].host).toBe("elsewhere")
			t.expect(rows[1].cli).toBe("kimi")
		end)
	end)

	it("AC4: with no CLI named and no marker the CLI cell says unknown, never a guess", function()
		local root = `{BASE}/unknown`
		if fs.isDir(root) then
			fs.removeDir(root)
		end
		fs.writeDir(`{root}/item`)
		withEnv(
			{},
			{ "ZN_CLI", "CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "KIMI_SESSION_ID", "KIMI_CODE_SESSION_ID" },
			function()
				local planned = costrow.plan(
					root,
					{ c0010 = `{root}/item` },
					{ c0010 = { row("build", nil, nil, nil) } },
					false
				)
				local rows = buffer.parseTsv(planned.files[1].text) :: { ledger.Row }
				t.expect(rows[1].cli).toBe("unknown")
			end
		)
	end)

	it("AC4: the dispatcher sets the CLI of each attempt next to its model", function()
		local text = fs.readFile("engine/dispatcher.luau")
		t.expect(string.find(text, "env.ZN_CLI = spec.cli", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "env.ZN_MODEL = spec.model", 1, true) ~= nil).toBe(true)
	end)
end)
