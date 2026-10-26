--!strict
-- c0134 AC2: prints, byte for byte, the body (split.cut: everything but the header) of the file text on stdin, so
-- check.sh compares two bodies cut by the same rule as header.spec.
local split = require("./split")
local stdio = require("@lune/stdio")

local _, body = split.cut(stdio.readToEnd())
stdio.write(body)
