#!/usr/bin/env bash
# Forwarder (c0114): the gate is z-nile/check.sh. Kept for the check.sh files and specs that name this path.
exec bash "$(dirname "$0")/../z-nile/check.sh" "$@"
