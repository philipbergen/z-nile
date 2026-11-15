#!/usr/bin/env bash
# E4: the promoted and tooling specs that read z-design's SKILL.md or the real lessons stay green on the prototype
# (the reference lesson, the step-1 bullet, the harvest note), and c0270's own spec passes there. Works only in a
# fresh `mktemp -d` clone of this checkout's HEAD with this item's folder copied over it, which it removes.
# Run: ./zn run --time 1800 -- z-nile/.tracker/issues/c0270/experiments/E4-specs.sh [baseline]
# With `baseline`, the same specs run on the clone without the prototype (c0270's own spec is then expected red), so
# a failure that is the environment's shows in both runs.
set -uo pipefail
mode="${1:-prototype}"
here="$(cd "$(dirname "$0")" && pwd -P)"
item="$(cd "$here/.." && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
git clone -q --no-hardlinks "$top" "$t/c" || exit 1
c="$t/c"
rel="${item#"$top"/}"
rm -rf "${c:?}/$rel" && cp -R "$item" "$c/$rel"
if [[ $mode != baseline ]]; then
  cp "$here/ref-lesson.md.txt" "$c/z-nile/skills/z-design/lessons/one-prep-per-issue.md"
  S="$c/z-nile/skills/z-design/SKILL.md"
  awk -v b="$here/ref-skill-bullet.txt" '{print} /^- If an issue is missing, create it first with the `z-ticket` skill\.$/{while((getline l < b)>0) print l}' "$S" >"$S.new" && mv "$S.new" "$S"
  { cat "$item/harvest.md" 2>/dev/null; echo "- note c0264 prepped twice at once, PR #256's work lost (erred z-design): z-design/one-prep-per-issue"; } >"$t/h" && mv "$t/h" "$c/$rel/harvest.md"
fi
cd "$c/z-nile" || exit 1
echo "mode: $mode"
specs=$( { grep -rlF -e "z-design/SKILL.md" tests; grep -rlF -e "SKILL.md" tests | xargs grep -lE "skills/\*|for .* in .*skills|readDir\(.*skills"; grep -rlE "/lessons/|lessons\.load|lessons --check|\"lessons\"" tests | xargs grep -L "trackerfix\|fixture"; } 2>/dev/null | sort -u)
lune run tests/run -- $specs ".tracker/issues/c0270/acceptance/docs.spec.luau" 2>&1 | grep -E "^FAIL |passed, [0-9]+ failed"
