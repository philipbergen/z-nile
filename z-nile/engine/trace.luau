--!strict
-- Final review traceability table (`<raft-dir>/trace.md`) and recorded green
-- spec results (`<issue-dir>/results.txt`): pure claim derivation, skeleton
-- generation, table parser, stale decision, and mechanical verification.
--
-- Contract for the Python port:
--
-- 1. CLI:
--    `./zn trace <R-id>`
--      Prints the trace table skeleton for active raft `<R-id>` to stdout.
--      Requires every layer of `<R-id>` to be finished and every ticket to
--      have its required sections (`## Problem`, `## Solution`,
--      `## Acceptance criteria`).
--    `./zn trace <R-id> --check`
--      Reads `<raft-dir>/trace.md` and each ticket's `<issue-dir>/results.txt`
--      from git at the top layer's commit and verifies the table against the
--      finished stack. Prints `ok: <R-id>` and exits 0 when valid; prints each
--      failure (`row <row>, <cell>: <message>`) to stderr and exits 1 when any
--      check fails.
--
-- 2. Stable claim names (`deriveClaims`):
--    For each member ticket `<id>` of the raft, in the raft's layer order:
--    - `<id>:P1`, `<id>:P2`, ... : each outcome (paragraph or bullet item)
--      under `## Problem` in `./zn capture <id>` (the ticket's captured idea
--      before prep).
--    - `<id>:S1`, `<id>:S2`, ... : each outcome (paragraph or bullet item)
--      under `## Solution` in `./zn capture <id>`.
--    - `<id>:AC1`, `<id>:AC2`, ... : each criterion under
--      `## Acceptance criteria` in `<id>.md` at the commit being landed
--      (preserving explicit `AC<N>` numbers when written, else 1..N).
--    Every ticket must have a captured `## Problem`, a captured `## Solution`,
--    and `## Acceptance criteria`; a missing or empty section is a failure
--    naming the ticket and the missing section (no vacuous fallback).
--
-- 3. Recorded green spec results (`<issue-dir>/results.txt`):
--    `trace.renderResults` is the only serializer and `trace.parseResults` the
--    only reader. `./zn finish <id>` asks `z-nile/specs.luau --out` to write the
--    file, then commits it on the layer. `./zn trace <R-id> --check` reads it
--    from git at the commit being landed:
--    - Plain text, UTF-8, LF-separated.
--    - Each spec that ran green is a line at column 1:
--      `<repo-relative-spec-path>` (sorted lexicographically).
--    - Immediately below each spec line, one tab-indented line per green test
--      case in that spec: `\t<case-name>`.
--    A spec cell in `trace.md` passes only when its spec path is listed in the
--    ticket's `results.txt` at the commit being landed and its named case
--    equals (`==`) one of that spec's recorded `\t<case-name>` lines.
--
-- 4. File format (`<raft-dir>/trace.md`) and commit rule:
--    ```markdown
--    # Trace: <R-id>
--
--    Commit: <top-layer-finish-sha>
--
--    ## Claims
--
--    | claim | design | test | code |
--    |---|---|---|---|
--    | <id>:<key>: <summary> | <doc>:<line> | <spec-or-check>:<line> | <src>:<line> |
--
--    ## Source files
--
--    | file | claims |
--    |---|---|
--    | <repo-relative-source-path> | <id>:<key>, ... |
--    ```
--    - `trace.md` and `final-review-NNN.md` (and optional `final-refute-NNN.md`)
--      are committed on the top layer after its finish commit, in commits that
--      touch only the raft's and tickets' tracker files.
--    - `Commit:` names the top layer's finish commit (`<issue>: <title>`).
--      Anything else added after the table, or any layer rewritten, makes the
--      table stale.
--    - A claim deliberately not met writes `not met: "<ruling>"` in `design`
--      (with `test` and `code` empty or `-`), quoting a `Ruled (user, ...):`
--      line from `## Open to the human` in `<id>.md` or `<R-id>.md`.
--    - When the stack changed no source file (`## Source files` has no rows),
--      a met claim's `code` cell must be the literal `none` (accepted only
--      when the stack changed no source file).

local trace = {}

export type Claim = {
	id: string,
	issue: string,
	kind: string,
	text: string,
	rowLabel: string,
}

export type IssueDoc = {
	id: string,
	docPath: string,
	checkPath: string,
	dirPath: string,
	home: string,
	capturedText: string,
	docText: string,
	checkText: string?,
	resultsPath: string?,
	resultsText: string?,
}

export type RecordedSpec = {
	spec: string,
	cases: { string },
}

export type LayerCommit = {
	sha: string,
	parent: string,
	subject: string,
	files: { string },
}

