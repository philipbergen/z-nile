--!strict
-- The reservation for the CICD places (c0172). One data-store entry, taken and released with
-- compare-and-swap. The store is not a hiscore store: those are shared by every place in the experience.
-- The HTTP call is injected. The key is never copied into an error.
local net = require("@lune/net")
local serde = require("@lune/serde")
local task = require("@lune/task")

export type Hold = { token: string, holder: string, expires: number }
export type Remote = { version: string?, hold: Hold? }
export type Response = { statusCode: number, body: string, headers: { [string]: string } }
export type Request = { url: string, method: string, headers: { [string]: string }, body: string? }
export type Http = (Request) -> Response

export type Config = {
	apiKey: string,
	universeId: string,
	base: string,
	request: Http?,
	sleep: ((number) -> ())?,
	now: (() -> number)?,
}

local Lease = {}
Lease.STORE = "PickmanCicdLease"
Lease.ENTRY = "hold"
Lease.SECONDS = 20 * 60

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function redact(text: string, key: string): string
	if key == "" then
		return text
	end
	local parts = {}
	local rest = text
	while true do
		local from, to = string.find(rest, key, 1, true)
		if from == nil then
			table.insert(parts, rest)
			break
		end
		table.insert(parts, string.sub(rest, 1, from - 1))
		table.insert(parts, "<key>")
		rest = string.sub(rest, (to :: number) + 1)
	end
	return table.concat(parts)
end

local function hexToBytes(hex: string): string
	local chars = {}
	for i = 1, #hex, 2 do
		table.insert(chars, string.char(tonumber(string.sub(hex, i, i + 1), 16) :: number))
	end
	return table.concat(chars)
end

local function base64(raw: string): string
	local out = {}
	local i = 1
	while i <= #raw do
		local remain = #raw - i + 1
		local a = string.byte(raw, i)
		local b = if remain > 1 then string.byte(raw, i + 1) else 0
		local c = if remain > 2 then string.byte(raw, i + 2) else 0
		local chunk = a * 65536 + b * 256 + c
		local function piece(shift: number): string
			local index = math.floor(chunk / shift) % 64
			return string.sub(ALPHABET, index + 1, index + 1)
		end
		table.insert(out, piece(262144))
		table.insert(out, piece(4096))
		table.insert(out, if remain > 1 then piece(64) else "=")
		table.insert(out, if remain > 2 then piece(1) else "=")
		i += 3
	end
	return table.concat(out)
end

-- Base64 of the MD5 of the body, which the data-store write requires.
function Lease.contentMd5(body: string): string
	return base64(hexToBytes(serde.hash("md5", body)))
end

local function escape(text: string): string
	local replaced = string.gsub(text, '[\\"]', function(char: string): string
		return "\\" .. char
	end)
	return (
		string.gsub(replaced, "%c", function(char: string): string
			return string.format("\\u%04x", string.byte(char))
		end)
	)
end

-- Stable JSON. `until` is the file's name for expires; it is a Luau keyword, so the field here is expires.
function Lease.encode(hold: Hold): string
	local untilAt = string.format("%d", hold.expires)
	return `\{"token":"{escape(hold.token)}","holder":"{escape(hold.holder)}","until":{untilAt}\}`
end

function Lease.decode(body: string): Hold?
	local ok, decoded = pcall(serde.decode, "json" :: "json", body)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local token = (decoded :: any).token
	local holder = (decoded :: any).holder
	local expires = (decoded :: any)["until"]
	if type(token) ~= "string" or token == "" or type(holder) ~= "string" or type(expires) ~= "number" then
		return nil
	end
	return { token = token, holder = holder, expires = expires }
end

-- create: the entry is absent. replace: a tombstone, an expiry, or a hold that is already ours.
-- busy: someone else holds a live lease.
function Lease.planTake(now: number, remote: Remote, token: string): "create" | "replace" | "busy"
	local hold = remote.hold
	if hold == nil then
		if remote.version ~= nil and remote.version ~= "" then
			return "replace"
		end
		return "create"
	end
	if hold.expires <= now or hold.token == token then
		return "replace"
	end
	return "busy"
