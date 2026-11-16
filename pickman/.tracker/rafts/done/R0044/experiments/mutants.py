#!/usr/bin/env python3
# R0044 prep mutation check. Usage: python3 mutants.py <prototype worktree>
# Applies each mutant to the prototype (one at a time, restored after), runs d0124's sequestered specs, and
# requires at least one FAIL whose message is an assertion (not a load or syntax error).
import subprocess, sys, pathlib
root = pathlib.Path(sys.argv[1])
H = 'src/shared/Logic/Hiscores/init.luau'
F = 'src/shared/Logic/Flow/init.luau'
L = 'src/shared/Logic/Lobby/init.luau'
S = 'src/server/HiscoreStore.luau'
B = 'src/lobby/server/Boards.luau'
R = 'src/server/Ranks.luau'
FV = 'src/client/FlowView.luau'
LV = 'src/lobby/client/LobbyView.luau'
MUTANTS = [
  ('tie-later-run-first', H, 'return a.at < b.at -- the earlier run keeps a tied place', 'return a.at > b.at'),
  ('no-cap', H, '''	table.sort(out, before)
	while #out > Hiscores.N do''', '''	table.sort(out, before)
	while #out > Hiscores.N + 5 do'''),
  ('no-id-dedupe', H, 'if validRun(e) and not seen[e.id] then', 'if validRun(e) then'),
  ('runid-no-server', H, ':{string.format("%d", run)}:{job}`', ':{string.format("%d", run)}`'),
  ('topRun-skips-valid', H, 'if not Hiscores.valid(attempt) or not whole(unix) or not whole(run) then', 'if not whole(unix) or not whole(run) then'),
  ('validRun-skips-at', H, '''		and whole(e.at)
''', '\n'),
  ('topRows-rank-off-by-one', H, 'table.insert(out, { rank = i, name = e.name,', 'table.insert(out, { rank = i + 1, name = e.name,'),
  ('no-missed', H, 'missed = if place == nil then Hiscores.N else nil', 'missed = nil'),
  ('one-attempt', H, 'for _, delay in Hiscores.attemptDelays(policy) do', 'for _, delay in { 0 } do'),
  ('best-accepts-level-0', H, 'if not whole(companion.level) or companion.level < 1 then', 'if not whole(companion.level) then'),
  ('fresh-inclusive', H, 'now >= at and now - at < ttl', 'now >= at and now - at <= ttl'),
  ('missLine-accepts-0', F, 'if type(top) ~= "number" or top < 1 or top ~= math.floor(top)', 'if type(top) ~= "number" or top < 0 or top ~= math.floor(top)'),
  ('missLine-wording', F, 'return `NOT IN THE ALL-TIME TOP {string.format("%d", top)}`', 'return `NOT IN THE TOP {string.format("%d", top)}`'),
  ('hearMiss-drops-next', F, '''			pending = nil,
			pendingRun = run,
			pendingMissed = top,''', '''			pending = view.pending,
			pendingRun = view.pendingRun,
			pendingMissed = view.pendingMissed,'''),
  ('follow-drops-pending-miss', F, 'missed = if mine then view.pendingMissed else nil,', 'missed = nil,'),
  ('shown-ignores-miss', F, 'return Flow.rankLine(view.rank) or Flow.missLine(view.missed)', 'return Flow.rankLine(view.rank)'),
  ('hearMiss-keeps-rank', F, '''		return {
			over = view.over,
			rank = nil,
			missed = top,''', '''		return {
			over = view.over,
			rank = view.rank,
			missed = top,'''),
  ('hearMiss-before-overlay', F, '''	if run == view.over and view.over >= 1 then
		if not gameOver then
			return view
		end
		return {
			over = view.over,
			rank = nil,''', '''	if run == view.over and view.over >= 1 then
		return {
			over = view.over,
			rank = nil,'''),
  ('bestLine-any-board', L, 'if id ~= "all" or type(best) ~= "table" then', 'if type(best) ~= "table" then'),
  ('text-best-first', L, 'return `{body}\\n{line}`', 'return `{line}\\n{body}`'),
  ('store-no-jobid', S, '''				run,
				(game :: any).JobId
			)''', '''				run,
				nil
			)'''),
  ('ranks-drops-miss', R, 'remote:FireClient(player, run, rank, missed)', 'remote:FireClient(player, run, rank)'),
  ('flowview-ignores-miss', FV, 'rankView = Flow.hearMiss(Flow.hearRank(rankView, run, place, gameOverUp), run, missed, gameOverUp)', 'rankView = Flow.hearRank(rankView, run, place, gameOverUp)'),
  ('lobbyview-no-best', LV, 'list.Text = Lobby.text(drawn, highlight, best, shown)', 'list.Text = Lobby.lines(drawn, highlight)'),
  ('boards-no-list', B, '''			local listed = Hiscores.topRows(list)
			if listed ~= nil then
				return listed
			end''', ''),
  ('boards-list-error-falls-back', B, '''			local list = DataStoreService:GetDataStore(Hiscores.TOP_STORE, Hiscores.TOP_SCOPE)
				:GetAsync(Hiscores.TOP_KEY)''', '''			local _, list = pcall(function()
				return DataStoreService:GetDataStore(Hiscores.TOP_STORE, Hiscores.TOP_SCOPE):GetAsync(Hiscores.TOP_KEY)
			end)'''),
  ('boards-best-every-board', B, '''		if id == "all" then
			readBest(player, now)
		end''', '''		readBest(player, now)'''),
  ('boards-send-best-every-board', B, 'local held = if id == "all" then bests[tostring(player.UserId)] else nil', 'local held = bests[tostring(player.UserId)]'),
  ('boards-no-best-cache', B, 'if not Hiscores.needsRead(held, now, Hiscores.CACHE_TTL) then', 'if false then'),
  ('boards-best-kept-after-leave', B, '''		bests[tostring(player.UserId)] = nil
	end)''', '''	end)'''),
  ('boards-one-best-for-all', B, '''		local userId = tostring(player.UserId)
		local held = bests[userId]''', '''		local userId = tostring(player.UserId)
		local held = bests["all"]'''),
  ('best-at-now', H, '''		level = row.level,
		at = 0,''', '''		level = row.level,
		at = 2 ^ 40,'''),
  ('add-before-stored-copy', H, '''	local all = ordered(list)
	table.insert(all, run)''', '''	local all = ordered(list)
	table.insert(all, 1, run)'''),
  ('no-merge', H, 'local made, at = Hiscores.mergeRun(base, entry, bests or {})', 'local made, at = Hiscores.mergeRun(base, entry, if type(old) == "table" then {} else bests or {})'),
  ('create-without-bests', H, 'blind = type(old) ~= "table" and bests == nil', 'blind = false'),
  ('write-when-unchanged', H, '''		if type(old) == "table" and sameIds(ordered(old), made) then
			return nil -- nothing changes
		end''', ''),
  ('skip-budget', H, '''		if affords(io, "get", "set") then
			local _, err = top.update(transform)''', '''		if true then
			local _, err = top.update(transform)'''),
  ('drivetop-nil-only', H, '''	if run == nil or not validRun(run) then
		return unknown
	end
	local entry = run :: TopRun
	local place''', '''	if run == nil then
		return unknown
	end
	local entry = run :: TopRun
	local place'''),
  ('best-accepts-negative', H, 'if type(companion) ~= "table" or not whole(companion.score) or companion.score < 0 then', 'if type(companion) ~= "table" or not whole(companion.score) then'),
  ('needsRead-ignores-reading', H, 'return not held.reading and not Hiscores.fresh(held.at, now, ttl)', 'return not Hiscores.fresh(held.at, now, ttl)'),
  ('store-top-first', S, '''			local result = Hiscores.drive(io, attempt, now, Hiscores.RETRY)
			local placed = Hiscores.driveTop(top, io, entry, result.rows, Hiscores.RETRY)''', '''			local placed = Hiscores.driveTop(top, io, entry, Hiscores.readAll(io, now), Hiscores.RETRY)
			Hiscores.drive(io, attempt, now, Hiscores.RETRY)'''),
  ('store-no-bests', S, 'Hiscores.driveTop(top, io, entry, result.rows, Hiscores.RETRY)', 'Hiscores.driveTop(top, io, entry, {}, Hiscores.RETRY)'),
  ('store-drive-rank', S, 'listener(userId, run, placed.place, placed.missed)', 'listener(userId, run, result.rank, placed.missed)'),
  ('boards-no-inflight-mark', B, '''		local mark = { at = now, best = if held then held.best else nil, reading = true }
		bests[userId] = mark''', '''		local mark = { at = now, best = if held then held.best else nil, reading = true }'''),
  ('boards-store-after-leave', B, 'if bests[userId] == mark and player.Parent ~= nil then', 'if true then'),
  ('boards-best-error-kept', B, 'best = if ok then Hiscores.best(got) else nil, reading = false', 'best = if ok then Hiscores.best(got) else (if held then held.best else nil), reading = false'),
  ('commit-drops-run', H, 'run = if named then attempt.run else nil,', 'run = nil,'),
  ('rows-drop-run', H, 'run = if named then companion.run else nil,', 'run = nil,'),
  ('rows-no-validate', H, 'local named = type(companion.run) == "string" and companion.run ~= "" and whole(companion.at)', 'local named = companion.run ~= nil'),
  ('bestRun-ignores-row-id', H, 'if type(row.run) == "string" and row.run ~= "" and whole(row.at) then', 'if false then'),
  ('bestRun-no-validate', H, 'if type(row.run) == "string" and row.run ~= "" and whole(row.at) then', 'if row.run ~= nil then'),
  ('bestRun-named-at-zero', H, '''			level = row.level,
			at = row.at :: number,''', '''			level = row.level,
			at = 0,'''),
  ('store-attempt-unnamed', S, 'run = if entry then entry.id else nil,', 'run = nil,'),
  ('marker-drops-held-best', B, 'local mark = { at = now, best = if held then held.best else nil, reading = true }', 'local mark = { at = now, best = nil, reading = true }'),
  ('best-id-no-score', H, 'id = `best:{row.userId}:{string.format("%d", score)}:{string.format("%d", row.level)}`,', 'id = `best:{row.userId}`,'),
  ('best-uses-ordered-score', H, 'local score = row.runScore', 'local score = row.score'),
  ('rows-no-runScore', H, '''runScore = if whole(companion.score) and companion.score >= 0
						then companion.score
						else nil,''', 'runScore = entry.score,'),
  ('best-without-score-falls-back', H, '''	if type(score) ~= "number" or not whole(score) or score < 0 then
		return nil
	end''', '''	if type(score) ~= "number" or not whole(score) or score < 0 then
		score = row.score
	end'''),
  ('cover-by-value', H, '''		local made = Hiscores.bestRun(row)
		if made ~= nil then''', '''		local made = Hiscores.bestRun(row)
		local seen = false
		for _, e in all do
			if e.userId == row.userId and e.score >= row.score then
				seen = true
			end
		end
		if made ~= nil and not seen then'''),
  ('place-kept-across-calls', H, '''		place = nil
		blind = type(old) ~= "table" and bests == nil
		if blind then
			return nil
		end
		local base: { TopRun } = if type(old) == "table" then old else {}
		local made, at = Hiscores.mergeRun(base, entry, bests or {})
		place = at''', '''		blind = type(old) ~= "table" and bests == nil
		if blind then
			return nil
		end
		local base: { TopRun } = if type(old) == "table" then old else {}
		local made, at = Hiscores.mergeRun(base, entry, bests or {})
		place = place or at'''),
  ('blind-sticky', H, 'blind = type(old) ~= "table" and bests == nil', 'blind = blind or (type(old) ~= "table" and bests == nil)'),
]
SPECS = sorted(str(p) for p in (root / 'tracker/issues/d0124/acceptance').glob('*.spec.luau'))
bad = []
for name, rel, old, new in MUTANTS:
    path = root / rel
    src = path.read_text()
    if src.count(old) != 1:
        bad.append(f'{name}: anchor found {src.count(old)} times'); continue
    path.write_text(src.replace(old, new))
    try:
        out = subprocess.run(['lune', 'run', 'tests/run', '--'] + SPECS, cwd=root, capture_output=True, text=True).stdout
    finally:
        path.write_text(src)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    load = [l for l in fails if 'could not load' in l]
    if not fails or load:
        bad.append(f'{name}: {"survived" if not fails else "load error"}')
    else:
        first = fails[0].split(' :: ', 1)[-1]
        print(f'killed {name}: {len(fails)} case(s), e.g. "{first}"')
print('\n'.join(bad) if bad else f'ALL {len(MUTANTS)} MUTANTS KILLED ON ASSERTIONS')
sys.exit(1 if bad else 0)
