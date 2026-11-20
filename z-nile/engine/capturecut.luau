--!strict
-- c0260: which issues must carry a capture record (or the agent-filed marker). The cut-over is a mark stored in the
-- issue itself: `./zn new issue` writes the frontmatter line `capture: required` when the base (origin/main) holds
-- the marker file z-nile/.tracker/capture-since, the file the landing commit adds. Nothing reads history, so a
-- squash or merge landing, a shallow clone, a renumbering or a compaction cannot change what an issue is: an issue
-- made before the landing has no mark and is never judged; nothing is migrated. A fixture that copies the tooling
-- but no tracker state has no marker file, so its issues get no mark.
local capturecheck = require("./capturecheck")

local capturecut = {}

capturecut.MARKER = "z-nile/.tracker/capture-since"
capturecut.KEY = "capture"
capturecut.VALUE = "required"

-- True when the issue's frontmatter says the record is required of it.
function capturecut.required(front: { [string]: string }): boolean
	return front[capturecut.KEY] == capturecut.VALUE
end

-- `doc` with the mark added after its `design:` line (an issue document always has one), or unchanged without it.
function capturecut.mark(doc: string): string
	-- only the frontmatter block counts: a Problem line that starts with `capture: ` is not the mark (review 005 F2)
	local block = string.match(doc, "^%-%-%-\n(.-)\n%-%-%-") or ""
	if string.find("\n" .. block .. "\n", "\n" .. capturecut.KEY .. ": ", 1, true) then
		return doc
	end
	return (
		string.gsub(doc, "^(%-%-%-\n.-\ndesign: [^\n]*\n)", function(head: string)
			return `{head}{capturecut.KEY}: {capturecut.VALUE}\n`
		end, 1)
	)
end

-- The document of a new backlog issue: `idea: unchallenged` (z-ticket step 4: every ticket's Problem is written as
-- checkable outcomes and challenged by `./zn idea`, the user's ruling of 2026-11-13); for a ticket an agent files from
-- its own finding (`--filed-by <source>`) also the agent-filed marker, which exempts it from the Ask, the Interview and
-- the Confirmation only (c0260); then the mark when `marked`. Returns nil and the reason when the source is not a lesson,
-- a review finding or an agent finding.
function capturecut.newDoc(
	doc: string,
	setFront: (string, string, string) -> string,
	filedBy: string?,
	marked: boolean
): (string?, string?)
	local out = setFront(doc, "idea", "unchallenged")
	if filedBy ~= nil then
		local source = capturecheck.source(filedBy)
		if not source then
			return nil, capturecheck.SOURCE_RULE
		end
		out = (
			string.gsub(out, "\n## Non%-goals", function()
				return "\n" .. capturecheck.SCOPE_LINE .. "\n\n## Non-goals"
			end, 1)
		)
		out = (
			string.gsub(out, "\n## Design", function()
				return "\n## Filed by (agent)\nSource: " .. source .. "\n\n## Design"
			end, 1)
		)
	end
	return if marked then capturecut.mark(out) else out, nil
end

-- The raw idea reviews beside an issue document on origin/main: `folder` is the issue's folder, `paths` origin's paths
-- and `read` its reader. Name -> text.
function capturecut.reviewsBeside(
	folder: string,
	paths: { string },
	read: (string) -> string?
): { [string]: string }
	local reviews: { [string]: string } = {}
	for _, path in paths do
		local name = string.match(path, "^" .. string.gsub(folder, "%p", "%%%0") .. "/([^/]+)$")
		if name and string.match(name, capturecheck.REVIEW) then
			reviews[name] = read(path) or ""
		end
	end
	return reviews
end

-- The claim gate (`status <id> preparing`, and `new raft` for each member): nil, or why issue `id` (document `doc`
-- at `docPath` on origin/main) is not claimed. An issue marked `capture: required` is claimed only with the record
-- (Ask, Interview and Confirmation, checked by capturecheck.satisfies with the reviews beside it) or the agent-filed
-- marker. Before the marker file is on origin/main no issue carries the mark, and an unmarked issue is older: neither
-- is judged.
function capturecut.refusal(
	id: string,
	doc: string,
	docPath: string,
	paths: { string },
	read: (string) -> string?
): string?
	if read(capturecut.MARKER) == nil then
		return nil
	end
	local block = string.match(doc, "^%-%-%-\n(.-)\n%-%-%-") or ""
	if
		not string.find(
			"\n" .. block .. "\n",
			"\n" .. capturecut.KEY .. ": " .. capturecut.VALUE .. "\n",
			1,
			true
		)
	then
		return nil
	end
	local folder = string.sub(docPath, 1, #docPath - #id - 4)
	if capturecheck.satisfies(doc, capturecut.reviewsBeside(folder, paths, read)) then
		return nil
	end
	return `{id} was made after the capture record landed and has neither the record (## Ask (verbatim), ## Interview, ## Confirmation: ./zn idea {id} --record, --confirm) nor ## Filed by (agent): continue its capture with the z-ticket skill on this id (steps 0a to 4b)`
end

-- Whether `--filed-by <source>` names something that exists on origin/main: a review finding needs the review file and
-- its `### F<n>`, an `agent:` or `review:` source needs the item. A `lesson:` source is written by the prep that takes the
-- issue, so it cannot be looked up. nil when it passes, else why not. `docOf(id)` is the item's document path there.
function capturecut.sourceProblem(
	source: string,
	docOf: (string) -> string?,
	read: (string) -> string?
): string?
	local kind, id = string.match(source, "^(%a+):([fdcR]%d%d%d%d)/")
	if kind ~= "review" and kind ~= "agent" then
		return nil
	end
	local doc = docOf(id :: string)
	if not doc then
		return `--filed-by {source}: {id} is not on origin/main`
	end
	if kind == "review" then
		local file, n = string.match(source, "^review:[^/]+/([%w%-]+) F(%d+)$")
		if file == nil or n == nil then
			return `--filed-by {source}: not a review finding`
		end
		local folder = string.sub(doc, 1, #doc - #(id :: string) - 4)
		local text = read(`{folder}/{file}.md`)
		if text == nil then
			return `--filed-by {source}: {folder}/{file}.md is not on origin/main`
		end
		if
			not string.find("\n" .. text, "\n###%s+F" .. n .. "[%s%[]")
			and not string.find("\n" .. text .. "\n", "\n###%s+F" .. n .. "\n")
		then
			return `--filed-by {source}: {file}.md has no finding F{n}`
		end
	end
	return nil
end

return capturecut
