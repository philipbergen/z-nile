# c0256 mutation check. Builds its OWN scratch repository (a standalone clone of the checkout this file is in, in a fresh
# tempfile.mkdtemp outside any checkout), applies prototype.patch and the acceptance specs to it, runs the baseline and
# then each mutant of the Rules table, and removes the scratch folder. It takes no target and writes nothing in the real
# repository (c0269's lesson: a script that moves refs needs its own clone). Usage, from anywhere:
#   ./zn run --time 3000 -- python3 <this file> [fast|slow|all] [<mutant id>...]
# `fast` runs the pure mutants against exchange.spec (seconds), `slow` the dispatcher mutants against retry.spec (about
# 2.5 minutes each), `all` both. Output: one line per mutant, "red" when the spec failed on an assertion (the mutant
# is killed), "SURVIVED" when it passed, "NOT APPLIED" when its text was not found exactly once.
import pathlib, re, shutil, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
ISSUE = HERE.parent
SRC = pathlib.Path(subprocess.run(["git", "-C", str(HERE), "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip())
WHICH = sys.argv[1] if len(sys.argv) > 1 else "fast"
ONLY = set(sys.argv[2:])  # optional mutant ids: run just these

EX = "z-nile/engine/exchange.luau"
DP = "z-nile/engine/dispatcher.luau"
DI = "z-nile/engine/dispatch.luau"
MN = "z-nile/engine/main.luau"
BR = "z-nile/engine/broker.luau"
SPEC_E = ".tracker/issues/c0256/acceptance/exchange.spec.luau"
ACC = ".tracker/issues/c0256/acceptance/"
SPEC_R = ACC + "retry.spec.luau"
SPEC_S = ACC + "step.spec.luau"
SPEC_C = ACC + "capture.spec.luau"
SPEC_U = ACC + "rounds.spec.luau"

# (id, what it breaks, file, old text (exactly once), new text, spec)
FAST = [
    ("M1", "a two-digit number in a file name", EX, '"%03d-%s.md"', '"%02d-%s.md"', SPEC_E),
    ("M2", "the body of an answer is trimmed when read", EX, "date = date :: string, step = nil, body = body :: string }", 'date = date :: string, step = nil, body = (string.gsub(body :: string, "%s+$", "")) }', SPEC_E),
    ("M3", "a newline is added when rendered", EX, 'else ""}\\n{body}`', 'else ""}\\n{body}\\n`', SPEC_E),
    ("M4", "any date line is accepted", EX, "(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ)", "([^\\n]+)", SPEC_E),
    ("M5", "a gap in the numbers is skipped", EX, "\t\tif name == nil then\n\t\t\treturn nil,", "\t\tif name == nil and false then\n\t\t\treturn nil,", SPEC_E),
    ("M6", "a repeated number is accepted", EX, "if byN[got.n] ~= nil then", "if false then", SPEC_E),
    ("M7", "two questions in a row are accepted", EX, 'elseif same(kind, "question") and same(before, "question") then', "elseif false then", SPEC_E),
    ("M8", "an answer with no question before it is accepted", EX, 'elseif same(kind, "answer") and not same(before, "question") then', "elseif false then", SPEC_E),
    ("M9", "an ask that is not first is accepted (order)", EX, 'if same(kind, "ask") and n ~= 1 then\n\t\t\treturn nil, `{name}', 'if false then\n\t\t\treturn nil, `{name}', SPEC_E),
    ("M10", "a stray file name is skipped", EX, "\t\t\tif got == nil then\n\t\t\t\treturn nil, `{name} is not an exchange file (NNN-ask|question|answer.md)`\n\t\t\tend\n\t\t\tif byN[got.n]", "\t\t\tif got == nil then\n\t\t\t\tgot = { n = 0, kind = \"ask\" }\n\t\t\tend\n\t\t\tif byN[got.n]", SPEC_E),
    ("M11", "a file being written (a dot name) is counted", EX, 'if string.sub(name, 1, 1) ~= "." then', "if true then", SPEC_E),
    ("M12", "the exchange is full at 1000", EX, "exchange.MAX = 999", "exchange.MAX = 1000", SPEC_E),
    ("M13", "the prompt paragraph is never added", DI, "if p.exchange and #p.exchange > 0 then", "if false then", SPEC_E),
    ("M14", "the prompt paragraph is added with nothing exchanged", DI, "if p.exchange and #p.exchange > 0 then", "if p.exchange then", SPEC_E),
    ("M15", "the prompt joins the names without a space", DI, 'local files = table.concat(p.exchange :: { string }, ", ")', 'local files = table.concat(p.exchange :: { string }, ",")', SPEC_E),
    ("M16", "an ask that is not first is accepted (next)", EX, 'if same(kind, "ask") and n ~= 1 then\n\t\treturn nil, "an ask', 'if false then\n\t\treturn nil, "an ask', SPEC_E),
    ("M17", "a question without its step line is accepted", EX, "if step == nil or body == nil then", "if false then", SPEC_E),
    ("M18", "an ask with a step line is accepted", EX, 'local body = string.match(rest :: string, "^\\n(.*)$")', 'local body = string.match(rest :: string, "^[^\\n]*\\n*(.*)$")', SPEC_E),
    ("M19", "the seal ignores a changed file", EX, "elseif now[name] ~= seal[name] then", "elseif false then", SPEC_E),
    ("M20", "the seal ignores an added file", EX, "if seal[name] == nil then\n\t\t\treturn `added", "if false then\n\t\t\treturn `added", SPEC_E),
    ("M21", "the seal ignores a removed file", EX, "elseif now[name] == nil then\n\t\t\treturn `removed", "elseif false then\n\t\t\treturn `removed", SPEC_E),
    ("M22", "an answer may be one byte over the limit", EX, "#text > exchange.LIMIT then", "#text > exchange.LIMIT + 1 then", SPEC_E),
    ("M23", "an answer with a NUL byte is accepted", EX, 'string.find(text, "\\0", 1, true)', "false", SPEC_E),
    ("M24", "every step is told it is a re-run", DI, "if p.exchangeAsker == p.step and p.exchangeLastStep == p.step and lastIsAnswer then", "if true then", SPEC_E),
    ("M25", "the step that asked is told the history is others'", DI, "if p.exchangeAsker == p.step and p.exchangeLastStep == p.step and lastIsAnswer then", "if false then", SPEC_E),
    ("M26", "a no-reply re-run is not told its question stands", DI, "your question stands unanswered", "your question is settled", SPEC_E),
    ("M27", "a question alone is read as an approval", DI, "If it holds only your question, the user gave no reply and your question stands", "If it holds only your question, the user approved it and your question is settled", SPEC_E),
]
SLOW = [
    ("C1", "the step is not told about its exchange", DP, "exchange = exNames,", "exchange = nil,", SPEC_S),
    ("C2", "a question is not copied when the step stops", DP, "\t\tlocal why = exchangeQuestion(st, step)\n", "\t\tlocal why = nil\n", SPEC_R),
    ("C3", "the answer is not stored", DP, 'local added = exchangeAdd(st, "answer", body)', "local added = nil", SPEC_R),
    ("C4", "a file answer is trimmed", DP, "got = fs.readFile(file[1])", "got = trim(fs.readFile(file[1]))", SPEC_U),
    ("C5", "an answer where no question waits is accepted", DP, "if answer and not waiting then", "if false then", SPEC_R),
    ("C6", "both answer flags are accepted", DP, "if text and file then", "if false then", SPEC_R),
    ("C7", "a stop with questions is 'z-ticket made 0 issues'", DP, '\t\tif asked and (zUnknown ~= nil or #made == 0) then', '\t\tif asked and zUnknown ~= nil then', SPEC_C),
    ("C8", "the capture's exchange is copied, not moved", DP, "fs.move(`{stateDir}/{exchange.DIR}`, `{st.dir}/{exchange.DIR}`)", "fs.copy(`{stateDir}/{exchange.DIR}`, `{st.dir}/{exchange.DIR}`)", SPEC_C),
    ("C9", "a dry run records the words", DP, 'if not opts["--dry-run"] then\n\t\t\t\tif fs.isFile(', "if true then\n\t\t\t\tif fs.isFile(", SPEC_C),
    ("C10", "the retry of a capture re-runs z-ticket with other words", DP, "ask = entries[1].body", 'ask = "other words"', SPEC_C),
    ("C11", "new words are taken while a capture waits", DP, "\t\t\t\tif fs.isFile(`{st.dir}/questions.md`) then\n\t\t\t\t\tprint(", "\t\t\t\tif false then\n\t\t\t\t\tprint(", SPEC_C),
    ("C12", "a retry with no answer records an empty answer", DP, "body = exchange.NO_REPLY", 'body = ""', SPEC_R),
    ("C13", "the retry does not check the exchange before it moves anything", DP, "local entries, readWhy = exchangeRead(st)", "local entries, readWhy = {}, nil", SPEC_R),
    ("C14", "a step starts on an exchange it cannot read", DP, "local exEntries, exWhy = exchangeRead(st)", "local exEntries, exWhy = {}, nil", SPEC_R),
    ("C15", "what the user wrote into questions.md is ignored", DP, "elseif edited then", "elseif false then", SPEC_R),
    ("C16", "an edit together with --answer is accepted", DP, "if answer and edited then", "if false then", SPEC_R),
    ("C17", "a link in the exchange is read like a file", DP, "if isLink(path) or not fs.isFile(path) then", "if not fs.isFile(path) then", SPEC_R),
    ("C18", "a link in place of the folder is followed", DP, "if isLink(dir) then\n\t\treturn nil,", "if false then\n\t\treturn nil,", SPEC_R),
    ("C19", "a questions.md that is a link is copied", DP, "if isLink(q) then\n\t\t\treturn refuse(", "if false then\n\t\t\treturn refuse(", SPEC_R),
    ("C20", "a step that rewrote the exchange is not noticed", DP, "local changed = exchange.changed(st.sealed, texts)", "local changed = nil", SPEC_R),
    ("C21", "a refused question stays waiting", DP, "if fs.isFile(qf) or isLink(qf) then", "if false then", SPEC_R),
    ("C22", "a step the exchange refused ends ok", DP, 'if exProblem then\n\t\toutcome = "failed"', "if exProblem then\n\t\toutcome = outcome", SPEC_R),
    ("C23", "a second answer is accepted after one was recorded", DP, "\t\telseif answer then\n\t\t\treturn refuse(\n\t\t\t\t`an answer is already", "\t\telseif false then\n\t\t\treturn refuse(\n\t\t\t\t`an answer is already", SPEC_R),
    ("C24", "the answer limit is not checked", DP, "local why = exchange.answerRefusal(got)", "local why = nil", SPEC_R),
    ("C25", "a step starts by hand while a question waits", DP, 'if s.kind == "model" and fs.isFile(`{st.dir}/questions.md`) then\n\t\t\tprint(', 'if false then\n\t\t\tprint(', SPEC_S),
    ("C26", "a nested step is told to use a retry that refuses it", DP, "\t\t\tif nested then\n\t\t\t\t-- a step the dispatcher started for another", "\t\t\tif false then\n\t\t\t\t-- a step the dispatcher started for another", SPEC_S),
    ("C27", "the slot new is left running after a capture", DP, "\tsave(slot)\n", "", SPEC_C),
    ("C28", "a failed capture's stop names no id", DP, 'id = if id == "" then "new" else id,', "id = id,", SPEC_C),
    ("C29", "every step is told the exchange is its own re-run", DP, "exchangeAsker = exAsker,", "exchangeAsker = step,", SPEC_S),
    ("C30", "a new capture deletes the earlier exchange", DP, "fs.move(old, freeName(st.dir, `{exchange.DIR}-{os.time()}`, \"\", false))", "fs.removeDir(old)", SPEC_C),
    ("C32", "--forget-exchange keeps the seal of the folder it set aside", DP, "\t\t\tst.sealed, st.answering = nil, nil\n", "\t\t\tst.answering = nil\n", SPEC_R),
    ("C33", "--forget-exchange deletes the folder", DP, 'fs.move(ex, freeName(st.dir, `{exchange.DIR}-forgotten-{os.time()}`, "", false))', "fs.removeDir(ex)", SPEC_R),
    ("C31", "the seal outlives the exchange that was set aside", DP, "\t\t\t\t\t\tst.sealed = nil\n", "", SPEC_C),
    ("C34", "the half state is guessed from a waiting file and a last answer", DP, 'local half = qtext ~= nil\n\t\t\tand st.answering ~= nil\n\t\t\tand st.answering == serde.hash("sha256", qtext :: string)', 'local half = qtext ~= nil and last ~= nil and last.kind == "answer"', SPEC_R),
    ("C36", "a name the dispatcher picks ignores a planted link", DP, "return process.exec(\"readlink\", { path }).ok or fs.isFile(path) or fs.isDir(path)", "return fs.isFile(path)", SPEC_R),
    ("C37", "a nested step is not told about its parent's exchange", DP, "parentExchange = parentNames,", "parentExchange = nil,", SPEC_S),
    ("C38", "a question the retry copied is recorded as 'no reply'", DP, "body = exchange.UNKNOWN_REPLY", "body = exchange.NO_REPLY", SPEC_R),
    ("C39", "an editor's line ends count as an edit", DP, "exchange.normal(text) ~= exchange.normal(lastQ.body)", "text ~= lastQ.body", SPEC_R),
    ("C40", "a deleted questions.md leaves no way to answer", DP, "if answer and not waiting and not unanswered then", "if answer and not waiting then", SPEC_R),
    ("C41", "a blanked questions.md with a flag counts as an edit", DP, "local edited = not copiedNow\n\t\t\t\t\t\tand not isBlank\n", "local edited = not copiedNow\n", SPEC_R),
    ("C42", "the retry of a capture runs z-ticket blind after a landed issue", DP, "local made, unknown = dispatcher.issuesAddedBy(ctx, st.pushes)", "local made, unknown = {}, nil", SPEC_C),
    ("C44", "--forget-exchange moves the folder before a refusal that needs no exchange", DP, 'elseif answer and not waiting then', 'elseif false then', SPEC_R),
    ("C43", "new words are taken over a failed capture", DP, "\t\t\t\t\t\tand entries[1].kind == \"ask\"\n\t\t\t\t\tthen", "\t\t\t\t\t\tand entries[1].kind == \"ask\"\n\t\t\t\t\t\tand false\n\t\t\t\t\tthen", SPEC_C),
    ("C45", "a question over 64 KiB is copied", DP, 'local bad = exchange.answerRefusal(text, "the question")', "local bad = nil", SPEC_R),
    ("C46", "an --answer-file that is a link is read", DP, "if isLink(file[1]) or not fs.isFile(file[1]) then", "if not fs.isFile(file[1]) then", SPEC_R),
    ("C47", "a retry of a capture with no ask takes an answer", DP, 'if answer then\n\t\t\t\t\treturn refuse("no capture waits: --answer has nothing to answer")', 'if false then\n\t\t\t\t\treturn refuse("no capture waits: --answer has nothing to answer")', SPEC_C),
    ("C50", "the capture's words are set aside before --answer is refused", DP, 'if answer and id == "new" then', 'if false then', SPEC_C),
    ("C48", "every new issue on origin counts as this capture's", DP, '"--diff-filter=A", push.base, push.sha', '"--diff-filter=A", push.base, fresh', SPEC_C),
    ("C49", "a z-ticket that made an issue and asked is accepted", DP, "elseif asked or #made ~= 1 then", "elseif #made ~= 1 then", SPEC_C),
    ("C54", "a withdrawn question is read as an answer", DP, "(exLast.body == exchange.NO_REPLY or exLast.body == exchange.WITHDRAWN)", "exLast.body == exchange.NO_REPLY", SPEC_R),
    ("C55", "the push is not recorded before it is made", BR, "	if intent then\n		intent(fresh, sha)", "	if false then\n		intent(fresh, sha)", SPEC_C),
    ("C56", "a fetch that fails reads as 'none made'", DP, '		return nil, "origin\'s main could not be fetched"', '		return {}, nil', SPEC_C),
    ("C57", "an adopted capture's exchange stays behind in the slot", DP, "local why = dispatcher.finishCapture(ctx, st, dir, made[1])", "local why = nil", SPEC_C),
    ("C51", "an open question is not closed as withdrawn", DP, 'local closed = exchangeAdd(st, "answer", exchange.WITHDRAWN)', 'local closed = nil', SPEC_R),
    ("C53", "a nested reviewer is pointed at its own folder", DP, 'parentStateDir = parentDir,', 'parentStateDir = stateDir,', SPEC_S),
]


CASE = {
    "M1": "a file name says its number",
    "M2": "kept exactly as written",
    "M3": "kept exactly as written",
    "M4": "without a date line",
    "M5": "a gap, a repeat",
    "M6": "a gap, a repeat",
    "M7": "a gap, a repeat|the order is the number",
    "M8": "a gap, a repeat",
    "M9": "a gap, a repeat",
    "M10": "a gap, a repeat",
    "M11": "the order is the number",
    "M12": "holds 999",
    "M13": "re-run's prompt names",
    "M14": "re-run's prompt names",
    "M15": "re-run's prompt names",
    "M16": "the next message is numbered",
    "M17": "a question names the step",
    "M18": "without a date line|a question names the step",
    "M19": "the seal notices",
    "M20": "the seal notices",
    "M21": "the seal notices",
    "M22": "blank, over 64 KiB",
    "M23": "blank, over 64 KiB",
    "M24": "did not ask",
    "M25": "re-run's prompt names|asked long ago",
    "M26": "no reply was given",
    "C1": "re-run step reads both",
    "C2": "leaves its question, dated",
    "C3": "the answer is stored after the question",
    "C4": "a second round appends",
    "C5": "an answer where no question waits|a refused retry leaves",
    "C6": "cannot take its answer",
    "C7": "stops with questions is 'needs the user'",
    "C8": "exchange moves to the new issue",
    "C9": "a dry run of a new capture",
    "C10": "re-runs z-ticket with the same words|failed is retried by name",
    "C11": "new words are not taken while a capture waits",
    "C12": "no reply was given",
    "C13": "cannot be read stops the retry|rewrites the exchange|stray file and a question|died after storing",
    "C14": "does not start on an exchange it cannot read",
    "C15": "what the user writes into questions.md",
    "C16": "edited questions.md together with --answer",
    "C17": "a link in the exchange",
    "C18": "a link in the exchange",
    "C19": "a link in the exchange",
    "C20": "rewrites the exchange",
    "C21": "rewrites the exchange|stray file and a question",
    "C22": "rewrites the exchange|stray file and a question",
    "C23": "died after storing",
    "C24": "over 64 KiB or binary|cannot take its answer",
    "C25": "started by hand while a question waits",
    "C26": "review the author started",
    "C27": "second capture in a row",
    "C28": "failed is retried by name",
    "C29": "a step that ran after the asker",
    "C30": "abandoned earlier exchange",
    "C31": "abandoned earlier exchange",
    "C32": "rewrites the exchange",
    "C33": "rewrites the exchange",
    "C34": "lost its dispatcher",
    "C36": "a planted link is skipped",
    "C37": "review the author started",
    "C38": "may hold the user's answer",
    "C39": "line ends and trailing space",
    "C40": "a blank or deleted file",
    "C41": "a blank or deleted file",
    "C42": "landed its issue and died",
    "C43": "new words are not taken over a failed capture",
    "C44": "a refused retry leaves the exchange",
    "C46": "a retry that cannot take its answer",
    "C47": "a retry of a capture",
    "C48": "landed its issue and died",
    "C49": "made an issue and then asked",
    "C54": "a question left open when questions.md",
    "C55": "landed its issue and died",
    "C56": "landed its issue and died",
    "C57": "landed its issue and died",
    "C50": "cannot serve",
    "C51": "a question left open when questions.md",
    "C53": "review the author started",
    "M27": "last file is a question",
    "C45": "a question over 64 KiB",
}  # the case that must fail for each mutant (any of the |-separated titles)


def run(args, cwd, check=False):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=check)


def main():
    if WHICH not in ("fast", "slow", "all"):
        sys.exit("usage: mutants.py [fast|slow|all]")
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="c0256-mut-"))
    try:
        # the scratch folder is outside every checkout (refused otherwise), and the clone has no remote
        if str(tmp).startswith(str(SRC) + "/"):
            sys.exit(f"refusing: {tmp} is inside the checkout {SRC}")
        clone = tmp / "p"
        run(["git", "clone", "-q", "--no-hardlinks", str(SRC), str(clone)], cwd=tmp, check=True)
        run(["git", "remote", "remove", "origin"], cwd=clone, check=True)
        # in the raft the design is already implemented in HEAD: mutate that, not the prototype
        built = (clone / EX).exists()
        if not built:
            r = run(["git", "apply", str(HERE / "prototype.patch")], cwd=clone)
            if r.returncode != 0:
                sys.exit(f"prototype.patch does not apply to {SRC}'s HEAD: {r.stderr}")
        dest = clone / "z-nile/.tracker/issues/c0256/acceptance"
        dest.mkdir(parents=True, exist_ok=True)
        for f in (ISSUE / "acceptance").glob("*.luau"):
            shutil.copy(f, dest / f.name)
        home = clone / "z-nile"

        def spec(path):
            r = run([str(clone / "zn"), "run", "--time", "1200", "--", "lune", "run", "tests/run", "--", path], cwd=home)
            return r.returncode, r.stdout + r.stderr

        def pristine():
            run(["git", "checkout", "-q", "--", "z-nile/engine"], cwd=clone)
            run(["git", "clean", "-fq", "--", "z-nile/engine"], cwd=clone)
            if not built:
                run(["git", "apply", str(HERE / "prototype.patch")], cwd=clone, check=True)

        todo = []
        if WHICH in ("fast", "all"):
            todo += FAST
        if WHICH in ("slow", "all"):
            todo += SLOW
        def judge(out):
            """(failed cases, why not) from the runner's own summary line, whatever the exit code: the sweeper may exit 71
            on a busy machine after a clean run, and a timeout or a spec that did not load shows no summary of its own."""
            if "could not load spec" in out:
                return None, "the spec did not load"
            found = re.search(r"(\d+) passed, (\d+) failed", out)
            if not found:
                return None, "no summary line (a timeout?)"
            return int(found.group(2)), None

        if ONLY:
            todo = [m for m in todo if m[0] in ONLY]
        for spec_path in sorted({m[5] for m in todo}):
            code, out = spec(spec_path)
            failed, why = judge(out)
            print(f"baseline {spec_path.split('/')[-1]}: {'passes' if failed == 0 else 'FAILS'}")
            if failed != 0:
                print(why or out[-1500:])
                sys.exit(1)
        survived = 0
        for mid, what, rel, old, new, spec_path in todo:
            p = clone / rel
            text = p.read_text()
            if text.count(old) != 1:
                print(f"{mid} NOT APPLIED ({what}): {text.count(old)} occurrences of {old[:50]!r}")
                survived += 1
                continue
            p.write_text(text.replace(old, new))
            code, out = spec(spec_path)
            lines = out.splitlines()
            failed, why = judge(out)
            fails = [l for l in lines if l.startswith("FAIL ") and "::" in l]
            if failed is None:
                print(f"{mid} INCONCLUSIVE ({what}): {why}")
                survived += 1
            elif failed == 0:
                print(f"{mid} SURVIVED ({what})")
                survived += 1
            elif not fails:
                print(f"{mid} INCONCLUSIVE ({what}): {failed} failed but no case line")
                survived += 1
            elif not any(want in line for line in fails for want in CASE[mid].split("|")):
                print(f"{mid} FAILED ELSEWHERE ({what}): wanted a case like {CASE[mid]!r}, got {fails[0][:100]}")
                survived += 1
            else:
                print(f"{mid} red ({what}): {fails[0][:110]}")
            pristine()
        print(f"done: {len(todo)} mutants, {survived} not killed")
        sys.exit(1 if survived else 0)
    finally:
        # only the folder this run made, checked by its prefix and its place outside the checkout
        if tmp.name.startswith("c0256-mut-") and not str(tmp).startswith(str(SRC) + "/"):
            shutil.rmtree(tmp, ignore_errors=True)


main()
