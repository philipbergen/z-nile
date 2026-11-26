# Idea review 003

## Findings

- F1: The sentence listing what zn writes in the host's `.git` will turn out false as soon as zn starts a ticket. The sentence on refs makes this worse, because it can be read either way. To start a ticket branch from the host's current default branch, zn has to fetch origin first. A fetch writes origin's remote-tracking refs (including `origin/main`), `FETCH_HEAD`, and objects that sit on no ticket branch. None of those are on the list. A reader could also count moving `origin/main` as moving "a ref of the default branch", which the next sentence forbids. Without a fetch, every ticket branch starts from whatever old commit the clone last saw, and its pull request may conflict with the host's default branch. Pushing with an upstream set also writes `refs/remotes/<fork>/<branch>`, which "the refs and upstream settings of ticket branches" covers only if you read it generously. The idea needs to say whether zn fetches. If it does, the list has to name what fetching and pushing write, and the refs sentence has to say whether remote-tracking refs count.

## Verdict

revise
