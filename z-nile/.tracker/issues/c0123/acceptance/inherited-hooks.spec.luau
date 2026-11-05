--!strict
-- c0123 AC1: the fence trusts only the ref guard's own hooks. An inherited PICKMAN_FENCE_HOOKS is used only
-- when its files are exactly the guard's (z-nile/lib/fence.sh pins their SHA-256), whatever the caller exported; any
-- other value is ignored with a message, and a fence with no matching folder refuses. A nested copy of the fence that
-- lacks z-nile/lib/git-hooks keeps working through a genuine inherited value. The repository's own hook (the one in
-- its .git/hooks, such as c0189's) is no guard folder: it runs after the guard allows an update and can only refuse more.
-- Fixtures only, all under this home's .cache: `checkout` (a repository holding a copy of the tooling's z-nile/lib),
-- `bare` (one that holds fence.sh alone, a nested copy), `origin` for the fetch, and the folders the variants make.
-- Every fence call runs in a shell of its own with its markers set explicitly (no jail: the hooks must apply), and
-- git runs only inside the fixtures, as example.invalid.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the checkout's top, and this home's (z-nile/) own .cache, which holds the fixtures
local home = fixture.physical(".") :: string
local root = string.match(home, "^(.*)/[^/]+$") :: string
local base = `{home}/.cache/c0123-hooks`
local checkout = `{base}/checkout`
local bare = `{base}/bare`
local origin = `{base}/origin`
local permissive = `{base}/permissive`
local own = `{checkout}/z-nile/lib/git-hooks`

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function sh(cmd: string, dir: string?)
	local r = process.exec("bash", { "-c", cmd }, { cwd = dir })
	if not r.ok then
		error(`{cmd} failed: {r.stderr}{r.stdout}`)
	end
end

local function identity(dir: string, args: { string })
	local a = { "-c", "user.name=c0123", "-c", "user.email=dev@example.invalid" }
	for _, x in args do
		table.insert(a, x)
	end
	fixture.git(dir, a)
end

local ready = false
local function setUp()
	if ready then
		return
	end
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(`{checkout}/z-nile`)
	fs.writeDir(`{bare}/z-nile/lib`)
	fs.writeDir(origin)
	sh(`cp -R "{root}/z-nile/lib" "{checkout}/z-nile/lib" && chmod -R +x "{own}"`)
	sh(`cp "{root}/z-nile/lib/fence.sh" "{bare}/z-nile/lib/fence.sh"`)
	-- a folder of hooks that permit everything, as an attacker would export
	sh(`cp -R "{own}" "{permissive}"`)
	for _, hook in { "reference-transaction", "pre-push" } do
		fs.writeFile(`{permissive}/{hook}`, "#!/bin/sh\nexit 0\n")
		sh(`chmod +x "{permissive}/{hook}"`)
	end
	for _, dir in { checkout, bare, origin } do
		process.exec("git", { "init", "-q", "-b", "main", dir })
		fs.writeFile(`{dir}/README`, "c0123 fixture\n")
		fixture.git(dir, { "add", "-A" })
		identity(dir, { "commit", "-qm", "fixture" })
	end
	fixture.git(checkout, { "remote", "add", "origin", origin })
	ready = true
end

