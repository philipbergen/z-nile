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
	P1:portal:game-carousel:A3 \
	P2:portal:boards-per-game:A1,P1 \
	P3:portal:free-game-timer:A3,P1 \
	P4:portal:play-buttons:A2,A3,P1 \
	P5:portal:portal-start-place:Z3,P2,P4 \
	Z3:portal:n-place-deploy:P2,P4 \
	S1:snake:arena-maps-growth:c0184 \
	S2:snake:shared-snake-arena:S3,A2,A3 \
	S3:snake:snake-first-person-view:S1,A2,A3,A4 \
	S4:snake:boost-golden-apples-crumbs:S1 \
	S5:snake:snake-scores-and-revives:S1,A1,A2,A3 \
	I1:invaders:invaders-classic-rules:c0184 \
	I2:invaders:invaders-two-players:c0184 \
	I3:invaders:invaders-cannon-view:I1,I2,A2,A3,A4,P4,Z3 \
	I4:invaders:invaders-scores-and-revives:I1,A1,A2,A3 \
	T1:asteroids:asteroids-classic-rules:c0184 \
	T2:asteroids:asteroids-two-players:c0184 \
	T3:asteroids:asteroids-cockpit-view:T1,T2,A2,A3,A4,I3 \
	T4:asteroids:asteroids-scores-and-revives:T1,A1,A2,A3"
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
# retire-lobby-place (c0188) gains P5 and Z3, game-over-returns-to-portal (f0187) gains Z3, both read at the same commit.
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
	for row in retire-lobby-place:P5,Z3 game-over-returns-to-portal:Z3; do
		hit=$(git -C "$ZN_ROOT" grep -l -e "^slug: ${row%%:*}$" "$sha" -- "$p/.tracker/issues" | grep -E '/([fdc][0-9]{4})/\1\.md$')
		[[ -n $hit && $hit != *$'\n'* ]] || { echo "${row%%:*}: not exactly one issue at $sha"; return 1; }
		k=${row#*:}
		for k in ${k//,/ }; do
			git -C "$ZN_ROOT" show "$hit" | depsof | grep -qx -- "$(idof "$k")" || { echo "${row%%:*} does not depend on $k at $sha"; return 1; }
		done
	done
}
check "AC3: as captured, each issue depends on exactly what the list gives it, and c0188 and f0187 wait for the portal" ac3
# sha256:slug of each issue's title line and its text from Problem to Design, ids masked (experiments/capture.py
# digests, on prep's prototype): the titles, Problems and Non-goals prep wrote and the review read.
DIGESTS="37a5294e0416314616640e4d6f731e45a74ea8ddc85883f5817e3e224006b456:hiscores-with-revives \
	c73177cbf9fd39431e6fe446ee3d38e6adc495637f866b0965029a4e4e945c51:switch-to-arcade-hiscores \
	d21be73c8199f215d796efedd043821f4ee073e13fd98e9ff4f031f38d03e835:shared-travel \
	32307ea4e0e1a4f62a57d65a2d51d22c50ecfa26a782395e9a424a62277471df:switch-to-arcade-travel \
	8bec5af007de1f48439aabac9395b9325f49cdfece73b08e8e6e4eec535f9199:paid-play-and-receipts \
	eae47258031c4ab09253115ff4c1bab74be061036849ed7a5bce3323dfa52fef:switch-to-arcade-paid-play \
	bea7a233a6b9c41cd592c6ccaf524674c552979ad6c2a4186912bcd149f1a140:input-and-look-cores \
	419bda96068dd6e43f6ce959028fba18abc5fc8793549e8c936c03d21a9a8913:switch-to-arcade-input-cores \
	1ec094b54fe3cd8351c1069d1c53e4ee57916d4c44f161890fd7802b548bfaae:game-carousel \
	4a33a33bfab6d3ec84df46423f0dee71dbba189ca906cff58ddc4876a084ca4f:boards-per-game \
	c39ef37ecf6a909d745a4b1912cfd88fa21c9595d6ce88085da539d7e421b14a:free-game-timer \
	15c34cb31ca26edc812c821a515734b227afe54a8cb42beb1f6d3a071e99d352:play-buttons \
	e40b80fb16e3dfd2d6f618621ed2439342cb455a7a239a1571f7237070dcb0dd:portal-start-place \
	68654c92b467067bb9bba762c7390fdad6e40c47d90200eb27dabdcb22281757:n-place-deploy \
	4993e6c4948e004f6cf57bb0d6f39badc7cf350a0d7727db1f82a99250b1caae:arena-maps-growth \
	95096209e5dc02cccf0b57d2f69bd3104437a3fe44925e8818608e8dfe06e17a:shared-snake-arena \
	33536be8b252c770418f8b4d005071dfeacc26b071a3381a9bca1f61c592fa6f:snake-first-person-view \
	c343809b48b90a3de678bd0909b91554195be4be141716524d4bff0cf195f364:boost-golden-apples-crumbs \
	853f5ef1e65fb938cd9d2ce6eaec2948e1559af6f3f86be3dc3b240f7dd3b710:snake-scores-and-revives \
	aae737a5fe971fe02bc3e5fabbda6414a133ce6cdc28f79f7217e00ea9e46c38:invaders-classic-rules \
	e4bed603104248ae5164953d38acdda7e0be29f3b180ad7fc4532704182202db:invaders-two-players \
	77d4d33ca1e842a1fc26920876802ee5de65113de9a28471dfca07d056fa98e6:invaders-cannon-view \
	5c6150e5eec08efc89167f6fa88041c2ae6947d705ce025e291aa144258a0a08:invaders-scores-and-revives \
	db084f042be5434840327c2bb73f250bffb0388f2e198cd42c723d671aeb6639:asteroids-classic-rules \
	f38dba8159b2c85ed08f9bb0095bfc53335e80bab01f26d783aa1016a7ce1cc4:asteroids-two-players \
	f1554ec5b03942bb8ad15873b5900db36557d41f26c895a8f2b1581e0d0cd65e:asteroids-cockpit-view \
	6f225fdede8718abfb45524f3c67ef767b266c702f5f79b40d5dd5cb9ece0a98:asteroids-scores-and-revives"
section() { { grep -m1 '^title: '; } <<<"$1"; awk '/^## Design$/{exit} f||/^## Problem$/{f=1; print}' <<<"$1"; }
ac4() {
	local row s p doc body got
	for row in $DIGESTS; do
		s=${row#*:} p=
		for r in $ROWS; do
			fields "$r"
			[[ $SLUG == "$s" ]] && p=$P
		done
		doc=$(docof "$p" "$s") || return 1
		body=$(capof "$(basename "$doc" .md)") || return 1
		got=$(section "$(tail -n +2 <<<"$body")" | sed -E 's/[fdcR][0-9]{4}/ID/g' | shasum -a 256 | cut -d" " -f1)
		[[ $got == "${row%%:*}" ]] || { echo "$s: the captured title, Problem or Non-goals differ from prep's"; return 1; }
	done
}
check "AC4: as captured, each issue's title, Problem and Non-goals are the ones prep wrote" ac4

finish