export type LayerHistory = {
	name: string,
	issue: string,
	title: string,
	base: string,
	tip: string?,
	stackedOnBelow: boolean,
	commits: { LayerCommit },
}

export type ClaimRow = {
	rawClaim: string,
	claimId: string,
	design: string,
	test: string,
	code: string,
}

export type SourceRow = {
	file: string,
	claims: string,
}

export type ParsedTable = {
	raftId: string?,
	commit: string?,
	claims: { ClaimRow },
	sources: { SourceRow },
}

export type FileMeta = {
	lines: { string },
}

export type CheckInput = {
	raftId: string?,
	raftDir: string?,
	tableText: string,
	expectedCommit: string?,
	staleReason: string?,
	layers: { LayerHistory }?,
	issues: { IssueDoc },
	raftDocText: string,
	changedSources: { string },
	filesAtCommit: { [string]: FileMeta },
	finishedIssues: { [string]: boolean }?,
}

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or ""
end

local function normalizeInline(s: string): string
	local collapsed = string.gsub(trim(s), "%s+", " ")
	local safePipes = string.gsub(collapsed, "|", "/")
	return safePipes
end

function trace.splitLines(text: string): { string }
	local out: { string } = {}
	if text == "" then
		return out
	end
	local pos = 1
	local len = #text
	while pos <= len do
		local nl = string.find(text, "\n", pos, true)
		if nl == nil then
			table.insert(out, string.sub(text, pos))
			break
		end
		local line = string.sub(text, pos, nl - 1)
		if string.sub(line, -1) == "\r" then
			line = string.sub(line, 1, -2)
		end
		table.insert(out, line)
		pos = nl + 1
	end
	return out
end

function trace.renderResults(specs: { RecordedSpec }): string
	local sorted = table.clone(specs)
	table.sort(sorted, function(a, b)
		return a.spec < b.spec
	end)
	local lines: { string } = {}
	for _, entry in sorted do
		table.insert(lines, entry.spec)
		for _, c in entry.cases do
			local clean = string.gsub(c, "[\r\n\t]+", " ")
			table.insert(lines, "\t" .. clean)
		end
	end
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

function trace.parseResults(text: string): ({ [string]: { [string]: boolean } }?, string?)
	local out: { [string]: { [string]: boolean } } = {}
	local currentSpec: string? = nil
	for lineNo, line in trace.splitLines(text) do
		if line ~= "" then
			if string.sub(line, 1, 1) == "\t" then
				if currentSpec == nil then
					return nil, `line {lineNo}: case line without a preceding spec path`
				end
				local caseName = string.sub(line, 2)
				if caseName == "" then
					return nil, `line {lineNo}: empty case name`
				end
				out[currentSpec][caseName] = true
			else
				local specPath = trim(line)
				if specPath == "" then
					continue
				end
				currentSpec = specPath
				if out[specPath] == nil then
					out[specPath] = {}
				end
			end
		end
	end
	return out, nil
end

local function sectionBody(md: string, heading: string): string?
	local lines = trace.splitLines(md)
	local target = "## " .. string.lower(heading)
	local collecting = false
	local buf: { string } = {}
	for _, line in lines do
		local trimmed = trim(line)
		if string.sub(trimmed, 1, 3) == "## " then
			if collecting then
				break
			end
			if string.lower(trimmed) == target then
				collecting = true
			end
		elseif collecting then
			table.insert(buf, line)
		end
	end
	if not collecting then
		return nil
	end
	return table.concat(buf, "\n")
end

local function isPrepAdditionLine(trimmed: string): boolean
	if string.find(trimmed, "^%(Added in prep") ~= nil then
		return true
	end
	if string.find(trimmed, "^Decided with the user") ~= nil then
		return true
	end
	if string.find(trimmed, "^%*%*Scope decision") ~= nil then
		return true
	end
	return false
end

local function extractOutcomes(body: string?): { string }
	if body == nil then
		return {}
	end
	local items: { string } = {}
	local cur: { string } = {}
	local inFence = false

	local function flush()
		if #cur > 0 then
			local text = normalizeInline(table.concat(cur, " "))
			if text ~= "" and text ~= "-" then
				table.insert(items, text)
			end
			cur = {}
		end
	end

	for _, raw in trace.splitLines(body) do
		local trimmed = trim(raw)
		if string.sub(trimmed, 1, 3) == "```" then
			flush()
			inFence = not inFence
		elseif not inFence then
			if isPrepAdditionLine(trimmed) then
				flush()
				break
			elseif
				trimmed == ""
				or string.sub(trimmed, 1, 4) == "<!--"
				or string.sub(trimmed, 1, 3) == "###"
			then
				flush()
			else
				local bullet = string.match(trimmed, "^[%-%*]%s+(.+)$")
					or string.match(trimmed, "^%d+%.%s+(.+)$")
				if bullet ~= nil then
					flush()
					table.insert(cur, bullet)
				else
					table.insert(cur, trimmed)
				end
			end
		end
	end
	flush()
	return items
