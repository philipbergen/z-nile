--!strict
-- Closing an issue as won't do (c0278): pure rules over texts and tables, no I/O. `./zn close` stamps the issue's
-- `status:` line `closed-<three words>` and appends `wont_do: <why>`; the folder stays where it is. What counts as
-- closed is `isClosed`, and the reason has one reader, `reasonOf`: every reader that hands out work goes through them.
local statusLib = require("./status")

local closing = {}

closing.KEY = "wont_do"

export type Facts = {
	id: string,
	kind: string, -- "issue" | "raft"
	where: string, -- "backlog" | "active" | "done" | "none" (not on the tree judged)
	status: string, -- status.effective of the document there
	raft: string, -- its raft: line, "" for none
	dependents: { string }, -- ids of backlog or active items whose depends_on names it, sorted
}

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- The frontmatter as `key: value` pairs, read as store.readFront reads a file (one reader's rule, copied so this
-- module stays pure); nil when the text has no frontmatter.
local function frontOf(text: string): { [string]: string }?
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if not block then
		return nil
	end
	local out: { [string]: string } = {}
	for line in string.gmatch(block, "[^\n]+") do
		local k, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
		if k and v then
			out[k] = v
		end
	end
	return out
end

-- `text` with frontmatter key `key` set to `value`, added as the last key when missing (store.withFront's
-- anchored-line rule, copied: a title that mentions `status:` must not absorb the value); nil without frontmatter.
local function withFront(text: string, key: string, value: string): string?
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-.*)$")
	if not head or not block or not rest then
		return nil
	end
	local replaced, n = string.gsub("\n" .. block, `\n{key}:[^\n]*\n`, function()
		return `\n{key}: {value}\n`
	end, 1)
	if n == 0 then
		replaced = "\n" .. block .. `{key}: {value}\n`
	end
	return head .. string.sub(replaced, 2) .. rest
end

function closing.isClosed(front: { [string]: string }): boolean
	return statusLib.parse(front.status) == "closed"
end

-- The trimmed wont_do value, nil when it is missing or empty.
function closing.reasonOf(front: { [string]: string }): string?
	local v = front[closing.KEY]
	if v == nil then
		return nil
	end
	local r = trim(v)
	return if r == "" then nil else r
end

-- Why `reason` can't be a reason, or nil. It is stored trimmed, on one line: the document's wont_do: line.
function closing.checkReason(reason: string?): string?
	if reason == nil or trim(reason) == "" then
		return `close needs --reason "<why it won't be done>"`
	end
	if string.find(reason, "[\n\r]") then
		return "a reason is one line: it is the document's wont_do: line"
	end
	return nil
end

-- Why `close` refuses, or nil; `how` names the tree judged ("origin/main" or "this tree"). First match wins.
function closing.refusal(f: Facts, how: string): string?
	local id = f.id
	if f.kind == "raft" then
		return `{id} is a raft: close takes an issue (a raft is emptied with ./zn unfold and retired with ./zn recombine, or given back with ./zn release or ./zn stop)`
	end
	if f.where == "none" then
		return `{id} is not on {how}`
	end
	if f.where == "done" then
		return `{id} is done: a done issue is not closed`
	end
	if f.where == "active" then
		local raft = if f.raft ~= "" then f.raft else "<raft>"
		return `{id} is readied (in active/): give its raft back with ./zn stop {raft}, then close it`
	end
	if f.status == "closed" then
		return `{id} is already closed`
	end
	if f.status == "preparing" then
		return `{id} is being prepared (preparing on {how}): its holder gives it back first (./zn status {id} new)`
	end
	if f.raft ~= "" then
		return `{id} is in {f.raft}: z-raft takes it out first (./zn unfold {f.raft} {id}), then close it`
	end
	if #f.dependents > 0 then
		return `{id} is named in the depends_on of {table.concat(f.dependents, ", ")}: drop it there first (by pull request), or close those too`
	end
	return nil
end

-- The closed document: `status:` set to `stamp` and `wont_do: <reason>` appended as the frontmatter's last key,
-- every other byte kept; nil without frontmatter.
function closing.edit(text: string, reason: string, stamp: string): string?
	local stamped = withFront(text, "status", stamp)
	if not stamped then
		return nil
	end
	return withFront(stamped, closing.KEY, trim(reason))
end

-- The publish guard: nil exactly when `after` is a close of `before` (`edit` recomputed from after's own values and
-- compared byte for byte, so the writer and the validator agree), else why not.
function closing.guard(before: string, after: string): string?
	local bf = frontOf(before)
	if not bf then
		return "the document has no frontmatter"
	end
	if closing.isClosed(bf) or bf[closing.KEY] ~= nil then
		return "the document is already closed or carries wont_do:"
	end
	local af = frontOf(after)
	if not af then
		return "the closed document has no frontmatter"
	end
	local stamp = af.status or ""
	if not string.match(stamp, "^closed%-%a+%-%a+%-%a+$") then
		return "a close stamps status: closed-<three words>"
	end
	local reason = af[closing.KEY]
	local bad = closing.checkReason(reason)
	if bad then
		return bad
	end
	if closing.edit(before, reason :: string, stamp) ~= after then
		return "a close changes only the status: line and appends one wont_do: line"
	end
	return nil
end

-- A git run as these guards see it (sh.Result's fields they read).
export type Run = { ok: boolean, code: number, stdout: string }

-- The paths a `git grep -l` prefilter found, or nil and why when it failed. Exit 1 with no output is "no match";
-- any other non-zero exit is an error the guard must not read as no dependents (fails closed: R0115 review 001 F2).
function closing.grepHits(run: Run): ({ string }?, string?)
	if run.ok then
		local out: { string } = {}
		for line in string.gmatch(run.stdout, "[^\n]+") do
			table.insert(out, line)
		end
		return out, nil
	end
	if run.code == 1 and trim(run.stdout) == "" then
		return {}, nil
	end
	return nil, `git grep for dependents failed (exit {run.code}): refusing rather than reading it as none`
end

-- Why a capture that adds `dep` to `path`'s depends_on refuses, from git's view of `depDoc` at the base (`listed`:
-- its ls-tree; `shown`: its show, nil when listing found nothing), or nil. A failed read refuses: it can't tell a
-- closed issue from an open one (fails closed: R0115 review 001 F2).
function closing.addedDependency(path: string, dep: string, depDoc: string, listed: Run, shown: Run?): string?
	if not listed.ok then
		return `not a capture change: cannot list {depDoc} at the base to check {dep} is not closed (exit {listed.code})`
	end
	if trim(listed.stdout) == "" then
		return nil
	end
	if not shown or not shown.ok then
		return `not a capture change: cannot read {depDoc} at the base to check {dep} is not closed`
	end
	if closing.closedDoc(shown.stdout) then
		return `not a capture change: {path} adds {dep} to depends_on, and {dep} is closed (won't do): drop it from depends_on`
	end
	return nil
end

-- The document is closed or carries wont_do (either one): the publish guard never publishes it again.
function closing.closedDoc(text: string): boolean
	local front = frontOf(text)
	if not front then
		return false
	end
	return closing.isClosed(front) or front[closing.KEY] ~= nil
end

return closing
