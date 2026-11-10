--!strict
-- Refuse a watch file that does not parse, that is empty, that names a path that is not a file,
-- or a spec that no watch file covers.
--   lune run z-nile/watch-check
-- Prints one problem per line and exits 1. Prints nothing and exits 0 when every watch file is sound.

local context = require("./lib/context")
local process = require("@lune/process")
local projects = require("./engine/projects")
local stdio = require("@lune/stdio")

local _, why = context.build(projects.load())
if why then
	stdio.ewrite(why .. "\n")
	process.exit(1)
end
