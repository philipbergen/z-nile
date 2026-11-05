--!strict
-- c0172: the local CICD command reserves the places, publishes them, and runs both runtime suites.
-- The Open Cloud here is a loopback fake. Nothing in this file reads ~/.config or the real key.
-- The modules are loaded from the checkout root so the same requires work in the issue folder and,
-- after promotion, in tests/acceptance/c0172.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function loadModule(rel: string): any
	local chunk, err = loadstring(fs.readFile(`{TOP}/{rel}`))
	if chunk == nil then
		error(err)
	end
	return chunk()
end

local CicdConfig = loadModule("pickman/scripts/lib/cicdconfig.luau")
local Lease = loadModule("pickman/scripts/lib/lease.luau")
local LeaseFile = loadModule("pickman/scripts/lib/leasefile.luau")

local PICKMAN = `{TOP}/pickman`
local root = (string.gsub(process.cwd, "/+$", ""))
local script = `{PICKMAN}/scripts/cicd`
local work = `{root}/.cache/cicd-spec`
local KEY = "KEY-NOT-IN-OUTPUT"
local INHERITED = "INHERITED-KEY-NOT-IN-OUTPUT"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function toml(): string
	return table.concat({
		`api_key = "{KEY}"`,
		'universe_id = "111"',
		"",
		"[places]",
		'cicd = "222"',
		'cicd_game = "333"',
		"",
	}, "\n")
end

type Saved = { version: string, body: string }

local function serve(opts: {
	rootPlace: string?,
	saved: Saved?,
	failPublish: boolean?,
	failRuntime: boolean?,
	failLease: boolean?,
	tombstone: boolean?,
	bare204: boolean?,
}): (number, { string }, () -> (), { [string]: number })
	local calls: { string } = {}
	local versions: { [string]: number } = {}
	local saved = opts.saved
	local versionN = if saved then 1 else 0
	local tasks = 0
	local tomb = opts.tombstone == true
	local tombVersion = "v-tomb"
	local bare = opts.bare204 == true
	local function describe(req: any): string
		local bits = {}
		local query = req.query
		if type(query) == "table" then
			for key, value in query do
				table.insert(bits, `{key}={value}`)
			end
			table.sort(bits)
		end
		local joined = table.concat(bits, "&")
		return if joined == "" then `{req.method} {req.path}` else `{req.method} {req.path}?{joined}`
	end
	local function header(req: any, name: string): string?
		local headers = req.headers
		if type(headers) ~= "table" then
			return nil
		end
		for key, value in headers do
			if string.lower(key) == name then
				return tostring(value)
			end
		end
		return nil
	end
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				local line = describe(req)
				table.insert(calls, line)
				if req.method == "GET" and req.path == "/cloud/v2/universes/111" then
					local place = opts.rootPlace or "999"
					return {
						status = 200,
						body = serde.encode("json" :: "json", { rootPlace = `universes/111/places/{place}` }),
					}
				end
				local query = req.query
				local store = if type(query) == "table" then query.datastoreName else nil
				if
					store == "Hiscores"
					or store == "HiscoreEntries"
					or (store ~= nil and store ~= Lease.STORE)
				then
					return { status = 400, body = "wrong store" }
				end
				if req.path == "/datastores/v1/universes/111/standard-datastores/datastore/entries/entry" then
					if req.method == "GET" then
						if opts.failLease then
							return { status = 403, body = "INSUFFICIENT_SCOPE" }
						end
						if tomb then
							return {
								status = 204,
								headers = { ["roblox-entry-version"] = tombVersion },
								body = "",
							}
						end
						if bare then
							return { status = 204, body = "" }
						end
						if saved == nil then
							return { status = 404, body = "missing" }
						end
						return {
							status = 200,
							headers = { ["roblox-entry-version"] = saved.version },
							body = saved.body,
						}
					end
					if req.method == "DELETE" then
						if saved == nil or query.matchVersion ~= saved.version then
							return { status = 412, body = "conflict" }
						end
						saved = nil
						return { status = 204, body = "" }
					end
					if req.method == "POST" then
						if header(req, "content-md5") ~= Lease.contentMd5(req.body) then
							return { status = 400, body = "bad md5" }
						end
						local untilAt = 0
						local parsed, decoded = pcall(serde.decode, "json" :: "json", req.body)
						if
							parsed
							and type(decoded) == "table"
							and type((decoded :: any)["until"]) == "number"
						then
							untilAt = (decoded :: any)["until"]
						end
						calls[#calls] ..= ` until={untilAt} clock={os.time()}`
						local match = query.matchVersion
						if bare and query.exclusiveCreate == "true" then
							bare = false
							tomb = true
							tombVersion = "v-reread"
							return { status = 412, body = "conflict" }
						end
						if tomb then
							if query.exclusiveCreate == "true" or match ~= tombVersion then
								return { status = 412, body = "conflict" }
							end
							tomb = false
						elseif query.exclusiveCreate == "true" then
							if saved ~= nil then
								return { status = 412, body = "conflict" }
							end
						elseif saved == nil or match ~= saved.version then
							return { status = 412, body = "conflict" }
						end
						versionN += 1
						-- `saved` is an upvalue, so the assignment does not narrow it for the type checker
						local writtenVersion = `v{versionN}`
						saved = { version = writtenVersion, body = req.body }
						return {
							status = 200,
							body = serde.encode("json" :: "json", { version = writtenVersion }),
						}
					end
				end
				local universe, place = string.match(req.path, "^/universes/v1/(%d+)/places/(%d+)/versions$")
				-- a match fills both captures, so requiring place narrows it and changes no request
				if req.method == "POST" and universe ~= nil and place ~= nil then
					if opts.failPublish then
						return { status = 400, body = "publish failed" }
					end
					local number = math.random(20, 4000)
					versions[place] = number
					return { status = 200, body = serde.encode("json" :: "json", { versionNumber = number }) }
				end
				if req.method == "POST" and has(req.path, "luau-execution-session-tasks") then
					tasks += 1
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ path = `tasks/{tasks}`, state = "PROCESSING" }
						),
					}
				end
				local taskId = string.match(req.path, "^/cloud/v2/tasks/(%d+)$")
				if req.method == "GET" and taskId ~= nil then
					local value = if opts.failRuntime then "nope" else "PASS"
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ path = `tasks/{taskId}`, state = "COMPLETE", output = { results = { value } } }
						),
					}
				end
				return { status = 404, body = `unexpected {line}` }
			end :: any
		)
		if ok then
			return port, calls, function()
				(handle :: any):stop()
			end, versions
		end
	end
	error("no free port")
