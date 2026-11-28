#!/usr/bin/env python3
"""Mutation check for c0182's narrowed.spec.luau.
Runs only in a throwaway --no-hardlinks clone under $TMPDIR (refuses any real checkout).
Usage: python3 mutants.py <prep-worktree>
"""
import os, pathlib, shutil, subprocess, sys, tempfile

if len(sys.argv) != 2:
    sys.exit("usage: mutants.py <prep-worktree>")

wt = pathlib.Path(sys.argv[1]).resolve()
tmp_root = pathlib.Path(tempfile.gettempdir()).resolve()
clone = pathlib.Path(tempfile.mkdtemp(prefix="c0182-mutants-", dir=tmp_root)).resolve()
assert tmp_root in clone.parents, f"refused: {clone} is not under {tmp_root}"

try:
    subprocess.run(["git", "clone", "--no-hardlinks", "--quiet", str(wt), str(clone)], check=True)
    # Copy prep worktree's edited done/*/check.sh and c0182 files into clone
    for rel in [
        "pickman/.tracker/issues/done/f0027/check.sh",
        "pickman/.tracker/issues/done/f0028/check.sh",
        "pickman/.tracker/issues/done/f0110/check.sh",
        "pickman/.tracker/issues/done/f0126/check.sh",
    ]:
        shutil.copy2(wt / rel, clone / rel)
    spec_dst = clone / "pickman/.tracker/issues/c0182/acceptance/narrowed.spec.luau"
    spec_dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(wt / "pickman/.tracker/issues/c0182/acceptance/narrowed.spec.luau", spec_dst)
    # Apply narrowing.patch
    subprocess.run(
        ["git", "-C", str(clone), "apply", str(wt / "pickman/.tracker/issues/c0182/experiments/narrowing.patch")],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(clone), "-c", "user.name=mutants", "-c", "user.email=mutants@example.invalid", "add", "-A"],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(clone), "-c", "user.name=mutants", "-c", "user.email=mutants@example.invalid", "commit", "-qm", "base"],
        check=True,
    )

    def run_spec() -> tuple[int, str]:
        p = subprocess.run(
            ["lune", "run", "tests/run", "--", ".tracker/issues/c0182/acceptance/narrowed.spec.luau"],
            cwd=str(clone / "pickman"),
            text=True,
            capture_output=True,
        )
        return p.returncode, p.stdout + p.stderr

    def reset():
        subprocess.run(["git", "-C", str(clone), "checkout", "--", "."], check=True)
        subprocess.run(["git", "-C", str(clone), "clean", "-fd", "pickman/tests/acceptance"], check=True)

    rc, out = run_spec()
    assert rc == 0, f"BASE FAILED:\n{out}"
    print("BASE: PASS")

    acc = clone / "pickman/tests/acceptance"

    def edit_file(rel: str, old: str, new: str):
        p = clone / rel
        txt = p.read_text()
        assert old in txt, f"pattern not found in {rel}: {old!r}"
        p.write_text(txt.replace(old, new, 1))

    mutants = [
        ("M1_removed_file_kept", lambda: (acc / "f0027/swipe.spec.luau").write_text("-- kept\n")),
        ("M2_check_still_runs_removed", lambda: edit_file(
            "pickman/.tracker/issues/done/f0027/check.sh",
            "# Narrowed by c0182",
            'check "AC1: swipe" lune run tests/run -- "$A/swipe.spec.luau"\n# Narrowed by c0182',
        )),
        ("M3_check_drops_kept", lambda: edit_file(
            "pickman/.tracker/issues/done/f0029/check.sh",
            'check "AC5:',
            '# check "AC5:',
        )),
        ("M4_assertion_deleted", lambda: edit_file(
            "pickman/tests/acceptance/f0027/screen.spec.luau",
            "\t\tt.expect(y).toBe(320)\n",
            "",
        )),
        ("M5_joined_onto_comment", lambda: edit_file(
            "pickman/tests/acceptance/f0027/place.spec.luau",
            "-- the conversion reads the area inline, so it cannot be cached at start\n\t\tlocal a, b =",
            "-- the conversion reads the area inline, so it cannot be cached at start local a, b =",
        )),
        ("M6_added_early_return", lambda: edit_file(
            "pickman/tests/acceptance/f0158/clear.spec.luau",
            "local function overlaps(a: Rect, b: Rect): boolean\n",
            "local function overlaps(a: Rect, b: Rect): boolean\n\tif true then return false end\n",
        )),
        ("M7_string_spaces_changed", lambda: edit_file(
            "pickman/tests/acceptance/f0143/place.spec.luau",
            '"two quick pulls up on the steer circle"',
            '"two  quick pulls up on the steer circle"',
        )),
        ("M8_c0155_pad_rule_weakened", lambda: edit_file(
            "pickman/tests/acceptance/c0155/narrowed.spec.luau",
            "t.expect(ownActions(Pad.BUTTONS :: any)).toBe(true)",
            "t.expect(true).toBe(true)",
        )),
    ]

    for name, fn in mutants:
        fn()
        rc, out = run_spec()
        reset()
        if rc == 0:
            sys.exit(f"SURVIVED: {name}")
        if "expected " not in out:
            sys.exit(f"ERROR (non-assertion): {name}\n{out}")
        print(f"KILLED: {name}")

    print(f"ALL {len(mutants)} MUTANTS KILLED ON ASSERTIONS")
finally:
    shutil.rmtree(clone, ignore_errors=True)
