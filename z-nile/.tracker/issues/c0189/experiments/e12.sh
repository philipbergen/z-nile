#!/bin/sh
# E12 (c0189): does `git branch -m` / `-c` / `pack-refs` reach reference-transaction? Throwaway repo under $TMPDIR only.
set -u
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e12.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" && git init -q -b main repo && cd repo
git config user.email real@x.test; git config user.name real
git commit -q --allow-empty -m base
git -c user.email=p@example.invalid commit -q --allow-empty -m proto
git branch old; git reset -q --hard HEAD~1
cat > .git/hooks/reference-transaction <<'H'
#!/bin/sh
{ printf '[%s]' "$1"; while read -r o n r; do printf ' %s->%s %s;' "$(echo $o | cut -c1-4)" "$(echo $n | cut -c1-4)" "$r"; done; echo; } >> "$LOG"
exit 0
H
chmod +x .git/hooks/reference-transaction
export LOG=$T/log
for c in "branch -m old archived" "branch -c archived copied" "pack-refs --all"; do
  : > "$LOG"; git $c >/dev/null 2>&1; echo "## git $c -> exit=$?"; grep prepared "$LOG" | cut -c1-160
done
echo "refs now: $(git for-each-ref --format='%(refname) %(authoremail)' | tr '\n' ' ')"
