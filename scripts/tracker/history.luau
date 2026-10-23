--!strict
-- Forwarder (c0114): moved to z-nile/engine/history.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/history")
export type Spell = m.Spell
export type Parsed = m.Parsed
return m
