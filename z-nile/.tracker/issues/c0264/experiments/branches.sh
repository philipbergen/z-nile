#!/usr/bin/env bash
# c0264 E3b: which remote branches edit z-nile/README.md, and what each does to the step-1 merge. For each, the branch's own
# README change (git diff origin/main...<branch>) is applied to README.base.md ("landed first"), then
# git merge-file (ours=landed base theirs=draft) is run and its conflicts counted. Read-only: temp files only.
set -u
B=z-nile/.tracker/issues/c0264/experiments
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
git fetch -q origin
for b in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v -e HEAD -e '^origin$'); do
	git diff origin/main..."$b" --quiet -- z-nile/README.md 2>/dev/null && continue
	git diff origin/main..."$b" -- z-nile/README.md >"$T/p.patch"
	cp "$B/README.base.md" "$T/landed.md"
	if ! patch -s "$T/landed.md" <"$T/p.patch" >/dev/null 2>&1; then echo "$b: its README change does not apply to the base"; continue; fi
	n="$(git merge-file -p "$T/landed.md" "$B/README.base.md" "$B/README.draft.md" | grep -c '^<<<<<<<')"
	echo "$b: $n conflict(s)"
done
