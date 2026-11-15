# d0333: the two zz-execute sentences the fix makes true. Usage: python3 -I apply-docs.py <checkout>
import sys
p = sys.argv[1] + "/z-nile/skills/zz-execute/SKILL.md"
s = open(p).read()
EDITS = [
    (
        "Verify `./zn trace <R-id> --check` passes and commit `trace.md` and the final review files with `./zn commit --phase code-review --model <reviewer model>`.",
        "Commit `trace.md` and the final review files with `./zn commit --phase code-review --model <reviewer model>`, after step 1's commit (an issue document committed after the table makes it stale), then verify that `./zn trace <R-id> --check` passes: before the table is committed the check reports the commits after the finish as added before `trace.md`.",
    ),
    (
        "3. After a fix on a lower layer, `./zn finish` that layer again and `./zn restack <R-id>` before an upper layer is reviewed or `./zn done` lands the stack.",
        "3. After a fix on a lower layer, `./zn finish` that layer again and `./zn restack <R-id>` before an upper layer is reviewed or `./zn done` lands the stack. The same goes for any other commit on a lower layer after its finish (its review files included): only the top layer may carry commits after its finish commit.",
    ),
]
for old, new in EDITS:
    if s.count(old) != 1:
        sys.exit(f"anchor found {s.count(old)} times: {old[:60]}")
    s = s.replace(old, new)
open(p, "w").write(s)
