--!strict
-- Final review traceability table (`<raft-dir>/trace.md`): pure claim
-- derivation, skeleton generation, table parser, and mechanical verification.
--
-- Contract for the Python port:
--
-- 1. CLI:
--    `./zn trace <R-id>`
--      Prints the trace table skeleton for active raft `<R-id>` to stdout.
--      Requires every layer of `<R-id>` to be finished.
--    `./zn trace <R-id> --check`
--      Reads `<raft-dir>/trace.md` from the top layer's commit (or working
--      tree when at the top layer's finished commit) and verifies it against
--      the finished stack. Prints `ok: <R-id>` and exits 0 when valid; prints
--      each failure (`row <row>, <cell>: <message>`) to stderr and exits 1
--      when any check fails.
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
--    Fallback for minimal fixture tickets without those sections: `AC<N>`
--    check lines in `<id>/check.sh`, else the first body paragraph of
--    `<id>.md` as `<id>:P1`.
--
-- 3. File format (`<raft-dir>/trace.md`):
--    ```markdown
--    # Trace: <R-id>
--
--    Commit: <top-layer-finished-sha>
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
--    A claim deliberately not met writes `not met: "<ruling>"` in `design`
--    (with `test` and `code` empty or `-`), quoting a `Ruled (user, ...):`
--    line from `## Open to the human` in `<id>.md` or `<R-id>.md`.

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

export type SpecResult = {
	passed: boolean,
	cases: { [string]: boolean }?,
}

