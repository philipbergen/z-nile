--!strict
-- c0114 AC14: the one rewrite finished items' check.sh files get (decided with the user, 2026-10-21: "Rewrite
-- finished files"). It is the user's exception to "sequestered files never change", for finished items only, in
-- c0114's PR: each moved path becomes its new location, and nothing else changes, apart from the few edits SPECIAL
-- lists, where a finished check reads a folder whose items now sit in two roots. Unfinished items' files never
-- change. Used by finished.spec.luau (no old path is left) and finished.luau (each file is its base text, rewritten).
local rewrites = {}

-- a path character: a token that follows one is part of a longer path, never the moved one
local function pathChar(c: string): boolean
	return string.match(c, "[%w_%.%-]") ~= nil
end

-- Every occurrence of `old` that does not follow a path character, replaced with new(prev) (prev: the character
-- before it, "" at the start).
local function replace(
	text: string,
	old: string,
	new: (prev: string) -> string,
	skip: ((before: string) -> boolean)?
): string
	local out: { string } = {}
	local i = 1
	while true do
		local s, e = string.find(text, old, i, true)
		if not s then
			table.insert(out, string.sub(text, i))
			return table.concat(out)
		end
		local prev = if s > 1 then string.sub(text, s - 1, s - 1) else ""
		table.insert(out, string.sub(text, i, s - 1))
		if pathChar(prev) or (skip and skip(string.sub(text, 1, s - 1))) then
			table.insert(out, old)
		else
			table.insert(out, new(prev))
		end
		i = (e :: number) + 1
	end
end

local function to(new: string): (string) -> string
	return function()
		return new
	end
end

-- the build's moved paths (c0114 §1); scripts/tracker.sh and bare tracker.sh are the command, ./zn (<dir>/zn
-- after a slash)
rewrites.SCRIPTS = {
	{ "scripts/tracker/", "z-nile/engine/" },
	{ "scripts/lib/ac.sh", "z-nile/lib/ac.sh" },
	{ "scripts/lib/fence.sh", "z-nile/lib/fence.sh" },
	{ "scripts/lib/par.sh", "z-nile/lib/par.sh" },
	{ "scripts/lib/replace-file.pl", "z-nile/lib/replace-file.pl" },
	{ "scripts/lib/git-hooks", "z-nile/lib/git-hooks" },
	{ "scripts/lib/sh.luau", "z-nile/lib/sh.luau" },
	{ "scripts/lib/graph.luau", "z-nile/lib/graph.luau" },
	{ "scripts/lib/changed.luau", "z-nile/lib/changed.luau" },
	{ "scripts/check.sh", "z-nile/check.sh" },
	{ "scripts/setup.sh", "z-nile/setup.sh" },
	{ "scripts/ci-verify.sh", "z-nile/ci-verify.sh" },
	{ "scripts/affected", "z-nile/affected" },
	{ "scripts/vendor", "z-nile/vendor" },
}
rewrites.TRACKER = {
	{ "tracker/templates", "z-nile/templates" },
	{ "tracker/compaction.txt", "z-nile/compaction.txt" },
}

-- `.claude/skills/tracker/...` is a skill, not the tracker's folder
local function inSkills(before: string): boolean
	return string.sub(before, -7) == "skills/"
end

-- `text` with every moved path rewritten. `moved`: the ids whose folders moved into z-nile/.tracker/; their item
-- paths (`tracker/issues/[active/|done/]<id>`, and rafts alike) move with them.
function rewrites.paths(text: string, moved: { [string]: boolean }): string
	text = replace(text, "scripts/tracker.sh", function(prev)
		return if prev == "/" then "zn" else "./zn"
	end)
	-- the command as a regular expression greps for it in a skill: `zn` matches `./zn`
	text = replace(text, "scripts/tracker\\.sh", to("zn"))
	text = replace(text, "tracker\\.sh", function(prev)
		return if prev == "/" then "tracker\\.sh" else "zn"
	end)
	-- the bare command name, as skills and messages wrote it
	text = replace(text, "tracker.sh", function(prev)
		return if prev == "/" then "tracker.sh" else "./zn"
	end)
	for _, r in rewrites.SCRIPTS do
		text = replace(text, r[1], to(r[2]))
	end
	for _, r in rewrites.TRACKER do
		text = replace(text, r[1], to(r[2]), inSkills)
	end
	for _, kind in { "issues", "rafts" } do
		local old = `tracker/{kind}/`
		local out: { string } = {}
		local i = 1
		while true do
			local s, e = string.find(text, old, i, true)
			if not s then
				table.insert(out, string.sub(text, i))
				break
			end
			table.insert(out, string.sub(text, i, s - 1))
			local prev = if s > 1 then string.sub(text, s - 1, s - 1) else ""
			local rest = string.sub(text, (e :: number) + 1)
			local id = string.match(rest, "^([fdcR]%d%d%d%d)")
				or string.match(rest, "^active/([fdcR]%d%d%d%d)")
				or string.match(rest, "^done/([fdcR]%d%d%d%d)")
			if id and moved[id] and not pathChar(prev) and not inSkills(string.sub(text, 1, s - 1)) then
				table.insert(out, "z-nile/." .. old)
			else
				table.insert(out, old)
			end
			i = (e :: number) + 1
		end
		text = table.concat(out)
	end
	return text
