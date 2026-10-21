--!strict
-- Forwarder (c0114): moved to z-nile/engine/trail.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/trail")
export type Cut = m.Cut
export type Commit = m.Commit
return m