export type CheckInput = {
	tableText: string,
	expectedCommit: string,
	staleReason: string?,
	issues: { IssueDoc },
	raftDocText: string,
	changedSources: { string },
	changedFiles: { string }?,
	changedSpecs: { [string]: boolean },
	filesAtCommit: { [string]: FileMeta },
	greenSpecs: { [string]: SpecResult },
	finishedIssues: { [string]: boolean },
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

local function fallbackBodyItem(md: string): string?
	local inFence = false
	for _, raw in trace.splitLines(md) do
		local trimmed = trim(raw)
		if string.sub(trimmed, 1, 3) == "```" then
			inFence = not inFence
		elseif not inFence and trimmed ~= "" then
			if string.sub(trimmed, 1, 1) ~= "#" and string.sub(trimmed, 1, 4) ~= "<!--" then
				return normalizeInline(trimmed)
			end
		end
	end
	return nil
end

local function extractCheckAcs(checkText: string?): { { key: string, text: string } }
	local out: { { key: string, text: string } } = {}
	if checkText == nil then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, line in trace.splitLines(checkText) do
		local acNum, desc = string.match(line, 'check%s+"AC(%d+)[:%s%-]*(.-)"')
		if acNum ~= nil then
			local key = "AC" .. acNum
			if not seen[key] then
				seen[key] = true
				local summary = normalizeInline(desc or "")
				if summary == "" then
					summary = key
				end
				table.insert(out, { key = key, text = summary })
			end
		end
	end
	return out
end

function trace.deriveClaims(issues: { IssueDoc }): { Claim }
	local out: { Claim } = {}
	for _, issue in issues do
		local issueClaims = 0
		local captured = if issue.capturedText ~= "" then issue.capturedText else issue.docText
		local problems = extractOutcomes(sectionBody(captured, "Problem"))
		for i, text in problems do
			local id = `{issue.id}:P{i}`
			table.insert(out, {
				id = id,
				issue = issue.id,
				kind = "P",
				text = text,
				rowLabel = `{id}: {text}`,
			})
			issueClaims += 1
		end

		local solutions = extractOutcomes(sectionBody(captured, "Solution"))
		for i, text in solutions do
			local id = `{issue.id}:S{i}`
			table.insert(out, {
				id = id,
				issue = issue.id,
				kind = "S",
				text = text,
				rowLabel = `{id}: {text}`,
			})
			issueClaims += 1
		end

		local acBody = sectionBody(issue.docText, "Acceptance criteria")
			or sectionBody(captured, "Acceptance criteria")
		local acItems = extractOutcomes(acBody)
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
			issueClaims += 1
		end

		if issueClaims == 0 then
			local checkAcs = extractCheckAcs(issue.checkText)
			for _, item in checkAcs do
				local id = `{issue.id}:{item.key}`
				table.insert(out, {
					id = id,
					issue = issue.id,
					kind = "AC",
					text = item.text,
					rowLabel = `{id}: {item.text}`,
				})
				issueClaims += 1
			end
		end

		if issueClaims == 0 then
			local bodyItem = fallbackBodyItem(captured) or fallbackBodyItem(issue.docText) or issue.id
			local id = `{issue.id}:P1`
			table.insert(out, {
				id = id,
				issue = issue.id,
				kind = "P",
				text = bodyItem,
				rowLabel = `{id}: {bodyItem}`,
			})
		end
	end
	return out
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

local function isSpecForIssue(path: string, issue: IssueDoc, changedSpecs: { [string]: boolean }): boolean
	if string.sub(path, -10) ~= ".spec.luau" then
		return false
	end
	local issueAccPrefix = issue.dirPath .. "/acceptance/"
	if string.sub(path, 1, #issueAccPrefix) == issueAccPrefix then
		return true
	end
	local homeAccPrefix = issue.home .. "/tests/acceptance/" .. issue.id .. "/"
	if string.sub(path, 1, #homeAccPrefix) == homeAccPrefix then
		return true
	end
	local anyAccIssue = string.match(path, "/tests/acceptance/([cCrR]%d+)/")
		or string.match(path, "/issues/[^/]+/([cCrR]%d+)/acceptance/")
	if anyAccIssue ~= nil and anyAccIssue ~= issue.id then
		return false
	end
	local homeTestsPrefix = issue.home .. "/tests/"
	if string.sub(path, 1, #homeTestsPrefix) == homeTestsPrefix and changedSpecs[path] then
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

	if input.staleReason ~= nil and input.staleReason ~= "" then
		table.insert(findings, `row Commit, commit: table is stale ({input.staleReason})`)
	elseif parsed.commit == nil or parsed.commit == "" then
		table.insert(findings, "row Commit, commit: table is stale (missing Commit header)")
	elseif parsed.commit ~= input.expectedCommit then
		table.insert(
			findings,
			`row Commit, commit: table is stale (table commit {parsed.commit} ~= stack commit {input.expectedCommit})`
		)
	end

	local derived = trace.deriveClaims(input.issues)
	local derivedById: { [string]: Claim } = {}
	for _, c in derived do
		derivedById[c.id] = c
	end

	local issueById: { [string]: IssueDoc } = {}
	local rulingsByIssue: { [string]: { string } } = {}
	local raftRulings = extractHumanRulings(input.raftDocText)
	for _, issue in input.issues do
		issueById[issue.id] = issue
		local list = extractHumanRulings(issue.docText)
		for _, r in raftRulings do
			table.insert(list, r)
		end
		rulingsByIssue[issue.id] = list
	end

	local changedSourcesSet: { [string]: boolean } = {}
	for _, src in input.changedSources do
		changedSourcesSet[src] = true
	end
	local allowedCodeSet: { [string]: boolean } = changedSourcesSet
	if #input.changedSources == 0 and input.changedFiles ~= nil then
		allowedCodeSet = {}
		for _, f in input.changedFiles do
			allowedCodeSet[f] = true
		end
	end

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
					elseif not input.finishedIssues[issue.id] then
						table.insert(
							findings,
							`row {cid}, test: {ref.path}:{ref.line} did not run green for this stack`
						)
					end
				elseif isSpecForIssue(ref.path, issue, input.changedSpecs) then
					local specRes = input.greenSpecs[ref.path]
					local explicitCase = string.match(row.test, "::%s*([^,;|\n]+)")
					if explicitCase ~= nil then
						explicitCase = trim(explicitCase)
					end
					if specRes == nil or not specRes.passed then
						table.insert(findings, `row {cid}, test: {ref.path} did not run green for this stack`)
					elseif meta ~= nil then
						local lineText = meta.lines[ref.line] or ""
						local caseTitle = explicitCase
							or string.match(lineText, 'it%s*%(%s*"([^"]+)"')
							or string.match(lineText, 'test%s*%(%s*"([^"]+)"')
						if caseTitle ~= nil then
							local matched: boolean? = nil
							if specRes.cases ~= nil and next(specRes.cases) ~= nil then
								matched = specRes.cases[caseTitle]
								if matched == nil then
									for k, ok in specRes.cases do
										if string.find(k, caseTitle, 1, true) ~= nil then
											matched = ok
											break
										end
									end
								end
								if matched == nil then
									matched = false
								end
							elseif explicitCase ~= nil then
								matched = string.find(lineText, explicitCase, 1, true) ~= nil
							end
							if matched == false then
								table.insert(
									findings,
									`row {cid}, test: case "{caseTitle}" in {ref.path} did not run green for this stack`
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
		else
			local refs = extractRefs(row.code)
			if #refs == 0 then
				table.insert(findings, `row {cid}, code: missing file:line reference`)
			end
			for _, ref in refs do
				local _, err = checkFileLineExists(ref, input.filesAtCommit)
				if err ~= nil then
					table.insert(findings, `row {cid}, code: {err}`)
				elseif not allowedCodeSet[ref.path] then
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
