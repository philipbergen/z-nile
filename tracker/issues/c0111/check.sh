#!/usr/bin/env bash
# Acceptance checks for c0111. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0111 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0111"

check "AC1: a lesson file parses, and every bad field is named" lune run tests/run -- "$A/lesson-format.spec.luau"
check "AC2: ledgers, findings, sources, coverage and check are exact" lune run tests/run -- "$A/harvest.spec.luau"
check "AC3: selection filters, sorts and indexes lessons" lune run tests/run -- "$A/select.spec.luau"
check "AC4: tracker.sh lessons lists, shows, searches, validates and reports coverage" lune run tests/run -- "$A/lessons-cli.spec.luau"
check "AC5: the execution prompt carries the build lessons" lune run tests/run -- "$A/prompt-lessons.spec.luau"
check "AC6: every skill reads its lessons and routes new ones by role, and the pipeline steps say so" lune run tests/run -- "$A/skill-docs.spec.luau"
# tests/run takes spec files, not folders
AC7=(tests/acceptance/c00{01,03,47,48,50,57,64,67,68,69,74,81,82}/*.spec.luau tests/acceptance/c0043/{format,review-skill,ticket-prep}.spec.luau tests/acceptance/c0052/{skill-doc,new-spacing,renumber}.spec.luau tests/acceptance/c0107/keep.spec.luau tests/tooling/{ready-members,start-pr-reuse,tracker-guarded,migrate-odd}.spec.luau)
check "AC7: the existing specs that read the prompt template, the skills or main.luau pass" lune run tests/run -- "${AC7[@]}"
check "AC8: the real tree's lessons and ledgers are valid" scripts/tracker.sh lessons --check
check "AC8: R0040's own reviews are fully harvested" scripts/tracker.sh lessons --uncovered R0040

finish
