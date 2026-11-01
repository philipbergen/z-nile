#!/usr/bin/env bash
# Acceptance checks for c0190. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0190 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0190"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The promoted spec pins what a later prep keeps (each issue, its type, the dependencies the capture names, its Problem's
# quote and pointer), found by slug. AC4 to AC6 are claims about the capture as it landed, which run at done and never
# again: `./zn capture` reads origin/main, which a gate clone has no copy of, and later preps add dependencies and detail.
check "AC1: each listed issue exists once in its project, with its type" lune run tests/run -- "$A/captured.spec.luau"
check "AC2: each issue's depends_on holds the dependencies the capture names" lune run tests/run -- "$A/captured.spec.luau"
check "AC3: each Problem quotes the user and points at its design" lune run tests/run -- "$A/captured.spec.luau"
# key:project:slug:depends_on (keys of this list or ids) of every listed issue, in the list's order (c0190 Design item 2)
ROWS="A1:arcade:hiscores-with-revives:c0184 \
	K1:pickman:switch-to-arcade-hiscores:A1,c0185 \
	A2:arcade:shared-travel:c0184 \
	K2:pickman:switch-to-arcade-travel:A2,c0185 \
	A3:arcade:paid-play-and-receipts:c0184 \
	K3:pickman:switch-to-arcade-paid-play:A3,f0145,f0186,c0185 \
	A4:arcade:input-and-look-cores:c0184 \
	K4:pickman:switch-to-arcade-input-cores:A4,c0185 \
	P1:portal:game-carousel:A3,c0185 \
	P2:portal:boards-per-game:A1,P1 \
	P3:portal:free-game-timer:A3,P1 \
	P4:portal:play-buttons:A2,A3,P1 \
	P5:portal:portal-start-place:Z3,P4 \
	Z3:portal:n-place-deploy:c0184 \
	S1:snake:arena-maps-growth:c0184 \
	S2:snake:shared-snake-arena:c0184 \
	S3:snake:snake-first-person-view:S1,A4,c0185 \
	S4:snake:boost-golden-apples-crumbs:S1 \
	S5:snake:snake-scores-and-revives:S1,A1,A2,A3,c0185 \
	I1:invaders:invaders-classic-rules:c0184 \
	I2:invaders:invaders-two-players:c0184 \
	I3:invaders:invaders-cannon-view:I1,A4,c0185 \
	I4:invaders:invaders-scores-and-revives:I1,A1,A2,A3,c0185 \
	T1:asteroids:asteroids-classic-rules:c0184 \
	T2:asteroids:asteroids-two-players:c0184 \
	T3:asteroids:asteroids-cockpit-view:T1,A4,c0185 \
	T4:asteroids:asteroids-scores-and-revives:T1,A1,A2,A3,c0185"