end

local function run(port: number?, commandArgs: { string }, env: { [string]: string }?)
	local argv = { "run", script, "--" }
	for _, arg in commandArgs do
		table.insert(argv, arg)
	end
	local childEnv: { [string]: string } = {
		ROBLOX_API_KEY = INHERITED,
		ROBLOX_BETA_UNIVERSE_ID = "99999",
		ROBLOX_BETA_PLACE_ID = "88888",
		ROBLOX_BETA_GAME_PLACE_ID = "77777",
		ROBLOX_BETA_LOBBY_PLACE_ID = "66666",
	}
	if port ~= nil then
		childEnv.OPENCLOUD_BASE = `http://127.0.0.1:{port}`
	end
	if env then
		for key, value in env do
			childEnv[key] = value
		end
	end
	return process.exec("lune", argv, { cwd = PICKMAN, env = childEnv })
end

local function output(result: any): string
	return result.stdout .. result.stderr
end

local function joined(calls: { string }): string
	return table.concat(calls, "\n")
end

local function countLuau(rel: string): number
	local n = 0
	for _, name in fs.readDir(`{PICKMAN}/{rel}`) do
		if string.sub(name, -5) == ".luau" then
			n += 1
		end
	end
	return n
end

local function taskCount(calls: { string }, place: string, version: number): number
	local n = 0
	local needle = `/places/{place}/versions/{version}/luau-execution-session-tasks`
	for _, line in calls do
		if string.sub(line, 1, 5) == "POST " and has(line, needle) then
			n += 1
		end
	end
	return n
end

local function indexOf(calls: { string }, needle: string, last: boolean): number
	local found = 0
	for i, line in calls do
		if has(line, needle) then
			found = i
			if not last then
				return i
			end
		end
	end
	return found
end

