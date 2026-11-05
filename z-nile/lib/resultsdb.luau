--!strict
-- The shared results db (c0165), through the sqlite3 CLI: one row per spec fingerprint, one per whole-gate key. Adapter:
-- it runs `sqlite3` (PICKMAN_SQLITE3 when set) and reads its JSON. Every call ends with exactly one SELECT of a
-- json_object, so the last line of output is the answer. WAL mode, a busy timeout, and a schema version in
-- `PRAGMA user_version`: c0238 and c0240 raise `resultsdb.SCHEMA` and migrate older files; a db with a higher number was
-- made by newer code, and `open` leaves it alone (reuse off).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local resultsdb = {}

resultsdb.SCHEMA = 1
local KEEP_SECONDS = 30 * 86400

export type Case = { name: string, ok: boolean }
export type Row = {
	state: string, -- "passed" | "failed"
	cases: { Case },
	detail: string?,
	seconds: number?,
	updated: number,
}
export type Db = { path: string }

local function binary(): string
	local b = process.env.PICKMAN_SQLITE3
	return if b ~= nil and b ~= "" then b else "sqlite3"
end

local function q(s: string): string
	return "'" .. string.gsub(s, "'", "''") .. "'"
end

-- Runs SQL on a db file and returns the decoded last output line, or nil and the error text.
local function call(path: string, sql: string): (any, string?)
	local ok, r = pcall(process.exec, binary(), { "-batch", "-bail", "-noheader", "-list", path }, {
		stdio = { stdin = ".timeout 10000\n" .. sql .. "\n" },
		env = { PATH = process.env.PATH or "" }, -- the child looks the binary up on the PATH the caller sees
	})
	if not ok then
		return nil, `sqlite3 could not run: {r}`
	end
	if not r.ok then
		return nil, `sqlite3 failed: {r.stderr}{r.stdout}`
	end
	local last = ""
	for line in string.gmatch(r.stdout, "[^\n]+") do
		last = line
	end
	if last == "" then
		return nil, "sqlite3 answered nothing"
	end
	local decoded, value = pcall(serde.decode, "json" :: "json", last)
	if not decoded then
		return nil, `sqlite3 answered unreadable JSON: {last}`
	end
	return value, nil
end

local SCHEMA_SQL = [[
CREATE TABLE IF NOT EXISTS specs(
  fp TEXT PRIMARY KEY, home TEXT NOT NULL, spec TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('passed','failed')),
  cases TEXT, detail TEXT, seconds REAL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS gates(key TEXT PRIMARY KEY, mode TEXT NOT NULL, projects TEXT NOT NULL,
  passed_at INTEGER NOT NULL, summary TEXT NOT NULL);
]]

-- Opens (creating it) the db at `path`: nil and a reason when it can't be used.
function resultsdb.open(path: string): (Db?, string?)
	local folder = string.match(path, "^(.*)/[^/]+$")
	if folder and folder ~= "" then
		local ok, err = pcall(fs.writeDir, folder)
		if not ok then
			return nil, `cannot create {folder}: {err}`
		end
	end
	local v, err = call(path, "SELECT json_object('v', (SELECT user_version FROM pragma_user_version));")
	if v == nil then
		return nil, err
	end
	local version = (v :: any).v :: number
	if version > resultsdb.SCHEMA then
		return nil, `schema {version} is newer than this code's {resultsdb.SCHEMA}`
	end
	if version == 0 then
		local _, werr = call(
			path,
			`PRAGMA journal_mode=WAL;\n{SCHEMA_SQL}PRAGMA user_version={resultsdb.SCHEMA};\nSELECT json_object('ok', 1);`
		)
		if werr then
			return nil, werr
		end
	end
	-- a number between 0 and SCHEMA is an older db the code would migrate here (none exists while SCHEMA is 1)
	return { path = path }, nil
end

-- fingerprint -> row, for the fingerprints that have one.
function resultsdb.rows(db: Db, fps: { string }): { [string]: Row }
	if #fps == 0 then
		return {}
	end
	local list: { string } = {}
	for _, fp in fps do
		table.insert(list, q(fp))
	end
	local v, err = call(
		db.path,
		`SELECT json_object('rows', json((SELECT json_group_array(json_object('fp', fp, 'state', state, 'cases', cases, 'detail', detail, 'seconds', seconds, 'updated', updated)) FROM specs WHERE fp IN ({table.concat(
			list,
			","
		)}))));`
	)
	if v == nil then
		error(err)
	end
	local out: { [string]: Row } = {}
	-- a nested array comes back as an array on some sqlite3 builds and as text on others; json() above makes it one,
	-- and a text one is decoded here too, so no build can break the read
	local found: any = (v :: any).rows or {}
	if type(found) == "string" then
		local decoded = serde.decode("json" :: "json", found)
		found = decoded
	end
	for _, r in found do
		local cases: { Case } = if r.cases then serde.decode("json" :: "json", r.cases) else {}
		out[r.fp] = {
			state = r.state,
			cases = cases,
			detail = r.detail,
			seconds = r.seconds,
			updated = r.updated,
		}
	end
	return out