end

-- Keyed by the finished check.sh's path (a compaction rewrites paths in tests/, never bare ids). Finished checks whose
-- meaning needs more than a path: a folder that held every item and now has two roots, a copy
-- of the runner's guards, a gate stage or spec case renamed with the move, and three spec case names the rewrite would
-- otherwise change, and c0069's comparison with a spec c0114 overrides. Literal { old, new } edits applied after `paths`,
-- in order.
rewrites.SPECIAL = {
	-- greps for a promoted spec's case name, which keeps its words: the rewrite left them as they are
	["z-nile/.tracker/issues/done/c0007/check.sh"] = {
		{ "z-nile/affected takes its changed files", "scripts/affected takes its changed files" },
	},
	["z-nile/.tracker/issues/done/c0034/check.sh"] = {
		{ "./zn check and done refuse to run", "tracker.sh check and done refuse to run" },
	},
	["z-nile/.tracker/issues/done/c0045/check.sh"] = {
		{ '"./zn commit refuses', '"tracker.sh commit refuses' },
	},
	-- the gate's moved stage names and spec cases (c0114 renamed them with the move)
	["z-nile/.tracker/issues/done/c0049/check.sh"] = {
		{ "tests \\+ scripts with Lune definitions", "tests \\+ scripts \\+ z-nile with Lune definitions" },
	},
	["z-nile/.tracker/issues/done/c0077/check.sh"] = {
		{
			'"every .cache line in scripts/ is on the reviewed list"',
			'"every .cache line in scripts/ and z-nile/ is on the reviewed list"',
		},
	},
	-- copies of the runner and its guards: the guards now live in z-nile/lib/
	["z-nile/.tracker/issues/done/c0058/check.sh"] = {
		{ 'mkdir -p "$copy/scripts/lib"', 'mkdir -p "$copy/z-nile/lib"' },
		{ '"$copy/scripts/lib/"', '"$copy/z-nile/lib/"' },
	},
	["z-nile/.tracker/issues/done/c0076/check.sh"] = {
		{
			"tests/run.luau tests/lib scripts/lib .luaurc",
			"tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc",
		},
		{
			"tests/run.luau tests/lib scripts/lib .luaurc",
			"tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc",
		},
	},
	-- every item folder, in both roots
	["z-nile/.tracker/issues/done/c0044/check.sh"] = {
		{ 'find tracker -name "[fdcR]', 'find tracker z-nile/.tracker -name "[fdcR]' },
		{
			"find tracker/issues tracker/rafts -maxdepth",
			"find tracker/issues tracker/rafts z-nile/.tracker/issues z-nile/.tracker/rafts -maxdepth",
		},
	},
	-- five done tooling items, by brace list
	["z-nile/.tracker/issues/done/c0067/check.sh"] = {
		{ "tracker/issues/done/{c0005,", "z-nile/.tracker/issues/done/{c0005," },
	},
	-- every finished check.sh, in both roots
	["z-nile/.tracker/rafts/done/R0013/check.sh"] = {
		{
			"for f in tracker/issues/done/*/check.sh tracker/rafts/done/*/check.sh; do",
			"for f in {tracker,z-nile/.tracker}/{issues,rafts}/done/*/check.sh; do",
		},
	},
	-- its members, tooling items, by variable
	["z-nile/.tracker/rafts/done/R0025/check.sh"] = {
		{
			'bash "tracker/issues/done/$id/check.sh" >/dev/null',
			'bash "z-nile/.tracker/issues/done/$id/check.sh" >/dev/null',
		},
		{
			'bash "tracker/issues/done/$id/check.sh" | grep',
			'bash "z-nile/.tracker/issues/done/$id/check.sh" | grep',
		},
	},
	-- c0114 overrides the c0005 spec (G3: its captures name --project pickman), so c0053's copy of it, kept as c0053's
	-- record, no longer matches it: the check asks only that the copy is still there (decided with the user,
	-- 2026-10-21: "Fix it in the rewrite")
	["z-nile/.tracker/issues/done/c0069/check.sh"] = {
		{
			'cmp -s z-nile/.tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau tests/acceptance/c0005/worktree.spec.luau || { echo "c0053 replacement differs from the c0005 spec"; exit 1; }',
			'test -f z-nile/.tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau || { echo "c0053 replacement copy is missing"; exit 1; }',
		},
	},
} :: { [string]: { { string } } }

