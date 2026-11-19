#!/usr/bin/env python3
# Mutation check for c0189 on the scratch prototype: apply one mutant at a time, run its spec file, record the failing cases.
import subprocess, sys, os, json, shutil
# usage: python3 mutate.py <scratch clone> <bounded.pl> [mutant ids...]   (the clone has the prototype applied, with this folder's
# acceptance specs copied in; bounded.pl runs a command in its own process group and kills it on timeout)
S = sys.argv.pop(1)
BOUNDED = sys.argv.pop(1) if len(sys.argv) > 1 and sys.argv[1].endswith('.pl') else None  # optional bounded runner
HOOK = 'z-nile/lib/repo-hooks/reference-transaction'
PLAN = 'z-nile/engine/hooks.luau'
MAIN = 'z-nile/engine/main.luau'
A = '.tracker/issues/c0189/acceptance/'
SPECS = {'hook': A + 'repo-hook.spec.luau', 'plan': A + 'hooks-plan.spec.luau', 'cmd': A + 'hooks-command.spec.luau',
         'wire': A + 'wiring.spec.luau', 'mode': A + 'replace-mode.spec.luau',
         'c0077': 'tests/acceptance/c0077/replace-file.spec.luau'}
REPLACE = 'z-nile/lib/replace-file.pl'
SH = 'z-nile/lib/sh.luau'
# id: (file, old, new, spec key)
M = {}
def m(id, f, old, new, spec): M[id] = (f, old, new, spec)
# --- the hook
m('H1', HOOK, "if (tolower($1) ~ /@example\\.invalid$/) print sha, \"author\", $1", "if (0) print sha, \"author\", $1", 'hook')
m('H2', HOOK, "if (tolower($2) ~ /@example\\.invalid$/) print sha, \"committer\", $2", "if (0) print sha, \"committer\", $2", 'hook')
m('H3a', HOOK, "*@[eE][xX][aA][mM][pP][lL][eE].[iI][nN][vV][aA][lL][iI][dD]*) ;;", "*@example.invalid*) ;;", 'hook')
m('H3b', HOOK, "if (tolower($1) ~ /@example\\.invalid$/) print sha, \"author\", $1\n    if (tolower($2) ~ /@example\\.invalid$/)", "if ($1 ~ /@example\\.invalid$/) print sha, \"author\", $1\n    if ($2 ~ /@example\\.invalid$/)", 'hook')
m('H4', HOOK, "if (tolower($1) ~ /@example\\.invalid$/) print sha, \"author\", $1\n    if (tolower($2) ~ /@example\\.invalid$/) print sha, \"committer\", $2", "if (tolower($1) ~ /@example\\.invalid/) print sha, \"author\", $1\n    if (tolower($2) ~ /@example\\.invalid/) print sha, \"committer\", $2", 'hook')
m('H5a', HOOK, '($3 == "HEAD" || $3 ~ /^refs\\//)', '($3 ~ /^refs\\/heads\\//)', 'hook')
m('H5b', HOOK, '($3 == "HEAD" || $3 ~ /^refs\\//)', '($3 ~ /^refs\\//)', 'hook')
m('H5c', HOOK, '($3 == "HEAD" || $3 ~ /^refs\\//)', '($3 == "HEAD" || $3 ~ /^refs\\/(heads|tags)\\//)', 'hook')
m('H6', HOOK, " && $2 !~ /^0+$/ {", " {", 'hook')
m('H6b', HOOK, "    pairs = pairs $2 \" \" $3 \"\\n\"\n    if (!seen[$2]++) shas = shas $2 \"\\n\"", "    pairs = pairs $2 \" \" $3 \"\\n\"\n    if (!seen[$2]++) shas = shas $2 \"\\n\"\n    if ($1 !~ /^0+$/) { pairs = pairs $1 \" \" $3 \"\\n\"; if (!seen[$1]++) shas = shas $1 \"\\n\" }", 'hook')
m('H6c', HOOK, " && $2 !~ /^0+$/ {\n    pairs = pairs $2 \" \" $3 \"\\n\"\n    if (!seen[$2]++) shas = shas $2 \"\\n\"", " {\n    v = ($2 ~ /^0+$/) ? $1 : $2\n    pairs = pairs v \" \" $3 \"\\n\"\n    if (!seen[v]++) shas = shas v \"\\n\"", 'hook')
m('H7', HOOK, "$1 != $2 && (", "(", 'hook')
m('H8a', HOOK, '($3 == "HEAD" || $3 ~ /^refs\\//) && ', '', 'hook')
m('H8b', HOOK, " && $2 ~ /^[0-9a-f]+$/", "", 'hook')
m('H9', HOOK, '[ -n "$found" ] || exit 0', '[ -n "$found" ] || exit 0', 'hook')  # placeholder, replaced below
m('H10', HOOK, '[ "$1" = prepared ] || exit 0\n', '', 'hook')
m('H11', HOOK, "refuse \"cannot read the new commits; refusing (remove the hook only if git itself is broken)\"", "true", 'hook')
m('H12a', HOOK, "A prototype lives in a scratch clone (git clone this checkout under the main checkout's .cache/.tmp/, never a git worktree add) or commits under your own identity (git commit --amend --reset-author takes over a prototype commit; c0189, zz-test skill).", "Do not do that.", 'hook')
m('H12b', HOOK, "if (refs[$1] ~ / refs\\/remotes\\//) remote = 1", "if (0) remote = 1", 'hook')
m('H12c', HOOK, "if (refs[$1] ~ / refs\\/remotes\\//) remote = 1", "remote = 1", 'hook')
m('H13', HOOK, "print sha, \"committer\", $2", "print sha, \"author\", $2", 'hook')
m('H14', HOOK, "} >&2\nexit 1", "} >&2\nexit 0", 'hook')
# H9: a tree must be allowed: fail on empty output
m('H9', HOOK, "# cheap test first", "[ -n \"$who\" ] || refuse \"nothing to read\"\n# cheap test first", 'hook')
# --- plan
m('P1', PLAN, 'elseif s.kind == "absent" then\n\t\ttable.insert(problems, `hooks: {s.dest} is missing; run ./zn hooks`)', 'elseif s.kind == "absent" then', 'plan')
m('P2', PLAN, "elseif s.installed ~= s.source then", "elseif false then", 'plan')
m('P3', PLAN, "elseif not s.executable then", "elseif false then", 'plan')
m('P4', PLAN, "elseif s.installed == nil or not hooks.isOurs(s.installed) then", "elseif s.installed == nil then", 'plan')
m('P5', PLAN, 'if s.kind == "link" then', 'if false then', 'plan')
m('P6', PLAN, "for _, r in s.redirects do", "for _, r in {} do", 'plan')
m('P7', PLAN, "if s.source == nil or not hooks.isOurs(s.source) then", "if false then", 'plan')
m('P9a', PLAN, 'if scope and path and scope ~= "command" then', 'if scope and path then', 'plan')
m('P9b', PLAN, 'if winner and winner.path ~= own then', 'if winner then', 'plan')
m('P10', PLAN, "if line == hooks.MARKER then", "if string.find(line, hooks.MARKER, 1, true) then", 'plan')
m('P11', PLAN, 'elseif s.kind == "other" then', 'elseif false then', 'plan')
# --- the command
m('C1old', MAIN, "\t\tprint(`hooks: {hooksLib.NAME} installed in {dir}, ok`)\n\t\treturn\n\tend\n\tif plan.action == \"refuse\"", "\t\tprint(`hooks: {hooksLib.NAME} installed in {dir}, ok`)\n\tend\n\tif plan.action == \"refuse\"", 'cmd')
m('C1', MAIN, 'if opts["--check"] then\n\t\tif plan.action == "install" and plan.older then', 'if false then\n\t\tif plan.action == "install" and plan.older then', 'cmd')
m('C3', MAIN, "\tif plan.action == \"ok\" then\n\t\tprint(`hooks: {dest} is up to date`)\n\t\treturn\n\tend", "", 'cmd')
m('C5', MAIN, 'if sh.run("test", { "-L", dest }).ok then\n\t\tkind = "link"\n\telseif', 'if false then\n\t\tkind = "link"\n\telseif', 'cmd')
m('C6', MAIN, '{ "config", "--show-scope", "--get-all", hooksLib.CONFIG_KEY }', '{ "config", "--get-all", hooksLib.CONFIG_KEY }', 'cmd')
m('C7', MAIN, '{ "rev-parse", "--path-format=absolute", "--git-common-dir" })\n\tlocal dir = `{common}/hooks`', '{ "rev-parse", "--path-format=absolute", "--git-dir" })\n\tlocal dir = `{common}/hooks`', 'cmd')
m('C8', MAIN, "function cmd.hooks(pos: { string }, opts: { [string]: { string } })\n", "function cmd.hooks(pos: { string }, opts: { [string]: { string } })\n\trefuseInMainCheckout(\"hooks\")\n", 'cmd')
m('C10', MAIN, '\t\tif k ~= "--check" then\n\t\t\tfail(`usage: ./zn hooks [--check] (unknown option {k})`)', '\t\tif false then\n\t\t\tfail(`usage: ./zn hooks [--check] (unknown option {k})`)', 'cmd')
# --- wiring (text)
m('W1', 'z-nile/check.sh', '[[ -f z-nile/lib/repo-hooks/reference-transaction ]] && par_start "hooks (./zn hooks --check)" ./zn hooks --check\n', '', 'wire')
m('W2', 'z-nile/setup.sh', 'say "repository hook"\n./zn hooks # refuses commits under a fixture identity; the gate checks it\n\n', '', 'wire')
m('W3', 'z-nile/skills/zz-execute/SKILL.md', "never commits as `@example.invalid` in the real repository", "never commits as `@example.invalid` anywhere", 'wire')
m('W4', 'AGENTS.md', "retry the gate or `./zn land` once without asking", "retry the gate or `./zn land` without asking", 'wire')
m('W5', 'z-nile/skills/zz-rules/SKILL.md', "| hooks | `./zn hooks [--check]` |", "| hook | `./zn hooks [--check]` |", 'wire')

