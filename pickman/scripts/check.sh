#!/usr/bin/env bash
# Forwarder (c0120): pickman's check.sh files run from pickman/ and name scripts/check.sh; it runs pickman's gate
# alone (pickman/check.sh, decided with the user: "pickman's gate only"). Kept until every raft whose sequestered
# check.sh calls this path is done (as scripts/check.sh).
exec bash "$(dirname "$0")/../check.sh" "$@"
