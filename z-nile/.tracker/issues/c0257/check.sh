#!/usr/bin/env bash
# Acceptance checks for c0257. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0257 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0257"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the plugin holds exactly its planned files, the manifest names real entry points and the settings keep the rank command empty" lune run tests/run -- "$A/app.spec.luau"
check "AC2: the model's own tests pass under node" lune run tests/run -- "$A/modeltests.spec.luau"
check "AC3: the ordering, link, additive-key and rank-command rules hold" lune run tests/run -- "$A/rules.spec.luau"
check "AC4: the place-deploy workflow ignores pushes that touch only the plugin" lune run tests/run -- "$A/deploy.spec.luau"
check "AC5: no shell string or shell argument array in any file of the plugin, and the scripts stop on error" lune run tests/run -- "$A/noshell.spec.luau"
check "AC6: the documented test command runs on node 22, and SETUP.md, the README and zz-rules say what the app needs" lune run tests/run -- "$A/docs.spec.luau"
check "AC7: fetch.sh builds the model through ./zn only, derives the web base from the remote, and fails with its own codes; prs.sh prints [] when gh cannot answer" lune run tests/run -- "$A/fetch.spec.luau"
check "AC8: the board page's model is what the app reads" lune run tests/run -- "$A/contract.spec.luau"
# AC9 is this landing's only: the plugin is the reviewed prototype, byte for byte, but the files this issue changes. It is
# not a promoted spec, because c0249 and c0290 change these files after. A read of git objects, nothing is written.
PROTO=e467e31017007f60dccd73e7550cf6b23547a880
check "AC9: the plugin's files equal the reviewed prototype's but the four this issue changes" bash -c '
  cd "$ZN_ROOT" || exit 1
  git cat-file -e "$0^{commit}" 2>/dev/null || git fetch -q origin "$0" || exit 1
  for f in BarWidget.qml Board.qml Chip.qml CopyBox.qml IdChip.qml IdLinks.qml Model.js NewTicketDialog.qml PlainLabel.qml \
      Service.qml SmoothWheel.qml TicketTile.qml TypeBadge.qml agents.sh manifest.json prs.sh settings.json; do
    p=z-nile-omarchy/znile.board/$f
    [[ -f $p && "$(git hash-object "$p")" == "$(git rev-parse "$0:$p")" ]] || { echo "differs from $0: $p" >&2; exit 1; }
  done
' "$PROTO"
check "AC10: a change to the app selects c0257's specs through the watch map" lune run tests/run -- "$A/watch.spec.luau"

finish
