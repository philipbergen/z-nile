--!strict
-- The assertions every spec uses are the shared runner's (z-nile/tests/lib/t.luau); this home's specs reach them
-- as @tests/lib/t, which this home's .luaurc points at its own tests/ (c0184).
local t = require("../../../z-nile/tests/lib/t")

export type Case = t.Case
export type Spec = t.Spec

return t