m('P8', PLAN, '\tif s.kind == "link" then', '\tif refuse then\n\t\treturn { action = "refuse", problems = problems }\n\tend\n\tif s.kind == "link" then', 'plan')
m('C13', MAIN, '\tif plan.action == "refuse" then\n\t\tfail(table.concat(plan.problems, "\\n"))\n\tend\n\tif plan.action == "ok" then', '\tif plan.action == "ok" then', 'cmd')
m('C14', MAIN, '\tif plan.action == "ok" then\n\t\tprint(`hooks: {dest} is up to date`)', '\tif plan.action == "ok" or kind == "file" then\n\t\tprint(`hooks: {dest} is up to date`)', 'cmd')
m('W6', 'z-nile/skills/zz-rules/SKILL.md', "Run `./zn hooks` in the clone (the gate's static stage checks the repository it runs in, and a fresh clone has no hook of its own). Spawn the gate there", "Spawn the gate there", 'wire')

m('S1', MAIN, 'if fetched then\n\t\tfrom = "origin/main"', 'if false then\n\t\tfrom = "origin/main"', 'cmd')
m('S3', MAIN, '\t\tsource = nil\n\t\tif sh.trim(listed.stdout) ~= "" then', '\t\tif sh.trim(listed.stdout) ~= "" then', 'cmd')
m('S4', MAIN, 'if hasOrigin and not fetched then', 'if not fetched then', 'cmd')
m('N1', PLAN, 'if s.source == nil and s.from == "origin/main" then', 'if false then', 'plan')
m('R1', PLAN, '\t\t\twinner = { scope = scope, path = path }', '\t\t\twinner = winner or { scope = scope, path = path }', 'plan')
m('H15', HOOK, "git rev-list --no-walk=unsorted --stdin", "env -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_QUARANTINE_PATH git rev-list --no-walk=unsorted --stdin", 'hook')
m('H12d', HOOK, " Pushing a prototype to a repository with this hook is refused the same way.", "", 'hook')
m('W7', MAIN, 'local USAGE = [[', '-- core.hooksPath\nlocal USAGE = [[', 'wire')

