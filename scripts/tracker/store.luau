--!strict
-- Forwarder (c0114): moved to z-nile/engine/store.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/store")
export type State = m.State
export type Kind = m.Kind
export type Item = m.Item
return m
