--!strict
-- c0156: the small reporter of the check.sh-only scripts here (consumers.luau, record.luau, kills.luau). They read
-- other projects' files (pickman's pins and a done raft's record), and a promoted spec of this project must not (a
-- pickman-only change would turn z-nile's gate red without selecting it: zz-test/specs-pin-only-their-own-project), so
-- check.sh runs them and the spec runner never does, as c0120's finished.luau is run. Read-only apart from a fixture
-- folder under the home's .cache. Usage: lune run <script>.luau -- <the checkout's top>
local process = require("@lune/process")

local scripted = {}

local failed = 0

-- the checkout's top: the first argument that isn't `--` (lune keeps it when the script is named by an absolute path)
function scripted.top(): string
	for _, a in process.args do
		if a ~= "--" then
			return a
		end
	end
	error("usage: <script>.luau -- <the checkout's top>")
end

function scripted.check(label: string, ok: boolean, detail: string?)
	if ok then
		print(`ok   {label}`)
	else
		failed += 1
		print(`FAIL {label}{if detail then `: {detail}` else ""}`)
	end
end

function scripted.has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

function scripted.finish()
	if failed > 0 then
		print(`{failed} checks failed`)
		process.exit(1)
	end
	print("all checks passed")
end

return scripted
