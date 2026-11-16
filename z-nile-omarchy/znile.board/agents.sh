#!/usr/bin/env bash
# Prints the AI CLIs that are really installed (not just mise's lazy
# install-on-first-run wrappers), one id per line, then `default <id>` for
# Omarchy's default agent.
set -uo pipefail
mkdir -p "$HOME/.local/state/znile-board"
wrapper() { [[ ! -L $1 ]] && head -c 4096 "$1" | grep -qaE 'mise (use|x) '; }
for a in claude codex grok kimi opencode copilot agy cursor-agent qwen pi crush; do
  if [[ -x $HOME/.local/bin/$a ]] && ! wrapper "$HOME/.local/bin/$a"; then echo "$a"
  elif MISE_OFFLINE=1 mise which "$a" &>/dev/null; then echo "$a"
  fi
done
f=$HOME/.config/omarchy/defaults/agent
[[ -f $f ]] && read -r d <"$f" && echo "default $d"
exit 0
