--!strict
-- The approval contract. Pure: texts in, a hash out. The caller reads the files.
--
-- What is hashed, in this order: the design sections (Problem, Solution, Design, Acceptance criteria,
-- Test plan), then check.sh, then each acceptance spec. The hash is sha256 of one canonical blob, so
-- two machines agree:
--   line endings: CR and CRLF become LF
--   a non-empty text that does not end in LF gets one trailing LF (other trailing LFs stay)
--   spec names are the path relative to acceptance/ or tests/acceptance/<id>/, with "/", sorted
--   check.sh only: /issues/active/, /issues/done/, /rafts/active/ and /rafts/done/ become /issues/ and
--   /rafts/, so the path rewrite `done` applies does not change the hash
-- Spec bodies are not rewritten. Frontmatter, status, spend, reviews and watch.txt are not inputs.
--
-- approval.md is the record, not an input. Its text is the port contract:
--   # approval
--   when	who	hash	parts
--   <UTC>	<git user.name>	<64 lowercase hex>	design=<64>;check.sh=<64>;<spec>=<64>
-- Oldest row first. The last row is the current approval. `parts` names the sha256 of each part so a
-- mismatch can say which part changed.

local serde = require("@lune/serde")

local contract = {}

contract.FILE = "approval.md"
contract.HEADS = { "Problem", "Solution", "Design", "Acceptance criteria", "Test plan" }

export type Parts = { [string]: string }
export type Row = { when: string, who: string, hash: string, parts: Parts }

local HEX = string.rep("%x", 64)
local WHEN = "%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ"

local function sha256(text: string): string
	return serde.hash("sha256", text)
end

function contract.normalize(text: string): string
	local n = (string.gsub(text, "\r\n", "\n"))
	n = (string.gsub(n, "\r", "\n"))
	if n ~= "" and string.sub(n, -1) ~= "\n" then
		n ..= "\n"
	end
	return n
end

-- The state segment `done` rewrites in a check.sh (`paths.rewrite`) is not part of the contract.
function contract.canonCheck(text: string): string
	local n = contract.normalize(text)
	n = (string.gsub(n, "/issues/active/", "/issues/"))
	n = (string.gsub(n, "/issues/done/", "/issues/"))
	n = (string.gsub(n, "/rafts/active/", "/rafts/"))
	n = (string.gsub(n, "/rafts/done/", "/rafts/"))
	return n
end

local function linesOf(text: string): { string }
	local out = {}
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		table.insert(out, line)
	end
	-- a trailing LF makes one empty match past the last line; drop it
	if #out > 0 and out[#out] == "" then
		table.remove(out)
	end
	return out
end

local function bodyOf(text: string, heading: string): string
	local lines = linesOf(text)
	local start: number? = nil
	for i, line in lines do
		if line == "## " .. heading then
			start = i
			break
		end
	end
	if not start then
		return ""
	end
	local acc = {}
	for i = start + 1, #lines do
		if string.sub(lines[i], 1, 3) == "## " then
			break
		end
		table.insert(acc, lines[i])
	end
	return table.concat(acc, "\n")
end

-- The five sections, in a fixed order, each present even when the document omits it.
function contract.designText(doc: string): string
	local text = contract.normalize(doc)
	local chunks = {}
	for _, heading in contract.HEADS do
		table.insert(chunks, `## {heading}\n{bodyOf(text, heading)}`)
	end
	return contract.normalize(table.concat(chunks, "\n"))
end

function contract.who(name: string): string
	local n = (string.gsub(name, "[\t\r\n]", " "))
	n = (string.gsub(n, "^%s+", ""))
	n = (string.gsub(n, "%s+$", ""))
	return n
end

local function rank(name: string): number
	if name == "design" then
		return 0
	end
	if name == "check.sh" then
		return 1
	end
	return 2
end

local function byName(a: string, b: string): boolean
	local ra, rb = rank(a), rank(b)
	if ra ~= rb then
		return ra < rb
	end
	return a < b
end

function contract.order(parts: Parts): { string }
	local names = {}
	for name in parts do
		table.insert(names, name)
	end
	table.sort(names, byName)
	return names
end

