--!strict
-- Forwarder (c0114): moved to z-nile/lib/graph.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/lib/graph")
export type Graph = m.Graph
export type GameRoot = m.GameRoot
return m
