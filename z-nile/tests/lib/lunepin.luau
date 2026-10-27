--!strict
-- The Lune the spec runner must run on (c0162). Pure: the runner reads rokit.toml and _VERSION and hands the texts here.
-- One reader for rokit.toml's lune pin (zz-arch rule 5); it refuses an ambiguous file (rule 6).
local lunepin = {}

lunepin.FIX =
	'run the pinned Lune: PATH="$HOME/.rokit/bin:$PATH" lune run tests/run …, or ./zn and the gate, which do'

-- rokit.toml's pinned Lune version ("0.10.5"), or nil and the problem. Only the [tools] table's `lune` key counts; a
-- second `lune` key, a `lune` key outside [tools], or a value that is not "lune-org/lune@<x.y.z>" is a problem.
function lunepin.pinned(text: string): (string?, string?)
	local section = ""
	local found: string? = nil
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		local bare = string.gsub(string.gsub(line, "#.*$", ""), "^%s+", "")
		bare = string.gsub(bare, "%s+$", "")
		local header = string.match(bare, "^%[([^%]]*)%]$")
		if header then
			section = header
		else
			local key, value = string.match(bare, "^([%w_%-]+)%s*=%s*(.-)$")
			if key == "lune" then
				if section ~= "tools" then
					return nil, `rokit.toml line {n}: lune is pinned outside [tools]`
				end
				if found then
					return nil, `rokit.toml line {n}: lune is pinned twice`
				end
				local version = string.match(value :: string, '^"lune%-org/lune@(%d+%.%d+%.%d+)"$')
				if not version then
					return nil, `rokit.toml line {n}: lune's pin is not "lune-org/lune@<x.y.z>": {value}`
				end
				found = version
			end
		end
	end
	if not found then
		return nil, "rokit.toml pins no lune in [tools]"
	end
	return found, nil
end

-- The running Lune's version from its _VERSION ("Lune 0.10.5+709" -> "0.10.5"), or nil when it has none.
function lunepin.running(version: string?): string?
	if type(version) ~= "string" then
		return nil
	end
	return string.match(version, "^Lune (%d+%.%d+%.%d+)[+%s]")
		or string.match(version, "^Lune (%d+%.%d+%.%d+)$")
end

-- The version a `lune --version` line names ("lune 0.10.5" -> "0.10.5"), or nil.
function lunepin.reported(line: string?): string?
	if type(line) ~= "string" then
		return nil
	end
	return string.match(line, "^lune (%d+%.%d+%.%d+)%s*$")
end

-- nil when `running` is the pin; else the refusal, naming both versions (or what is unknown) and the fix. Fails closed:
-- an unknown running version or an unreadable pin refuses too.
function lunepin.check(pinned: string?, problem: string?, running: string?, where: string): string?
	if pinned == nil then
		return `tests/run: cannot check the Lune version: {problem or "no pin"} ({where}); refusing to run`
	end
	if running == pinned then
		return nil
	end
	return `tests/run: this is Lune {running or "of an unknown version"}, but rokit.toml ({where}) pins {pinned}; refusing to run, since its results can differ from CI's. Fix: {lunepin.FIX}`
end

return lunepin