# the document of the one issue of project $1 with slug $2, in its root's backlog, active/ or done/; fails on none or two
docof() {
	local docs
	docs=$(grep -lx -- "slug: $2" "$ZN_ROOT/$1"/.tracker/issues/*/*.md "$ZN_ROOT/$1"/.tracker/issues/*/*/*.md 2>/dev/null)
	[[ -n $docs && $docs != *$'\n'* ]] || { echo "$1 $2: not exactly one issue" >&2; return 1; }
	printf "%s\n" "$docs"
}
# the id of a key of ROWS, or the argument itself when it is an id
idof() {
	local row
	for row in $ROWS; do
		[[ ${row%%:*} == "$1" ]] || continue
		row=${row#*:}
		basename "$(docof "${row%%:*}" "$(cut -d: -f2 <<<"$row")")" .md
		return
	done
	printf "%s\n" "$1"
}
# the sorted ids of a document's depends_on line
depsof() { grep -m1 '^depends_on:' "$1" | grep -oE '[fdcR][0-9]{4}' | sort; }
# Each issue's capture (`./zn capture`) is the filled document, from a commit whose subject lists the ids, so a prep
# reads the whole captured scope, never the one-line stub (z-ticket lesson capture-subject-lists-every-id).
ac4() {
	local row p s doc id head body
	for row in $ROWS; do
		row=${row#*:} p=${row%%:*} s=$(cut -d: -f2 <<<"$row")
		doc=$(docof "$p" "$s") || return 1
		id=$(basename "$doc" .md)
		body=$("$ZN_ROOT/zn" capture "$id") || { echo "$s: zn capture $id failed"; return 1; }
		head=${body%%$'\n'*}
		[[ $head == "capture "*" tracker: new "* && $head != *"(no capture commit"* && $head != *"(ambiguous"* ]] ||
			{ echo "$s: capture header: $head"; return 1; }
		[[ " ${head#* tracker: new } " == *" $id "* ]] || { echo "$s: $id not in the subject: $head"; return 1; }
		grep -qF -- '"I want to branch out into multiple games' <<<"$body" || { echo "$s: the capture of $id is the stub"; return 1; }
	done
}
check "AC4: each issue's capture is its filled document, from a capture commit that lists its id" ac4
# Each issue's depends_on is exactly the list's, and pickman's lobby retirement waits for the portal: c0188 gains P5 and
# Z3, f0187 gains Z3 (c0183's order "Z3 and P5 -> retire the lobby").
ac5() {
	local row k p s d want doc
	for row in $ROWS; do
		k=${row%%:*} row=${row#*:}
		p=${row%%:*} row=${row#*:}
		s=${row%%:*} d=${row#*:}
		doc=$(docof "$p" "$s") || return 1
		want=$(for x in ${d//,/ }; do idof "$x"; done | sort)
		[[ $(depsof "$doc") == "$want" ]] ||
			{ echo "$k ($s): depends_on is [$(depsof "$doc" | tr '\n' ' ')], want [$(tr '\n' ' ' <<<"$want")]"; return 1; }
	done
	# pickman's c0188 (retire-lobby-place) and f0187 (game-over-returns-to-portal), found by slug as the others are
	for row in retire-lobby-place:P5,Z3 game-over-returns-to-portal:Z3; do
		doc=$(docof pickman "${row%%:*}") || return 1
		d=${row#*:}
		for k in ${d//,/ }; do
			depsof "$doc" | grep -qx -- "$(idof "$k")" || { echo "${row%%:*} does not depend on $k"; return 1; }
		done
	done
}
check "AC5: each issue depends on exactly what the list gives it, and c0188 and f0187 wait for the portal" ac5
# sha256:slug of each issue's title line and Problem to Solution, ids masked (experiments/capture.py digests): the
# titles, Problems and Non-goals as prep wrote and reviewed them, so the executor can't land thinner ones.
DIGESTS="027c16d0856ab4b224982bd102d176b20ec623eadd034c7e80174657730daa6a:hiscores-with-revives \
	b6b18a6c35775e488c4748fef846a463fda6f5570d97f4bad4a5a5dc7fccfcd1:switch-to-arcade-hiscores \
	4046fa99d269bdd3560da12f98e794d3ed1770a73c52c1e13d4c3b899f13f8eb:shared-travel \
	c7075f74404694e1b7cd75eaf2de0c2d2cb96c8328b1ac39a02a0c6f515443bc:switch-to-arcade-travel \
	14da0e978089d9102bb75354f91b62707ff45b33e5f695cea92ff0395572a12f:paid-play-and-receipts \
	87c27f7b7bdf160c1192a23a80568dab00377973b52974edb3435bee442f8923:switch-to-arcade-paid-play \
	4a6471d59410f9dfa7a001dc9c2a1fb6f8a9063f89af7ee5d3eb86c1dae26f5a:input-and-look-cores \
	d6fb45e0f2ee4fc873c5e96a3e441e56f9c745b19284c19247abff0bb05e795e:switch-to-arcade-input-cores \
	700b34b90456d1c51a9a3490c477a85f09616cebcb000c060b44b02d221979d8:game-carousel \
	0cf17954c7db61e59a5c01444325204104d2b06bb49d69a91dc12cca15fe140f:boards-per-game \
	44231f9a2e45e59329c3c73ebbc2bb664ae3f727bf711057bb03f78865b0dd6d:free-game-timer \
	b072a8102047c9731f076bf995943c7094762c0e2fde4cc5673b9be987cba23f:play-buttons \
	9310a5ce1a4aad595299290d6e40f91ef587e063ef51d363c09bfe14d0b5169a:portal-start-place \
	2282882341346cf7b95acb4c397f95b87fc41bff8d20dedc71ed6351ef31a5fd:n-place-deploy \
	e948a70973366fa42a10a005a5cd58717544d0396f1ae45e27807ce13ac3391d:arena-maps-growth \
	9db05ae266004226b382858203f5b7549acdf11acd716cbfd5871a350633b6d6:shared-snake-arena \
	50d594beed032f658b74a9ed76947f48aa9336ba7d50d9b85e080f75b195434f:snake-first-person-view \
	9af1e2ed79b15f6fddc8f960e72d1cd666932ce33313c85f30b49c8b3ae42ff3:boost-golden-apples-crumbs \
	3b2d8bc7219b45efc35698491b23d03ed98f42ba28185ca72bd89f300df3e2af:snake-scores-and-revives \
	6b01668e9b75e3d4bdb66b767b994d01a05d211aeb9c5b6dfb04320ae776b620:invaders-classic-rules \
	7a4aef4beb4d7b088dce42242bc5b38c8ad989306465b7d14a9db97d9045d7c7:invaders-two-players \
	a0b923b47c9228bb970349753258072abfb08ef1feae4f8bf93667aebc793683:invaders-cannon-view \
	6e8fb9941aaed8037833b9053a846540b293c6b40e3ec15fdd6452edffad7cb7:invaders-scores-and-revives \
	6a51f2cae019daa93be72c3d70f9b26a9d75253e2c955f1b4a08e840cd128062:asteroids-classic-rules \
	b0d81e872c32efe139e8bf98bb2fe2cacc1653ab5e92a634d4b3d685ffaefeab:asteroids-two-players \
	3693d3d637854594d3f377147f25c50fbda28b0b874b881433baaeb0a26857fe:asteroids-cockpit-view \
	9e338f1ea89fc8b0252bca9784c12ed247ad13c4c160e6e8f75d4d69ee0757f3:asteroids-scores-and-revives"
section() { { grep -m1 '^title: ' "$1"; awk '/^## Design$/{exit} f||/^## Problem$/{f=1; print}' "$1"; } | sed -E 's/[fdcR][0-9]{4}/ID/g'; }
ac6() {
	local row r s p doc got
	for row in $DIGESTS; do
		s=${row#*:} p=
		for r in $ROWS; do
			r=${r#*:}
			[[ $(cut -d: -f2 <<<"$r") == "$s" ]] && p=${r%%:*}
		done
		doc=$(docof "$p" "$s") || return 1
		got=$(section "$doc" | shasum -a 256 | cut -d" " -f1)
		[[ $got == "${row%%:*}" ]] || { echo "$s: the title, Problem or Non-goals differ from prep's"; return 1; }
	done
}
check "AC6: each issue's title, Problem and Non-goals are the ones prep wrote" ac6

finish