end

function resultsdb.recordGate(
	db: Db,
	key: string,
	mode: string,
	projects: string,
	summary: string,
	now: number
)
	local _, err = call(
		db.path,
		`INSERT INTO gates(key, mode, projects, passed_at, summary) VALUES ({q(key)}, {q(mode)}, {q(projects)}, {now}, {q(
			summary
		)}) ON CONFLICT(key) DO UPDATE SET mode=excluded.mode, projects=excluded.projects, passed_at=excluded.passed_at, summary=excluded.summary;\nSELECT json_object('changes', changes());`
	)
	if err then
		error(err)
	end
end

function resultsdb.gatePassed(db: Db, key: string): { passedAt: number, summary: string }?
	local v, err = call(
		db.path,
		`SELECT json_object('gate', json((SELECT json_object('passed_at', passed_at, 'summary', summary) FROM gates WHERE key = {q(
			key
		)})));`
	)
	if v == nil then
		error(err)
	end
	local gate = (v :: any).gate
	if gate == nil then
		return nil
	end
	local decoded: any = if type(gate) == "string" then serde.decode("json" :: "json", gate) else gate
	return { passedAt = decoded.passed_at, summary = decoded.summary }
end

export type Item = {
	fp: string,
	home: string,
	spec: string,
	loaded: boolean,
	cases: { Case },
	detail: string?,
	seconds: number,
}

-- Text any bytes survive: SQLite's CLI reads its script as text, so a NUL byte ends a statement early and a stored
-- value that is not UTF-8 makes the JSON the reads come back in unreadable. Both become "?" (review 002 F1).
local function clean(s: string): string
	local out = string.gsub(s, "%z", "?")
	if utf8.len(out) == nil then
		out = string.gsub(out, "[\128-\255]", "?")
	end
	return out
end

-- The one rule for a result: passed only for a loaded file with every case ok; the latest write wins. record,
-- recordMany and every spec of AC4 go through this text (review 002 F2).
local function upsertSql(it: Item, now: number): string
	local passed = it.loaded
	for _, c in it.cases do
		if not c.ok then
			passed = false
		end
	end
	local cases: { Case } = {}
	for _, c in it.cases do
		table.insert(cases, { name = clean(c.name), ok = c.ok })
	end
	local encoded = serde.encode("json" :: "json", cases)
	local detail = if it.detail then q(clean(it.detail)) else "NULL"
	return `INSERT INTO specs(fp, home, spec, state, cases, detail, seconds, updated) VALUES ({q(clean(it.fp))}, {q(
		clean(it.home)
	)}, {q(clean(it.spec))}, {q(if passed then "passed" else "failed")}, {q(clean(encoded))}, {detail}, {it.seconds}, {now}) ON CONFLICT(fp) DO UPDATE SET home=excluded.home, spec=excluded.spec, state=excluded.state, cases=excluded.cases, detail=excluded.detail, seconds=excluded.seconds, updated=excluded.updated;`
end

local function pruneSql(now: number): string
	local cutoff = now - KEEP_SECONDS
	return `DELETE FROM specs WHERE updated < {cutoff};\nDELETE FROM gates WHERE passed_at < {cutoff};`
end

-- Records a result under a fingerprint: passed only for a loaded file with every case ok; the latest write wins.
function resultsdb.record(
	db: Db,
	fp: string,
	home: string,
	spec: string,
	loaded: boolean,
	cases: { Case },
	detail: string?,
	seconds: number,
	now: number?
)
	local it: Item = {
		fp = fp,
		home = home,
		spec = spec,
		loaded = loaded,
		cases = cases,
		detail = detail,
		seconds = seconds,
	}
	local _, err =
		call(db.path, `{upsertSql(it, now or os.time())}\nSELECT json_object('changes', changes());`)
	if err then
		error(err)
	end
end

-- Drops rows and gates older than 30 days.
function resultsdb.prune(db: Db, now: number)
	local _, err = call(db.path, `{pruneSql(now)}\nSELECT json_object('ok', 1);`)
	if err then
		error(err)
	end
end

-- Records every item and prunes in ONE sqlite3 call, in one transaction: a failure records nothing.
function resultsdb.recordMany(db: Db, items: { Item }, now: number)
	local sql = { "BEGIN IMMEDIATE;" }
	for _, it in items do
		table.insert(sql, upsertSql(it, now))
	end
	table.insert(sql, pruneSql(now))
	table.insert(sql, "COMMIT;")
	table.insert(sql, "SELECT json_object('ok', 1);")
	local _, err = call(db.path, table.concat(sql, "\n"))
	if err then
		error(err)
	end
end

return resultsdb
