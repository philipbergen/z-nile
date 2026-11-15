# c0359 AC7: GitHub enforces the `static` ruleset on this repository's main: `gh api repos/{owner}/{repo}/rules/branches/main`
# (the rules that apply to main, readable without admin rights) lists a `required_status_checks` rule whose checks are
# exactly the committed .github/rulesets/static.json's (the context `static` from the GitHub Actions app), from an active
# ruleset named `static`, and that rule does not require branches to be up to date. Its bypass list is readable only by
# an admin, so the committed file (workflow.spec) is what pins it. A network read; it writes nothing.
# Usage: python3 live.py <checkout>.
import json, pathlib, subprocess, sys
R = pathlib.Path(sys.argv[1])
def fail(msg):
    print(msg); sys.exit(1)
def gh(path):
    r = subprocess.run(["gh", "api", path], cwd=str(R), capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"gh api {path} failed: {r.stderr.strip()}")
    return json.loads(r.stdout)
committed_path = R / ".github/rulesets/static.json"
if not committed_path.is_file():
    fail(f"no {committed_path} (c0359 creates it)")
committed = json.loads(committed_path.read_text())
want = committed["rules"][0]["parameters"]["required_status_checks"]
rules = gh("repos/{owner}/{repo}/rules/branches/main")
found = [r for r in rules if r.get("type") == "required_status_checks"
         and r.get("parameters", {}).get("required_status_checks") == want]
if not found:
    fail("main has no required_status_checks rule with the checks .github/rulesets/static.json names: the user posts "
         "it once (SETUP.md, The required check on main)")
rule = found[0]
if rule["parameters"].get("strict_required_status_checks_policy"):
    fail("main's static rule requires branches to be up to date; .github/rulesets/static.json does not")
rs = gh(f"repos/{{owner}}/{{repo}}/rulesets/{rule['ruleset_id']}")
if rs.get("name") != "static" or rs.get("enforcement") != "active":
    fail(f"the rule comes from ruleset {rs.get('name')!r} ({rs.get('enforcement')}), not the active ruleset 'static'")
print(f"main requires {want} through the active ruleset static ({rule['ruleset_id']})")
