#!/usr/bin/env bash
# Forwarder (c0114): the bootstrap is z-nile/setup.sh. Kept for the check.sh files and specs that name this path.
exec bash "$(dirname "$0")/../z-nile/setup.sh" "$@"
