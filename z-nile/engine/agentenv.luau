--!strict
-- f0423: the environment variables that say an agent, not the person, is running a command. One list, read by the
-- engine's recording guard (approvewalk) and by the PreToolUse hook (boundcmd). Pure data.
local agentenv = {}

-- set by an agent CLI for everything it runs
agentenv.MARKERS = {
	"CLAUDECODE",
	"AI_AGENT",
	"CLAUDE_CODE_SESSION_ID",
	"CURSOR_AGENT",
	"GROK_SESSION_ID",
	"KIMI_SESSION_ID",
	"KIMI_CODE_SESSION_ID",
} :: { string }

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
