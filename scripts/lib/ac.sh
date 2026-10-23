#!/usr/bin/env bash
# Forwarder (c0114): the acceptance helpers are z-nile/lib/ac.sh. Every check.sh sources this path; a missing target
# fails the check.sh (fail closed).
source "$(dirname "${BASH_SOURCE[0]}")/../../z-nile/lib/ac.sh" || { echo "ac.sh: z-nile/lib/ac.sh is missing" >&2; exit 1; }
