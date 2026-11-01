#!/usr/bin/env bash
# Acceptance checks for c0190. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home

# Work outside `check` is limited to variables and function definitions; every read runs inside `check`.
# Every criterion reads the capture as it landed: `./zn capture <id>` (the newest `tracker: new` commit on origin/main
# whose subject lists the id), never the working tree, which later preps edit (design review 002 F3). They run at done
# and never again, so there is no promoted spec: one in z-nile would read six other projects' documents (zz-test lesson
# specs-pin-only-their-own-project, design review 002 F7).
# key:project:slug:depends_on (keys of this list or ids) of every listed issue, in the list's order (c0190 Design item 2)
ROWS="A1:arcade:hiscores-with-revives:c0185 \
	K1:pickman:switch-to-arcade-hiscores:A1 \
	A2:arcade:shared-travel:c0185 \
	K2:pickman:switch-to-arcade-travel:A2 \
	A3:arcade:paid-play-and-receipts:c0185 \
	K3:pickman:switch-to-arcade-paid-play:A3,f0145,f0186 \
	A4:arcade:input-and-look-cores:c0185 \
	K4:pickman:switch-to-arcade-input-cores:A4 \
	P1:portal:game-carousel:A2,A3 \
	P2:portal:boards-per-game:A1,P1 \
	P3:portal:free-game-timer:A3,P1 \
	P4:portal:play-buttons:A2,A3,P1 \
	P5:portal:portal-start-place:Z3,P2,P4,K3 \
	Z3:portal:n-place-deploy:P2,P4 \
	S1:snake:arena-maps-growth:c0184 \
	S2:snake:shared-snake-arena:S3,A2,A3 \
	S3:snake:snake-first-person-view:S1,S4,A2,A3,A4 \
	S4:snake:boost-golden-apples-crumbs:S1 \
	S5:snake:snake-scores-and-revives:S1,S2,S3,A1,A2,A3 \
	I1:invaders:invaders-classic-rules:c0184 \
	I2:invaders:invaders-two-players:c0184 \
	I3:invaders:invaders-cannon-view:I1,I2,A2,A3,A4,P5 \
	I4:invaders:invaders-scores-and-revives:I1,I3,A1,A2,A3 \
	T1:asteroids:asteroids-classic-rules:c0184 \
	T2:asteroids:asteroids-two-players:c0184 \
	T3:asteroids:asteroids-cockpit-view:T1,T2,A2,A3,A4,I3 \
	T4:asteroids:asteroids-scores-and-revives:T1,T3,A1,A2,A3"
