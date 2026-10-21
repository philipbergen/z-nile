#!/usr/bin/env bash
# Dispatch CI (.github/workflows/check.yml) for the current branch and wait for the result.
# Proves the exact local HEAD green on CI without taking the PR out of draft. See SETUP.md.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf 'ci-verify: %s\n' "$1" >&2; exit 1; }

branch=$(git branch --show-current)
[[ -n $branch && $branch != main ]] || die "run on a feature branch (current: '${branch:-detached}')"

git fetch -q origin "$branch" || die "branch $branch is not on origin; push it first"
head=$(git rev-parse HEAD)
[[ $head == "$(git rev-parse "origin/$branch")" ]] ||
  die "HEAD $head differs from origin/$branch; push (or pull) so CI tests exactly this commit"

before=$(gh run list --workflow check.yml --limit 20 --json databaseId -q '[.[].databaseId] | max // 0')
gh workflow run check.yml --ref "$branch"
echo "dispatched check.yml on $branch @ ${head:0:7}; waiting for the run to appear"

id=""
for _ in $(seq 24); do # 120 s, polling every 5 s
  id=$(gh run list --workflow check.yml --branch "$branch" --event workflow_dispatch \
    --json databaseId,headSha \
    -q "[.[] | select(.databaseId > $before and .headSha == \"$head\") | .databaseId] | max // empty")
  [[ -n $id ]] && break
  sleep 5
done
[[ -n $id ]] || die "no dispatched run for $head appeared within 120 s"

url=$(gh run view "$id" --json url -q .url)
echo "run: $url"
status=0
gh run watch "$id" --exit-status --interval 10 >/dev/null || status=$?
echo "run: $url ($(if [[ $status == 0 ]]; then echo success; else echo "failed, exit $status"; fi))"
exit "$status"
