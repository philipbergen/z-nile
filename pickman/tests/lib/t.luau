--!strict
-- The assertions every spec uses are the shared runner's (z-nile/tests/lib/t.luau); pickman's specs reach them
-- as @tests/lib/t, which pickman/.luaurc points at pickman/tests (c0120).
local t = require("../../../z-nile/tests/lib/t")

export type Case = t.Case
export type Spec = t.Spec

return t
