#!/usr/bin/env bash
# Forwarder (c0120): z-nile's check.sh files run from z-nile/ and name scripts/tracker.sh; the command is ./zn at the
# repository root. Kept until every raft whose sequestered check.sh calls this path is done (as scripts/tracker.sh).
exec bash "$(dirname "$0")/../../zn" "$@"