end

-- The body of the first of `headings` the document has, for callers that build fixture tickets.
function trace.extractSection(md: string, headings: { string }): string?
	for _, heading in headings do
		local body = sectionBody(md, heading)
		if body ~= nil then
			return body
		end
	end
	return nil
end

trace.extractOutcomes = extractOutcomes
-- Acceptance criteria are read the same way as outcomes: one per bullet or paragraph.
trace.extractAcs = extractOutcomes

function trace.deriveClaims(issues: { IssueDoc }): ({ Claim }, { string })
	local out: { Claim } = {}
	local errors: { string } = {}
	for _, issue in issues do
		local captured = if issue.capturedText ~= "" then issue.capturedText else issue.docText
		local problems = extractOutcomes(sectionBody(captured, "Problem"))
		if #problems == 0 then
			table.insert(errors, `row {issue.id}, claim: ticket {issue.id} is missing captured ## Problem`)
		else
			for i, text in problems do
				local id = `{issue.id}:P{i}`
				table.insert(out, {
					id = id,
					issue = issue.id,
					kind = "P",
					text = text,
					rowLabel = `{id}: {text}`,
				})
			end
		end

		local solutions = extractOutcomes(sectionBody(captured, "Solution"))
		if #solutions == 0 then
			table.insert(errors, `row {issue.id}, claim: ticket {issue.id} is missing captured ## Solution`)
		else
			for i, text in solutions do
				local id = `{issue.id}:S{i}`
				table.insert(out, {
					id = id,
					issue = issue.id,
					kind = "S",
					text = text,
					rowLabel = `{id}: {text}`,
				})
			end
		end

		local acBody = sectionBody(issue.docText, "Acceptance criteria")
			or sectionBody(captured, "Acceptance criteria")
		local acItems = extractOutcomes(acBody)
		if #acItems == 0 then
			table.insert(errors, `row {issue.id}, claim: ticket {issue.id} is missing ## Acceptance criteria`)
		else
			local seenAc: { [string]: boolean } = {}
			for i, item in acItems do
				local explicitNum, rest = string.match(item, "^%*?%*?AC(%d+)%*?%*?%s*[:%-–—]?%s*(.*)$")
				local key = if explicitNum ~= nil then `AC{explicitNum}` else `AC{i}`
				if seenAc[key] then
					key = `AC{i}`
				end
				seenAc[key] = true
				local summary = if explicitNum ~= nil
						and rest ~= nil
						and trim(rest) ~= ""
					then normalizeInline(rest)
					else item
				local id = `{issue.id}:{key}`
				table.insert(out, {
					id = id,
					issue = issue.id,
					kind = "AC",
					text = summary,
					rowLabel = `{id}: {summary}`,
				})
			end
		end
	end
	return out, errors
end