-- A copy of the guard's folder with one change made by `edit` (a shell command run inside the copy).
local function variant(name: string, edit: string): string
	setUp()
	local dir = `{base}/variant-{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	sh(`cp -R "{own}" "{dir}"`)
	sh(edit, dir)
	return dir
end

-- A repository of its own holding a copy of the tooling's z-nile/lib whose guard folder is changed by `edit` (a shell
-- command run inside that folder): a fence whose own folder is not the guard's.
local function fresh(name: string, edit: string): string
	setUp()
	local dir = `{base}/fresh-{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/z-nile`)
	sh(`cp -R "{checkout}/z-nile/lib" "{dir}/z-nile/lib"`)
	sh(edit, `{dir}/z-nile/lib/git-hooks`)
	process.exec("git", { "init", "-q", "-b", "main", dir })
	fs.writeFile(`{dir}/README`, "c0123 fixture\n")
	fixture.git(dir, { "add", "-A" })
	identity(dir, { "commit", "-qm", "fixture" })
	return dir
end

local WAIVER = { PICKMAN_TEST_JAIL = "sandbox-exec", PICKMAN_FENCE_SPECS = "1", PICKMAN_TEST_FENCE = home }

-- Fences `dir` as a check.sh flow does (`pickman_fence`; `twice` fences again inside the first fence, as a nested
-- fence does), with `inherited` as PICKMAN_FENCE_HOOKS (empty: none), then tries to write a ref in `dir`. Prints
-- FENCE-REFUSED, or the variable after the fence (HOOKS), whether the ref write was refused (GUARDED) or went through
-- (ESCAPED), and the variable as the caller left it (BEFORE) so a refused fence can be seen to leave it alone.
local function probe(
	dir: string,
	inherited: string,
	twice: boolean?,
	env: { [string]: string }?,
	jail: string?
): fixture.Result
	setUp()
	-- every marker the fence reads is set here, whatever the runner set for this host
	local e: { [string]: string } = {
		PICKMAN_TEST_JAIL = "none",
		PICKMAN_FENCE_SPECS = "1",
		PICKMAN_TEST_FENCE = home,
		PICKMAN_FENCE_HOOKS = inherited,
	}
	if env then
		for k, v in env do
			e[k] = v
		end
	end
	local script = table.concat({
		". z-nile/lib/fence.sh",
		'echo "BEFORE=[${PICKMAN_FENCE_HOOKS-unset}]"',
		(if jail then `pickman_fence "$PWD" specs {jail}` else 'pickman_fence "$PWD"')
			.. ' || { echo "FENCE-REFUSED"; echo "HOOKS=[${PICKMAN_FENCE_HOOKS-unset}]"; exit 0; }',
		twice and 'pickman_fence "$PWD" || { echo "FENCE-REFUSED-TWICE"; exit 0; }' or "",
		'echo "HOOKS=[${PICKMAN_FENCE_HOOKS-unset}]"',
		'echo "SSH=${GIT_SSH_COMMAND-unset} PROTO=${GIT_ALLOW_PROTOCOL-unset} PROMPT=${GIT_TERMINAL_PROMPT-unset}"',
		"if git update-ref refs/heads/c0123-escaped HEAD 2>/dev/null; then echo ESCAPED; else echo GUARDED; fi",
		"",
	}, "\n")
	local r = fixture.exec(dir, "bash", { "-c", script }, { env = e })
	if has(r.stdout, "ESCAPED") then
		pcall(fixture.git, dir, { "update-ref", "-d", "refs/heads/c0123-escaped" })
	end
	return r
end

local function guarded(r: fixture.Result): boolean
	return has(r.stdout, "GUARDED") and not has(r.stdout, "ESCAPED") and not has(r.stdout, "FENCE-REFUSED")
end

return t.spec("c0123 the fence trusts only its own ref guard hooks", function(it)
	it("a hook folder that is not the guard's is ignored, and the guard's own is used", function()
		local r = probe(checkout, permissive)
		t.expect(guarded(r)).toBe(true)
		t.expect(has(r.stdout, `HOOKS=[{own}]`)).toBe(true)
		t.expect(has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={permissive}`)).toBe(true)
		-- the message is for a bad value only: none, or the guard's own, says nothing
		for _, inherited in { "", own } do
			local quiet = probe(checkout, inherited)
			t.expect(guarded(quiet)).toBe(true)
			t.expect(has(quiet.stdout, `HOOKS=[{own}]`)).toBe(true)
			t.expect(has(quiet.stderr, "ignoring")).toBe(false)
		end
	end)

	it(
		"with no guard of its own to fall back on, a bad value refuses the fence and is left as it was",
		function()
			local r = probe(bare, permissive)
			t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(true)
			t.expect(has(r.stderr, "no ref guard")).toBe(true)
			-- a refused fence changes nothing (c0114): the inherited value is still the caller's
			t.expect(has(r.stdout, `BEFORE=[{permissive}]`)).toBe(true)
			t.expect(has(r.stdout, `HOOKS=[{permissive}]`)).toBe(true)
			t.expect(has(r.stdout, "ESCAPED")).toBe(false)
			-- and with nothing inherited either, there is nothing to trust
			local none = probe(bare, "")
			t.expect(has(none.stdout, "FENCE-REFUSED")).toBe(true)
			t.expect(has(none.stderr, "no ref guard")).toBe(true)
		end
	)

	it("under the jail's waiver a bad value is dropped, never exported or used", function()
		local r = probe(bare, permissive, false, WAIVER)
		t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(false)
		t.expect(has(r.stdout, "HOOKS=[unset]")).toBe(true)
		t.expect(has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={permissive}`)).toBe(true)
		-- and the guard's own folder, where there is one, is still used under the waiver
		local withHooks = probe(checkout, "", false, WAIVER)
		t.expect(has(withHooks.stdout, `HOOKS=[{own}]`)).toBe(true)
		t.expect(guarded(withHooks)).toBe(true)
	end)

	it("when the digest cannot be computed the fence refuses, and trusts nothing", function()
		setUp()
		-- a host without /usr/bin/perl (or without Digest::SHA) stands in: the fixture's copy of the fence points at a perl
		-- that does not exist, since the digest asks for the absolute program under an empty environment
		local fenceFile = `{checkout}/z-nile/lib/fence.sh`
		local text = fs.readFile(fenceFile)
		local patched = string.gsub(text, "/usr/bin/perl", "/nonexistent/perl")
		t.expect(patched ~= text).toBe(true)
		fs.writeFile(fenceFile, patched)
		local ok, err = pcall(function()
			for _, inherited in { "", own } do
				local r = probe(checkout, inherited, false)
				t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(true)
				t.expect(has(r.stderr, "no ref guard")).toBe(true)
				t.expect(has(r.stdout, "ESCAPED")).toBe(false)
			end
		end)
		fs.writeFile(fenceFile, text)
		if not ok then
			error(err, 0)
		end
	end)

	it("a folder that differs from the guard's in anything is rejected", function()
		setUp()
		-- the repository's own hooks folder is no guard folder, whatever it holds (c0189 installs a hook there)
		fs.writeFile(`{checkout}/.git/hooks/reference-transaction`, "#!/bin/sh\nexit 0\n")
		sh(`chmod +x "{checkout}/.git/hooks/reference-transaction"`)
		local cases: { [string]: string } = {
			["a guard hook changed"] = `printf '# x\\n' >> reference-transaction`,
			["the push guard changed"] = `printf '# x\\n' >> pre-push`,
			["another stub changed"] = `printf 'exit 1\\n' >> pre-commit`,
			["the helper changed"] = `printf '# x\\n' >> .repo.sh`,
			["a hook added"] = `cp pre-commit post-update`,
			["a hook removed"] = `rm commit-msg`,
			["a hook renamed"] = `mv commit-msg commit-msg2`,
			["a guard hook is a link"] = `cp reference-transaction ../real-rt && rm reference-transaction && ln -s ../real-rt reference-transaction`,
			["a folder inside"] = `mkdir sub`,
			["the guard hook is not executable"] = `chmod -x reference-transaction`,
			["the push guard is not executable"] = `chmod -x pre-push`,
		}
		local order = {}
		for name in cases do
			table.insert(order, name)
		end
		table.sort(order)
		for _, name in order do
			local dir = variant(string.gsub(name, "[^%w]+", "-") :: string, cases[name] :: string)
			local r = probe(bare, dir)
			if
				not has(r.stdout, "FENCE-REFUSED") or not has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={dir}`)
			then
				error(`{name}: the fence did not reject {dir}: {r.stdout}{r.stderr}`)
			end
		end
		local others: { [string]: string } = {
			["the repository's own hooks"] = `{checkout}/.git/hooks`,
			["an empty folder"] = permissive .. "-none",
			["a missing folder"] = `{base}/nowhere`,
		}
		for name, dir in others do
			if name == "an empty folder" then
				fs.writeDir(dir)
			end
			local r = probe(bare, dir)
			if
				not has(r.stdout, "FENCE-REFUSED") or not has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={dir}`)
			then
				error(`{name}: the fence did not reject {dir}: {r.stdout}{r.stderr}`)
			end
		end
	end)

	it("a nested copy that lacks z-nile/lib/git-hooks keeps the first guard's folder", function()
		local r = probe(bare, own)
		t.expect(guarded(r)).toBe(true)
		t.expect(has(r.stdout, `HOOKS=[{own}]`)).toBe(true)
		t.expect(has(r.stderr, "ignoring")).toBe(false)
		-- a fence inside that fence (the variable now exported by the first) keeps it too
		local nested = probe(bare, own, true)
		t.expect(guarded(nested)).toBe(true)
		t.expect(has(nested.stdout, "FENCE-REFUSED")).toBe(false)
		t.expect(has(nested.stdout, `HOOKS=[{own}]`)).toBe(true)
		-- the first guard's folder stays in force even where a copy of the fence has a genuine folder of its own
		local other = variant("genuine-copy", "true")
		local kept = probe(checkout, other)
		t.expect(guarded(kept)).toBe(true)
		t.expect(has(kept.stdout, `HOOKS=[{other}]`)).toBe(true)
		-- a link to the guard's folder resolves to the folder itself
		sh(`ln -sfn "{own}" "{base}/link-to-guard"`)
		local linked = probe(bare, `{base}/link-to-guard`)
		t.expect(guarded(linked)).toBe(true)
		t.expect(has(linked.stdout, `HOOKS=[{own}]`)).toBe(true)
	end)

	it(
		"the fence's own folder is used only when it is the guard's, and a refusal names what differs",
		function()
			local pin = string.match(
				fs.readFile(`{root}/z-nile/lib/fence.sh`),
				"_PICKMAN_FENCE_HOOKS_SHA256=(%x+)"
			) :: string
			-- edited bytes, an extra file (an editor backup or Finder's .DS_Store counts), a missing hook: nothing inherited
			local tampered: { [string]: { edit: string, says: string } } = {
				bytes = {
					edit = `printf '# x\\n' >> reference-transaction`,
					says = "a file differs in bytes",
				},
				extra = { edit = "touch .DS_Store", says = "unexpected .DS_Store" },
				missing = { edit = "rm commit-msg", says = "missing commit-msg" },
				copy = { edit = "touch 'pre-push copy'", says = "unexpected pre-push copy" },
				star = { edit = "touch '*'", says = "unexpected *)" },
			}
			local order = {}
			for name in tampered do
				table.insert(order, name)
			end
			table.sort(order)
			for _, name in order do
				local dir = fresh(name, tampered[name].edit)
				local r = probe(dir, "")
				if not has(r.stdout, "FENCE-REFUSED") or not has(r.stderr, "no ref guard") then
					error(`{name}: the fence trusted its own tampered folder: {r.stdout}{r.stderr}`)
				end
				if not has(r.stderr, tampered[name].says) then
					error(`{name}: the refusal does not say why ({tampered[name].says}): {r.stderr}`)
				end
				-- the diagnosis never prints the value that would make a fence pass
				t.expect(has(r.stdout .. r.stderr, pin)).toBe(false)
			end
			-- a genuine inherited folder serves a copy whose own folder is not the guard's
			local dir = fresh("tampered-with-inherited", "touch .DS_Store")
			local r = probe(dir, own)
			t.expect(guarded(r)).toBe(true)
			t.expect(has(r.stdout, `HOOKS=[{own}]`)).toBe(true)
		end
	)

	it("an exported shell function of the same name as perl cannot make a bad folder pass", function()
		-- a function that prints the guard's pin, exported to every child shell (the digest asks for perl by name)
		local pin = string.match(
			fs.readFile(`{root}/z-nile/lib/fence.sh`),
			"_PICKMAN_FENCE_HOOKS_SHA256=(%x+)"
		) :: string
		local r = probe(bare, permissive, false, { ["BASH_FUNC_perl%%"] = `() \{ echo {pin}; \}` })
		t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(true)
		t.expect(has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={permissive}`)).toBe(true)
		t.expect(has(r.stdout, "ESCAPED")).toBe(false)
	end)

	it("perl's own variables cannot decide the digest: PERL5LIB and PERL5OPT", function()
		setUp()
		local pin = string.match(
			fs.readFile(`{root}/z-nile/lib/fence.sh`),
			"_PICKMAN_FENCE_HOOKS_SHA256=(%x+)"
		) :: string
		-- a Digest::SHA that prints the guard's pin whatever it is given, found through PERL5LIB
		local lib = `{base}/fake-perl-lib`
		fs.writeDir(`{lib}/Digest`)
		fs.writeFile(
			`{lib}/Digest/SHA.pm`,
			`package Digest::SHA; sub new \{ bless \{\}, shift \} sub add \{ 1 \} sub hexdigest \{ "{pin}" \} 1;\n`
		)
		local r = probe(bare, permissive, false, { PERL5LIB = lib })
		t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(true)
		t.expect(has(r.stderr, `ignoring PICKMAN_FENCE_HOOKS={permissive}`)).toBe(true)
		t.expect(has(r.stdout, "ESCAPED")).toBe(false)
		-- a missing module forced in by PERL5OPT would make every digest fail: the guard's own folder is still recognised
		local opt = probe(checkout, "", false, { PERL5OPT = "-MNoSuchModuleC0123" })
		t.expect(has(opt.stdout, "FENCE-REFUSED")).toBe(false)
		t.expect(guarded(opt)).toBe(true)
	end)

	it("a CDPATH or GIT_EXEC_PATH in the environment cannot switch the guard off", function()
		setUp()
		-- fence level: both are removed from the environment, and a ref write is still refused
		local planted = `{base}/planted-exec`
		fs.writeDir(planted)
		fs.writeFile(`{planted}/cat`, "#!/bin/sh\nexit 0\n")
		sh(`chmod +x "{planted}/cat"`)
		local r = probe(checkout, "", false, {
			CDPATH = `.:{base}`,
			GIT_EXEC_PATH = `{planted}:{trim(process.exec("git", { "--exec-path" }).stdout)}`,
		})
		t.expect(guarded(r)).toBe(true)
		-- hook level, for a caller that sets them after the fence: the guard's own hook, run as git runs it (cwd the
		-- repository, `.git` found relative), refuses a branch write in the protected repository whatever CDPATH holds.
		-- Under the system sh (bash on macOS) and under dash, where there is one.
		local common = trim(
			process.exec(
				"git",
				{ "rev-parse", "--path-format=absolute", "--git-common-dir" },
				{ cwd = checkout }
			).stdout
		)
		local line = `{string.rep("0", 40)} {string.rep("1", 40)} refs/heads/c0123-cdpath\n`
		for _, shell in { "/bin/sh", "/bin/dash" } do
			if shell == "/bin/sh" or fs.isFile(shell) then
				local run = process.exec(shell, { `{own}/reference-transaction`, "prepared" }, {
					cwd = checkout,
					stdio = { stdin = line },
					env = { PICKMAN_FENCE_REAL_GIT = common, PICKMAN_FENCE_SPECS = "1", CDPATH = `.:{base}` },
				})
				if run.ok then
					error(`{shell}: the ref guard hook allowed a branch write with CDPATH set`)
				end
				t.expect(has(run.stderr, "refused")).toBe(true)
			end
		end
	end)

	it("an exported shell function cannot hijack the guard's hook: it starts as sh -p", function()
		setUp()
		local common = trim(
			process.exec(
				"git",
				{ "rev-parse", "--path-format=absolute", "--git-common-dir" },
				{ cwd = checkout }
			).stdout
		)
		-- the hook file itself is run, so its shebang decides; a function named pwd that lies about the repository
		-- would make the protected-repository match fail in a shell that imports it
		local run = process.exec(`{own}/reference-transaction`, { "prepared" }, {
			cwd = checkout,
			stdio = { stdin = `{string.rep("0", 40)} {string.rep("1", 40)} refs/heads/c0123-fn\n` },
			env = {
				PICKMAN_FENCE_REAL_GIT = common,
				PICKMAN_FENCE_SPECS = "1",
				["BASH_FUNC_pwd%%"] = "() { echo /nonexistent; }",
				["BASH_FUNC_cd%%"] = "() { builtin cd /; }",
			},
		})
		if run.ok then
			error("the ref guard hook allowed a branch write with exported functions set")
		end
		t.expect(has(run.stderr, "refused")).toBe(true)
		t.expect(string.split(fs.readFile(`{own}/reference-transaction`), "\n")[1]).toBe("#!/bin/sh -p")
	end)

	it("a check-mode fence drops the caller's ssh command, protocol list and prompt setting", function()
		-- a check's git uses the person's own ssh and protocols; the spec-mode fence sets its own
		local r = probe(checkout, "", false, {
			PICKMAN_FENCE_SPECS = "",
			GIT_SSH_COMMAND = "evil",
			GIT_ALLOW_PROTOCOL = "ssh",
			GIT_TERMINAL_PROMPT = "1",
		})
		t.expect(guarded(r)).toBe(true)
		t.expect(has(r.stdout, "SSH=unset PROTO=unset PROMPT=unset")).toBe(true)
		local specsMode = probe(checkout, "", false, { GIT_SSH_COMMAND = "evil" })
		t.expect(has(specsMode.stdout, "SSH=evil")).toBe(false)
	end)

	it("under the jail the fence neither reads nor changes the inherited folder", function()
		-- a genuine value stays as the caller had it (the kernel covers the repository; every fence that uses it verifies it)
		local r = probe(checkout, own, false, nil, "sandbox-exec")
		t.expect(has(r.stdout, "FENCE-REFUSED")).toBe(false)
		t.expect(has(r.stdout, `HOOKS=[{own}]`)).toBe(true)
		-- and a bad one too: nothing was examined, so nothing is dropped or said
		local bad = probe(checkout, permissive, false, nil, "sandbox-exec")
		t.expect(has(bad.stdout, `HOOKS=[{permissive}]`)).toBe(true)
		t.expect(has(bad.stderr, "ignoring")).toBe(false)
	end)

	it("the folder the fence uses is the folder it verified", function()
		-- a genuine inherited folder, and a shell function pwd that names the permissive folder: the path is resolved
		-- before it is checked, so the function can only make the check fail, never swap the folder after it
		local r = probe(checkout, own, false, { ["BASH_FUNC_pwd%%"] = `() \{ echo {permissive}; \}` })
		t.expect(has(r.stdout, "ESCAPED")).toBe(false)
		t.expect(has(r.stdout, `HOOKS=[{permissive}]`)).toBe(false)
	end)

	it("the digest frames every name and every file", function()
		setUp()
		-- without lengths, bytes can move between a name and the file before it: {a: "bc"} and {ab: "c"} must differ
		local function digestOf(name: string, files: { [string]: string }): string
			local dir = `{base}/frame-{name}`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			fs.writeDir(dir)
			for file, text in files do
				fs.writeFile(`{dir}/{file}`, text)
			end
			local r = process.exec(
				"bash",
				{ "-c", `. z-nile/lib/fence.sh; pickman_fence_hooks_digest "{dir}"` },
				{ cwd = checkout }
			)
			t.expect(r.ok).toBe(true)
			return r.stdout
		end
		local one = digestOf("one", { a = "bc" })
		local two = digestOf("two", { ab = "c" })
		t.expect(one ~= two).toBe(true)
		t.expect(one ~= "").toBe(true)
		-- and the same folder twice gives the same digest
		t.expect(digestOf("again", { a = "bc" })).toBe(one)
	end)

	it(
		"the pinned digest is the guard folder's, and only a readable folder of plain files has one",
		function()
			setUp()
			-- the rule, not a value: whoever edits a hook gets this message and the value to pin
			local r = process.exec("bash", {
				"-c",
				'. z-nile/lib/fence.sh && got=$(pickman_fence_hooks_digest z-nile/lib/git-hooks) && { [ "$got" = "$_PICKMAN_FENCE_HOOKS_SHA256" ] || { echo "z-nile/lib/fence.sh pins $_PICKMAN_FENCE_HOOKS_SHA256 but z-nile/lib/git-hooks is $got: set _PICKMAN_FENCE_HOOKS_SHA256 to it"; exit 1; }; }',
			}, { cwd = root })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			local names = process.exec("bash", {
				"-c",
				'. z-nile/lib/fence.sh && got=$(ls -A z-nile/lib/git-hooks | LC_ALL=C sort | tr "\\n" " " | sed "s/ $//") && { [ "$got" = "$_PICKMAN_FENCE_HOOKS_NAMES" ] || { echo "z-nile/lib/fence.sh names [$_PICKMAN_FENCE_HOOKS_NAMES] but z-nile/lib/git-hooks holds [$got]: set _PICKMAN_FENCE_HOOKS_NAMES to it"; exit 1; }; }',
			}, { cwd = root })
			if not names.ok then
				error(names.stdout .. names.stderr)
			end
			fs.writeDir(`{base}/empty`)
			for name, dir in
				{
					empty = `{base}/empty`,
					missing = `{base}/nowhere`,
					linked = variant("digest-link", "ln -s pre-push zz-link"),
				}
			do
				local d = process.exec(
					"bash",
					{ "-c", `. z-nile/lib/fence.sh; pickman_fence_hooks_digest "{dir}"` },
					{ cwd = checkout }
				)
				if d.ok or d.stdout ~= "" then
					error(`{name}: a digest of {dir}: {d.stdout}`)
				end
			end
		end
	)

	it(
		"the repository's own hook runs after the guard allows an update, and cannot allow what it refuses",
		function()
			setUp()
			local hook = `{checkout}/.git/hooks/reference-transaction`
			local log = `{base}/own-hook.log`
			-- a fetch is the update the guard allows from a check.sh flow (no spec-run marker): refs/remotes/ created
			local function fetch(body: string): fixture.Result
				fs.writeFile(hook, `#!/bin/sh\n{body}\n`)
				sh(`chmod +x "{hook}"`)
				if fs.isFile(log) then
					fs.removeFile(log)
				end
				pcall(fixture.git, checkout, { "update-ref", "-d", "refs/remotes/origin/main" })
				local script =
					'. z-nile/lib/fence.sh && pickman_fence "$PWD" && git fetch -q origin; echo "FETCH=$?"'
				return fixture.exec(checkout, "bash", { "-c", script }, {
					env = { PICKMAN_TEST_JAIL = "none", PICKMAN_FENCE_SPECS = "", PICKMAN_FENCE_HOOKS = "" },
				})
			end
			local allowed = fetch(`cat >/dev/null; echo "$1" >> "{log}"`)
			t.expect(has(allowed.stdout, "FETCH=0")).toBe(true)
			t.expect(has(fs.readFile(log), "prepared")).toBe(true)
			local refused = fetch(`cat >/dev/null; echo "$1" >> "{log}"; echo "own hook says no" >&2; exit 1`)
			t.expect(has(refused.stdout, "FETCH=0")).toBe(false)
			t.expect(has(refused.stderr, "own hook says no")).toBe(true)
			-- a refused branch write: the guard decides in `prepared` and never runs the repository's hook there; every
			-- other phase goes straight to it, so it sees the refused update as `preparing` then `aborted`
			fs.writeFile(hook, `#!/bin/sh\ncat >/dev/null\necho "$1" >> "{log}"\n`)
			sh(`chmod +x "{hook}"`)
			if fs.isFile(log) then
				fs.removeFile(log)
			end
			t.expect(guarded(probe(checkout, ""))).toBe(true)
			local seen = fs.readFile(log)
			if seen ~= "preparing\naborted\n" then
				error(`the repository's hook saw: {seen}`)
			end
			-- and a permissive own hook allows nothing the guard refuses: a branch write is still refused
			fs.writeFile(hook, "#!/bin/sh\ncat >/dev/null\nexit 0\n")
			sh(`chmod +x "{hook}"`)
			t.expect(guarded(probe(checkout, ""))).toBe(true)
		end
	)
end)
