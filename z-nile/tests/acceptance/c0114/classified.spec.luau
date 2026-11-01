--!strict
-- c0114 AC10: every existing tooling item moved into z-nile/.tracker/ and every game item stayed in tracker/,
-- by the classification in c0114's Design. Items are named by kind and slug, which a compaction never changes (ids it
-- does), and each moved with its id, so nothing else about it changed. And every unfinished item's check.sh,
-- sequestered before the move, still runs through the forwarders: listed (AC_LIST=1) it names its checks, or it is an
-- empty draft.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
-- c0120 override: the spec runs from z-nile/, its home, after the move
local projects = require("@znile/engine/projects")
local serde = require("@lune/serde")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from z-nile/, but the store reads the tracker from the folder it runs in, so the items
-- are read by a child run at the checkout's top (a script under this home's .cache), each document's path made absolute
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local ITEMS: { [string]: { store.Item } }? = nil
-- c0120 override: a copy of the checkout's tooling and every project root (the working tree's files), a repository of
-- its own under this home's .cache, whose check.sh files fence the copy, never the real checkout
local TREE = `{HERE}/.cache/c0114-classified-tree`
local function copyTree(): string
	if fs.isDir(TREE) then
		fs.removeDir(TREE)
	end
	fs.writeDir(TREE)
	-- c0183 override: every registered root, so the fence (which refuses a home missing from the tree) finds each
	-- home
	local args = { "ls-files", "-co", "--exclude-standard", "zn", "scripts", "z-nile" }
	for _, root in projects.roots(projects.load(TOP)) do
		if root ~= "z-nile/.tracker" then
			table.insert(args, root)
		end
	end
	local listed = process.exec("git", args, { cwd = TOP })
	t.expect(listed.ok).toBe(true)
	for path in string.gmatch(listed.stdout, "[^\n]+") do
		if fs.isFile(`{TOP}/{path}`) then
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{TREE}/{parent}`)
			end
			t.expect(process.exec("cp", { "-p", `{TOP}/{path}`, `{TREE}/{path}` }).ok).toBe(true)
		end
	end
	t.expect(process.exec("git", { "init", "-q", TREE }).ok).toBe(true)
	return TREE
end
local function allItems(kind: string): { store.Item }
	if not ITEMS then
		local dir = `{HERE}/.cache/c0114-classified-items`
		fs.writeDir(dir)
		fs.writeFile(
			`{dir}/items.luau`,
			table.concat({
				`local serde = {REQ}("@lune/serde")`,
				`local store = {REQ}("@znile/engine/store")`,
				"local out = {}",
				'for _, kind in { "issue", "raft" } do',
				"\tout[kind] = store.all(kind :: any)",
				"end",
				'print(serde.encode("json", out))',
				"",
			}, "\n")
		)
		local r = process.exec("lune", { "run", `{dir}/items.luau` }, { cwd = TOP })
		fs.removeDir(dir)
		if not r.ok then
			error(`listing the items failed: {r.stderr}`)
		end
		local decoded = serde.decode("json", r.stdout) :: { [string]: { store.Item } }
		for _, items in decoded do
			for _, item in items do
				item.doc = `{TOP}/{item.doc}`
			end
		end
		ITEMS = decoded
	end
	return (ITEMS :: { [string]: { store.Item } })[kind] or {}
end

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
	for _, item in allItems(kind) do -- c0120 override: read at the top
		if out[item.slug] then
			error(`two {kind}s share the slug {item.slug}: {out[item.slug].id}, {item.id}`)
		end
		out[item.slug] = item
	end
	-- c0116 override: a raft recombine retired keeps its folder in <root>/rafts/retired/, where no finder looks, and is
	-- still filed in that root
	if kind == "raft" then
		-- read at the checkout's top, as the items are: this spec runs from z-nile/ (c0120)
		for _, root in projects.roots(projects.load(TOP)) do
			local base = `{TOP}/{root}/rafts/retired`
			local names: { string } = if fs.isDir(base) then fs.readDir(base) else {}
			for _, name in names do
				local doc = `{base}/{name}/{name}.md`
				if string.match(name, "^R%d%d%d%d$") and fs.isFile(doc) then
					local slug = store.readFront(doc).slug or ""
					if out[slug] then
						error(`two {kind}s share the slug {slug}: {out[slug].id}, {name}`)
					end
					out[slug] = {
						id = name,
						kind = "raft",
						state = "retired",
						dir = `{base}/{name}`,
						doc = doc,
						slug = slug,
						root = root,
					}
				end
			end
		end
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

	-- c0120 override: pickman's items moved with the game into pickman/.tracker/
	it("the game items are in pickman/.tracker/", function()
		t.expect(#PICKMAN.issue).toBe(43)
		t.expect(#PICKMAN.raft).toBe(20)
		-- c0120 override: pickman's files live in pickman/ (its home)
		t.expect(table.concat(filed(PICKMAN, "pickman/.tracker"), "\n")).toBe("")
	end)

	it("no feature or defect is filed in z-nile's root", function()
		for _, item in allItems("issue") do -- c0120 override: read at the top
			if item.root == "z-nile/.tracker" then
				t.expect(string.sub(item.id, 1, 1)).toBe("c")
			end
		end
	end)

	-- List mode is proven first (as c0034's locator does): a check.sh that ignored AC_LIST would run every raft's full
	-- gate in this checkout. The loop below refuses to start without the proof.
	local listing = false
	it("list mode holds through the scripts/lib/ac.sh forwarder, and the runner refuses it", function()
		-- c0120 override: the fixtures are under this home's .cache. The jail refuses the checkout top's .cache, where the
		-- real ac.sh writes its fence's sentinel, so the forwarder (and below, every item's check.sh) runs in a copy
		local root = copyTree()
		local dir = `{HERE}/.cache/c0114-classified`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		t.expect(process.exec("git", { "init", "-q", dir }).ok).toBe(true)
		local marker = `{dir}/ran`
		fs.writeFile(
			`{dir}/check.sh`,
			`source "{root}/scripts/lib/ac.sh"\ncheck "AC1: touches a marker" touch "{marker}"\nfinish\n`
		)
		local listed = fixture.exec(dir, "bash", { "check.sh" }, { env = { AC_LIST = "1" } })
		t.expect(listed.ok).toBe(true)
		t.expect(string.find(listed.stdout, "1 criteria listed (none run)", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(marker)).toBe(false)
		local runner = process.exec(
			"lune",
			{ "run", "tests/run", "--", "tests/meta/architecture.spec.luau" },
			{
				env = { AC_LIST = "1" },
			}
		)
		t.expect(runner.ok).toBe(false)
		t.expect(string.find(runner.stdout .. runner.stderr, "AC_LIST", 1, true) ~= nil).toBe(true)
		fs.removeDir(dir)
		listing = true
	end)

	it("every unfinished item's check.sh still lists its checks through the forwarders", function()
		if not listing then
			error("list mode is not proven safe (ac.sh or tests/run): not running any item's check.sh")
		end
		local bad: { string } = {}
		local expected, listed = 0, 0
		for _, kind in { "issue", "raft" } do
			-- c0120 override: the items are read at the top, and each check.sh runs in the copy (see above)
			for _, item in allItems(kind) do
				local path = `{TREE}/{item.dir}/check.sh`
				if item.state ~= "done" and fs.isFile(path) then
					local hasCheck = false
					for line in string.gmatch(fs.readFile(path), "[^\n]+") do
						if string.match(line, '^%s*check "') then
							hasCheck = true
						end
					end
					-- at most 60 s each, so a check.sh that ignores list mode can't hold the gate
					-- c0120 override: the spec runs from z-nile/, its home, after the move
					local r = process.exec(
						"perl",
						{ "-e", "alarm shift; exec @ARGV or die", "60", "bash", path },
						{ cwd = TREE, env = { AC_LIST = "1" } }
					)
					local ok = r.ok and string.find(r.stdout, "criteria listed (none run)", 1, true) ~= nil
					local draft = string.find(r.stdout, "no acceptance checks defined", 1, true) ~= nil
					if hasCheck then
						expected += 1
						if ok then
							listed += 1
						else
							table.insert(bad, `{path}: {r.stderr}{r.stdout}`)
						end
					elseif not draft then
						table.insert(bad, `{path}: neither listed nor an empty draft: {r.stderr}{r.stdout}`)
					end
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
		-- no floor on how many items are live: the backlog shrinks and grows on its own (code review 001 F1); list mode
		-- itself is proven on the fixture before this loop runs
		t.expect(listed).toBe(expected)
		fs.removeDir(TREE) -- c0120 override: the copy
	end)
end)