m('Q1', PLAN, 'if s.reviewed and s.executable then', 'if s.executable then', 'cmd')
m('Q1p', PLAN, 'if s.reviewed and s.executable then', 'if s.executable then', 'plan')
m('Q2', PLAN, 'if s.reviewed and s.executable then', 'if s.reviewed then', 'plan')
m('Q3', MAIN, 'if plan.action == "install" and plan.older then', 'if false then', 'cmd')
m('Q4', PLAN, 'if new and not string.match(new, "^0+$") then', 'if new then', 'plan')
m('S5', MAIN, '\t\tif not listed.ok then\n\t\t\tfail(`hooks: cannot read origin/main: {sh.trim(listed.stderr)}`)\n\t\tend\n', '', 'cmd')
m('S6', MAIN, '\tif hasOrigin and not fetched then\n\t\t-- an origin whose main was never fetched must not fall back to a branch\'s unmerged copy\n\t\tfail("hooks: origin has no main fetched; run git fetch origin main")\n\tend\n', '', 'cmd')
m('H16', HOOK, 'printf \'%s\\n%s\\n\' "$peeled" "$found"', 'printf \'%s\\n%s\\n\' "$updates" "$found"', 'hook')

m('F1m', MAIN, '"--first-parent",\n\t\t\t\t"--format=",', '"--format=",', 'cmd')
m('F2m', MAIN, 'local shown = sh.run("git", { "cat-file", "blob", `origin/main:{hooksLib.SOURCE}` })', 'local shown = { ok = true, stdout = sh.git({ "show", `origin/main:{hooksLib.SOURCE}` }) .. "\\n", stderr = "" }', 'cmd')
m('H17', HOOK, '  echo "If this stopped a rebase or cherry-pick of older prototype commits: git rebase --abort (or git cherry-pick --abort), then merge instead of rebasing, or move the prototype to a scratch clone."\n', '', 'hook')

