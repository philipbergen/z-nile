--!strict
-- f0423: the environment variables that say an agent, not the person, is running a command. One list, read by the
-- engine's recording guard (approvewalk) and by the PreToolUse hook (boundcmd). Pure data.
local agentenv = {}

-- Each marker with the worker CLI (models.CLIS) whose sessions set it: the one definition of which marker belongs to
-- which CLI. Adding a worker CLI adds its marker here in the same change (f0421 escape, 2026-11-24: agy came without
-- one; tests/tooling/agentenv.spec ties every CLI to a marker). AI_AGENT was seen in Claude Code's shell (c0250 E3).
agentenv.OWNERS = {
	{ "CLAUDECODE", "claude" },
	{ "AI_AGENT", "claude" },
	{ "CLAUDE_CODE_SESSION_ID", "claude" },
	{ "CURSOR_AGENT", "agent" },
	{ "GROK_SESSION_ID", "grok" },
	{ "KIMI_SESSION_ID", "kimi" },
	{ "KIMI_CODE_SESSION_ID", "kimi" },
	{ "ANTIGRAVITY_AGENT", "agy" },
} :: { { string } }

-- set by an agent CLI for everything it runs: the markers of OWNERS, in its order
agentenv.MARKERS = {} :: { string }
for _, pair in agentenv.OWNERS do
	table.insert(agentenv.MARKERS, pair[1])
end

-- set by z-nile itself: the dispatcher's runs and the walkthrough's session
agentenv.OWN = { "ZN_DISPATCH", "ZN_APPROVE_SESSION" } :: { string }

-- The first variable of `names` that is set (non-empty) in `env`, or nil.
function agentenv.firstSet(env: { [string]: string? }, names: { string }): string?
	for _, name in names do
		local v = env[name]
		if v ~= nil and v ~= "" then
			return name
		end
	end
	return nil
end

-- every name a command may unset to look like the person
function agentenv.all(): { string }
	local out = table.clone(agentenv.MARKERS)
	for _, n in agentenv.OWN do
		table.insert(out, n)
	end
	return out
end

return agentenv
