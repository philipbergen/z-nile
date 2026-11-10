--!strict
-- A spec's fingerprint and the content digest of a whole gate (c0165). Pure: the caller reads the blob map (every
-- file present, tracked or not), the tools line and git's state; nothing here touches the disk.
-- One predicate, select.isInput, decides what enters a spec's fingerprint and what the selector picks.

local select = require("./select")
local serde = require("@lune/serde")

local fingerprint = {}

export type Blobs = { [string]: string } -- repo path -> "<mode> <blob id>" for every file present (tracked + untracked)
export type GitState = { head: string, refs: { [string]: string } }

-- a spec's declared entries (none: an empty list), typed so a loop over it checks
local function entriesOf(ctx: select.Context, spec: string): { string }
	local list: { string } = ctx.inputs[spec] or {}
	return list
end

local function sha256(text: string): string
	return serde.hash("sha256", text)
end

local function isRef(entry: string): boolean
	return string.sub(entry, 1, 4) == "ref:"
end

-- sorted paths p of `blobs` with isInput(spec, p)
function fingerprint.inputs(ctx: select.Context, spec: string, blobs: Blobs): { string }
	local out: { string } = {}
	for path in blobs do
		if select.isInput(ctx, spec, path) then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

-- sorted full ref names a spec declares with ref:
function fingerprint.refs(ctx: select.Context, spec: string): { string }
	local out: { string } = {}
	for _, e in entriesOf(ctx, spec) do
		if isRef(e) then
			table.insert(out, string.sub(e, 5))
		end
	end
	table.sort(out)
	return out
end

function fingerprint.of(
	ctx: select.Context,
	spec: string,
	blobs: Blobs,
	tools: string,
	mode: "affected" | "full",
	git: GitState
): string
	local lines = { "c0165 v1", `mode {mode}`, spec, tools }
	for _, p in fingerprint.inputs(ctx, spec, blobs) do
		table.insert(lines, `{p}\t{blobs[p]}`)
	end
	for _, e in entriesOf(ctx, spec) do
		table.insert(lines, e)
	end
	-- a `*` spec is valid for the blobs above, not for which commit HEAD names: a tracker commit that does not
	-- change those blobs does not invalidate it
	for _, ref in fingerprint.refs(ctx, spec) do
		table.insert(lines, `{ref}\t{git.refs[ref] or "MISSING"}`)
	end
	return sha256(table.concat(lines, "\n"))
end

-- The facts a whole affected gate's digest holds besides the files: the mode, the projects, and every declared ref of
-- the selected specs (the caller appends each project's selection). Not main's sha and not HEAD: a gate is valid for
-- the content of its inputs, not for a position of main. Pure.
function fingerprint.digestExtra(mode: string, names: { string }, git: GitState, refs: { string }): { string }
	local extra = { `mode {mode}`, `projects {table.concat(names, ",")}` }
	for _, ref in refs do
		table.insert(extra, `{ref}\t{git.refs[ref] or "MISSING"}`)
	end
	return extra
end

-- A spend.md under a project root: `./zn spend` writes it late, so it never enters a digest.
local function isSpend(path: string): boolean
	return string.match(path, "[^/]*$") == "spend.md" and string.find(path, "/.tracker/", 1, true) ~= nil
end

-- The content digest of a whole gate: the tools line, the gate's own facts (`extra`: mode, projects, ...) and
-- every file's blob, minus the spend.md files under project roots. Main's sha is not a fact.
function fingerprint.digest(blobs: Blobs, tools: string, extra: { string }): string
	local lines = { "c0165 digest v1", tools }
	for _, e in extra do
		table.insert(lines, e)
	end
	local paths: { string } = {}
	for p in blobs do
		if not isSpend(p) then
			table.insert(paths, p)
		end
	end
	table.sort(paths)
	for _, p in paths do
		table.insert(lines, `{p}\t{blobs[p]}`)
	end
	return sha256(table.concat(lines, "\n"))
end

return fingerprint
