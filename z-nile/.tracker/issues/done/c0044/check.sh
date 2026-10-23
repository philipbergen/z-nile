#!/usr/bin/env bash
# Acceptance checks for c0044. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0044 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0044"

# AC1-AC5 and AC8 are cases of one end-to-end spec (shared fixture). It runs once; each check then
# requires its own named cases to exist in the spec and not fail, and that the spec loaded at all.
spec="$A/naming.spec.luau"
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
  local c
  for c in "$@"; do
    grep -qF "it(\"$c" "$spec" || { echo "the spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$spec_out" | grep -qF ":: $c"; then grep -F ":: $c" <<<"$spec_out"; return 1; fi
  done
}
all_cases_pass() {
  grep -q "could not load spec" <<<"$spec_out" && { echo "$spec_out"; return 1; }
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
}

check "AC1: new writes <ID>.md with a slug; bad slugs rejected" cases_pass \
  "new issue writes" "new raft writes" "new rejects a bad slug"
check "AC2: find, list, members, start on the new layout; slug from the frontmatter" cases_pass \
  "find, list, members and start" "a document without a slug"
check "AC3: a legacy-named document is an error pointing at migrate" cases_pass "a legacy-named document"
check "AC4: migrate converts legacy documents, idempotent, refuses ambiguity, adopts a merged branch" cases_pass \
  "migrate converts" "migrate is idempotent" "a branch that added a legacy document"
check "AC5: renumber renames the document and rewrites references" cases_pass "renumber renames"
check "AC6: the repo is migrated: no legacy document, every item has <ID>.md with a slug" bash -c '
  legacy=$(find tracker z-nile/.tracker -name "[fdcR][0-9][0-9][0-9][0-9]-*.md")
  [ -z "$legacy" ] || { echo "legacy documents:"; echo "$legacy"; exit 1; }
  n=0
  for d in $(find tracker/issues tracker/rafts z-nile/.tracker/issues z-nile/.tracker/rafts -maxdepth 3 -type d -name "[fdcR][0-9][0-9][0-9][0-9]"); do
    id=$(basename "$d"); n=$((n+1))
    [ -f "$d/$id.md" ] || { echo "$d has no $id.md"; exit 1; }
    grep -q "^slug: " "$d/$id.md" || { echo "$d/$id.md has no slug:"; exit 1; }
  done
  [ "$n" -gt 0 ] || { echo "no item directories found"; exit 1; }
  ./zn list >/dev/null'
check "AC7: the specs that named the old paths pass on the new layout" \
  lune run tests/run -- tests/acceptance/c0001/tracker-lifecycle.spec.luau \
  tests/acceptance/c0043/rounds.spec.luau tests/tooling/metrics-rounds.spec.luau
check "AC8: two branches creating the same id conflict on the document" cases_pass \
  "two branches creating the same id"
check "AC9: the skill describes the layout; no text still says <ID>-<slug>.md" bash -c '
  grep -qF "<ID>/<ID>.md" .claude/skills/tracker/SKILL.md || { echo "tracker skill: layout line"; exit 1; }
  grep -qi "migrate" .claude/skills/tracker/SKILL.md || { echo "tracker skill: no migrate procedure"; exit 1; }
  grep -qF "add/add" .claude/skills/tracker/SKILL.md || { echo "tracker skill: only add/add means renumber"; exit 1; }
  bad=$(grep -rnF -e "<ID>-<slug>" -e "<id>-<slug>" -e "-slug.md" -e "-<slug>.md" .claude scripts z-nile/templates SETUP.md AGENTS.md || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC10: no spec names a legacy document path (the permanent guard)" \
  lune run tests/run -- "$A/guard.spec.luau"
check "AC1-AC5, AC8: every case of the naming spec passes" all_cases_pass

finish
