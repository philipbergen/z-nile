--!strict
-- c0153: plain data, as replicated frames and snapshots are: nil, booleans, finite numbers, strings, and tables
-- without a metatable or a cycle that are either a sequence (number keys exactly 1..n, no holes) or a map (string
-- keys only); the empty table is both. Anything else (functions, userdata, threads, holes, sparse, fractional, zero
-- or negative number keys, mixed tables) is lost or changed by replication or JSON. Lune's JSON encoder writes the
-- shortest exact text, but its decoder can return a number one ulp off (13.783333333333333 comes back
-- 13.783333333333331), so a round trip is compared within a number tolerance, and NaN is never within it. An absolute
-- tolerance of 1e-9 holds for non-integers under about 1e6 (positions in tiles, speeds); a larger non-integer (a
-- wall-clock time) comes back further off and needs a larger tolerance. Integers of any size round-trip exactly.
local serde = require("@lune/serde")

local plain = {}

local function walk(v: any, path: string, seen: { [any]: boolean }): (boolean, string?)
	local kind = type(v)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return true, nil
	elseif kind == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return false, `{path}: {v} is not a finite number`
		end
		return true, nil
	elseif kind == "table" then
		if getmetatable(v) ~= nil then
			return false, `{path}: a table with a metatable`
		end
		if seen[v] then
			return false, `{path}: a cycle`
		end
		seen[v] = true
		local count, strings, numbers = 0, 0, 0
		for k in v do
			count += 1
			if type(k) == "string" then
				strings += 1
			elseif type(k) == "number" then
				numbers += 1
			else
				return false, `{path}: a {type(k)} key`
			end
		end
		if strings > 0 and numbers > 0 then
			return false, `{path}: a table with both string and number keys`
		end
		if numbers > 0 then
			for i = 1, count do
				if v[i] == nil then
					return false, `{path}: a hole at {i} (number keys must be 1..{count})`
				end
			end
		end
		for k, child in v do
			local ok, why = walk(child, `{path}.{tostring(k)}`, seen)
			if not ok then
				return false, why
			end
		end
		seen[v] = nil
		return true, nil
	end
	return false, `{path}: a {kind}`
end

-- Is `v` plain data? Returns false and where it isn't.
function plain.check(v: any): (boolean, string?)
	return walk(v, "value", {})
end

-- Are `a` and `b` the same plain data, numbers within `eps` (NaN, or a NaN eps, never is)? Returns false and the
-- first difference.
function plain.equalWithin(a: any, b: any, eps: number, path: string?): (boolean, string?)
	local at = path or "value"
	if type(a) ~= type(b) then
		return false, `{at}: {type(a)} against {type(b)}`
	end
	if type(a) == "number" then
		if not (math.abs(a - b) <= eps) then
			return false, `{at}: {a} against {b}`
		end
		return true, nil
	elseif type(a) == "table" then
		for k, v in a do
			local ok, why = plain.equalWithin(v, b[k], eps, `{at}.{tostring(k)}`)
			if not ok then
				return false, why
			end
		end
		for k in b do
			if a[k] == nil then
				return false, `{at}.{tostring(k)}: missing on the left`
			end
		end
		return true, nil
	end
	if a ~= b then
		return false, `{at}: {tostring(a)} against {tostring(b)}`
	end
	return true, nil
end

-- Is `v` plain data that survives a JSON round trip, numbers within `eps`? Never raises.
function plain.roundTrip(v: any, eps: number): (boolean, string?)
	local ok, why = plain.check(v)
	if not ok then
		return false, why
	end
	local done, back = pcall(function()
		return serde.decode("json", serde.encode("json", v))
	end)
	if not done then
		return false, `value: the JSON round trip failed: {back}`
	end
	return plain.equalWithin(back, v, eps)
end

return plain
