# Idea review 001

## Findings

- F1: The non-goal leaves check-paths failing on main (f0201, c0292 and c0225; d0383 records main going red on `c0120/check-paths`). With that left as is, the Solution's "so the failure shows on that pull request" is false as stated. Once the spec is selected, every pull request that touches a check.sh goes red on main's old failures as well as its own. The pull request's own failure can't be told apart from them, and under the prep-gate rule (merge only when the only `--affected` failures are the pull request's own acceptance specs) every prep pull request is blocked. So the idea needs one of two things. Either the repair is a dependency, not just a fence, or the Solution says the run judges only the check.sh files the change adds or edits.

## Verdict

revise
