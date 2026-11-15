#!/bin/bash
cursor=""
for i in $(seq 1 12); do
  after=""; [ -n "$cursor" ] && after=", after: \"$cursor\""
  r=$(gh api graphql -f query="{ repository(owner: \"$1\", name: \"$2\") { pullRequests(states: MERGED, first: 50$after, orderBy:{field:CREATED_AT,direction:DESC}) { pageInfo { endCursor hasNextPage } nodes { number title mergeCommit { oid messageHeadline } commits(first: 100) { nodes { commit { messageHeadline } } } } } } }")
  echo "$r" | jq -r '.data.repository.pullRequests.nodes[] | select([.commits.nodes[].commit.messageHeadline | test("^tracker: new ")] | any) | "\(.number)\t\(.mergeCommit.messageHeadline)\t\([.commits.nodes[].commit.messageHeadline | select(test("^tracker: new "))] | join(" | "))"'
  [ "$(echo "$r" | jq -r .data.repository.pullRequests.pageInfo.hasNextPage)" = true ] || break
  cursor=$(echo "$r" | jq -r .data.repository.pullRequests.pageInfo.endCursor)
done
