--!strict
-- Forwarder (c0114): moved to z-nile/engine/board.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/board")
export type Bucket = m.Bucket
export type ViewName = m.ViewName
export type Groups = m.Groups
export type Raft = m.Raft
export type Issue = m.Issue
export type Model = m.Model
return m