# the document of the one issue of project $1 with slug $2 (`<id>/<id>.md` in its root's backlog, active/ or done/)
docof() {
	local f hits=""
	for f in "$ZN_ROOT/$1"/.tracker/issues/*/*.md "$ZN_ROOT/$1"/.tracker/issues/*/*/*.md; do
		[[ -f $f && $(basename "$(dirname "$f")") == "$(basename "$f" .md)" ]] || continue
		grep -qx -- "slug: $2" "$f" && hits="$hits$f"$'\n'
	done
	[[ -n $hits && ${hits%$'\n'} != *$'\n'* ]] || { echo "$1 $2: not exactly one issue" >&2; return 1; }
	printf "%s" "$hits"
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
# `./zn capture <id>`: a header line, then the document as captured
capof() { "$ZN_ROOT/zn" capture "$1" || { echo "zn capture $1 failed" >&2; return 1; }; }
# the sorted ids of the depends_on line of a document on stdin
depsof() { grep -m1 '^depends_on:' | grep -oE '[fdcR][0-9]{4}' | sort; }
# the slug, the expected type and the project of each row
fields() { local r=${1#*:}; P=${r%%:*} r=${r#*:}; SLUG=${r%%:*} DEPS=${r#*:}; }
ac1() {
	local row doc id want
	for row in $ROWS; do
		fields "$row"
		doc=$(docof "$P" "$SLUG") || return 1
		id=$(basename "$doc" .md)
		want=$(cut -c1 <<<"${row%%:*}")
		case $want in K | Z) want=c ;; *) want=f ;; esac
		[[ ${id:0:1} == "$want" ]] || { echo "${row%%:*} ($SLUG): $id is not a $want issue"; return 1; }
	done
}
check "AC1: each listed issue exists once in its project, found by its slug, with its type" ac1
# One batched land: every issue's capture is the same commit, whose subject lists its id, with no marker, holding the
# filled document (z-ticket lesson capture-subject-lists-every-id).
ac2() {
	local row id body head sha first=""
	for row in $ROWS; do
		fields "$row"
		id=$(idof "${row%%:*}") || return 1
		body=$(capof "$id") || return 1
		head=${body%%$'\n'*}
		[[ $head == "capture "*" tracker: new "* && $head != *"(no capture commit"* && $head != *"(ambiguous"* &&
			$head != *"(history before"* ]] || { echo "$SLUG: capture header: $head"; return 1; }
		[[ " ${head#* tracker: new } " == *" $id "* ]] || { echo "$SLUG: $id not in the subject: $head"; return 1; }
		sha=$(cut -d" " -f2 <<<"$head")
		[[ -z $first || $sha == "$first" ]] || { echo "$SLUG: captured by $sha, the others by $first"; return 1; }
		first=$sha
		grep -qF -- '"I want to branch out into multiple games' <<<"$body" || { echo "$SLUG: the capture of $id is the stub"; return 1; }
	done
}
check "AC2: all the issues were captured by one land, whose subject lists every id, each filled, not a stub" ac2
# At the capture, each issue's depends_on is exactly the list's, and pickman's lobby retirement waits for the portal:
# retire-lobby-place (c0188) gains P5, Z3 and K3, game-over-returns-to-portal (f0187) gains Z3, both read at the same commit.
ac3() {
	local row id want sha="" k hit p=pickman
	for row in $ROWS; do
		fields "$row"
		id=$(idof "${row%%:*}") || return 1
		want=$(for k in ${DEPS//,/ }; do idof "$k"; done | sort)
		body=$(capof "$id") || return 1
		sha=$(head -1 <<<"$body" | cut -d" " -f2)
		[[ $(tail -n +2 <<<"$body" | depsof) == "$want" ]] ||
			{ echo "${row%%:*} ($SLUG): captured depends_on is [$(tail -n +2 <<<"$body" | depsof | tr '\n' ' ')], want [$(tr '\n' ' ' <<<"$want")]"; return 1; }
	done
	for row in retire-lobby-place:P5,Z3,K3 game-over-returns-to-portal:Z3; do
		hit=$(git -C "$ZN_ROOT" grep -l -e "^slug: ${row%%:*}$" "$sha" -- "$p/.tracker/issues" | grep -E '/([fdc][0-9]{4})/\1\.md$')
		[[ -n $hit && $hit != *$'\n'* ]] || { echo "${row%%:*}: not exactly one issue at $sha"; return 1; }
		k=${row#*:}
		for k in ${k//,/ }; do
			git -C "$ZN_ROOT" show "$hit" | depsof | grep -qx -- "$(idof "$k")" || { echo "${row%%:*} does not depend on $k at $sha"; return 1; }
		done
	done
}
check "AC3: as captured, each issue depends on exactly what the list gives it, and c0188 and f0187 wait for the portal" ac3
# sha256:slug of each issue's title line and its text from Problem to Design, each of the 27 new ids written as its key
# (they are allocated at capture time; every other id stays literal, so a wrong sibling id fails) (experiments/capture.py
# digests, on prep's prototype): the titles, Problems and Non-goals prep wrote and the review read.
DIGESTS="b342322ab4a3588e457d2020ac1dca127d61a9aee49fa19add82774e0ba6d1b3:hiscores-with-revives \
	5870033e8971df6c3d96f17f18c545875d28475c6b0187d2cc4f4244ec788a01:switch-to-arcade-hiscores \
	0cef8b1dde871e8ef865abe749d9028a6a4bbe1079ce6f8a65501a8148213df4:shared-travel \
	397c1382c52e9c5a6ebd4e4251f998b83e20a08f62a857d3b547902191b05058:switch-to-arcade-travel \
	4056af7e5faf53f272d412a87358bb2eb26fe0d0b9935eb405030bba478c8656:paid-play-and-receipts \
	2220d871a2a9d1b321f74298cb21a69e4f0291b85cc57b46ae14e3d6308c2613:switch-to-arcade-paid-play \
	aa990726e6f2a5ea93cc98aa59fd3a2ab50550e203750690288c970ffc94cf57:input-and-look-cores \
	cf60137b49ac1b55fd03ee3cebee21383d8fabd662a66ef1f6c6c8bf74415453:switch-to-arcade-input-cores \
	0f6dd6bb0eedbc4f6de7c2c912a2c008463fe848c1afee8c24c3fa77003f4040:game-carousel \
	167f67a76f385a0835a7f6641a64d429a354ca4b5deeb2e33d8b0e6937469803:boards-per-game \
	fb219522df9f6dd4582bad87b8e605dad4fd2ca61598a5590bbfebe24caf22b8:free-game-timer \
	fa055c97d3b780b48bb9f1935297fe083a8f958cd42bbcca44a4ce6f4b76416b:play-buttons \
	ee66d97293ce20f2d8cdfcf6fa2a983d7171c44ead2353ce184a64bbab59b557:portal-start-place \
	4c0bb5b2b39c8a352c92abcc9bdc07989d532fd711f36b48f0bc76d0b9959956:n-place-deploy \
	f9e09887a117b4b8e3ab1bb3e04c47d207eb4d6639e0953783702b6a219a73cb:arena-maps-growth \
	abd94f64ddd24d48890779e034d14193170920fdf8338b47775aff41b49348e9:shared-snake-arena \
	29af9cb343ceab4052673557a08562764eb0307426466aa4a60ba7700fe4e478:snake-first-person-view \
	38536e4bb6dda866074d74da00648e7d652d8ebbd7454113a7f92807f5100c6c:boost-golden-apples-crumbs \
	5d5505ba1a00326a418476bade0c2737eb0df9864e5a583b026f9a9cfc324aea:snake-scores-and-revives \
	a3736b06dae80450f0f661cb7776b4d0c5ad5d3ffa8e8f03a7e4ac6fc192cb58:invaders-classic-rules \
	aec93b189b1ead601af93b575fac809baffc9f392fab4bd6c15583919048b301:invaders-two-players \
	479281c79ac2701f5035f1408446b63f2e7ff3039bd0f85e30962d4702e88826:invaders-cannon-view \
	ac0e798a85cbfe9c004b6a4d3a7b2f6ec257d5c5134e0d80e8f4b9d18f3d1a98:invaders-scores-and-revives \
	28095e203f3e2818990f6640d95d5b70a142e7f54f9a411f231968d85063f262:asteroids-classic-rules \
	c3db791985dff1fdadf4c4ec96ab135c9528824304c879c30c186b1d5da541f0:asteroids-two-players \
	ac8b284871a2cfdff1adbaf4b063efc08116d51ba7a0b9c86f7fb07003781df6:asteroids-cockpit-view \
	4957fc64e49874864abd8eab7595ebafd4666ab1ea2c9632f81225be2a64ff15:asteroids-scores-and-revives"
section() { { grep -m1 '^title: '; } <<<"$1"; awk '/^## Design$/{exit} f||/^## Problem$/{f=1; print}' <<<"$1"; }
ac4() {
	local row r s p doc body got id keys=()
	for r in $ROWS; do
		id=$(idof "${r%%:*}") || return 1
		keys+=(-e "s/$id/${r%%:*}/g")
	done
	for row in $DIGESTS; do
		s=${row#*:} p=
		for r in $ROWS; do
			fields "$r"
			[[ $SLUG == "$s" ]] && p=$P
		done
		doc=$(docof "$p" "$s") || return 1
		body=$(capof "$(basename "$doc" .md)") || return 1
		got=$(section "$(tail -n +2 <<<"$body")" | sed "${keys[@]}" | shasum -a 256 | cut -d" " -f1)
		[[ $got == "${row%%:*}" ]] || { echo "$s: the captured title, Problem or Non-goals differ from prep's"; return 1; }
	done
}
check "AC4: as captured, each issue's title, Problem and Non-goals are the ones prep wrote" ac4

finish
