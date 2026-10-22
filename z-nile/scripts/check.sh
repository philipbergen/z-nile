#!/usr/bin/env bash
# Forwarder (c0120): z-nile's check.sh files run from z-nile/ and name scripts/check.sh; it runs z-nile's gate alone,
# as a home's scripts/check.sh does for its project. Kept until every raft whose sequestered check.sh calls this path
# is done (as scripts/check.sh).
exec bash "$(dirname "$0")/../check.sh" --project z-nile "$@"