end

-- absent: nothing to clear. delete: it is ours, or it has expired. reject: a live lease with another token.
function Lease.planRelease(now: number, remote: Remote, token: string?): "absent" | "delete" | "reject"
	local hold = remote.hold
	if hold == nil then
		return "absent"
	end
	if hold.expires <= now then
		return "delete"
	end
	if token ~= nil and token ~= "" and hold.token == token then
		return "delete"
	end
	return "reject"
end

local function urlEncode(text: string): string
	return (
		string.gsub(text, "[^%w%-_%.~]", function(char: string): string
			return string.format("%%%02X", string.byte(char))
		end)
	)
end

local function entryUrl(cfg: Config, query: { string }): string
	if Lease.STORE == "Hiscores" or Lease.STORE == "HiscoreEntries" then
		error("cicd: the lease store is a hiscore store", 0)
	end
	local parts = { `datastoreName={Lease.STORE}`, `entryKey={Lease.ENTRY}` }
	for _, item in query do
		table.insert(parts, item)
	end
	return `{cfg.base}/datastores/v1/universes/{cfg.universeId}/standard-datastores/datastore/entries/entry?{table.concat(
		parts,
		"&"
	)}`
end

local function defaultRequest(request: Request): Response
	local res = net.request({
		url = request.url,
		method = request.method :: any,
		headers = request.headers,
		body = request.body,
	})
	local headers: { [string]: string } = {}
	for name, value in res.headers do
		-- Lune types a header as one string or a list of them. The lease only reads single values.
		local text = if type(value) == "string" then value else table.concat(value, ", ")
		headers[string.lower(name)] = text
	end
	return { statusCode = res.statusCode, body = res.body, headers = headers }
end

local function httpOf(cfg: Config): Http
	return cfg.request or defaultRequest
end

local function nap(cfg: Config, seconds: number)
	if cfg.sleep then
		cfg.sleep(seconds)
	else
		task.wait(seconds)
	end
end

local function send(cfg: Config, request: Request): Response
	local call = httpOf(cfg)
	local pause = 5
	local attempt = 1
	while true do
		local res = call(request)
		local transient = res.statusCode == 429 or (res.statusCode >= 500 and res.statusCode <= 599)
		if not transient or attempt >= 5 then
			return res
		end
		nap(cfg, pause)
		attempt += 1
	end
end

local function headers(cfg: Config, body: string?): { [string]: string }
	local result: { [string]: string } = { ["x-api-key"] = cfg.apiKey }
	if body ~= nil then
		result["content-md5"] = Lease.contentMd5(body)
		result["Content-Type"] = "application/json"
	end
	return result
end

local function failed(cfg: Config, what: string, res: Response): string
	return redact(`cicd: {what} failed with HTTP {res.statusCode}: {res.body}`, cfg.apiKey)
end

local function clock(cfg: Config): number
	return if cfg.now then cfg.now() else os.time()
end

local function read(cfg: Config): (Remote?, string?)
	local res = send(cfg, {
		url = entryUrl(cfg, {}),
		method = "GET",
		headers = headers(cfg, nil),
		body = nil,
	})
	if res.statusCode == 404 then
		return { version = nil, hold = nil }, nil
	end
	-- A deleted entry can come back as 204, "the key is marked as deleted", with or without a version.
	if res.statusCode == 204 then
		local marked = res.headers["roblox-entry-version"]
		if marked == nil or marked == "" then
			return { version = nil, hold = nil }, nil
		end
		return { version = marked, hold = nil }, nil
	end
	if res.statusCode ~= 200 then
		return nil, failed(cfg, "reading the lease", res)
	end
	local version = res.headers["roblox-entry-version"]
	if version == nil or version == "" then
		return nil, "cicd: the lease entry has no version"
	end
	local hold = Lease.decode(res.body)
	if hold == nil then
		return nil, "cicd: the lease entry is not a reservation"
	end
	return { version = version, hold = hold }, nil
