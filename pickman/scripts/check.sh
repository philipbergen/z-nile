#!/usr/bin/env bash
# Forwarder (c0120): pickman's check.sh files run from pickman/ and name scripts/check.sh, the repository's gate
# (every project). Kept until every raft whose sequestered check.sh calls this path is done (as scripts/check.sh).
exec bash "$(dirname "$0")/../../z-nile/check.sh" "$@"
