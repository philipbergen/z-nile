#!/usr/bin/env bash
# Forwarder (c0114): CI dispatch is z-nile/ci-verify.sh. Kept for the check.sh files and specs that name this path.
exec bash "$(dirname "$0")/../z-nile/ci-verify.sh" "$@"
