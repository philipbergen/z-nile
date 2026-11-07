--!strict
-- The agent's GitHub credential (c0117, the user's "Bot token, no bypass"): a dispatched model step runs with a token
-- of its own (a fine-grained token or a GitHub App's) that can push branches and open pull requests but can't merge,
-- bypass `main`'s protection or write protection or rulesets. The user's token never enters the step's environment:
-- GH_TOKEN and GITHUB_TOKEN are the agent's, gh reads an empty configuration folder of the step's own, and git's
-- credential helpers are reset to one that answers with the agent's token. What the OS can't stop: a process of the
-- same user can still read the user's own credentials where they live (the keychain, ~/.config/gh); only a separate
-- OS user would close that, and the dispatcher's tripwire and main's protection are what catch its use.
local fs = require("@lune/fs")
local process = require("@lune/process")

local credential = {}

-- Where the agent's token is read from: the file ZN_AGENT_TOKEN_FILE names (then nowhere else), else
-- ~/.config/zn/agent-token, else the macOS keychain item `zn-dispatch-agent`.
credential.KEYCHAIN = "zn-dispatch-agent"

function credential.token(): (string?, string)
	local file = process.env.ZN_AGENT_TOKEN_FILE
	if file and file ~= "" then
		-- a named file is the only place looked at
		local t = if fs.isFile(file) then (string.gsub(fs.readFile(file), "%s+", "")) else ""
		if t ~= "" then
			return t, file
		end
		return nil,
			`no agent credential in {file} (ZN_AGENT_TOKEN_FILE): store the agent's token first (zz-rules, Dispatch, the agent credential)`
	end
	local home = process.env.HOME or ""
	for _, path in { `{home}/.config/zn/agent-token` } do
		if path ~= "" and fs.isFile(path) then
			local t = (string.gsub(fs.readFile(path), "%s+", ""))
			if t ~= "" then
				return t, path
			end
		end
	end
	local r = process.exec("security", { "find-generic-password", "-s", credential.KEYCHAIN, "-w" })
	if r.ok then
		local t = (string.gsub(r.stdout, "%s+", ""))
		if t ~= "" then
			return t, `keychain {credential.KEYCHAIN}`
		end
	end
	return nil,
		"no agent credential: store the agent's token (zz-rules, Dispatch, the agent credential) first"
end

-- The variables a step's environment gets on top of `base` (the dispatcher's): the agent's token for gh and git, an
-- empty gh configuration folder, no ssh agent, no prompts. git configuration entries are appended after any the
-- environment already carries (the repository guards' own, in a check), never in their place.
function credential.agentEnv(
	base: { [string]: string? },
	token: string,
	configDir: string
): { [string]: string }
	fs.writeDir(configDir)
	local n = tonumber(base.GIT_CONFIG_COUNT or "0") or 0
	local env: { [string]: string } = {
		GH_TOKEN = token,
		GITHUB_TOKEN = token,
		ZN_AGENT_GH_TOKEN = token,
		GH_CONFIG_DIR = configDir,
		GH_PROMPT_DISABLED = "1",
		GIT_TERMINAL_PROMPT = "0",
		SSH_AUTH_SOCK = "",
		GIT_CONFIG_COUNT = tostring(n + 2),
		[`GIT_CONFIG_KEY_{n}`] = "credential.helper",
		[`GIT_CONFIG_VALUE_{n}`] = "",
		[`GIT_CONFIG_KEY_{n + 1}`] = "credential.helper",
		[`GIT_CONFIG_VALUE_{n + 1}`] = '!f() { test "$1" = get && echo username=x-access-token && echo "password=$ZN_AGENT_GH_TOKEN"; }; f',
	}
	return env
end

return credential
