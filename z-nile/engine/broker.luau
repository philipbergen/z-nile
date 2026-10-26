--!strict
-- The publish broker (c0117): a dispatched agent's credential can't push to `main`, so the tracker's own pushes of
-- tracker state (`publish`'s push, `land`) from inside a step are handed to the dispatcher that runs the step, which
-- pushes them with the user's credential after checking them. A request is a file in that dispatcher's own broker
-- folder (`ZN_PUBLISH_BROKER`), bound to it by its run token (`ZN_PUBLISH_TOKEN`); the answer is a file beside it.
-- The push is a fast-forward of a freshly fetched `main` only (never forced), and only of tracker state as
-- trackerstate.luau defines it, commit by commit (design review 002 F1 to F3, F7; 003 F1, F3, F10). Like every guard
-- here it detects honest mistakes and casual misbehaviour, not a determined agent of the same OS user.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local trackerstate = require("./trackerstate")

local broker = {}

-- how long a client waits for its answer: the dispatcher may be fetching for its tripwire when the request lands
broker.WAIT_SECONDS = 600
-- the ref the dispatcher fetches `main` into: its own, never the tracking ref an agent can rewrite
broker.FRESH = "refs/zn-dispatch/main"

local function uuid(): string
	return string.lower((string.gsub(process.exec("uuidgen", {}).stdout, "%s+", "")))
end

-- Client side: asks the dispatcher to put `sha` on main. Waits for its answer.
function broker.request(dir: string, token: string, sha: string, base: string?): (boolean, string)
	fs.writeDir(dir)
	local stem = `{dir}/{uuid()}`
	fs.writeFile(`{stem}.tmp`, serde.encode("json", { token = token, sha = sha, base = base or "" }))
	fs.move(`{stem}.tmp`, `{stem}.req`)
	local waited = 0
	while waited < broker.WAIT_SECONDS do
		if fs.isFile(`{stem}.res`) then
			local ok, res = pcall(function()
				return serde.decode("json", fs.readFile(`{stem}.res`))
			end)
			pcall(fs.removeFile, `{stem}.res`)
			if ok and type(res) == "table" then
				return res.ok == true, tostring(res.message or "")
			end
			return false, "the broker's answer does not parse"
		end
		waited += task.wait(0.1)
	end
	return false, `no answer from the dispatcher's publish broker in {broker.WAIT_SECONDS} s`
end

-- Server side: claims every request in `dir` (a rename, which only one server wins) and answers it with `push`;
-- a request without this run's `token` is refused. Never raises: a failure is an answer, never a dead dispatcher.
function broker.serve(dir: string, token: string, push: (sha: string) -> (boolean, string))
	pcall(function()
		if not fs.isDir(dir) then
			return
		end
		for _, name in fs.readDir(dir) do
			if string.match(name, "%.req$") then
				local stem = `{dir}/{string.sub(name, 1, -5)}`
				local claimed = pcall(fs.move, `{stem}.req`, `{stem}.taken`)
				if claimed then
					local good, message = false, "the request does not parse"
					local ok, req = pcall(function()
						return serde.decode("json", fs.readFile(`{stem}.taken`))
					end)
					if ok and type(req) == "table" then
						if req.token ~= token then
							good, message =
								false, "the request is not this dispatcher's (its run token differs)"
						elseif type(req.sha) == "string" and string.match(req.sha, "^%x+$") then
							local pok, a, b = pcall(push, req.sha)
							if pok then
								good, message = a, b
							else
								good, message = false, `the broker failed: {tostring(a)}`
							end
						end
					end
					pcall(fs.removeFile, `{stem}.taken`)
					pcall(function()
						fs.writeFile(`{stem}.rtmp`, serde.encode("json", { ok = good, message = message }))
						fs.move(`{stem}.rtmp`, `{stem}.res`)
					end)
				end
			end
		end
	end)
end

-- The URLs a run pinned at its start (review 003 F3): every fetch and push names them, never `origin` as the shared
-- configuration resolves it later.
export type Origin = { fetch: string, push: string }

-- The push itself, in the repository `root`: fetch `main` fresh from the pinned URL, refuse anything but a fast-forward
-- of it, refuse a history the watermark would refuse (each first-parent commit judged against its parent, by its
-- parent's registry, sequestered: review 003 F10), then a plain push to the pinned push URL (never forced: a `main` that
-- moved since the fetch refuses it, and the client rebuilds on it and asks again). `roots` reads the registry's roots at
-- a ref.
function broker.push(
	root: string,
	sha: string,
	roots: (ref: string) -> { string }?,
	origin: Origin?,
	ref: string? -- the run's own fetch ref (review 005 F1); a spec's single broker may use the default
): (boolean, string)
	local function git(args: { string }): (boolean, string)
		local r = process.exec("git", args, { cwd = root })
		return r.ok, (string.gsub(r.stdout, "%s+$", ""))
	end
	local from = if origin then origin.fetch else "origin"
	local to = if origin then origin.push else "origin"
	local into = ref or broker.FRESH
	local fetched = false
	for attempt = 1, 4 do
		if git({ "fetch", "-q", from, `+refs/heads/main:{into}` }) then
			fetched = true
			break
		end
		task.wait(0.2 * attempt)
	end
	if not fetched then
		return false, "the dispatcher could not fetch origin's main (after retries: the network?)"
	end
	local _, fresh = git({ "rev-parse", into })
	if not process.exec("git", { "merge-base", "--is-ancestor", fresh, sha }, { cwd = root }).ok then
		return false, `{sha} is not a fast-forward of main ({fresh}): rebuild it on main and ask again`
	end
	local why = trackerstate.checkEach(git, fresh, sha, roots, true)
	if why then
		return false,
			`the dispatcher pushes only tracker state to main, commit by commit (squash it and ask again): {why}`
	end
	local r = process.exec("git", { "push", "-q", to, `{sha}:refs/heads/main` }, { cwd = root })
	if r.ok then
		return true, "pushed"
	end
	return false, (string.gsub(r.stderr, "%s+$", ""))
end

return broker
