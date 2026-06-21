---
name: mainctrl
description: >
  Manage OpenClaw agent tool-call permissions.  A runtime plugin hook
  intercepts write, edit, exec, process, and apply_patch from
  controlled agents, redirecting them to delegate work through
  sub-agents.  Designed for environments that enforce "main never
  writes code directly".
metadata:
  author: iClaw
  version: "1.0.0"
---

# mainctrl — Agent Tool Access Control

Toggle destructive tool access for controlled agents at runtime,
without restarting OpenClaw or changing agent configs.

## How it works

A lightweight OpenClaw plugin (`extensions/mainctrl`) hooks
`before_tool_call` and inspects every tool call.  When the caller is
one of the `controlledAgents` and `mainctrl` is **off** by default (permissive),
the following tools are blocked:

| Tool         | Why blocked                          |
|--------------|--------------------------------------|
| `write`      | File creation / overwrite            |
| `edit`       | In-place file edits                  |
| `exec`       | Shell command execution              |
| `process`    | Background process management        |
| `apply_patch`| Multi-file patching                  |

Agents not in `controlledAgents` are **never** affected —
they always have full tool access.

## Agent behavior rule

When the main agent receives the block message:

> Delegate this work to a sub-agent instead.
> Use sessions_spawn to dispatch to coder, tester, auditor, or publicist.

it MUST:
1. Briefly inform the user that the operation has been blocked and is being delegated.
2. Immediately spawn a sub-agent (coder, tester, auditor, or publicist) to complete the blocked operation.

Do NOT wait for the user to confirm — report and delegate in the same turn.

## Why this approach

`mainctrl` uses an OpenClaw `before_tool_call` plugin hook rather than
agent-level `tools.deny` for two reasons.  First, `tools.deny` is
static — toggling it requires editing agent config and restarting the
gateway.  The plugin hook reads `state.json` on every call, so safety
can be toggled at runtime with a single command and takes effect
immediately.  Second, agent configs cannot distinguish which *caller*
is invoking a tool; the plugin hook can selectively block agents
listed in `controlledAgents` while leaving sub-agents (like `coder`)
unaffected.

## Commands

Use the `mainctrl.sh` script in the `scripts/` directory:

| Command                          | Effect                              |
|----------------------------------|-------------------------------------|
| `./scripts/mainctrl.sh status`                | Show current state (enabled + agents + per-tool) |
| `./scripts/mainctrl.sh on`                    | Enable blocking                     |
| `./scripts/mainctrl.sh off`                   | Disable blocking (all tools pass through) |
| `./scripts/mainctrl.sh agents <a1> [a2] ...` | Set which agents are controlled     |
| `./scripts/mainctrl.sh tools [<t1> [t2] ...]` | Set or show blocked tools list      |
| `./scripts/mainctrl.sh plugin install` | Install the companion plugin via openclaw plugins |
| `./scripts/mainctrl.sh plugin remove`  | Disable and uninstall the companion plugin       |

### Plugin Installation

Instead of manually adding the plugin path to `plugins.load.paths`,
use the built-in script:

```bash
# Install the plugin
./scripts/mainctrl.sh plugin install

# Remove the plugin
./scripts/mainctrl.sh plugin remove
```

This calls `openclaw plugins install` / `uninstall`, which manages the
plugin under OpenClaw's native plugin registry.  After install or remove,
restart the gateway for the change to take effect.

### Examples

```bash
# Check current state
./scripts/mainctrl.sh status

# Control main only (default)
./scripts/mainctrl.sh agents main

# Control main and auditor
./scripts/mainctrl.sh agents main auditor

# Remove all agents from control (effectively disables blocking)
./scripts/mainctrl.sh agents

# Emergency off — let everyone do anything
./scripts/mainctrl.sh off

# Turn safety back on
./scripts/mainctrl.sh on
```

## State file

`skills/mainctrl/scripts/state.json` (in the `scripts/` directory):

```json
{
  "enabled": false,
  "controlledAgents": ["main"],
  "blockedTools": ["write", "edit", "exec", "process", "apply_patch"]
}
```

Changes take effect immediately on the next tool call — no restart needed.

## Plugin

The companion extension lives at `extensions/mainctrl/`.
It reads `state.json` on every `before_tool_call` event,
so the latency is a single `fs.readFileSync` per tool call.

## Verification

- [ ] Plugin installed: `./scripts/mainctrl.sh plugin install`
- [ ] Blocking active: `./scripts/mainctrl.sh status` shows safety ON
- [ ] Tool blocked: main agent exec/write/edit/process/apply_patch return block message
- [ ] Sub-agent unaffected: coder can still use write/exec
- [ ] Toggle works: `./scripts/mainctrl.sh off` then `./scripts/mainctrl.sh on` restores blocking