local function isTrackerFileOf(path: string, raftId: string, raftDir: string, issues: { IssueDoc }): boolean
	if string.find(path, "/spend%.d/", 1, false) ~= nil then
		return true
	end
	local raftPrefix = raftDir .. "/"
	if string.sub(path, 1, #raftPrefix) == raftPrefix then
		local name = string.sub(path, #raftPrefix + 1)
		if
			name == "trace.md"
			or name == `{raftId}.md`
			or string.match(name, "^review%-%d+%.md$") ~= nil
			or string.match(name, "^refute%-%d+%.md$") ~= nil
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
			or string.match(name, "^final%-refute%-%d+%.md$") ~= nil
		then
			return true
		end
	end
	for _, issue in issues do
		if path == issue.docPath then
			return true
		end
	end
	return false
end

local function isAllowedAfterTrace(path: string, raftId: string, raftDir: string): boolean
	if string.find(path, "/spend%.d/", 1, false) ~= nil then
		return true
	end
	local raftPrefix = raftDir .. "/"
	if string.sub(path, 1, #raftPrefix) == raftPrefix then
		local name = string.sub(path, #raftPrefix + 1)
		if
			name == `{raftId}.md`
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
			or string.match(name, "^final%-refute%-%d+%.md$") ~= nil
		then
			return true
		end
	end
	return false
end

-- Pure stale decision over the stack's layers and commits.
-- Rule: `trace.md` and `final-review-NNN.md` are committed on the top layer after its finish commit,
-- in commits that touch only the raft's and tickets' tracker files; `Commit:` names the top layer's
-- finish commit; anything else added after the table, or any layer rewritten, makes it stale.
function trace.staleReason(
	raftId: string,
	raftDir: string,
	issues: { IssueDoc },
	layers: { LayerHistory },
	tableCommit: string?
): (string?, { [string]: boolean }, string?)
	local finishedIssues: { [string]: boolean } = {}
	local topFinishSha: string? = nil

	if #layers == 0 then
		return `{raftId} has no layers: ./zn start {raftId}`, finishedIssues, nil
	end
	if #layers ~= #issues then
		return `{raftId} has {#layers} layer(s) for {#issues} issue(s)`, finishedIssues, nil
	end

	local tracePath = `{raftDir}/trace.md`

	for i, issue in issues do
		local layer = layers[i]
		if layer == nil or layer.issue ~= issue.id then
			local got = if layer then layer.name else "(missing)"
			return `{raftId} layer {i} is {got}, expected {issue.id}`, finishedIssues, topFinishSha
		end
		if layer.tip == nil or layer.tip == "" then
			return `{layer.name} has no tip`, finishedIssues, topFinishSha
		end
		if not layer.stackedOnBelow then
			return `{layer.name} is not stacked on the layer below`, finishedIssues, topFinishSha
		end
		if #layer.commits == 0 then
			return `layer {layer.name} has no finish commit`, finishedIssues, topFinishSha
		end
		local first = layer.commits[1]
		local expectedSubject = `{issue.id}: {layer.title}`
		if first.subject ~= expectedSubject then
			return `{issue.id} is not finished (expected "{expectedSubject}", got "{first.subject}")`,
				finishedIssues,
				topFinishSha
		end
		if first.parent ~= layer.base then
			return `layer {layer.name} was rewritten (expected "{expectedSubject}" on {string.sub(
				layer.base,
				1,
				12
			)})`,
				finishedIssues,
				topFinishSha
		end

		if i < #layers then
			if #layer.commits > 1 then
				local extra = layer.commits[#layer.commits]
				return `layer {layer.name} has commit {string.sub(extra.sha, 1, 12)} after finish commit {string.sub(
					first.sha,
					1,
					12
				)}`,
					finishedIssues,
					topFinishSha
			end
			local upper = layers[i + 1]
			if upper ~= nil and upper.base ~= first.sha then
				return `layer {layer.name} was rewritten after {upper.name} stacked on it`,
					finishedIssues,
					topFinishSha
			end
			finishedIssues[issue.id] = true
		else
			topFinishSha = first.sha
			finishedIssues[issue.id] = true

			if tableCommit == nil or tableCommit == "" then
				return "missing Commit: header", finishedIssues, topFinishSha
			end
			if tableCommit ~= first.sha then
				return `table names commit {tableCommit}, but top layer finish commit is {first.sha}`,
					finishedIssues,
					topFinishSha
			end

			if #layer.commits > 1 then
				local lastTraceIdx = 0
				for j = 2, #layer.commits do
					local c = layer.commits[j]
					for _, p in c.files do
						if p == tracePath then
							lastTraceIdx = j
						end
					end
				end

				for j = 2, #layer.commits do
					local c = layer.commits[j]
					if #c.files == 0 then
						if lastTraceIdx > 0 and j > lastTraceIdx then
							return `commit {string.sub(c.sha, 1, 12)} added to {layer.name} after trace.md`,
								finishedIssues,
								topFinishSha
						end
						return `commit {string.sub(c.sha, 1, 12)} added to {layer.name} after finish commit {string.sub(
							first.sha,
							1,
							12
						)}`,
							finishedIssues,
							topFinishSha
					end
					for _, p in c.files do
						if not isTrackerFileOf(p, raftId, raftDir, issues) then
							if lastTraceIdx > 0 and j > lastTraceIdx then
								return `commit {string.sub(c.sha, 1, 12)} added to {layer.name} after trace.md`,
									finishedIssues,
									topFinishSha
							end
							return `commit {string.sub(c.sha, 1, 12)} on {layer.name} touches non-tracker file {p} after finish`,
								finishedIssues,
								topFinishSha
						end
					end
				end

				if lastTraceIdx == 0 then
					local last = layer.commits[#layer.commits]
					return `commit {string.sub(last.sha, 1, 12)} added to {layer.name} before trace.md`,
						finishedIssues,
						topFinishSha
				end

				for j = lastTraceIdx + 1, #layer.commits do
					local c = layer.commits[j]
					for _, p in c.files do
						if not isAllowedAfterTrace(p, raftId, raftDir) then
							return `commit {string.sub(c.sha, 1, 12)} added to {layer.name} after trace.md`,
								finishedIssues,
								topFinishSha
						end
					end
				end
			end
		end
	end

	if tableCommit == nil or tableCommit == "" then
		return "missing Commit header", finishedIssues, topFinishSha
	end

	return nil, finishedIssues, topFinishSha
end

function trace.skeleton(raftId: string, commit: string, claims: { Claim }, sources: { string }): string
	local lines: { string } = {
		`# Trace: {raftId}`,
		"",
		`Commit: {commit}`,
		"",
		"## Claims",
		"",
		"| claim | design | test | code |",
		"|---|---|---|---|",
	}
	for _, c in claims do
		table.insert(lines, `| {c.rowLabel} |  |  |  |`)
	end
	table.insert(lines, "")
	table.insert(lines, "## Source files")
	table.insert(lines, "")
	table.insert(lines, "| file | claims |")
	table.insert(lines, "|---|---|")
	local sortedSources = table.clone(sources)
	table.sort(sortedSources)
	for _, src in sortedSources do
		table.insert(lines, `| {src} |  |`)
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

local function splitPipeRow(line: string): { string }?
	local trimmed = trim(line)
	if string.sub(trimmed, 1, 1) ~= "|" or string.sub(trimmed, -1) ~= "|" then
		return nil
	end
	local inner = string.sub(trimmed, 2, -2)
	local cells: { string } = {}
	local pos = 1
	local len = #inner
	while true do
		local bar = string.find(inner, "|", pos, true)
		if bar == nil then
			table.insert(cells, trim(string.sub(inner, pos)))
			break
		end
		table.insert(cells, trim(string.sub(inner, pos, bar - 1)))
		pos = bar + 1
		if pos > len then
			table.insert(cells, "")
			break
		end
	end
	return cells
end

local function isSeparatorRow(cells: { string }): boolean
	if #cells == 0 then
		return false
	end
	for _, c in cells do
		if string.match(c, "^:?%-+:?$") == nil then
			return false
		end
	end
	return true
end

local function parseClaimId(raw: string): string
	local id = string.match(trim(raw), "^([A-Za-z0-9_%-]+:[A-Za-z]+%d+)")
	if id ~= nil then
		return id
	end
	local head = string.match(trim(raw), "^([^:]+:%S+)")
	return head or trim(raw)
end

function trace.parse(text: string): (ParsedTable?, string?)
	local raftId: string? = nil
	local commit: string? = nil
	local claims: { ClaimRow } = {}
	local sources: { SourceRow } = {}
	local section: string? = nil

	for _, line in trace.splitLines(text) do
		local trimmed = trim(line)
		local hdrRaft = string.match(trimmed, "^#%s+Trace:%s*(%S+)")
		if hdrRaft ~= nil then
			raftId = hdrRaft
		end
		local hdrCommit = string.match(trimmed, "^Commit:%s*(%S+)")
		if hdrCommit ~= nil and commit == nil then
			commit = hdrCommit
		end
		if string.lower(trimmed) == "## claims" then
			section = "claims"
		elseif string.lower(trimmed) == "## source files" then
			section = "sources"
		elseif string.sub(trimmed, 1, 3) == "## " then
			section = nil
		elseif section == "claims" then
			local cells = splitPipeRow(trimmed)
			if cells ~= nil and not isSeparatorRow(cells) then
				if #cells >= 4 and string.lower(cells[1]) ~= "claim" then
					table.insert(claims, {
						rawClaim = cells[1],
						claimId = parseClaimId(cells[1]),
						design = cells[2],
						test = cells[3],
						code = cells[4],
					})
				end
			end
		elseif section == "sources" then
			local cells = splitPipeRow(trimmed)
			if cells ~= nil and not isSeparatorRow(cells) then
				if #cells >= 2 and string.lower(cells[1]) ~= "file" then
					table.insert(sources, {
						file = cells[1],
						claims = cells[2],
					})
				end
			end
		end
	end

	return {
		raftId = raftId,
		commit = commit,
		claims = claims,
		sources = sources,
	}, nil
end

local function extractHumanRulings(md: string): { string }
	local body = sectionBody(md, "Open to the human")
	if body == nil then
		return {}
	end
	local out: { string } = {}
	for _, line in trace.splitLines(body) do
		local ruling = string.match(trim(line), "Ruled%s*%([^)]*%):%s*(.+)$")
		if ruling ~= nil then
			local norm = normalizeInline(ruling)
			if norm ~= "" then
				table.insert(out, norm)
			end
		end
	end
	return out
end

local function parseNotMet(cell: string): (boolean, string?)
	local trimmed = trim(cell)
	local lower = string.lower(trimmed)
	if lower == "not met" or lower == "not met:" then
		return true, nil
	end
	local rest = string.match(trimmed, "^[Nn][Oo][Tt]%s+[Mm][Ee][Tt]%s*:%s*(.+)$")
	if rest == nil then
		return false, nil
	end
	local unquoted = trim(rest)
	unquoted = string.match(unquoted, '^"(.*)"$') or string.match(unquoted, "^'(.*)'$") or unquoted
	unquoted = normalizeInline(unquoted)
	if unquoted == "" then
		return true, nil
	end
	return true, unquoted
end

local function rulingMatches(quoted: string, rulings: { string }): boolean
	local qLower = string.lower(normalizeInline(quoted))
	if #qLower < 3 then
		return false
	end
	for _, r in rulings do
		local rLower = string.lower(r)
		if rLower == qLower or string.find(rLower, qLower, 1, true) ~= nil then
			return true
		end
	end
	return false
end

type FileLineRef = {
	path: string,
	line: number,
	endLine: number?,
}

local function extractRefs(cell: string): { FileLineRef }
	local refs: { FileLineRef } = {}
	for path, startStr, maybeRange in string.gmatch(cell, "([A-Za-z0-9_./%-]+):(%d+)(%-?%d*)") do
		local line = tonumber(startStr)
		local endLine: number? = nil
		if maybeRange ~= nil and string.sub(maybeRange, 1, 1) == "-" then
			endLine = tonumber(string.sub(maybeRange, 2))
		end
		if line ~= nil then
			table.insert(refs, {
				path = path,
				line = line,
				endLine = endLine,
			})
		end
	end
	return refs
end

local function isSpecForIssue(path: string, issue: IssueDoc): boolean
	if string.sub(path, -10) ~= ".spec.luau" then
		return false
	end
	local issueAccPrefix = issue.dirPath .. "/acceptance/"
	if string.sub(path, 1, #issueAccPrefix) == issueAccPrefix then
		return true
	end
	local homePrefix = if issue.home == "." then "" else issue.home .. "/"
	local homeAccPrefix = homePrefix .. "tests/acceptance/" .. issue.id .. "/"
	if string.sub(path, 1, #homeAccPrefix) == homeAccPrefix then
		return true
	end
	local anyAccIssue = string.match(path, "/tests/acceptance/([fdcR]%d+)/")
		or string.match(path, "^tests/acceptance/([fdcR]%d+)/")
		or string.match(path, "/issues/[^/]+/([fdcR]%d+)/acceptance/")
		or string.match(path, "/issues/([fdcR]%d+)/acceptance/")
	if anyAccIssue ~= nil and anyAccIssue ~= issue.id then
		return false
	end
	local homeTestsPrefix = homePrefix .. "tests/"
	if string.sub(path, 1, #homeTestsPrefix) == homeTestsPrefix then
		return true
	end
	return false
end

local function checkFileLineExists(
	ref: FileLineRef,
	filesAtCommit: { [string]: FileMeta }
): (FileMeta?, string?)
	local meta = filesAtCommit[ref.path]
	if meta == nil then
		return nil, `{ref.path}:{ref.line} does not exist at commit`
	end
	local total = #meta.lines
	if ref.line < 1 or ref.line > total then
		return nil, `{ref.path}:{ref.line} does not exist (file has {total} lines)`
	end
	if ref.endLine ~= nil and (ref.endLine < ref.line or ref.endLine > total) then
		return nil, `{ref.path}:{ref.line}-{ref.endLine} does not exist (file has {total} lines)`
	end
	return meta, nil
end

function trace.check(input: CheckInput): { string }
	local findings: { string } = {}
	local parsed, parseErr = trace.parse(input.tableText)
	if parsed == nil then
		table.insert(findings, `row trace, table: {parseErr or "invalid table"}`)
		return findings
	end

	local finishedIssues: { [string]: boolean } = input.finishedIssues or {}
	local expectedCommit: string = input.expectedCommit or ""
	local staleWhy: string? = input.staleReason

	if input.layers ~= nil then
		local rId = input.raftId or parsed.raftId or "raft"
		local rDir = input.raftDir or ""
		local computedStale, compFinished, compTopFinish =
			trace.staleReason(rId, rDir, input.issues, input.layers, parsed.commit)
		staleWhy = staleWhy or computedStale
		if input.finishedIssues == nil then
			finishedIssues = compFinished
		end
		if expectedCommit == "" and compTopFinish ~= nil then
			expectedCommit = compTopFinish
		end
	end

	if staleWhy ~= nil and staleWhy ~= "" then
		table.insert(findings, `row Commit, commit: table is stale ({staleWhy})`)
	elseif parsed.commit == nil or parsed.commit == "" then
		table.insert(findings, "row Commit, commit: table is stale (missing Commit header)")
	elseif expectedCommit ~= "" and parsed.commit ~= expectedCommit then
		table.insert(
			findings,
			`row Commit, commit: table is stale (table commit {parsed.commit} ~= stack commit {expectedCommit})`
		)
	end

	local derived, claimErrors = trace.deriveClaims(input.issues)
	for _, cerr in claimErrors do
		table.insert(findings, cerr)
	end
	local derivedById: { [string]: Claim } = {}
	for _, c in derived do
		derivedById[c.id] = c
	end

	local issueById: { [string]: IssueDoc } = {}
	local rulingsByIssue: { [string]: { string } } = {}
	local resultsByIssue: { [string]: { [string]: { [string]: boolean } }? } = {}
	local resultsErrByIssue: { [string]: string? } = {}
	local raftRulings = extractHumanRulings(input.raftDocText)
	for _, issue in input.issues do
		issueById[issue.id] = issue
		local list = extractHumanRulings(issue.docText)
		for _, r in raftRulings do
			table.insert(list, r)
		end
		rulingsByIssue[issue.id] = list
		if issue.resultsText ~= nil then
			local parsedRes, resErr = trace.parseResults(issue.resultsText)
			resultsByIssue[issue.id] = parsedRes
			resultsErrByIssue[issue.id] = resErr
		end
	end

	local changedSourcesSet: { [string]: boolean } = {}
	for _, src in input.changedSources do
		changedSourcesSet[src] = true
	end

	local commitLabel = if expectedCommit ~= ""
		then expectedCommit
		elseif parsed.commit ~= nil and parsed.commit ~= "" then parsed.commit
		else "HEAD"

	local seenClaims: { [string]: boolean } = {}
	local notMetClaims: { [string]: boolean } = {}

	for _, row in parsed.claims do
		local cid = row.claimId
		local claim = derivedById[cid]
		if claim == nil then
			table.insert(findings, `row {cid}, claim: unknown claim {cid}`)
			continue
		end
		if seenClaims[cid] then
			table.insert(findings, `row {cid}, claim: duplicate claim {cid}`)
			continue
		end
		seenClaims[cid] = true

		local issue = issueById[claim.issue]
		local isNotMet, quotedRuling = parseNotMet(row.design)
		if not isNotMet then
			local testNotMet, _ = parseNotMet(row.test)
			local codeNotMet, _ = parseNotMet(row.code)
			if testNotMet or codeNotMet then
				isNotMet = true
				quotedRuling = nil
			end
		end

		if isNotMet then
			notMetClaims[cid] = true
			if quotedRuling == nil then
				table.insert(
					findings,
					`row {cid}, design: claim marked not met without a human ruling from ## Open to the human`
				)
			elseif not rulingMatches(quotedRuling, rulingsByIssue[claim.issue] or {}) then
				table.insert(
					findings,
					`row {cid}, design: ruling "{quotedRuling}" is not recorded under ## Open to the human`
				)
			end
			continue
		end

		-- Design cell verification
		if row.design == "" then
			table.insert(findings, `row {cid}, design: empty cell`)
		else
			local refs = extractRefs(row.design)
			if #refs == 0 then
				table.insert(findings, `row {cid}, design: missing file:line reference`)
			end
			for _, ref in refs do
				local _, err = checkFileLineExists(ref, input.filesAtCommit)
				if err ~= nil then
					table.insert(findings, `row {cid}, design: {err}`)
				elseif ref.path ~= issue.docPath then
					table.insert(
						findings,
						`row {cid}, design: {ref.path} is not ticket {issue.id}'s document ({issue.docPath})`
					)
				end
			end
		end

		-- Test cell verification
		if row.test == "" then
			table.insert(findings, `row {cid}, test: empty cell`)
		else
			local refs = extractRefs(row.test)
			if #refs == 0 then
				table.insert(findings, `row {cid}, test: missing file:line reference`)
			end
			for _, ref in refs do
				local meta, err = checkFileLineExists(ref, input.filesAtCommit)
				if err ~= nil then
					table.insert(findings, `row {cid}, test: {err}`)
				elseif ref.path == issue.checkPath then
					local lineText = if meta ~= nil then trim(meta.lines[ref.line] or "") else ""
					if lineText == "" or string.sub(lineText, 1, 1) == "#" then
						table.insert(
							findings,
							`row {cid}, test: {ref.path}:{ref.line} is not a check command line`
						)
					elseif not finishedIssues[issue.id] then
						table.insert(
							findings,
							`row {cid}, test: {ref.path}:{ref.line} did not run green for this stack`
						)
					end
				elseif isSpecForIssue(ref.path, issue) then
					local resultsPath = issue.resultsPath or `{issue.dirPath}/results.txt`
					if issue.resultsText == nil then
						table.insert(
							findings,
							`row {cid}, test: results file {resultsPath} for ticket {issue.id} does not exist at commit {commitLabel}`
						)
					elseif resultsErrByIssue[issue.id] ~= nil then
						table.insert(
							findings,
							`row {cid}, test: invalid results file {resultsPath} for ticket {issue.id}: {resultsErrByIssue[issue.id]}`
						)
					else
						local issueResults = resultsByIssue[issue.id]
						local specCases = if issueResults ~= nil then issueResults[ref.path] else nil
						if specCases == nil then
							table.insert(
								findings,
								`row {cid}, test: {ref.path} did not run green for ticket {issue.id}`
							)
						elseif meta ~= nil then
							local explicitCase = string.match(row.test, "::%s*([^,;|\n]+)")
							if explicitCase ~= nil then
								explicitCase = trim(explicitCase)
							end
							local lineText = meta.lines[ref.line] or ""
							local caseTitle = explicitCase
								or string.match(lineText, 'it%s*%(%s*"([^"]+)"')
								or string.match(lineText, "it%s*%(%s*'([^']+)'")
								or string.match(lineText, 'test%s*%(%s*"([^"]+)"')
								or string.match(lineText, "test%s*%(%s*'([^']+)'")
							if caseTitle == nil or caseTitle == "" then
								table.insert(
									findings,
									`row {cid}, test: {ref.path}:{ref.line} does not name a test case`
								)
							elseif specCases[caseTitle] ~= true then
								table.insert(
									findings,
									`row {cid}, test: case "{caseTitle}" in {ref.path} did not run green for ticket {issue.id}`
								)
							end
						end
					end
				else
					table.insert(
						findings,
						`row {cid}, test: {ref.path} is not a spec or check.sh of ticket {issue.id}`
					)
				end
			end
		end

		-- Code cell verification
		if row.code == "" then
			table.insert(findings, `row {cid}, code: empty cell`)
		elseif #input.changedSources == 0 then
			if string.lower(trim(row.code)) ~= "none" then
				table.insert(findings, `row {cid}, code: stack changed no source file (expected "none")`)
			end
		elseif string.lower(trim(row.code)) == "none" then
			table.insert(
				findings,
				`row {cid}, code: "none" is only valid when the stack changed no source file`
			)
		else
			local refs = extractRefs(row.code)
			if #refs == 0 then
				table.insert(findings, `row {cid}, code: missing file:line reference`)
			end
			for _, ref in refs do
				local _, err = checkFileLineExists(ref, input.filesAtCommit)
				if err ~= nil then
					table.insert(findings, `row {cid}, code: {err}`)
				elseif not changedSourcesSet[ref.path] then
					table.insert(findings, `row {cid}, code: {ref.path} was not changed by this stack`)
				end
			end
		end
	end

	for _, c in derived do
		if not seenClaims[c.id] then
			table.insert(findings, `row {c.id}, claim: missing claim {c.id} ({c.text})`)
		end
	end

	local seenSources: { [string]: boolean } = {}
	for _, srow in parsed.sources do
		local file = srow.file
		if file == "" then
			table.insert(findings, "row (empty), file: empty source file cell")
			continue
		end
		if seenSources[file] then
			table.insert(findings, `row {file}, file: duplicate source file {file}`)
			continue
		end
		seenSources[file] = true

		if not changedSourcesSet[file] then
			table.insert(findings, `row {file}, file: {file} was not changed by this stack`)
		end

		if trim(srow.claims) == "" then
			table.insert(findings, `row {file}, claims: empty cell`)
		else
			local cids: { string } = {}
			for cid in string.gmatch(srow.claims, "([A-Za-z0-9_%-]+:[A-Za-z]+%d+)") do
				table.insert(cids, cid)
			end
			if #cids == 0 then
				table.insert(findings, `row {file}, claims: no valid claim id named`)
			end
			local metCount = 0
			local notMetListed: { string } = {}
			for _, cid in cids do
				if derivedById[cid] == nil then
					table.insert(findings, `row {file}, claims: unknown claim {cid}`)
				elseif notMetClaims[cid] then
					table.insert(notMetListed, cid)
				else
					metCount += 1
				end
			end
			if metCount == 0 and #notMetListed > 0 then
				for _, cid in notMetListed do
					table.insert(findings, `row {file}, claims: claim {cid} is marked not met`)
				end
			end
		end
	end

	for _, src in input.changedSources do
		if not seenSources[src] then
			table.insert(findings, `row {src}, file: changed source file missing from table`)
		end
	end

	return findings
end

return trace