m('K1', HOOK, '[ "${ref#refs/rewritten/}" = "$ref" ] && [ "$(git rev-parse -q --verify "$ref" 2>/dev/null)" = "$sha" ]; then', 'false; then', 'hook')
m('K2', HOOK, '$1 != $2 && (', '$1 != $2 && $1 !~ /^0+$/ && (', 'hook')

m('K3', HOOK, 'if [ "$ref" != HEAD ] && [ "${ref#refs/bisect/}"', 'if [ "${ref#refs/bisect/}"', 'hook')
m('H18', HOOK, '    if (head) print "If this stopped a checkout', '    if (0) print "If this stopped a checkout', 'hook')
m('H18b', HOOK, 'refs[$1] != "" && refs[$1] ~ / HEAD( |$)/ { head = 1 }', 'refs[$1] != "" { head = 1 }', 'hook')
m('H19', HOOK, "(git commit --amend --reset-author takes over a prototype commit; c0189, zz-test skill)", "(c0189, zz-test skill)", 'hook')

# --- re-prep (R0070's coherence review): the scratch clone goes under .cache/.tmp/, and the install makes no temporary name
m('W8a', 'z-nile/skills/zz-execute/SKILL.md', "under the main checkout's `.cache/.tmp/` (never the system temp folder or a harness's scratchpad) or commits", "into `$TMPDIR` or the scratchpad or commits", 'wire')
m('W8b', HOOK, "git clone this checkout under the main checkout's .cache/.tmp/, never a git worktree add", "git clone this checkout into \\$TMPDIR or the scratchpad", 'wire')
m('W8c', HOOK, "git clone this checkout under the main checkout's .cache/.tmp/, never a git worktree add", "git clone this checkout somewhere", 'hook')
m('W8d', HOOK, "git clone this checkout under the main checkout's .cache/.tmp/, never a git worktree add", "git clone this checkout under the main checkout's .cache/.tmp/ (or the scratchpad), never a git worktree add", 'hook')
m('W9a', MAIN, "\tfs.writeDir(dir)\n\tlocal ok, err = pcall(sh.writeReplacing", "\tfs.writeDir(dir)\n\tlocal _ = sh.must(\"mktemp\", { `{dir}/.x.XXXXXX` })\n\tlocal ok, err = pcall(sh.writeReplacing", 'wire')
m('W9b', MAIN, 'pcall(sh.writeReplacing, dest, state.source :: string, "0755")', 'pcall(sh.writeReplacing, dest, state.source :: string)', 'cmd')
m('W9c', MAIN, 'local ok, err = pcall(sh.writeReplacing, dest, state.source :: string, "0755")', 'local ok, err = pcall(function()\n\t\tsh.writeReplacing(dest, state.source :: string)\n\t\tsh.must("chmod", { "755", dest })\n\tend)', 'wire')
m('C12', MAIN, 'if not ok then\n\t\tfail(`hooks: could not install {dest}: {err}`)\n\tend\n', '', 'cmd')
m('M1', REPLACE, 'chmod $mode, $tmp', 'chmod 0644, $tmp', 'mode')
m('M2', REPLACE, "    unless ($given =~ /\\A[0-7]{3,4}\\z/) {", "    unless (1) {", 'mode')
m('M3', REPLACE, 'chmod $mode, $tmp', 'chmod 0755, $tmp', 'mode')
m('M4', REPLACE, "    shift @ARGV;\n", "", 'mode')
m('M5', SH, "args = { `{LIB}/replace-file.pl`, `--mode={mode}`, path }", "args = { `{LIB}/replace-file.pl`, path }", 'mode')
m('M6', REPLACE, "    $mode = oct($given);", "    $mode = oct($given) & 0644;", 'mode')
m('W10', 'z-nile/skills/zz-test/SKILL.md', "run `./zn hooks` there first, outside any spec jail, and make any commit that clone needs under a fixture identity before it (the hook refuses those).", "run the gate there.", 'wire')
m('W10b', 'z-nile/skills/zz-test/SKILL.md', " A clone holding unguarded code (Running specs against unguarded code) runs spec files only, jailed, and needs no hook.", "", 'wire')
m('M9', REPLACE, "[0-7]{3,4}", "[0-7]{1,4}", 'mode')
m('M7', REPLACE, "    unlink $tmp if defined $tmp;\n", "", 'c0077')
m('M8', REPLACE, "if (-d $dest && !-l $dest) {", "if (0) {", 'mode')

