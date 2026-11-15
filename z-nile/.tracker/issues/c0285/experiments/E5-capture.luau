--!strict
-- E5 (c0285): run with the fixture as the current directory. Prints the capture `./zn capture` would take for c0001
-- (trail.read over the path-limited log, then trail.capture) and the document at that commit.
local process = require("@lune/process")
local trail = require("../../../../engine/trail")
local commits = trail.read("issues", "c0001", function(name: string): boolean
	return name == "c0001.md"
end, "HEAD", { "z/.tracker" })
assert(commits, "no history")
local c, isCapture = trail.capture(commits)
assert(c, "no capture")
local doc = process.exec("git", { "show", `{c.sha}:{c.path}` }).stdout
print(`capture {string.sub(c.sha, 1, 8)} {c.subject}{if isCapture then "" else " (no capture commit)"}`)
print(`doc: {(string.gsub(string.match(doc, "## Solution\n[^\n]*") or "?", "\n", " | "))}`)
