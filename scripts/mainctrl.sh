#!/usr/bin/env bash
set -euo pipefail

# mainctrl.sh — Manage agent tool-blocking state.
#
# Commands:
#   mainctrl status                    Show current state
#   mainctrl on                        Enable blocking (safety on)
#   mainctrl off                       Disable blocking (all tools passthrough)
#   mainctrl agents <agent1> [agent2]  Set which agents are controlled
#   mainctrl tools [<t1> <t2> ...]     Set or show blocked tools list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$SCRIPT_DIR/state.json"
ALL_TOOLS=("write" "edit" "exec" "process" "apply_patch")

# --- helpers ---------------------------------------------------------

die() { echo "mainctrl: $*" >&2; exit 1; }

read_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"enabled":true,"controlledAgents":["main"],"blockedTools":["write","edit","exec","process","apply_patch"]}'
    return
  fi
  cat "$STATE_FILE"
}

write_state() {
  local json="$1"
  echo "$json" | python3 -m json.tool --compact > "$STATE_FILE.tmp" 2>/dev/null || die "invalid JSON"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# --- commands --------------------------------------------------------

cmd_status() {
  local state
  state="$(read_state)"
  local enabled agents blocked
  enabled="$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['enabled'])" 2>/dev/null || echo "true")"
  agents="$(echo "$state" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).get('controlledAgents',['main'])))" 2>/dev/null || echo "main")"
  blocked="$(echo "$state" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)['blockedTools']))" 2>/dev/null || echo "")"

  echo "mainctrl status:"
  if [[ "$enabled" == "True" ]]; then
    echo "  safety:            ON  (blocking is active)"
  else
    echo "  safety:            OFF (all tools passthrough)"
  fi
  echo "  controlled agents: $agents"
  echo ""
  echo "  Tool          Status"
  echo "  ------------  --------"
  for tool in "${ALL_TOOLS[@]}"; do
    if [[ "$enabled" != "True" ]]; then
      printf "  %-14s ALLOWED (safety off)\n" "$tool"
    elif echo " $blocked " | grep -q " $tool "; then
      printf "  %-14s BLOCKED\n" "$tool"
    else
      printf "  %-14s ALLOWED\n" "$tool"
    fi
  done
}

cmd_on() {
  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "import sys,json; s=json.load(sys.stdin); s['enabled']=True; print(json.dumps(s, separators=(',',':')))")" 2>/dev/null || die "failed to update state"
  write_state "$state"
  echo "mainctrl: safety ON — destructive tools blocked for controlled agents"
}

cmd_off() {
  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "import sys,json; s=json.load(sys.stdin); s['enabled']=False; print(json.dumps(s, separators=(',',':')))")" 2>/dev/null || die "failed to update state"
  write_state "$state"
  echo "mainctrl: safety OFF — all tools allowed for all agents"
}

cmd_agents() {
  shift  # discard "agents" itself
  local args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    die "usage: mainctrl agents <agent1> [agent2] ..."
  fi

  # Build JSON array from args
  local json_agents
  json_agents="$(printf '%s\n' "${args[@]}" | python3 -c "
import sys, json
agents = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(agents, separators=(',',':')))
")"

  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s['controlledAgents'] = ${json_agents}
print(json.dumps(s, separators=(',',':')))
")" 2>/dev/null || die "failed to update state"
  write_state "$state"
  echo "mainctrl: controlled agents set to: ${args[*]}"
}

cmd_tools() {
  shift  # discard "tools" itself
  local args=("$@")

  if [[ ${#args[@]} -eq 0 ]]; then
    # Show current blocked tools
    local state blocked
    state="$(read_state)"
    blocked="$(echo "$state" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)['blockedTools']))" 2>/dev/null || echo "")"
    local enabled
    enabled="$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['enabled'])" 2>/dev/null || echo "true")"

    echo "mainctrl blocked tools:"
    if [[ "$enabled" != "True" ]]; then
      echo "  safety is OFF — all tools passthrough"
    fi
    echo ""
    echo "  Tool          Status"
    echo "  ------------  --------"
    for tool in "${ALL_TOOLS[@]}"; do
      if [[ "$enabled" != "True" ]]; then
        printf "  %-14s ALLOWED (safety off)\n" "$tool"
      elif echo " $blocked " | grep -q " $tool "; then
        printf "  %-14s BLOCKED\n" "$tool"
      else
        printf "  %-14s ALLOWED\n" "$tool"
      fi
    done
    return
  fi

  # Validate each arg is a known tool
  local valid=true
  for tool in "${args[@]}"; do
    local found=false
    for known in "${ALL_TOOLS[@]}"; do
      if [[ "$tool" == "$known" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" != "true" ]]; then
      echo "mainctrl: unknown tool '$tool' — must be one of: ${ALL_TOOLS[*]}" >&2
      valid=false
    fi
  done
  $valid || exit 1

  # Build JSON array from args
  local json_tools
  json_tools="$(printf '%s\n' "${args[@]}" | python3 -c "
import sys, json
tools = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(tools, separators=(',',':')))
")"

  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s['blockedTools'] = ${json_tools}
print(json.dumps(s, separators=(',',':')))
")" 2>/dev/null || die "failed to update state"
  write_state "$state"
  echo "mainctrl: blocked tools set to: ${args[*]}"
}

# --- plugin commands -------------------------------------------------

cmd_plugin_install() {
  # Install the companion plugin from projects source
  local src="$SCRIPT_DIR/../plugin"
  if [[ ! -f "$src/package.json" ]]; then
    die "plugin source not found at $src"
  fi
  openclaw plugins install "$src" --force
  openclaw plugins enable mainctrl
  echo "mainctrl: plugin installed. Restart gateway to activate."
}

cmd_plugin_remove() {
  openclaw plugins disable mainctrl
  openclaw plugins uninstall mainctrl
  echo "mainctrl: plugin removed. Restart gateway to activate."
}

# --- dispatch --------------------------------------------------------

case "${1:-}" in
  status)  cmd_status ;;
  on)      cmd_on ;;
  off)     cmd_off ;;
  agents)  cmd_agents "$@" ;;
  tools)   cmd_tools "$@" ;;
  plugin)  [[ -z "${2:-}" ]] && die "usage: mainctrl plugin {install|remove}"
           case "$2" in
             install) cmd_plugin_install ;;
             remove)  cmd_plugin_remove ;;
             *)       die "unknown subcommand: $2" ;;
           esac ;;
  *)       echo "Usage: mainctrl {status|on|off|agents <agent1> [agent2] ...|tools [<t1> <t2> ...]|plugin {install|remove}}" >&2; exit 1 ;;
esac