-- `specs` maps a path relative to the acceptance directory to the file's bytes.
function contract.build(doc: string, check: string, specs: { [string]: string }): (Parts?, string?)
	local parts: Parts = {
		design = contract.designText(doc),
		["check.sh"] = contract.canonCheck(check),
	}
	for name, text in specs do
		if name == "" or name == "design" or name == "check.sh" or string.match(name, "[=;\r\n]") then
			return nil, `a spec path cannot be hashed: "{name}"`
		end
		parts[name] = contract.normalize(text)
	end
	return parts, nil
end

local function blob(parts: Parts): string
	local chunks = {}
	for _, name in contract.order(parts) do
		local text = parts[name]
		table.insert(chunks, `{name}\n{tostring(#text)}\n{text}`)
	end
	return table.concat(chunks, "\n")
end

function contract.hash(parts: Parts): string
	return sha256(blob(parts))
end

function contract.partHashes(parts: Parts): Parts
	local out: Parts = {}
	for name, text in parts do
		out[name] = sha256(text)
	end
	return out
end

function contract.encodeParts(hashes: Parts): (string?, string?)
	local bits = {}
	for _, name in contract.order(hashes) do
		local hash = hashes[name]
		if not string.match(hash, "^" .. HEX .. "$") then
			return nil, `part {name} is not a sha256`
		end
		if string.match(name, "[=;\r\n]") then
			return nil, `part name "{name}" cannot be recorded`
		end
		table.insert(bits, `{name}={hash}`)
	end
	return table.concat(bits, ";"), nil
end

function contract.decodeParts(cell: string): (Parts?, string?)
	if cell == "" then
		return nil, "parts is empty"
	end
	local out: Parts = {}
	for bit in string.gmatch(cell, "[^;]+") do
		local name, hash = string.match(bit, "^([^=]+)=(" .. HEX .. ")$")
		if not name or not hash then
			return nil, `parts has a bad entry "{bit}"`
		end
		if out[name] then
			return nil, `parts repeats {name}`
		end
		out[name] = hash
	end
	return out, nil
end

local HEADER = "# approval\nwhen\twho\thash\tparts\n"

function contract.render(rows: { Row }): string
	local lines = { "# approval", "when\twho\thash\tparts" }
	for _, row in rows do
		local cell = contract.encodeParts(row.parts)
		table.insert(lines, `{row.when}\t{row.who}\t{row.hash}\t{cell :: string}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

function contract.parse(text: string): ({ Row }?, string?)
	local norm = contract.normalize(text)
	if string.sub(norm, 1, #HEADER) ~= HEADER then
		return nil, "the first lines must be the approval header"
	end
	local rows: { Row } = {}
	local rest = string.sub(norm, #HEADER + 1)
	if rest == "" then
		return nil, "approval has no row"
	end
	for line in string.gmatch(rest, "(.-)\n") do
		if line ~= "" then
			local when, who, hash, cell = string.match(line, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
			if not when then
				return nil, `a row is not four tab-separated fields: "{line}"`
			end
			if not string.match(when :: string, "^" .. WHEN .. "$") then
				return nil, `when is not UTC: "{when}"`
			end
			if who == "" then
				return nil, "who is empty"
			end
			if not string.match(hash :: string, "^" .. HEX .. "$") then
				return nil, "hash is not a sha256"
			end
			local parts, err = contract.decodeParts(cell :: string)
			if not parts then
				return nil, err
			end
			table.insert(
				rows,
				{ when = when :: string, who = who :: string, hash = hash :: string, parts = parts }
			)
		end
	end
	if #rows == 0 then
		return nil, "approval has no row"
	end
	return rows, nil
end

-- Names of the parts whose hash differs from the latest approval, in contract order.
-- Empty when the approval still holds. "contract" when the row's hash differs and no part explains it.
function contract.changed(row: Row, parts: Parts): { string }
	if row.hash == contract.hash(parts) then
		return {}
	end
	local now = contract.partHashes(parts)
	local names: { [string]: boolean } = {}
	for name in now do
		names[name] = true
	end
	for name in row.parts do
		names[name] = true
	end
	local list = {}
	for name in names do
		if now[name] ~= row.parts[name] then
			table.insert(list, name)
		end
	end
	table.sort(list, byName)
	if #list == 0 then
		table.insert(list, "contract")
	end
	return list
end

function contract.reapprovals(rows: { Row }): number
	if #rows == 0 then
		return 0
	end
	return #rows - 1
end

return contract
