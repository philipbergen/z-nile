# c0392 AC1: c0210's promoted folder and finished check.sh are exactly c0210's reviewed files with lobby-start.spec and
# the AC11 check removed, and nothing else changed, added or left naming the file. Read as bytes, compared byte for
# byte (a git blob id is the SHA-1 of "blob <size>\0" and the bytes, so a deleted assertion, a line joined onto a
# comment, an added `do return end` or a changed line ending is red):
# - every other file of portal/tests/acceptance/c0210/ is its blob in c0210's prepared acceptance folder (main
#   58a574506, c0210's prep #525), and the folder holds exactly those files and watch files (`./zn finish` writes
#   them), so lobby-start.spec is gone and nothing is added;
# - c0210's finished check.sh is its prepared blob 0fefecb3 with exactly the two lines of the AC11 check removed, which
#   is blob 259b5159 (c0392's pre-ready tracker PR, experiments/c0210-check.patch);
# - outside every record folder (each project's .tracker/, and every skill's lessons/, which harvests write: c0392
#   design review 001 F3) and this file's own folder, no tracked or untracked file names lobby-start, and no
#   check.sh anywhere names lobby-start.spec.luau.
# It holds from c0392's finish on, until the next item that changes c0210's files (f0187's chore removes way-back.spec
# and AC10). It is no spec: only c0392's check.sh runs it, so it charges no later editor of these files.
# Usage: python3 -I narrow.py <checkout>.
import hashlib, os, pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
HOME = R / "portal"
DONE = HOME / ".tracker/issues/done/c0210"
PROMOTED = HOME / "tests/acceptance/c0210"
GONE = "lobby-start.spec.luau"
CHECK_BASE = "0fefecb37d9ffda96cfeb198037807c438e6c8be"
CHECK_AFTER = "259b515938fd5dc3076747cba23f9e89ec98af40"
AC11 = (
    b'check "AC11: until f0209, the start place publishes pickman\'s lobby after the game, told GamePlaceId, the output'
    b" exactly version and lobby_version, and --place Portal runs the lobby's runtime scripts there (f0209's chore"
    b' removes this check)" \\\n\tlune run tests/run -- "$A/lobby-start.spec.luau"\n'
)
KEEP = {
    "build.spec.luau": "ee88cc08993d0e1856dc89ca2a4601de4e40929c",
    "deploy.spec.luau": "aa5f32f6735b824bae9da807a85825c8345557f7",
    "layout.spec.luau": "e453b797fcf869611cd091b363935f271b46683f",
    "manifest.spec.luau": "62ba40fe19c4f246e9fe7ec52cb50864e28975dd",
    "override-01.txt": "5052f65cb224a4a59f1b932934302db0f01f305b",
    "override-02.txt": "f8e6f95754661ab25fa4d54cb4d25a806d2c1607",
    "override-03.txt": "b50ad229ef984eb826a9ce4fd2bb5690c43476bd",
    "override-04.txt": "b4e9664f7667292a775d935f3b1f6afb2f092f68",
    "override-05.txt": "6648a46a7851e0668e6e391f3e63381d09afe090",
    "override-06.txt": "38a959d53180959594c1713ef2163d8271fdcc54",
    "override-07.txt": "0ddd833aab6cf1f3f7642869dd2904ea4b24be3e",
    "override-08.txt": "7e0ebd7357931c83464245d763fc55b658d02808",
    "override-09.txt": "df90803f43b327dfe1ce03f163d872924513b988",
    "override-10.txt": "3578f11887e52d991733f93a05e106798e80a6d2",
    "override-11.txt": "1248f4d49af87ca110ecbf78c401fe4a9f7b54c8",
    "override-12.txt": "ca6edd46dd1c55bfd118f21c39418f9e1aa621bd",
    "override-13.txt": "843be9db12e88a8d52c0ef77ee2c74e8346eae46",
    "override-14.txt": "811ca014778aea33f54e1546c29fedac1cdd6fdd",
    "override-15.txt": "bc36ec980a98e85783731e14830a009023de39c6",
    "override-16.txt": "bc65e99fdc1e33cb51cf06bf4f685814b4411c65",
    "override-17.txt": "3b7ac1e6cb735dd19045322a57fc356251904cb8",
    "overrides.spec.luau": "04c17f854585465a8ebd85e50de5bc7014da3117",
    "pickman.spec.luau": "e7a1f99b95e2336070d329d74cc9a148a3d84e2f",
    "plan.spec.luau": "0b0f9059172bf8d781def03542fc0def97801043",
    "runtime.spec.luau": "98723f4c640cb5c0b0b0fc9e958668c7ad3837f4",
    "way-back.spec.luau": "5c383490ebe35ba614ddfea4b6d192404271b8a6",
    "workflow.spec.luau": "896acdc0340a6fa86cc0d9719e5042d43f3cc024",
}
problems = []


