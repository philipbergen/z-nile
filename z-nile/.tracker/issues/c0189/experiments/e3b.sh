#!/bin/sh
set -u
HOOK=$1
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e3b.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" && git init -q -b main repo && cd repo
git config user.email real@x.test; git config user.name real
git commit -q --allow-empty -m base
printf '#!/bin/sh\nexit 0\n' > "$T/trivial"; chmod +x "$T/trivial"
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
bench() { n=$1; shift; s=$(now); i=0; while [ $i -lt $n ]; do "$@" >/dev/null 2>&1 </dev/null; i=$((i+1)); done; e=$(now); perl -e "printf \"%.1f\", ($e-$s)*1000/$n"; }
for round in 1 2; do
  for mode in none trivial ours; do
    rm -f .git/hooks/reference-transaction
    case $mode in trivial) cp "$T/trivial" .git/hooks/reference-transaction;; ours) cp "$HOOK" .git/hooks/reference-transaction; chmod +x .git/hooks/reference-transaction;; esac
    printf 'round %s %-8s update-ref %s ms   commit %s ms\n' $round $mode "$(bench 40 git update-ref refs/heads/p HEAD)" "$(bench 40 git commit -q --allow-empty -m b)"
  done
done
