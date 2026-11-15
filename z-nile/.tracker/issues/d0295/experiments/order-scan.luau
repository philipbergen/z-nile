--!strict
-- d0295 AC5 (check.sh only, never promoted): every prepared raft in a backlog folder has an Order whose text
-- `./zn ready` accepts (layergit.orderProblem), with three listed exceptions that do not fail it:
--   exempt   an unfinished item's check.sh pins its document (it names `find <R-id>`, `<R-id>.md` or `rafts/<R-id>`);
--            left for that raft's own re-prep (lesson z-raft/cross-raft-order-written-in-both).
--   re-raft  its members in first-mention order contradict their depends_on, so no line keeps its reviewed order;
--            left for its own re-rafting (`ready` refuses it, naming the fix).
--   cycle    its members' depends_on form a cycle the Order does not name: d0360's, not the Order's.
-- For each refused raft it prints the Migration line the Order becomes: the members in the order stack.order gives
-- for the old Order text with every non-member id and every repeat after the first deleted (its reviewed order).
-- Run from the repository root: ./zn run --time 120 -- lune run <this file>. Reads only; writes nothing.
local fs = require("@lune/fs")
local layergit = require("@znile/engine/layergit")
local process = require("@lune/process")
local stack = require("@znile/engine/stack")
local store = require("@znile/engine/store")

local listed = process.exec("git", { "ls-files", "--", "*check.sh" })
assert(listed.ok, "git ls-files failed: " .. listed.stderr)
local checks: { { path: string, text: string } } = {}
for path in string.gmatch(listed.stdout, "[^\n]+") do
	if
		string.find(path, "/.tracker/", 1, true)
		and not string.find(path, "/done/", 1, true)
		and not string.find(path, "/retired/", 1, true)
		and fs.isFile(path)
	then
		table.insert(checks, { path = path, text = fs.readFile(path) })
	end
end

local function pinnedBy(raft: store.Item): string?
	for _, c in checks do
		if not string.find(c.path, `/{raft.id}/check.sh`, 1, true) then
			for _, needle in { `find {raft.id}`, `{raft.id}.md`, `rafts/{raft.id}` } do
				if string.find(c.text, needle, 1, true) then
					return c.path
				end
			end
		end
	end
	return nil
end

-- the Order line the Migration writes, or nil and the refusal when the first-mention order contradicts depends_on
local function migrationLine(raft: store.Item, specs: { stack.Member }): (string?, string?)
	local isMember: { [string]: boolean } = {}
	for _, m in specs do
		isMember[m.id] = true
	end
	local kept: { string } = {}
	local seen: { [string]: boolean } = {}
	for id in string.gmatch(stack.orderSection(fs.readFile(raft.doc)), "[fdc]%d%d%d%d") do
		if isMember[id] and not seen[id] then
			seen[id] = true
			table.insert(kept, id)
		end
	end
	local ids, err = stack.order(raft.id, table.concat(kept, ", "), specs)
	if not ids then
		return nil, err
	end
	if #(ids :: { string }) == 0 then
		return "No members.", nil
	end
	return table.concat(ids :: { string }, ", then ") .. ".", nil
end

local refused = 0
for _, raft in store.all("raft") do
	local status = store.readFront(raft.doc).status or ""
	if raft.state == "backlog" and string.match(status, "^prepared") then
		local specs = layergit.memberSpecs(raft)
		local problem = layergit.orderProblem(raft)
		local _, startErr = layergit.order(raft)
		if not problem then
			if startErr then
				print(`cycle {raft.id} (d0360): {startErr}`)
			else
				print(`ok {raft.id}`)
			end
		else
			local pin = pinnedBy(raft)
			local line, why = migrationLine(raft, specs)
			if pin then
				print(`exempt {raft.id} (pinned by {pin}): {problem}`)
			elseif not line then
				print(`re-raft {raft.id}: {problem}; its first-mention order is refused too: {why}`)
			else
				refused += 1
				print(`refused {raft.id}: {problem}; Migration line: {line}`)
			end
		end
	end
end
if refused > 0 then
	print(
		`{refused} prepared raft(s) need the Migration (d0295 Design): the old Order body goes under ## Cross-raft waits`
	)
	process.exit(1)
end
