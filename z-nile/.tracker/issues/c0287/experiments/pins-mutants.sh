#!/usr/bin/env bash
# c0287 E6: acceptance/pins.sh on scratch copies of the prototype's files under $TMPDIR, each with one wrong fake or
# spec; every one must fail. Bounded by ./zn run:
#   ./zn run --time 120 -- bash <this file> <prototype checkout>
set -u
proto=$1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
pins="$here/../acceptance/pins.sh"
t=$(mktemp -d "${TMPDIR:-/tmp}/c0287-pins.XXXXXX") || exit 2
trap 'rm -rf "$t"' EXIT
trap 'exit 143' TERM INT HUP
fresh() {
  rm -rf "$t/z" && mkdir -p "$t/z/tests/lib" "$t/z/tests/acceptance" &&
  cp "$proto/z-nile/tests/lib/fakecli.luau" "$t/z/tests/lib/" &&
  cp -R "$proto/z-nile/tests/acceptance/c0117" "$proto/z-nile/tests/acceptance/c0279" "$t/z/tests/acceptance/"
}
sub() { python3 -I -c 'import sys; p,o,n=sys.argv[1:4]; s=open(p).read(); assert s.count(o)==1, o; open(p,"w").write(s.replace(o,n))' "$@"; }
try() { # try <name>: pins.sh must fail on the scratch copy
  if (cd "$t/z" && bash "$pins" > "$t/out" 2>&1); then echo "SURVIVED $1"; else echo "killed $1: $(head -n 1 "$t/out")"; fi
}
fresh; (cd "$t/z" && bash "$pins") && echo "control: the unmutated copy passes" || echo "CONTROL FAILED"
F=tests/lib/fakecli.luau
fresh; sub "$t/z/$F" $'\t\t\'[ -z "$step" ] || : > "$FAKE_DIR/started.$step"\',\n' ''
sub "$t/z/$F" $'\t\t\'step=$(printf' $'\t\t\'[ -z "$step" ] || : > "$FAKE_DIR/started.$step"\',\n\t\t\'step=$(printf'; try "marker before the step= line"
fresh; sub "$t/z/$F" $'\'[ -z "$step" ] || : > "$FAKE_DIR/started.$step"\'' $'\'[ -z "$step" ] || touch "$FAKE_DIR/started.$step"\''; try "marker written by touch (a spawn)"
fresh; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); o="& hb=$!; [ -z \"${FAKE_START_DELAY:-}\" ]"; assert s.count(o)==2; s=s.replace(o, "& hb=$!; kill $hb; [ -z \"${FAKE_START_DELAY:-}\" ]", 1); open(p,"w").write(s)' "$t/z/$F"; try "waitreview keepalive killed at once"
fresh; sub "$t/z/$F" '[ -f "$FAKE_DIR/late-go" ] && "$ZN_REAL_GIT" push' '"$ZN_REAL_GIT" push'; try "late push made without the marker"
fresh; sub "$t/z/$F" 'kill -9 "$ZN_DISPATCHER_PID"; sleep 3600 ;;' 'kill -9 "$ZN_DISPATCHER_PID"; sleep 20 ;;'; try "orphan hold cut to 20 s"
fresh; sub "$t/z/$F" '[ -z "${FAKE_DELAY:-}" ] || sleep "$FAKE_DELAY"]],' 'sleep ${FAKE_DELAY:-0}]],'; try "c0279's first line changed"
fresh; S=tests/acceptance/c0117/models.spec.luau; printf '\nlocal _ = require("@lune/task").wait(0)\n' >> "$t/z/$S"; try "a wait added to another c0117 spec"
fresh; sub "$t/z/tests/acceptance/c0117/control-cli.spec.luau" $'\t\ttask.wait(0.1)\n\tend\n\treturn true' $'\t\ttask.wait(0.1)\n\tend\n\ttask.wait(0)\n\treturn true'; try "a second wait in control-cli"
