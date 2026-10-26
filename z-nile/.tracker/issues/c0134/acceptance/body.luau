--!strict
-- c0134 AC2: prints the body (split.cut) of the file text on stdin, so check.sh compares two bodies cut by the same
-- reader as header.spec.
local split = require("./split")
local stdio = require("@lune/stdio")

local _, body = split.cut(stdio.readToEnd())
stdio.write(body .. "\n")
