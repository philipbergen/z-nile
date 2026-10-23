#!/usr/bin/env bash
# Forwarder (c0114): the command is ./zn. Kept until every raft whose sequestered check.sh calls this path is done.
exec bash "$(dirname "$0")/../zn" "$@"
