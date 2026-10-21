--!strict
-- c0114 AC18, AC20: every existing tooling item moved into z-nile/.tracker/ and every game item stayed in tracker/,
-- by the classification in c0114's Design. Items are named by kind and slug, which a compaction never changes (ids it
-- does), and each moved with its id, so nothing else about it changed. And every unfinished item's check.sh,
-- sequestered before the move, still runs through the forwarders: listed (AC_LIST=1) it names its checks, or it is an
-- empty draft.
local fs = require("@lune/fs")
local process = require("@lune/process")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

-- the tooling: the tracker, its board and spend, the gate and the selector, the repository guards and the spec runner,
-- CI and bootstrap, the skills and the process
local ZNILE: { [string]: { string } } = {
	issue = {
		"ci-and-host-bootstrap-proven",
		"check-affected-empty-array-bash32",
		"worktrees-by-default",
		"lifecycle-spec-clone-isolation",
		"affected-changed-files-spec",
		"done-ready-before-final-push",
		"renumber-scoped-to-item",
		"check-sh-after-promotion",
		"pr-visible-review-cadence",
		"post-merge-cleanup",
		"auto-merge-when-verified",
		"done-deferred-answer",
		"duplicate-id-detection",
		"reviewer-strong-model",
		"raft-browser",
		"review-second-order",
		"doc-filename-without-slug",
		"parallel-workstreams",
		"inside-repo-worktrees",
		"prep-spec-override-guard",
		"board-artifact",
		"parallel-gate-stages",
		"start-checks-depends-on",
		"renumber-step-one",
		"publish-state-to-main",
		"setup-script-behavioural-spec",
		"board-opens-by-default",
		"checks-never-touch-real-repo",
		"adapt-r0200-r0190-specs",
		"retrofit-fixture-checks",
		"gate-slow-c0053-commands",
		"c0038-cleanup-flake",
		"ready-raft",
		"stop-raft",
		"launch-raft",
		"board-follows-main",
		"board-live-server",
		"review-rounds-up-to-five",
		"capture-without-pr",
		"board-statistics",
		"done-gate-after-promotion",
		"fixture-shell-cd-escape",
		"detached-spec-processes-survive",
		"jail-cache-symlink-swap",
		"review-r0210-round6-fixes",
		"run-watchdog-spec",
		"review-fix-consequences",
		"compact-ids-next-number",
		"tracker-integrity-audit",
		"split-harness-game-suites",
		"track-sdlc-spend",
		"compaction-spec-cache-names",
		"spec-isolation-run-lock",
		"remap-index-free",
		"replace-file-stub-two-builds",
		"board-raft-issue-views",
		"quoted-board-download",
		"skill-lessons",
		"lessons-backfill",
		"skills-readme",
		"z-nile-home",
		"skill-names-readme",
		"split-raft-step",
		"models-and-dispatcher",
		"project-board",
		"scope-fidelity",
		"pickman-home",
	},
	raft = {
		"worktrees-by-default",
		"raft-browser",
		"review-second-order",
		"tracker-hardening",
		"parallel-gate-stages",
		"board-artifact-spec-guard",
		"renumber-step-one",
		"publish-state-to-main",
		"check-isolation",
		"board-opens-by-default",
		"setup-whole-run",
		"ready-raft",
		"guard-follow-ups",
		"compact-ids",
		"board-graphs",
		"suite-split",
		"lifecycle-spend",
		"board-raft-issue-views",
		"linux-spec-jail",
		"skill-lessons",
		"z-nile",
	},
}
-- the game: every feature and defect, and the chores that change only the game, its places, its specs, its test
-- helpers (sim, place) or its Roblox publishing; R0001 Foundation (c0001 tooling, c0002 game) stays with its game member
local PICKMAN: { [string]: { string } } = {
	issue = {
		"headless-place-tests",
		"open-cloud-runtime-tests",
		"game-sim-harness",
		"beta-deploy-on-ready",
		"game-alias-requires",
		"beta-poll-transient-errors",
		"acceptance-spec-typing",
		"narrow-play-again-specs",
		"publish-lobby-place",
		"narrow-key-map",
		"radar-jump-button",
		"minimap-clear-of-chat",
		"maze-model",
		"rail-movement",
		"game-session-server",
		"first-person-client",
		"pellets-and-score",
		"power-pellets",
		"lives-and-levels",
		"hud",
		"ghost-navigation",
		"ghost-mode-schedule",
		"ghost-house",
		"ghost-collisions",
		"hiscore-store",
		"hiscore-submit",
		"hiscore-board-ui",
		"touch-turn-controls",
		"touch-look",
		"mobile-hud-layout",
		"pellet-rendering",
		"game-flow",
		"ghost-rendering",
		"danger-awareness",
		"slow-game-speed",
		"game-place-teleport",
		"game-over-returns-to-lobby",
		"power-pellet-ghost-blaster",
		"explored-maze-minimap",
		"droppable-ghost-sensor",
		"new-key-controls",
		"frightened-colors",
		"touch-fire-and-hop",
	},
	raft = {
		"foundation",
		"sim-harness",
		"barebones-game",
		"game-alias-requires",
		"beta-deploy",
		"pellets-and-mechanics",
		"ghosts",
		"hiscores",
		"mobile-controls",
		"presentation",
		"slow-game-speed",
		"beta-poll-transient-errors",
		"game-place",
		"lobby-beta-publish",
		"narrow-play-again-specs",
		"game-over-to-lobby",
		"ghost-hunter-tools",
		"narrow-key-map",
		"radar-clear-of-chat",
		"radar-jump-button",
	},
}

