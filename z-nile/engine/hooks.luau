--!strict
-- The repository hook that refuses commits under a fixture identity (c0189). `z-nile/lib/repo-hooks/reference-transaction`
-- is its source; `./zn hooks` installs it as <git common dir>/hooks/reference-transaction, and `./zn hooks --check`
-- (the gate's static stage) reports what is wrong with the installed copy. The installed file is one file every worktree
-- shares, so the text it is judged against and installed from is one reference for all of them: `origin/main`'s copy of
-- the source, never the working tree of the checkout that happens to run the command (a branch's unmerged edit, or an
-- older branch, would turn the other checkouts' gates red and could install an unreviewed hook for every session). A
-- repository with no `origin/main` ref (a clone made for the final check) has nothing else, so it uses its own tree's
-- copy. `plan` is pure: main.luau reads the state (the reference text, what is installed, the git configuration) and
-- writes the one file the plan allows.
local hooks = {}

hooks.NAME = "reference-transaction"
hooks.SOURCE = "z-nile/lib/repo-hooks/reference-transaction"
-- The line that makes a hook this tool's own: `./zn hooks` replaces a file only when it carries it.
hooks.MARKER = "# pickman-repo-hook: reference-transaction"
-- The git setting that moves the hooks folder. Spelled here, in the one pure module, so that only this file needs the
-- fence scan's allowance for the name (repo-fence.spec); main.luau passes the constant to git.
hooks.CONFIG_KEY = "core.hooksPath"

-- What is at the hook's place: nothing, a regular file, a symbolic link, or anything else (a folder, a special file).
export type Kind = "absent" | "file" | "link" | "other"
-- A hooks folder git is configured to read instead of the repository's: where the setting is and its value.
export type Redirect = { scope: string, path: string }
-- Where the reference text came from: `origin/main`'s copy of the source, or the checkout's own tree (no origin/main).
export type From = "origin/main" | "tree"
export type State = {
	dest: string, -- <git common dir>/hooks/reference-transaction
	from: From,
	source: string?, -- the reference hook text; nil when `from` has none
	kind: Kind,
	installed: string?, -- the text at dest, for a regular file
	executable: boolean, -- for a regular file
	reviewed: boolean, -- the installed text is a copy origin/main's history of the source has held (an older, reviewed one)
	redirects: { Redirect },
}
-- `none`: origin/main has no hook yet (before the change that adds it lands), so there is nothing to judge or install.
-- `older`: the one thing to do is to update an older reviewed copy, which `--check` accepts with a note and the command updates.
export type Plan = { action: "ok" | "install" | "refuse" | "none", problems: { string }, older: boolean? }

-- Whether `text` is a hook this tool wrote: a line that is exactly the marker.
function hooks.isOurs(text: string): boolean
	for line in string.gmatch(text, "[^\n]+") do
		if line == hooks.MARKER then
			return true
		end
	end
	return false
end

-- What to do about `state`, and what is wrong. Pure. Problems that only a person can clear make the action `refuse`
-- (nothing is written, in either mode); a missing, stale or non-executable copy of our own file is `install`; an exact,
-- executable copy is `ok` with no problems; origin/main having no hook is `none`. Every other state refuses (a guard acts
-- on its one explicit "ok").
function hooks.plan(s: State): Plan
	local label = if s.from == "origin/main"
		then `origin/main's {hooks.SOURCE}`
		else `this tree's {hooks.SOURCE}`
	if s.source == nil and s.from == "origin/main" then
		return {
			action = "none",
			problems = {
				`hooks: origin/main has no {hooks.SOURCE} yet, so there is nothing to install or check`,
			},
		}
	end
	local problems: { string } = {}
	local refuse = false
	local older = false
	if s.source == nil or not hooks.isOurs(s.source) then
		table.insert(
			problems,
			`hooks: {label} is missing or has no "{hooks.MARKER}" line, so there is nothing to install`
		)
		refuse = true
	end
	for _, r in s.redirects do
		table.insert(
			problems,
			`hooks: git reads hooks from {r.path} ({r.scope} configuration), so {s.dest} would never run; remove that setting from your {r.scope} git configuration, or set it to this repository's own hooks folder`
		)
		refuse = true
	end
	if s.kind == "link" then
		table.insert(
			problems,
			`hooks: {s.dest} is a symbolic link; ./zn hooks replaces only its own regular file: remove the link, then run ./zn hooks`
		)
		refuse = true
	elseif s.kind == "other" then
		table.insert(
			problems,
			`hooks: {s.dest} is not a regular file; ./zn hooks replaces only its own regular file: move it aside, then run ./zn hooks`
		)
		refuse = true
	elseif s.kind == "absent" then
		table.insert(problems, `hooks: {s.dest} is missing; run ./zn hooks`)
	elseif s.installed == nil or not hooks.isOurs(s.installed) then
		table.insert(
			problems,
			`hooks: {s.dest} is a hook ./zn hooks does not recognise (no "{hooks.MARKER}" line); it never overwrites one: move it aside, then run ./zn hooks`
		)
		refuse = true
	elseif s.installed ~= s.source then
		if s.reviewed and s.executable then
			older = true
			table.insert(
				problems,
				`hooks: {s.dest} is an older reviewed copy of {label}; run ./zn hooks to update`
			)
		else
			table.insert(problems, `hooks: {s.dest} differs from {label}; run ./zn hooks`)
		end
	elseif not s.executable then
		table.insert(problems, `hooks: {s.dest} is not executable, so git skips it; run ./zn hooks`)
	end
	if refuse then
		return { action = "refuse", problems = problems }
	end
	return {
		action = if #problems == 0 then "ok" else "install",
		problems = problems,
		older = older and #problems == 1,
	}
end

-- The blob ids a `git log --first-parent --format= --raw --no-abbrev <ref> -- <source>` output names as the source's text after a
-- commit (`:<mode> <mode> <old> <new> <status><TAB><path>` lines): every text origin/main's first-parent history (the texts main itself held; not the work-in-progress commits of a merged branch) has held. A deletion's zero
-- name is left out.
function hooks.blobIds(raw: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for line in string.gmatch(raw, "[^\n]+") do
		local new = string.match(line, "^:%d+ %d+ %x+ (%x+) ")
		if new and not string.match(new, "^0+$") then
			out[new] = true
		end
	end
	return out
end

-- The redirect git really follows, from `git config --show-scope --get-all <CONFIG_KEY>`: one "<scope><TAB><value>"
-- line per value, in the order git reads them, the last one winning. The `command` scope (what the fence passes through
-- the environment) is not the person's configuration and is left out. None when the winning value names the
-- repository's own hooks folder, or when nothing is set; so a global value that a local one sets back to the own folder
-- is no redirect.
function hooks.redirects(listed: string, own: string): { Redirect }
	local winner: Redirect? = nil
	for line in string.gmatch(listed, "[^\n]+") do
		local scope, path = string.match(line, "^([^\t]+)\t(.*)$")
		if scope and path and scope ~= "command" then
			winner = { scope = scope, path = path }
		end
	end
	if winner and winner.path ~= own then
		return { winner }
	end
	return {}
end

return hooks
