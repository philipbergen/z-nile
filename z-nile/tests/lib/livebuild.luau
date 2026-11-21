--!strict
-- f0424: the live daemon a z-nile spec run needs, built by the runner's top process (outside the jail) when it is missing
-- or older than the Go sources, by the same z-nile/lib/gobuild.sh the gate uses. Writes only under <root>/.cache. Where
-- Go is absent or too old, or there are no sources, nothing is built and nothing fails (gobuild.sh exits 3): the live
-- specs then say so themselves, as they did before.
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local livebuild = {}

-- Whether a run builds: it is z-nile's own home, the Go sources exist, and the process is not already inside a guarded
-- run (`guarded`: a worker or a nested run is jailed and never builds). Pure.
function livebuild.wanted(home: string, hasSources: boolean, guarded: boolean): boolean
	return home == "z-nile" and hasSources and not guarded
end

-- Runs gobuild.sh for <root>: "built", "current" (the binary is up to date), "unavailable" (no Go, too old, or no
-- sources) or "failed" (the compiler's output goes to stderr; the specs then fail on the missing binary). `env` is for specs.
function livebuild.ensure(root: string, env: { [string]: string }?): string
	local r = process.exec("bash", {
		`{root}/z-nile/lib/gobuild.sh`,
		root,
		`{root}/.cache/bin/znlive`,
	}, { env = env })
	if r.ok then
		return if string.find(r.stdout, " up to date: ", 1, true) then "current" else "built"
	elseif r.code == 3 then
		return "unavailable"
	end
	stdio.ewrite(`tests/run: building the live daemon failed:\n{r.stderr}\n`)
	return "failed"
end

return livebuild