local function renewedBetween(calls: { string }, afterNeedle: string, beforeNeedle: string): boolean
	local afterAt = indexOf(calls, afterNeedle, true)
	local beforeAt = indexOf(calls, beforeNeedle, false)
	if afterAt == 0 or beforeAt == 0 or afterAt >= beforeAt then
		return false
	end
	for i, line in calls do
		local untilAt, clock = string.match(line, "until=(%d+) clock=(%d+)")
		if untilAt ~= nil and i > afterAt and i < beforeAt then
			if (tonumber(untilAt) :: number) >= (tonumber(clock) :: number) + 20 * 60 - 1 then
				return true
			end
		end
	end
	return false
end

return t.spec("c0172 scripts/cicd", function(it)
	fs.writeDir(work)

	it("content-md5 is the base64 of the md5", function()
		t.expect(Lease.contentMd5("hello")).toBe("XUFAKrxLKna5cZ2REBfFkg==")
	end)

	it("the lease store is not a hiscore store", function()
		t.expect(Lease.STORE).toBe("PickmanCicdLease")
		t.expect(Lease.STORE == "Hiscores").toBe(false)
		t.expect(Lease.STORE == "HiscoreEntries").toBe(false)
		t.expect(Lease.ENTRY).toBe("hold")
	end)

	it("a live lease held by someone else is busy, and an expired one can be taken", function()
		local remote = {
			version = "v1",
			hold = { token = "theirs", holder = "other-host", expires = 5000 },
		}
		t.expect(Lease.planTake(1000, remote, "ours")).toBe("busy")
		t.expect(Lease.planTake(1000, remote, "theirs")).toBe("replace")
		t.expect(Lease.planTake(5000, remote, "ours")).toBe("replace")
		t.expect(Lease.planTake(1000, { version = nil, hold = nil }, "ours")).toBe("create")
		t.expect(Lease.planTake(1000, { version = "tomb", hold = nil }, "ours")).toBe("replace")
		t.expect(Lease.planRelease(1000, remote, "ours")).toBe("reject")
		t.expect(Lease.planRelease(1000, remote, "theirs")).toBe("delete")
		t.expect(Lease.planRelease(5000, remote, nil)).toBe("delete")
		t.expect(Lease.planRelease(1000, { version = nil, hold = nil }, "ours")).toBe("absent")
	end)

	it("the reservation round-trips and does not use a hiscore name", function()
		local body = Lease.encode({ token = "abc", holder = "host:1", expires = 50 })
		t.expect(has(body, '"until":50')).toBe(true)
		local hold = Lease.decode(body)
		t.expect(hold ~= nil).toBe(true)
		t.expect((hold :: any).token).toBe("abc")
		t.expect((hold :: any).holder).toBe("host:1")
		t.expect((hold :: any).expires).toBe(50)
	end)

	it("the config accepts the two place keys and refuses a mix-up", function()
		local config = CicdConfig.parse(toml())
		t.expect(config ~= nil).toBe(true)
		local parsed = config :: any
		t.expect(parsed.universeId).toBe("111")
		t.expect(parsed.cicd).toBe("222")
		t.expect(parsed.cicdGame).toBe("333")
		local bad, err = CicdConfig.parse(string.gsub(toml(), 'cicd_game = "333"', 'cicd_game = "222"'))
		t.expect(bad).toBe(nil)
		t.expect(err).toBe("cicd: places.cicd and places.cicd_game must differ")
		local extra, extraErr = CicdConfig.parse(toml() .. 'note = "KEY-NOT-IN-OUTPUT"\n')
		t.expect(extra).toBe(nil)
		t.expect(has(extraErr :: string, "unknown key")).toBe(true)
		t.expect(has(extraErr :: string, KEY)).toBe(false)
	end)

	it("the child environment drops inherited Roblox settings", function()
		local config = CicdConfig.parse(toml()) :: any
		local env = CicdConfig.childEnv({
			ROBLOX_API_KEY = INHERITED,
			ROBLOX_BETA_UNIVERSE_ID = "99999",
			ROBLOX_BETA_LOBBY_PLACE_ID = "66666",
			PATH = "/bin",
		}, config)
		t.expect(env.ROBLOX_API_KEY).toBe(KEY)
		t.expect(env.ROBLOX_BETA_UNIVERSE_ID).toBe("111")
		t.expect(env.ROBLOX_BETA_PLACE_ID).toBe("222")
		t.expect(env.ROBLOX_BETA_GAME_PLACE_ID).toBe("333")
		t.expect(env.ROBLOX_BETA_LOBBY_PLACE_ID).toBe("")
		t.expect(env.GITHUB_OUTPUT).toBe("")
		t.expect(env.PATH).toBe(nil)
	end)

	it("the root place id is the last segment of rootPlace", function()
		local id = CicdConfig.rootPlaceId('{"rootPlace":"universes/111/places/999"}')
		t.expect(id).toBe("999")
		local baseUrl = CicdConfig.base({ OPENCLOUD_BASE = "http://example.com:1" })
		t.expect(baseUrl).toBe(nil)
	end)

	it("the token file is mode 600", function()
		local path = `{work}/lease-mode`
		LeaseFile.write(path, "abc")
		local st = process.exec("stat", { "-f", "%Lp", path })
		t.expect((string.gsub(st.stdout, "%s+$", ""))).toBe("600")
		t.expect(LeaseFile.read(path)).toBe("abc")
		LeaseFile.remove(path)
		t.expect(fs.isFile(path)).toBe(false)
	end)

	it("a missing config exits non-zero and does not skip", function()
		local result = run(nil, { "--config", `{work}/missing.toml`, "--lease-file", `{work}/missing.lease` })
		local text = output(result)
		t.expect(result.ok).toBe(false)
		t.expect(has(text, "not found")).toBe(true)
		t.expect(has(text, "skipped")).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
	end)

	it("a place that is the experience start place is refused before any publish", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ rootPlace = "222" })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		local text = output(result)
		t.expect(result.ok).toBe(false)
		t.expect(has(text, "places.cicd is the experience start place")).toBe(true)
		t.expect(has(joined(calls), "/versions")).toBe(false)
		t.expect(has(joined(calls), "datastoreName=")).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
		t.expect(has(text, INHERITED)).toBe(false)
	end)

	it("places.cicd_game as the experience start place is refused before any publish", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ rootPlace = "333" })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		local text = output(result)
		t.expect(result.ok).toBe(false)
		t.expect(has(text, "places.cicd_game is the experience start place")).toBe(true)
		t.expect(has(joined(calls), "/versions")).toBe(false)
		t.expect(has(joined(calls), "datastoreName=")).toBe(false)
	end)

	it("a lease the key cannot read stops the command before it publishes", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ failLease = true })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		local text = output(result)
		t.expect(result.ok).toBe(false)
		t.expect(has(text, "HTTP 403")).toBe(true)
		t.expect(has(joined(calls), "/versions")).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
	end)

	it("a live lease held by someone else stops the command before it publishes", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local body = Lease.encode({ token = "theirs", holder = "other-host", expires = os.time() + 600 })
		local port, calls, stop = serve({ saved = { version = "v1", body = body } })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		local text = output(result)
		t.expect(result.ok).toBe(false)
		t.expect(has(text, "other-host")).toBe(true)
		t.expect(has(joined(calls), "POST")).toBe(false)
		t.expect(has(joined(calls), "/versions")).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
	end)

	it("release refuses a live lease whose token is not ours", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local body = Lease.encode({ token = "theirs", holder = "other-host", expires = os.time() + 600 })
		LeaseFile.write(`{work}/lease`, "ours")
		local port, calls, stop = serve({ saved = { version = "v1", body = body } })
		local result =
			run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease`, "release" })
		stop()
		t.expect(result.ok).toBe(false)
		t.expect(has(output(result), "other-host")).toBe(true)
		t.expect(has(joined(calls), "DELETE")).toBe(false)
		t.expect(fs.isFile(`{work}/lease`)).toBe(true)
	end)

	it("release clears an expired lease without the token", function()
		fs.writeFile(`{work}/config.toml`, toml())
		LeaseFile.remove(`{work}/lease`)
		local body = Lease.encode({ token = "theirs", holder = "other-host", expires = 1 })
		local port, calls, stop = serve({ saved = { version = "v1", body = body } })
		local result =
			run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease`, "release" })
		stop()
		t.expect(result.ok).toBe(true)
		t.expect(has(output(result), "released")).toBe(true)
		t.expect(has(joined(calls), "until=1")).toBe(true)
		t.expect(has(joined(calls), "DELETE")).toBe(false)
	end)

	it("status names the holder and not the token or the key", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local body = Lease.encode({ token = "secret-token", holder = "other-host", expires = 4242 })
		local port, _, stop = serve({ saved = { version = "v1", body = body } })
		local result =
			run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease`, "status" })
		stop()
		local text = output(result)
		t.expect(result.ok).toBe(true)
		t.expect(has(text, "held by other-host until 4242")).toBe(true)
		t.expect(has(text, "secret-token")).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
	end)

	it("publishes the file's places, not the inherited universe, and runs both suites", function()
		fs.writeFile(`{work}/config.toml`, toml())
		LeaseFile.remove(`{work}/lease`)
		local port, calls, stop, versions = serve({})
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		local gameVersion = versions["333"]
		local lobbyVersion = versions["222"]
		local first = {}
		for _, line in calls do
			table.insert(first, line)
		end
		local again = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		local text = output(result)
		local log = joined(first)
		local files = countLuau("tests/runtime") + countLuau("tests/runtime/lobby")
		t.expect(result.ok).toBe(true)
		t.expect(again.ok).toBe(true)
		t.expect(has(output(again), "HTTP 204")).toBe(false)
		t.expect(has(log, "datastoreName=PickmanCicdLease")).toBe(true)
		t.expect(has(log, "Hiscores")).toBe(false)
		t.expect(has(log, "HiscoreEntries")).toBe(false)
		t.expect(has(log, "/universes/v1/111/places/333/versions")).toBe(true)
		t.expect(has(log, "/universes/v1/111/places/222/versions")).toBe(true)
		t.expect(has(log, "99999")).toBe(false)
		t.expect(has(log, "88888")).toBe(false)
		t.expect(taskCount(first, "333", gameVersion) + taskCount(first, "222", lobbyVersion)).toBe(files)
		t.expect(taskCount(first, "333", gameVersion) > 0).toBe(true)
		t.expect(taskCount(first, "222", lobbyVersion) > 0).toBe(true)
		t.expect(
			renewedBetween(
				first,
				"/universes/v1/111/places/222/versions",
				`/places/333/versions/{gameVersion}/luau-execution-session-tasks`
			)
		).toBe(true)
		t.expect(
			renewedBetween(
				first,
				`/places/333/versions/{gameVersion}/luau-execution-session-tasks`,
				`/places/222/versions/{lobbyVersion}/luau-execution-session-tasks`
			)
		).toBe(true)
		t.expect(has(log, "until=1")).toBe(true)
		t.expect(has(log, "DELETE")).toBe(false)
		t.expect(has(text, "PASS")).toBe(true)
		t.expect(fs.isFile(`{work}/lease`)).toBe(false)
		t.expect(has(text, KEY)).toBe(false)
		t.expect(has(text, INHERITED)).toBe(false)
	end)

	it("a versioned tombstone is replaced and the command still publishes", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ tombstone = true })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		t.expect(result.ok).toBe(true)
		t.expect(has(joined(calls), "matchVersion=v-tomb")).toBe(true)
		t.expect(has(joined(calls), "/versions")).toBe(true)
		t.expect(has(output(result), "HTTP 204")).toBe(false)
	end)

	it("a versionless tombstone is re-read once and then replaced", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ bare204 = true })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		t.expect(result.ok).toBe(true)
		t.expect(has(joined(calls), "matchVersion=v-reread")).toBe(true)
		t.expect(has(joined(calls), "/versions")).toBe(true)
		t.expect(has(output(result), "HTTP 204")).toBe(false)
	end)

	it("a failed publish releases the lease and exits non-zero", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ failPublish = true })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		t.expect(result.ok).toBe(false)
		t.expect(has(output(result), "the publish failed")).toBe(true)
		t.expect(has(joined(calls), "until=1")).toBe(true)
		t.expect(has(joined(calls), "DELETE")).toBe(false)
		t.expect(fs.isFile(`{work}/lease`)).toBe(false)
	end)

	it("a failed runtime suite releases the lease and exits non-zero", function()
		fs.writeFile(`{work}/config.toml`, toml())
		local port, calls, stop = serve({ failRuntime = true })
		local result = run(port, { "--config", `{work}/config.toml`, "--lease-file", `{work}/lease` })
		stop()
		t.expect(result.ok).toBe(false)
		t.expect(has(output(result), "runtime suite failed")).toBe(true)
		t.expect(has(joined(calls), "until=1")).toBe(true)
		t.expect(has(joined(calls), "DELETE")).toBe(false)
		t.expect(fs.isFile(`{work}/lease`)).toBe(false)
	end)
end)
