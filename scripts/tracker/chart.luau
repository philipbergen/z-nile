--!strict
-- Forwarder (c0114): moved to z-nile/engine/chart.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/chart")
export type Series = m.Series
export type Options = m.Options
return m
