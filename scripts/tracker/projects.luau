--!strict
-- Forwarder (c0114): moved to z-nile/engine/projects.luau. Kept for the specs that require this path; removed with the
-- scripts/tracker.sh forwarder.
local m = require("../../z-nile/engine/projects")
export type Project = m.Project
export type Registry = m.Registry
return m
