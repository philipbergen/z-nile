set -e
D=$(mktemp -d); cd $D; git init -q -b main r; cd r
git config user.email a@example.invalid; git config user.name a
mkdir -p i/c0019; echo doc > i/c0019/c0019.md; echo chk > i/c0019/check.sh
git add -A; git commit -qm base
git checkout -qb ours
echo ours > i/c0019/provenance.md; git add -A; git commit -qm ours
git checkout -q main
if [ "$1" = both ]; then echo theirs > i/c0019/provenance.md; git add -A; git commit -qm prov; fi
mkdir -p i/active; git mv i/c0019 i/active/c0019; git commit -qm move
git checkout -q ours
git merge --no-edit main || true
echo ---; git status --short; echo ---; git ls-files -u
echo "=== directoryRenames=true"; git merge --abort || true
git -c merge.directoryRenames=true merge --no-edit main || true
git status --short; git ls-files -u
