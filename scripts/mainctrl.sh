#!/usr/bin/env bash
set -euo pipefail

# mainctrl.sh — Manage agent tool-blocking state.
#
# Commands:
#   mainctrl status                    Show current state
#   mainctrl on                        Enable blocking (safety on)
#   mainctrl off                       Disable blocking (all tools passthrough)
#   mainctrl agents '<json-array>'     Set controlled agents (JSON array)
#   mainctrl tools [<json-array>]      Show blocked tools, or set (JSON array)
#   mainctrl allow-except '<json>'     Set execAllowExcept (JSON object)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$SCRIPT_DIR/state.json"
ALL_TOOLS=("write" "edit" "exec" "process" "apply_patch")

# --- helpers ---------------------------------------------------------

die() { echo "mainctrl: $*" >&2; exit 1; }


read_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"enabled":false,"controlledAgents":["main"],"blockedTools":["write","edit","exec","process","apply_patch"],"execAllowExcept":{"find":["-exec","-ok","-delete","-fprint","|","$(",">",">>"],"ls":[">",">>","|"],"pwd":[">",">>","|"]}}'
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
  enabled="$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['enabled'])" 2>/dev/null || echo "false")"
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

  echo ""

  # Show exec allow-except configuration
  local exec_allow_except
  exec_allow_except="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
allow_except = s.get('execAllowExcept', {})
if allow_except:
    print(json.dumps(allow_except, indent=2))
")"
  if [[ -n "$exec_allow_except" ]]; then
    echo "  exec allow-except:"
    echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
allow_except = s.get('execAllowExcept', {})
for cmd, patterns in sorted(allow_except.items()):
    print(f'    {cmd}: {patterns}')
"
  fi
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
  shift
  local agents_json="${1:-}"
  if [[ -z "$agents_json" ]]; then
    echo "Usage: mainctrl agents '<json-array>'" >&2
    echo "Example: mainctrl agents '[\"main\",\"coder\"]'" >&2
    exit 1
  fi

  # Validate JSON
  echo "$agents_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || die "invalid JSON array"

  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s['controlledAgents'] = json.loads(sys.argv[1])
print(json.dumps(s, separators=(',',':')))
" "$agents_json")" 2>/dev/null || die "failed to update agents"
  write_state "$state"
  echo "mainctrl: controlled agents updated"
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
    enabled="$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['enabled'])" 2>/dev/null || echo "false")"

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

    echo ""

    # Show exec allow-except configuration
    local exec_allow_except
    exec_allow_except="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
allow_except = s.get('execAllowExcept', {})
if allow_except:
    print(json.dumps(allow_except, indent=2))
")"
    if [[ -n "$exec_allow_except" ]]; then
      echo "  exec allow-except:"
      echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
allow_except = s.get('execAllowExcept', {})
for cmd, patterns in sorted(allow_except.items()):
    print(f'    {cmd}: {patterns}')
"
    fi
    return
  fi

  # Set mode — accept JSON array
  local tools_json="${args[0]}"
  echo "$tools_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || die "invalid JSON array"

  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s['blockedTools'] = json.loads(sys.argv[1])
print(json.dumps(s, separators=(',',':')))
" "$tools_json")" 2>/dev/null || die "failed to update tools"
  write_state "$state"
  echo "mainctrl: blocked tools updated"
}

cmd_allow_except() {
  shift
  local veto_json="${1:-}"
  if [[ -z "$veto_json" ]]; then
    echo "Usage: mainctrl allow-except '<json>'" >&2
    echo "Example: mainctrl allow-except '{\"ls\":[\">\",\">>\",\"|\"],\"pwd\":[\">\",\">>\",\"|\"],\"find\":[\"-exec\",\"-ok\",\"-delete\",\"-fprint\",\"|\",\"\$(\",\">\",\">>\"]}'" >&2
    exit 1
  fi

  # Validate JSON
  echo "$veto_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || die "invalid JSON for execAllowExcept"

  local state
  state="$(read_state)"
  state="$(echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s['execAllowExcept'] = json.loads(sys.argv[1])
print(json.dumps(s, separators=(',',':')))
" "$veto_json")" 2>/dev/null || die "failed to update exec allow-except"
  write_state "$state"
  echo "mainctrl: exec allow-except updated"
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
  status)       cmd_status ;;
  on)           cmd_on ;;
  off)          cmd_off ;;
  agents)       cmd_agents "$@" ;;
  tools)        cmd_tools "$@" ;;
  allow-except) cmd_allow_except "$@" ;;
  plugin)       [[ -z "${2:-}" ]] && die "usage: mainctrl plugin {install|remove}"
                case "$2" in
                  install) cmd_plugin_install ;;
                  remove)  cmd_plugin_remove ;;
                  *)       die "unknown subcommand: $2" ;;
                esac ;;
  *)            echo "Usage: mainctrl {status|on|off|agents '<json-array>'|tools [<json-array>]|allow-except '<json>'|plugin {install|remove}}" >&2; exit 1 ;;
esac
