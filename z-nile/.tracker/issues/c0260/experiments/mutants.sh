#!/usr/bin/env bash
# c0260 mutation check. Run from the prototype's z-nile/ (a worktree off origin/main with the change applied and the
# acceptance specs copied under .tracker/issues/c0260/acceptance/): each mutant is applied to one engine file, its
# spec case must FAIL on an assertion, and the file is restored. Usage: bash mutants.sh <prototype>/z-nile
set -u
cd "$1" || exit 2
A=.tracker/issues/c0260/acceptance
fail=0
mutate() { # name file python-regex-from python-to spec expected-failure-substring
  local name=$1 file=$2 from=$3 to=$4 spec=$5 want=$6
  cp "$file" "$file.bak"
  python3 - "$file" "$from" "$to" <<'PY'
import re, sys
p, a, b = sys.argv[1:4]
s = open(p).read()
n, c = re.subn(a, b, s, count=1, flags=re.S)
if c != 1:
    sys.exit("mutant did not apply")
open(p, "w").write(n)
PY
  local applied=$?
  if [ $applied -ne 0 ]; then echo "NOAPPLY $name"; mv "$file.bak" "$file"; fail=1; return; fi
  out=$(lune run tests/run -- "$A/$spec" 2>&1)
  mv "$file.bak" "$file"
  if echo "$out" | grep -q "FAIL" && echo "$out" | grep -qF -- "$want"; then echo "KILLED  $name"; else echo "SURVIVED $name :: $(echo "$out" | tail -3 | tr '\n' ' ')"; fail=1; fi
}
E=engine
mutate M1-ask-grows "$E/capturecheck.luau" 'if b == nil or string.sub\(b, 1, #held\) ~= held then\n\t\t\t\treturn false' 'if false then\n\t\t\t\treturn false' shape.spec.luau "only grow"
mutate M2-qnumbers "$E/capturecheck.luau" 'if firstQ and firstQ.head ~= `Q\{count \+ 1\}` then' 'if false then' shape.spec.luau "appends"
mutate M3-confirm-round "$E/capturecheck.luau" 'elseif final.round ~= last then' 'elseif false then' shape.spec.luau "confirmation names"
mutate M4-drop-confirmed "$E/capturecheck.luau" 'and string.sub\(line, 1, 11\) ~= "Confirmed \(" then\n\t\t\t\t\ttable.insert\(kept, line\)' 'and true then\n\t\t\t\t\ttable.insert(kept, line)' record.spec.luau "next round"
mutate M5-dispatch-confirm "$E/main.luau" 'if opts\["--confirm"\] and dispatched then' 'if false then' record.spec.luau "--confirm records"
mutate M6-challenge-record "$E/idea.luau" 'if record then\n\t\tagainst' 'if false then\n\t\tagainst' record.spec.luau "given the user"
mutate M7-claim-gate "$E/capturecut.luau" 'if capturecheck.satisfies\(doc, capturecut.reviewsBeside\(folder, paths, read\)\) then' 'if true then' claim.spec.luau "made after"
mutate M8-land-doc-changed "$E/main.luau" 'if not captured\[entry.id\] then\n\t\t\treturn `not a capture change: \{entry.path\} \(an idea review' 'if false then\n\t\t\treturn `not a capture change: {entry.path} (an idea review' land.spec.luau "refuses any other"
mutate M9-land-marker "$E/main.luau" 'if capturecheck.markerOf\(theirs.stdout\) ~= capturecheck.markerOf\(mine.stdout\) then' 'if false then' land.spec.luau "agent-filed marker"
mutate M10-filed-idea-key "$E/capturecut.luau" 'local out = setFront\(doc, "idea", "unchallenged"\)' 'local out = if filedBy == nil then setFront(doc, "idea", "unchallenged") else doc' exempt.spec.luau "same idea key"
mutate M11-unattended-anywhere "$E/main.luau" 'if opts\["--unattended"\] and not dispatched then' 'if false then' record.spec.luau "--confirm records"
mutate M12-standalone "$E/main.luau" 'if standalone > 1 or \(standalone == 1 and opts\["--text"\]\) then' 'if false then' record.spec.luau "--record appends"
mutate M13-raft-members "$E/main.luau" 'if st == "new" then\n\t\t\t\t\t\tlocal gap = require' 'if false then\n\t\t\t\t\t\tlocal gap = require' claim.spec.luau "new raft"
mutate M14-audit-unconfirmed "$E/audit.luau" 'if capturecheck.unconfirmed\(doc\) and' 'if false and' audit.spec.luau "still Unconfirmed"
mutate M15-dispatched-confirmed-land "$E/main.luau" 'process.env.ZN_DISPATCH == "1"\n\t\t\tand capturecheck.confirmed' 'false\n\t\t\tand capturecheck.confirmed' land.spec.luau "dispatched run"
mutate M16-record-first "$E/main.luau" 'if cutMod.required\(frontOf\(doc\)\) and capturecheck.kind\(doc\) == "none" then' 'if false then' record.spec.luau "ask is kept"
mutate M17-fences-ignored "$E/capturecheck.luau" 'local function fenceOf\(line: string\): \(string\?, number\)\n' 'local function fenceOf(line: string): (string?, number)\n\tif true then\n\t\treturn nil, 0\n\tend\n' record.spec.luau "pasted headings"
mutate M18-confirm-unbound "$E/capturecheck.luau" 'if capturing and final.kind == "Confirmed"' 'if false and final.kind == "Confirmed"' shape.spec.luau "bound to it"
mutate M19-skip-open-ignored "$E/idea.luau" 'local pending = if skipOpen then \{\} else openlist.pending\(doc\)' 'local pending = openlist.pending(doc)' record.spec.luau "leaves a finding open"
mutate M20-claim-skip-open "$E/main.luau" 'capturecut.required\(frontOf\(tt\)\) and require\("./capturecheck"\).unconfirmed\(tt\)' 'false' claim.spec.luau "full user record"
mutate M21-land-runs-no-check "$E/main.luau" 'local problems = capturecheck.check\(mine.stdout, landed\)' 'local problems = {}' land-marked.spec.luau "malformed record"
mutate M22-prepared-keeps-words "$E/main.luau" 'if not require\("./capturecheck"\).recordGrows\(tt, fs.readFile\(localItem.doc\)\) then' 'if false then' claim.spec.luau "full user record"
mutate M23-source-unchecked "$E/main.luau" 'if sourceWhy then' 'if false then' claim.spec.luau "--filed-by refuses"
mutate M24-audit-ready-open "$E/audit.luau" 'if design == "ready" and #openlist.pending\(doc\) > 0 then' 'if false then' audit.spec.luau "idea point still unruled"
mutate M25-idea-name-widened "$E/main.luau" 'idea%-review%-%d%d%d%\.md\$"\) or' 'idea%-re[a-z]+%-%d%d%d%.md$") or' land-marked.spec.luau "land beside a document"
mutate M26-idea-key-free "$E/main.luau" 'local ideaStep = k == "idea"\n\t\t\t\t\tand \(was\[k\] == "unchallenged" or was\[k\] == "challenged"\)\n\t\t\t\t\tand now\[k\] == "challenged"' 'local ideaStep = k == "idea"' land-marked.spec.luau "land beside a document"
mutate M27-confirm-incomplete "$E/main.luau" 'if #problems == 0 and not capturecheck.satisfies\(confirmed, reviews\) then' 'if false then' record.spec.luau "needs the interview"
mutate M28-ask-after-interview "$E/capturecheck.luau" '\["Ask \(verbatim\)"\] = \{ "Interview", "Confirmation", "Design" \}' '["Ask (verbatim)"] = { "Confirmation", "Design" }' shape.spec.luau "Interview only"
mutate M29-record-keeps-confirmed "$E/capturecheck.luau" 'local parts = split\(capturecheck.dropConfirmed\(doc\)\)' 'local parts = split(doc)' record.spec.luau "pasted headings"
mutate M30-no-loop "$E/idea.luau" 'idea.MAX_ROUNDS = 3' 'idea.MAX_ROUNDS = 1' loop.spec.luau "second challenge that approves"
mutate M31-cap-raised "$E/idea.luau" 'idea.MAX_ROUNDS = 3' 'idea.MAX_ROUNDS = 4' loop.spec.luau "never approves"
mutate M37-agent-refused "$E/main.luau" 'capturecheck.kind\(doc\) == "none" then' 'capturecheck.kind(doc) ~= "user" then' loop.spec.luau "agent-filed"
mutate M32-no-prior "$E/main.luau" 'prior = idea.priorText\(findings, answers\)' 'prior = nil' loop.spec.luau "second challenge that approves"
mutate M33-no-current "$E/main.luau" 'idea.answerPrompt\(rough, plain, record, idea.draftText\(current\)\)' 'idea.answerPrompt(rough, plain, record)' loop.spec.luau "second challenge that approves"
mutate M34-capped-closes-revised "$E/main.luau" 'local revisable = not done and #plain > 0 and n < idea.MAX_ROUNDS' 'local revisable = not done and #plain > 0' loop.spec.luau "never approves"
mutate M35-ask-forgotten "$E/main.luau" 'local askFindings, plain = idea.splitFindings\(findings\)' 'local askFindings, plain = idea.splitFindings(findings)\n\t\t\tasked = {}' loop.spec.luau "never closed"
mutate M36-number-on "$E/main.luau" 'local number = firstNumber \+ n - 1' 'local number = firstNumber' loop.spec.luau "second challenge that approves"
mutate M38-approve-alone "$E/main.luau" 'local done = verdict == "approve" and #findings == 0' 'local done = verdict == "approve"' loop.spec.luau "still lists a finding"
mutate M39-revise-with-nothing "$E/main.luau" '\(said == "revise" and #found > 0\)' 'said == "revise"' loop.spec.luau "still lists a finding"
mutate M40-revisions-not-excluded "$E/main.luau" 'table.insert\(wroteBy, reviser\)' 'local _ = reviser' loop.spec.luau "never challenges it"
mutate M41-exclude-dropped "$E/modelstep.luau" 'if d.exclude and #d.exclude > 0 then' 'if false then' loop.spec.luau "never challenges it"
mutate M42-no-beat "$E/modelstep.luau" 'beatFile = d.beatFile,' '' loop.spec.luau "beats into"
mutate M43-label-index "$E/main.luau" 'number,\n\t\t\t\twroteBy' 'n,\n\t\t\t\twroteBy' loop.spec.luau "numbered on"
mutate M44-scope-lost "$E/capturecheck.luau" 'if capturecheck.markerOf\(doc\) == nil then' 'if true then' loop.spec.luau "agent-filed ticket"
mutate M45-provenance-never "$E/main.luau" 'fs.isFile\("z-nile/engine/provenance.luau"\)' 'false' provenance.spec.luau "exactly one call"
mutate M46-provenance-on-unattended "$E/main.luau" 'if opts\["--confirm"\] and fs.isFile' 'if fs.isFile' provenance.spec.luau "unattended"
exit $fail
