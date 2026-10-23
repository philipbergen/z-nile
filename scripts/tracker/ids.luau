--!strict
-- Forwarder (c0114): moved to z-nile/engine/ids.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/ids")
export type Space = m.Space
export type Counters = m.Counters
return m
