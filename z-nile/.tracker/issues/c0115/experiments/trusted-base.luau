--!strict
-- c0115 (design review 011 F1): the one trusted base AC13 and AC14 judge the branch against, the same rule c0120
-- adopts for its AC18. Main's tip comes from the remote (`git ls-remote origin refs/heads/main`), never from the local
-- `refs/remotes/origin/main`, which one `git update-ref` forges. The base is `git merge-base HEAD <tip>`; the range
-- is empty when that is HEAD (the branch landed, or this is main). Red, naming why: ls-remote fails or prints nothing
-- (offline, no origin, no main), the tip isn't a local commit ("fetch origin"), or there is no merge-base (a shallow
-- clone). What review must still catch: an origin URL swapped before the run.
--   lune run <c0115>/experiments/trusted-base -- --print [<dir>]   -- prints `<base> empty|range`, or exits 1
-- Required by rewrite-finished.luau as a module: `trustedBase.get(dir)`.
local process = require("@lune/process")

export type Base = { ok: boolean, base: string, empty: boolean, why: string }

local trustedBase = {}

local function git(dir: string, args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = dir })
	return r.ok, (string.gsub(r.stdout, "%s+$", ""))
end

function trustedBase.get(dir: string): Base
	local okR, remote = git(dir, { "ls-remote", "origin", "refs/heads/main" })
	local tip = string.match(remote, "^(%x+)%s+refs/heads/main$")
	if not okR or not tip then
		return {
			ok = false,
			base = "",
			empty = false,
			why = "can't read main's tip from origin (git ls-remote origin refs/heads/main): offline, or no origin or no main",
		}
	end
	if not git(dir, { "cat-file", "-e", tip .. "^{commit}" }) then
		return {
			ok = false,
			base = "",
			empty = false,
			why = `origin's main ({string.sub(tip, 1, 12)}) isn't a local commit: fetch origin`,
		}
	end
	local okM, mb = git(dir, { "merge-base", "HEAD", tip })
	if not okM or mb == "" then
		return {
			ok = false,
			base = "",
			empty = false,
			why = `no merge-base of HEAD and origin's main ({string.sub(tip, 1, 12)}): a shallow clone, or unrelated history`,
		}
	end
	local _, head = git(dir, { "rev-parse", "HEAD" })
	return { ok = true, base = mb, empty = mb == head, why = "" }
end

local printAt = table.find(process.args, "--print")
if printAt then
	local b = trustedBase.get(process.args[printAt + 1] or ".")
	if not b.ok then
		print(`trusted-base: {b.why}`)
		process.exit(1)
	end
	print(`{b.base} {if b.empty then "empty" else "range"}`)
end

return trustedBase