-- The finished items' check.sh files this rewrite covers: the ones finished when c0114 lands (decided with the user,
-- 2026-10-21: "Only items done at landing"), at their new paths. A fixed list, never the live set of done/ folders: an
-- item finished later keeps its old paths, which work through the forwarders until the raft that removes them, so its
-- `done` never turns this spec red. Implementation step 9 adds nothing here: an item that finishes on main inside the
-- window is rewritten by step 9 and checked by finished.luau. Paths, so a compaction rewrites them with the items.
rewrites.FINISHED = {
	"tracker/issues/done/c0002/check.sh",
	"tracker/issues/done/c0003/check.sh",
	"tracker/issues/done/c0010/check.sh",
	"tracker/issues/done/c0015/check.sh",
	"tracker/issues/done/c0041/check.sh",
	"tracker/issues/done/c0051/check.sh",
	"tracker/issues/done/c0056/check.sh",
	"tracker/issues/done/c0063/check.sh",
	"tracker/issues/done/c0064/check.sh",
	"tracker/issues/done/c0103/check.sh",
	"tracker/issues/done/d0105/check.sh",
	"tracker/issues/done/f0011/check.sh",
	"tracker/issues/done/f0012/check.sh",
	"tracker/issues/done/f0013/check.sh",
	"tracker/issues/done/f0014/check.sh",
	"tracker/issues/done/f0016/check.sh",
	"tracker/issues/done/f0017/check.sh",
	"tracker/issues/done/f0018/check.sh",
	"tracker/issues/done/f0019/check.sh",
	"tracker/issues/done/f0020/check.sh",
	"tracker/issues/done/f0021/check.sh",
	"tracker/issues/done/f0022/check.sh",
	"tracker/issues/done/f0023/check.sh",
	"tracker/issues/done/f0024/check.sh",
	"tracker/issues/done/f0025/check.sh",
	"tracker/issues/done/f0026/check.sh",
	"tracker/issues/done/f0030/check.sh",
	"tracker/issues/done/f0031/check.sh",
	"tracker/issues/done/f0032/check.sh",
	"tracker/issues/done/f0033/check.sh",
	"tracker/issues/done/f0054/check.sh",
	"tracker/issues/done/f0061/check.sh",
	"tracker/rafts/done/R0001/check.sh",
	"tracker/rafts/done/R0003/check.sh",
	"tracker/rafts/done/R0004/check.sh",
	"tracker/rafts/done/R0005/check.sh",
	"tracker/rafts/done/R0008/check.sh",
	"tracker/rafts/done/R0009/check.sh",
	"tracker/rafts/done/R0010/check.sh",
	"tracker/rafts/done/R0011/check.sh",
	"tracker/rafts/done/R0015/check.sh",
	"tracker/rafts/done/R0017/check.sh",
	"tracker/rafts/done/R0018/check.sh",
	"tracker/rafts/done/R0024/check.sh",
	"tracker/rafts/done/R0032/check.sh",
	"tracker/rafts/done/R0033/check.sh",
	"tracker/rafts/done/R0036/check.sh",
	"tracker/rafts/done/R0037/check.sh",
	"z-nile/.tracker/issues/done/c0001/check.sh",
	"z-nile/.tracker/issues/done/c0004/check.sh",
	"z-nile/.tracker/issues/done/c0005/check.sh",
	"z-nile/.tracker/issues/done/c0006/check.sh",
	"z-nile/.tracker/issues/done/c0007/check.sh",
	"z-nile/.tracker/issues/done/c0008/check.sh",
	"z-nile/.tracker/issues/done/c0009/check.sh",
	"z-nile/.tracker/issues/done/c0034/check.sh",
	"z-nile/.tracker/issues/done/c0035/check.sh",
	"z-nile/.tracker/issues/done/c0036/check.sh",
	"z-nile/.tracker/issues/done/c0037/check.sh",
	"z-nile/.tracker/issues/done/c0038/check.sh",
	"z-nile/.tracker/issues/done/c0039/check.sh",
	"z-nile/.tracker/issues/done/c0040/check.sh",
	"z-nile/.tracker/issues/done/c0042/check.sh",
	"z-nile/.tracker/issues/done/c0043/check.sh",
	"z-nile/.tracker/issues/done/c0044/check.sh",
	"z-nile/.tracker/issues/done/c0045/check.sh",
	"z-nile/.tracker/issues/done/c0046/check.sh",
	"z-nile/.tracker/issues/done/c0047/check.sh",
	"z-nile/.tracker/issues/done/c0048/check.sh",
	"z-nile/.tracker/issues/done/c0049/check.sh",
	"z-nile/.tracker/issues/done/c0050/check.sh",
	"z-nile/.tracker/issues/done/c0052/check.sh",
	"z-nile/.tracker/issues/done/c0053/check.sh",
	"z-nile/.tracker/issues/done/c0055/check.sh",
	"z-nile/.tracker/issues/done/c0057/check.sh",
	"z-nile/.tracker/issues/done/c0058/check.sh",
	"z-nile/.tracker/issues/done/c0059/check.sh",
	"z-nile/.tracker/issues/done/c0060/check.sh",
	"z-nile/.tracker/issues/done/c0062/check.sh",
	"z-nile/.tracker/issues/done/c0066/check.sh",
	"z-nile/.tracker/issues/done/c0067/check.sh",
	"z-nile/.tracker/issues/done/c0068/check.sh",
	"z-nile/.tracker/issues/done/c0069/check.sh",
	"z-nile/.tracker/issues/done/c0070/check.sh",
	"z-nile/.tracker/issues/done/c0071/check.sh",
	"z-nile/.tracker/issues/done/c0072/check.sh",
	"z-nile/.tracker/issues/done/c0073/check.sh",
	"z-nile/.tracker/issues/done/c0074/check.sh",
	"z-nile/.tracker/issues/done/c0076/check.sh",
	"z-nile/.tracker/issues/done/c0077/check.sh",
	"z-nile/.tracker/issues/done/c0078/check.sh",
	"z-nile/.tracker/issues/done/c0079/check.sh",
	"z-nile/.tracker/issues/done/c0080/check.sh",
	"z-nile/.tracker/issues/done/c0081/check.sh",
	"z-nile/.tracker/issues/done/c0082/check.sh",
	"z-nile/.tracker/issues/done/c0084/check.sh",
	"z-nile/.tracker/issues/done/c0096/check.sh",
	"z-nile/.tracker/issues/done/c0097/check.sh",
	"z-nile/.tracker/issues/done/c0098/check.sh",
	"z-nile/.tracker/issues/done/c0099/check.sh",
	"z-nile/.tracker/issues/done/c0107/check.sh",
	"z-nile/.tracker/issues/done/c0108/check.sh",
	"z-nile/.tracker/issues/done/c0111/check.sh",
	"z-nile/.tracker/issues/done/c0119/check.sh",
	"z-nile/.tracker/rafts/done/R0002/check.sh",
	"z-nile/.tracker/rafts/done/R0006/check.sh",
	"z-nile/.tracker/rafts/done/R0007/check.sh",
	"z-nile/.tracker/rafts/done/R0013/check.sh",
	"z-nile/.tracker/rafts/done/R0014/check.sh",
	"z-nile/.tracker/rafts/done/R0016/check.sh",
	"z-nile/.tracker/rafts/done/R0019/check.sh",
	"z-nile/.tracker/rafts/done/R0020/check.sh",
	"z-nile/.tracker/rafts/done/R0021/check.sh",
	"z-nile/.tracker/rafts/done/R0022/check.sh",
	"z-nile/.tracker/rafts/done/R0023/check.sh",
	"z-nile/.tracker/rafts/done/R0025/check.sh",
	"z-nile/.tracker/rafts/done/R0026/check.sh",
	"z-nile/.tracker/rafts/done/R0027/check.sh",
	"z-nile/.tracker/rafts/done/R0028/check.sh",
	"z-nile/.tracker/rafts/done/R0031/check.sh",
	"z-nile/.tracker/rafts/done/R0038/check.sh",
	"z-nile/.tracker/rafts/done/R0042/check.sh",
}

-- What a finished item's file at `path` (its new location) must be: its base text, paths rewritten, then its special
-- edits.
function rewrites.expected(path: string, base: string, moved: { [string]: boolean }): string
	local text = rewrites.paths(base, moved)
	local edits: { { string } } = rewrites.SPECIAL[path] or {}
	for _, edit in edits do
		local s, e = string.find(text, edit[1], 1, true)
		if not s then
			error(`rewrites: {path}: {edit[1]} not found`, 0)
		end
		text = string.sub(text, 1, s - 1) .. edit[2] .. string.sub(text, (e :: number) + 1)
	end
	return text
end

return rewrites
