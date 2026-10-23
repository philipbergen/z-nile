--!strict
-- Forwarder (c0114): moved to z-nile/engine/stats.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/stats")
export type Kind = m.Kind
export type Spell = m.Spell
export type Item = m.Item
export type Spend = m.Spend
export type Bucket = m.Bucket
export type Counts = m.Counts
export type Ratios = m.Ratios
export type Row = m.Row
export type Spread = m.Spread
export type ByType = m.ByType
export type Stats = m.Stats
return m
