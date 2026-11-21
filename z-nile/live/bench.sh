#!/usr/bin/env bash
# usage: bench.sh idle|crash   (run under: /Users/philipbergen/code/pickman/zn run --time 600 -- ./bench.sh idle)
set -u
cd "$(dirname "$0")"
go build -o znlive . || exit 1
Z=$PWD/znlive
D=$(mktemp -d /tmp/zlb.XXXXXX)
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; rm -rf "$D"; }
trap cleanup EXIT
ps_of() { ps -o pid=,cputime=,rss=,command= -p "$1"; }
start_daemon() { "$Z" serve --dir "$D" --lost-after "$1" & DPID=$!; PIDS+=($DPID); sleep 0.5; }

idle_phase() { # $1 = heartbeats yes|no, $2 = lost-after
  rm -rf "$D"; mkdir -p "$D"; PIDS=()
  start_daemon "$2"
  WP=()
  for i in 1 2 3 4 5; do
    "$Z" register --dir "$D" --worker w$i --cli t --can x >/dev/null
    "$Z" wait --dir "$D" --worker w$i >/dev/null 2>&1 & WP+=($!); PIDS+=($!)
  done
  sleep 2
  echo "== phase heartbeats=$1 lost-after=$2 : before"
  ps_of $DPID; for p in "${WP[@]}"; do ps_of $p; done
  start=$(date +%s)
  while [ $(( $(date +%s) - start )) -lt 120 ]; do
    if [ "$1" = yes ]; then for i in 1 2 3 4 5; do "$Z" beat --dir "$D" --worker w$i >/dev/null; done; fi
    sleep 5
  done
  echo "== after 120 s"
  ps_of $DPID; for p in "${WP[@]}"; do ps_of $p; done
  echo "waiters still alive: $(for p in "${WP[@]}"; do kill -0 $p 2>/dev/null && echo -n x; done)"
  "$Z" events --dir "$D" | wc -l | xargs echo "events in log:"
  kill "${WP[@]}" $DPID 2>/dev/null; wait 2>/dev/null
}

if [ "$1" = idle ]; then
  # /usr/bin/time -l reports total user+sys of the daemon over its whole life
  idle_phase yes 15
  idle_phase no 1000
fi

if [ "$1" = crash ]; then
  start_daemon 15
  for i in 1 2 3 4 5; do "$Z" register --dir "$D" --worker w$i --cli t --can x >/dev/null; done
  for i in 1 2 3; do "$Z" claim --dir "$D" --worker w$i --unit R0$i --activity design --needs x >/dev/null; done
  for i in 4 5; do ( "$Z" wait --dir "$D" --worker w$i; echo "waiter w$i exit=$? at $(date +%T.%S)" ) & PIDS+=($!); done
  sleep 1
  echo "-- before kill -9"; "$Z" workers --dir "$D"
  kill -9 $DPID; echo "kill -9 at $(date +%T.%S)"; sleep 1
  ls -l "$D"
  "$Z" workers --dir "$D"; echo "workers (daemon down) exit=$?"
  start_daemon 15
  echo "-- restarted"; "$Z" workers --dir "$D"; "$Z" events --dir "$D"
  echo "-- wait 20 s without beats, expect lost"; sleep 20
  "$Z" workers --dir "$D"; "$Z" events --dir "$D" | tail -5
  wait 2>/dev/null
fi
