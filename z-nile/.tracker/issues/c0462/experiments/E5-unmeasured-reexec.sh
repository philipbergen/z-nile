set -e
R="$1"; B="$R/z-nile/.cache/c0462-e5"
rm -rf "$B"; mkdir -p "$B/z-nile/tests/probe" "$B/z-nile/lib"
cd "$R"
cp z-nile/tests/run.luau "$B/z-nile/tests/"; cp -R z-nile/tests/lib "$B/z-nile/tests/"
cp z-nile/lib/ac.sh z-nile/lib/fence.sh z-nile/lib/bounded.pl z-nile/lib/cpu.sh z-nile/lib/measure.pl "$B/z-nile/lib/"
cp -R z-nile/lib/git-hooks "$B/z-nile/lib/"; cp z-nile/.luaurc "$B/z-nile/"; cp .luaurc rokit.toml .gitignore "$B/"
printf -- '--!strict\nlocal t = require("@tests/lib/t")\nreturn t.spec("p", function(it)\n\tit("makes one", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n' > "$B/z-nile/tests/probe/ok.spec.luau"
git init -q -b main "$B"
git -C "$B" add -A; git -C "$B" -c user.name=dev -c user.email=dev@example.invalid commit -qm x
cd "$B/z-nile"
PICKMAN_TEST_FENCE= ZN_MEASURED= ZN_GATE_QUEUE=off ZN_VACUOUS_PARENT=c9999 lune run tests/run -- tests/probe/ok.spec.luau; echo "exit $?"
echo "--- with -u"
python3 - "$B/z-nile/tests/run.luau" <<'P'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('\t\t\t"env",\n\t\t\t"ZN_MEASURED=1",','\t\t\t"env",\n\t\t\t"-u",\n\t\t\t"ZN_VACUOUS_PARENT",\n\t\t\t"ZN_MEASURED=1",',1)
s=s.replace('local USAGE =','print("PARENTVAR=" .. tostring(process.env.ZN_VACUOUS_PARENT))\nlocal USAGE =',1)
open(p,'w').write(s)
P
git -C "$B" -c core.hooksPath=/dev/null add -A 2>/dev/null || true
PICKMAN_TEST_FENCE= ZN_MEASURED= ZN_GATE_QUEUE=off ZN_VACUOUS_PARENT=c9999 lune run tests/run -- tests/probe/ok.spec.luau 2>&1 | grep -E "PARENTVAR|passed"
echo "--- without -u (mutant)"
sed -i.bak '/^\t\t\t"-u",$/d; /^\t\t\t"ZN_VACUOUS_PARENT",$/d' tests/run.luau
PICKMAN_TEST_FENCE= ZN_MEASURED= ZN_GATE_QUEUE=off ZN_VACUOUS_PARENT=c9999 lune run tests/run -- tests/probe/ok.spec.luau 2>&1 | grep -E "PARENTVAR|passed"
