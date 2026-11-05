--!strict
-- What the orchestrator does with a spec given its stored row, and which runs may record (c0165). Pure.

local reuseplan = {}

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

export type Row = { state: string, updated: number? }

-- "reuse" a passed row; "run" for no row, a failed row, and every row under --fresh.
function reuseplan.decide(row: Row?, fresh: boolean): "reuse" | "run"
	if fresh or row == nil or row.state ~= "passed" then
		return "run"
	end
	return "reuse"
end

-- Whether a run in this jail may record results: only the host's strongest one (the name the runner wrote in
-- PICKMAN_TEST_JAIL), because a weaker jail lets a spec write what it likes. macOS: the sandbox, or a fixture of a
-- guarded checkout inside another sandbox; Linux has no jail, so "none (not macOS)". An empty name records nothing.
function reuseplan.records(jail: string, os: "macos" | "linux"): boolean
	if jail == "" then
		return false
	end
	if os == "macos" then
		return jail == "sandbox-exec" or startsWith(jail, "outer sandbox (a fixture of a guarded checkout")
	end
	return startsWith(jail, "none")
end

return reuseplan
