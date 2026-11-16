--!strict
-- c0180: the exact narrowings of the three promoted specs this chore overrides (the Regression guard's Overrides).
-- Each is { id, file, digest, old, new }: the file is tests/acceptance/<id>/<file> in z-nile's home, `old` occurs in
-- it exactly once in main's file, and the narrowing replaces it with `new`; `digest` is the sha256 of the narrowed file
-- with CRLF written LF and every item id (c, d, f or R and four digits) written ID, so a checkout's line endings and a
-- compaction leave it valid. Read by narrowed.spec; applied by the executor.
export type Narrowing = { id: string, file: string, digest: string, old: string, new: string }

local narrowings: { Narrowing } = {
	{
		id = "c" .. "0081",
		file = "publish-guard.spec.luau",
		digest = "1b2357f8e9e90924099ebbaf8e890b7bf9d99b01cd66952eac4f06d32958b318",
		old = '\tit("main.luau refuses a stale tree right before every publish.commit but remap\'s", function()\n\t\t-- c0120 override: specs run from z-nile\'s home, so the engine is z-nile\'s engine/\n\t\tlocal found = mentions(fs.readFile("engine/main.luau"))\n\t\tt.expect(#found > 0).toBe(true)\n\t\tlocal others = 0\n\t\tfor _, m in found do\n\t\t\tt.expect(string.find(m.code, "publish.commit(", 1, true) ~= nil).toBe(true) -- a call, never an alias\n\t\t\tif m.fn ~= "cmd.remap" then\n\t\t\t\tothers += 1\n\t\t\t\tt.expect(m.refused).toBe(true)\n\t\t\tend\n\t\tend\n\t\tt.expect(others > 0).toBe(true)\n\tend)\n',
		new = '\tit("every engine module refuses a stale tree right before every publish.commit but remap\'s", function()\n\t\t-- c0120 override: specs run from z-nile\'s home, so the engine is z-nile\'s engine/\n\t\t-- c0180 override: the commands moved to engine/cmd/, so every engine module is read; cmd/remap.luau is the\n\t\t-- exception, and engine/publish.luau, which defines publish.commit, is not a caller\n\t\tlocal others = 0\n\t\tlocal function scan(dir: string)\n\t\t\tfor _, name in fs.readDir(dir) do\n\t\t\t\tlocal path = `{dir}/{name}`\n\t\t\t\tif fs.isDir(path) then\n\t\t\t\t\tscan(path)\n\t\t\t\telseif string.match(name, "%.luau$") and path ~= "engine/publish.luau" then\n\t\t\t\t\tfor _, m in mentions(fs.readFile(path)) do\n\t\t\t\t\t\tt.expect(string.find(m.code, "publish.commit(", 1, true) ~= nil).toBe(true) -- a call, never an alias\n\t\t\t\t\t\tif path ~= "engine/cmd/remap.luau" then\n\t\t\t\t\t\t\tothers += 1\n\t\t\t\t\t\t\tt.expect(m.refused).toBe(true)\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tscan("engine")\n\t\tt.expect(others > 0).toBe(true)\n\tend)\n',
	},
	{
		id = "c" .. "0074",
		file = "done-gate.spec.luau",
		digest = "f3a3b469eab77061285f7772df99f15e4a72fad2f60e7eb06425fb34bed8881c",
		old = '\t\tlocal main = fs.readFile(`{root}/z-nile/engine/main.luau`)\n\t\tt.expect(string.find(main, "doneGate(process.env)", 1, true) ~= nil).toBe(true)\n\t\tt.expect((string.find(main, "PICKMAN_DONE_GATE", 1, true))).toBe(nil)\n',
		new = '\t\t-- c0180 override: done moved to engine/cmd/done.luau, and no engine module reads the switch itself\n\t\tlocal doneSource = fs.readFile(`{root}/z-nile/engine/cmd/done.luau`)\n\t\tt.expect(string.find(doneSource, "doneGate(process.env)", 1, true) ~= nil).toBe(true)\n\t\tlocal scanned = 0\n\t\tlocal function scan(dir: string)\n\t\t\tfor _, name in fs.readDir(dir) do\n\t\t\t\tlocal path = `{dir}/{name}`\n\t\t\t\tif fs.isDir(path) then\n\t\t\t\t\tscan(path)\n\t\t\t\telseif string.match(name, "%.luau$") then\n\t\t\t\t\tscanned += 1\n\t\t\t\t\tt.expect((string.find(fs.readFile(path), "PICKMAN_DONE_GATE", 1, true))).toBe(nil)\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tscan(`{root}/z-nile/engine`)\n\t\tt.expect(scanned > 1).toBe(true)\n',
	},
	{
		id = "c" .. "0115",
		file = "docs.spec.luau",
		digest = "3f608ecc23f1185222f1effc81c29a33a7f61eae4cd51730fefd5ca715094633",
		old = "(`FREEZES` in `z-nile/engine/main.luau`)",
		new = "(`FREEZES` in `z-nile/engine/cmd/busy.luau`)",
	},
}

return narrowings