-- every item of `kind` by slug, each slug seen once
local function bySlug(kind: string): { [string]: store.Item }
	local out: { [string]: store.Item } = {}
	for _, item in store.all(kind) do
		if out[item.slug] then
			error(`two {kind}s share the slug {item.slug}: {out[item.slug].id}, {item.id}`)
		end
		out[item.slug] = item
	end
	return out
end

local function filed(list: { [string]: { string } }, root: string): { string }
	local wrong: { string } = {}
	for kind, slugs in list do
		local items = bySlug(kind)
		for _, slug in slugs do
			local item = items[slug]
			if not item then
				table.insert(wrong, `{kind} {slug}: not found`)
			elseif item.root ~= root then
				table.insert(wrong, `{kind} {slug} ({item.id}): in {item.root}`)
			elseif root == "z-nile/.tracker" and store.typeOf(item) ~= "chore" then
				table.insert(wrong, `{kind} {slug} ({item.id}): a {store.typeOf(item)} in z-nile's root`)
			end
		end
	end
	table.sort(wrong)
	return wrong
end

return t.spec("c0114 every item is filed in its project", function(it)
	it("the tooling items are in z-nile/.tracker/, and each is a chore", function()
		t.expect(#ZNILE.issue).toBe(67)
		t.expect(#ZNILE.raft).toBe(21)
		t.expect(table.concat(filed(ZNILE, "z-nile/.tracker"), "\n")).toBe("")
	end)

	it("the game items are in tracker/", function()
		t.expect(#PICKMAN.issue).toBe(43)
		t.expect(#PICKMAN.raft).toBe(20)
		t.expect(table.concat(filed(PICKMAN, "tracker"), "\n")).toBe("")
	end)

	it("no feature or defect is filed in z-nile's root", function()
		for _, item in store.all("issue") do
			if item.root == "z-nile/.tracker" then
				t.expect(string.sub(item.id, 1, 1)).toBe("c")
			end
		end
	end)

	it("every unfinished item's check.sh still lists its checks through the forwarders", function()
		local bad: { string } = {}
		local checked = 0
		for _, kind in { "issue", "raft" } do
			for _, item in store.all(kind) do
				local path = `{item.dir}/check.sh`
				if item.state ~= "done" and fs.isFile(path) then
					local r = process.exec("bash", { path }, { env = { AC_LIST = "1" } })
					local listed = r.ok
						and string.find(r.stdout, "criteria listed (none run)", 1, true) ~= nil
					local draft = string.find(r.stdout, "no acceptance checks defined", 1, true) ~= nil
					if listed then
						checked += 1
					elseif not draft then
						table.insert(bad, `{path}: {r.stderr}{r.stdout}`)
					end
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
		t.expect(checked >= 10).toBe(true)
	end)
end)
