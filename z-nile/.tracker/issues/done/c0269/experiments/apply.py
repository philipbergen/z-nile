import pathlib,sys
R=pathlib.Path(sys.argv[1]); A=R/"z-nile/tests/acceptance"
subs={"c0074/done-gate.spec.luau":[("`tracker.sh done` runs the full gate on the final tree","`tracker.sh done` runs the affected gate on the final tree"),('t.spec("c0800 done runs the full gate after promotion"','t.spec("c0800 done runs the affected gate after promotion"'),('it("done runs the full gate on the promoted, moved tree, then commits"','it("done runs the affected gate on the promoted, moved tree, then commits"'),('it("the gate decision: full, unless inside a spec run without the switch"','it("the gate decision: affected, unless inside a spec run without the switch"')],
"c0080/consequences.spec.luau":[("(so done skips the full gate, c0800)","(so done skips the gate, c0800)")]}
for f,ss in subs.items():
    p=A/f; t=p.read_text()
    for o,n in ss:
        assert t.count(o)==1,(f,o); t=t.replace(o,n)
    p.write_text(t)
tsv=R/"z-nile/tests/inputs.tsv"; s=tsv.read_text()
if not s.endswith("\n"): s+="\n"
tsv.write_text(s+"tests/acceptance/c0269/titles.spec.luau\tz-nile/tests/\n")
