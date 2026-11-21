--!strict
-- f0420 step 3: the light path read from a checkout (the edge of light.luau): what `./zn done` and the dispatcher ask
-- of a raft. The rule itself is light.luau's; this reads the raft's documents, its diff and its ready commit.

local fs = require("@lune/fs")
local layergit = require("./layergit")
local light = require("./light")
local sh = require("../lib/sh")
local store = require("./store")

local lightgit = {}

export type Verdict = {
	light: boolean,
	why: string?, -- why not (nil when light)
	claimed: boolean, -- its ready commit says `Light: true`: `ready <issue>` made it for the light path
	reviewed: boolean, -- the raft's folder holds a review-NNN.md (a code review was run)
}

function lightgit.of(raft: store.Item): Verdict
	local members = store.members(raft.id)
	local front = store.readFront(raft.doc)
	local facts: { light.Member } = {}
	for _, m in members do
		local mf = store.readFront(m.doc)
		table.insert(facts, {
			risk = mf.risk,
			doc = if fs.isFile(m.doc) then fs.readFile(m.doc) else "",
			designReady = mf.design == "ready",
		})
	end
	local changed: number? = nil
	local layers = layergit.layersOf(raft.id)
	if #layers > 0 then
		local onto = layergit.raftBase(raft.id)
		local tip = layergit.layerTip(layers[#layers])
		if tip then
			local diffed = sh.run("git", { "diff", "--numstat", onto, tip })
			if diffed.ok then
				changed = light.changedLines(diffed.stdout)
			end
		end
	end
	local why = if front.single == "true"
		then light.reason({ members = facts, depsMet = true, changed = changed })
		else "it is not a single raft"
	local reviewed = false
	if fs.isDir(raft.dir) then
		for _, name in fs.readDir(raft.dir) do
			if string.match(name, "^review%-%d+%.md$") then
				reviewed = true
			end
		end
	end
	return {
		light = why == nil,
		why = why,
		claimed = layergit.readyRecord(raft.id).light == true,
		reviewed = reviewed,
	}
end

return lightgit