def blob(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def watch(name):
    return name == "watch.txt" or name.endswith(".watch.txt")


def grep(*args):
    r = subprocess.run(["git", "-C", str(R), "grep", "-l", "-F", *args], capture_output=True, text=True)
    if r.returncode not in (0, 1):
        sys.exit(f"git grep failed: {r.stderr.strip()}")
    return [p for p in r.stdout.splitlines() if p]


if not DONE.is_dir() or not PROMOTED.is_dir():
    sys.exit("c0210 is not done: portal/.tracker/issues/done/c0210 and portal/tests/acceptance/c0210 must both exist")
if (DONE / "acceptance").exists():
    problems.append("portal/.tracker/issues/done/c0210/acceptance exists: its check.sh would run that folder")

# c0210's finished check.sh: the prepared blob with exactly the AC11 check removed
base = subprocess.run(["git", "-C", str(R), "cat-file", "blob", CHECK_BASE], capture_output=True).stdout
if blob(base) != CHECK_BASE:
    sys.exit(f"c0210's prepared check.sh (blob {CHECK_BASE[:8]}) is not in this repository: fetch origin main")
if base.count(AC11) != 1:
    sys.exit(f"c0210's prepared check.sh holds the AC11 check {base.count(AC11)} times, not once")
want = base.replace(AC11, b"")
if blob(want) != CHECK_AFTER:
    sys.exit(f"the prepared check.sh without AC11 is blob {blob(want)[:8]}, not the reviewed {CHECK_AFTER[:8]}")
got = (DONE / "check.sh").read_bytes()
if got == base:
    problems.append("portal/.tracker/issues/done/c0210/check.sh still runs AC11: c0392's pre-ready tracker PR is missing")
elif got != want:
    problems.append(f"portal/.tracker/issues/done/c0210/check.sh is blob {blob(got)[:8]}, not {CHECK_AFTER[:8]} "
                    "(the prepared file with only the AC11 check removed)")

# the promoted folder: exactly the kept files, each its prepared blob, and watch files
names = sorted(os.listdir(PROMOTED))
for name in names:
    path = PROMOTED / name
    if watch(name) and path.is_file():
        continue
    if name == GONE:
        problems.append(f"portal/tests/acceptance/c0210/{GONE} is still there")
    elif name not in KEEP or not path.is_file():
        problems.append(f"portal/tests/acceptance/c0210/{name} is not one of c0210's reviewed files")
    elif blob(path.read_bytes()) != KEEP[name]:
        problems.append(f"portal/tests/acceptance/c0210/{name} is blob {blob(path.read_bytes())[:8]}, not c0210's "
                        f"{KEEP[name][:8]}")
for name in KEEP:
    if name not in names:
        problems.append(f"portal/tests/acceptance/c0210/{name} is missing")

# nothing outside the records (trackers, lessons) names the removed file, and no check.sh runs it
mine = os.path.relpath(os.path.dirname(os.path.realpath(__file__)), os.path.realpath(R))
for path in grep(
    "--untracked",
    "lobby-start",
    "--",
    ".",
    ":(exclude,glob)**/.tracker/**",
    ":(exclude,glob)**/lessons/**",
    f":(exclude){mine}",
):
    problems.append(f"{path} names lobby-start")
for path in grep("--untracked", GONE, "--", ":(glob)**/check.sh", f":(exclude){mine}"):
    problems.append(f"{path} names {GONE}")

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