only = sys.argv[1:] or list(M)
res = {}
for id in only:
    f, old, new, spec = M[id]
    path = os.path.join(S, f)
    orig = open(path).read()
    if old not in orig:
        res[id] = 'NOT APPLIED (old text not found)'
        print(id, res[id], flush=True); continue
    open(path, 'w').write(orig.replace(old, new, 1))
    try:
        r = subprocess.run(['bash', '-c', f'cd {S}/z-nile && export PATH=$HOME/.rokit/bin:$PATH && PICKMAN_JOBS=2 perl {BOUNDED or '-e "alarm shift; exec @ARGV"'} 150 lune run tests/run -- {SPECS[spec]} 2>&1'], capture_output=True, text=True)
        out = r.stdout
    finally:
        open(path, 'w').write(orig)
    fails = [l[len('FAIL '):] for l in out.splitlines() if l.startswith('FAIL ')]
    summary = [l for l in out.splitlines() if 'passed' in l and 'failed' in l][-1:] or ['(no summary) ' + out[-200:]]
    res[id] = (summary[0], [x.split(' :: ')[-1][:110] if ' :: ' in x else x[:110] for x in fails])
    print(id, res[id][0], '|', '; '.join(res[id][1]) if res[id][1] else 'NONE FAILED', flush=True)
