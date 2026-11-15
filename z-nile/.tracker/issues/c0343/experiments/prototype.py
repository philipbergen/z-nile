import pathlib, sys
root = pathlib.Path(sys.argv[1])
def edit(rel, pairs):
    p = root / rel; t = p.read_text()
    for a, b, n in pairs:
        assert t.count(a) == n, (rel, a, t.count(a))
        t = t.replace(a, b)
    p.write_text(t)
edit("z-nile/engine/layergit.luau", [(
'''			name == "trace.md"
			or name == `{raftId}.md`
''', '''			name == "trace.md"
			or name == "spend.md" -- c0343: `./zn commit` rewrites the raft's ledger in every commit
			or name == `{raftId}.md`
''', 1)])
edit("z-nile/engine/trace.luau", [(
'''			name == "trace.md"
			or name == `{raftId}.md`
''', '''			name == "trace.md"
			or name == "spend.md" -- c0343: `./zn commit` rewrites the raft's ledger in every commit
			or name == `{raftId}.md`
''', 1), (
'''		if
			name == `{raftId}.md`
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
''', '''		if
			name == `{raftId}.md`
			or name == "spend.md" -- c0343: the commit that carries the final review rewrites the ledger too
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
''', 1)])
