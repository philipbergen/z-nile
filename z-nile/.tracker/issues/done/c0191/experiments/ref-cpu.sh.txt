# zn_lower_cpu <seconds> (c0191): `ulimit -t <seconds>`, only when that lowers the CPU-time limit already in force. A limit
# cannot be raised again, so every setter (the spec runner's jail, `./zn`, the hook scripts, `./zn run`) goes through this
# one function: a caller that is already under a lower limit keeps it, and nothing fails for asking for more.
zn_lower_cpu() {
  _zn_cur=$(ulimit -t)
  if [ "$_zn_cur" = unlimited ] || [ "$_zn_cur" -gt "$1" ]; then
    ulimit -t "$1"
  fi
}