end

local function write(cfg: Config, body: string, version: string?): (string?, string?)
	local query = if version == nil
		then { "exclusiveCreate=true" }
		else { `matchVersion={urlEncode(version)}` }
	local res = send(cfg, {
		url = entryUrl(cfg, query),
		method = "POST",
		headers = headers(cfg, body),
		body = body,
	})
	if res.statusCode == 412 then
		return nil, "conflict"
	end
	if res.statusCode ~= 200 then
		return nil, failed(cfg, "writing the lease", res)
	end
	local ok, decoded = pcall(serde.decode, "json" :: "json", res.body)
	local written = ok and type(decoded) == "table" and (decoded :: any).version or nil
	if type(written) ~= "string" or written == "" then
		return nil, "cicd: the lease write answered without a version"
	end
	return written, nil
end

local function held(remote: Remote): string
	local hold = remote.hold :: Hold
	return `cicd: the CICD places are reserved by {hold.holder} until {string.format("%d", hold.expires)}`
end

-- Takes the lease for twenty minutes. On success, the version just written. A lost race is tried once more.
function Lease.acquire(cfg: Config, holder: string, token: string): (string?, string?)
	local expires = clock(cfg) + Lease.SECONDS
	local body = Lease.encode({ token = token, holder = holder, expires = expires })
	for _ = 1, 2 do
		local remote, err = read(cfg)
		if remote == nil then
			return nil, err
		end
		local action = Lease.planTake(clock(cfg), remote :: Remote, token)
		if action == "busy" then
			return nil, held(remote :: Remote)
		end
		local version, writeErr =
			write(cfg, body, if action == "create" then nil else (remote :: Remote).version)
		if version ~= nil then
			return version, nil
		end
		if writeErr ~= "conflict" then
			return nil, writeErr
		end
	end
	return nil, "cicd: the lease changed while taking it"
end

-- Moves the deadline, only while the stored token is still ours.
function Lease.renew(cfg: Config, holder: string, token: string): (string?, string?)
	local remote, err = read(cfg)
	if remote == nil then
		return nil, err
	end
	if
		Lease.planTake(clock(cfg), remote :: Remote, token) ~= "replace"
		or (remote :: Remote).version == nil
	then
		return nil, if (remote :: Remote).hold then held(remote :: Remote) else "cicd: the lease is free"
	end
	local body = Lease.encode({ token = token, holder = holder, expires = clock(cfg) + Lease.SECONDS })
	local version, writeErr = write(cfg, body, (remote :: Remote).version)
	if writeErr == "conflict" then
		return nil, "cicd: the lease changed while renewing it"
	end
	return version, writeErr
end

-- Clears the entry when the token matches, or when the deadline has passed. A live lease held by
-- someone else is left in place.
function Lease.release(cfg: Config, token: string?): (string?, string?)
	local remote, err = read(cfg)
	if remote == nil then
		return nil, err
	end
	local action = Lease.planRelease(clock(cfg), remote :: Remote, token)
	if action == "absent" then
		return "free", nil
	end
	if action == "reject" then
		return nil, held(remote :: Remote)
	end
	-- Post an expired hold. Delete would leave a tombstone, and the next read can be HTTP 204.
	local hold = (remote :: Remote).hold :: Hold
	local body = Lease.encode({
		token = if token ~= nil and token ~= "" then token else hold.token,
		holder = hold.holder,
		expires = 1,
	})
	local version, writeErr = write(cfg, body, (remote :: Remote).version)
	if version == nil then
		if writeErr == "conflict" then
			return nil, "cicd: the lease changed while releasing it"
		end
		return nil, writeErr
	end
	return "released", nil
end

function Lease.status(cfg: Config): (string?, string?)
	local remote, err = read(cfg)
	if remote == nil then
		return nil, err
	end
	if (remote :: Remote).hold == nil then
		return "free", nil
	end
	local hold = (remote :: Remote).hold :: Hold
	return `held by {hold.holder} until {string.format("%d", hold.expires)}`, nil
end

return Lease
