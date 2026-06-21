---
name: mainctrl
description: >
  Runtime safety guard for OpenClaw multi-agent workflows.
  Blocks destructive tools (write, edit, exec, process, apply_patch)
  for controlled agents, forcing delegation to sub-agents.
intents:
  - "stop main agent from writing files directly"
  - "enforce sub-agent delegation in OpenClaw"
  - "block destructive tools for controlled agents"
  - "runtime agent permission management"
  - "multi-agent tool access control"
tags: [multi-agent, access-control, delegation, openclaw, agent-orchestration, security]
icon: 🛡️
metadata:
  author: iClaw
  version: "1.0.6"
---

# mainctrl — Agent Tool Access Control

mainctrl lets you control which agents can use destructive tools (write,
edit, exec, process, apply_patch). Turn it on — main delegates everything
to sub-agents. Turn it off — main is free. Add or remove agents from the
controlled list to extend protection. Install or remove the companion
plugin in one command. No restarts, no config edits.

## Quick Start

1. Install the plugin and restart:
   ```bash
   ./scripts/mainctrl.sh plugin install
   ```
   Then restart the OpenClaw gateway.
   Safety starts **OFF** — nothing is blocked yet.

2. **Before turning on**, verify at least one sub-agent exists and main can spawn it.
   Check with the `agents_list` tool — you need at least one agent besides `main`:
   ```
   agents_list
   ```
   Also verify main's spawn permissions:
   ```
   gateway config.get agents.list → main.subagents.allowAgents
   ```
   mainctrl blocks main's destructive tools and *requires* at least one
   sub-agent to delegate the work to. If none is configured or main can't
   spawn them, set up a sub-agent first.

3. Turn blocking on:
   ```bash
   ./scripts/mainctrl.sh on
   ```

4. Verify:
   ```bash
   ./scripts/mainctrl.sh status
   ```
   Should show `safety: ON` and all tools `BLOCKED`.

5. Emergency off — temporarily allow all tools.
   When mainctrl is ON, main can't run commands itself. To turn it off:

   - **Delegate to a sub-agent** (e.g. coder):
     Spawn a sub-agent to run `./scripts/mainctrl.sh off`.
   - **Run the script manually** if no sub-agent has exec access:
     ```bash
     ./scripts/mainctrl.sh off
     ```

## Plugin + Skill

mainctrl is two parts that must be installed together:

- **Plugin** (`plugin/index.js`) — a `before_tool_call` hook. It reads
  `state.json` on every tool call and blocks or allows based on your settings.
  Installed via `./scripts/mainctrl.sh plugin install`.
- **Skill** (this directory) — the management side. The CLI script
  (`mainctrl.sh`) writes config to `state.json`; this SKILL.md tells the
  agent how to behave when blocked.

Both talk through a shared file — the skill writes `state.json`, the plugin
reads it. No sockets, no RPC, no restart.

**The skill installs the plugin for you** — run `./scripts/mainctrl.sh plugin install`
to set up both halves in one step.



## How it works

Mainctrl gives the agent two modes, like vi's V and I:

**Visual mode** (`mainctrl on`) — the agent can inspect, search, and read,
but cannot modify anything. Every destructive tool call is blocked:

| Tool         | Why blocked                          |
|--------------|--------------------------------------|
| `write`      | File creation / overwrite            |
| `edit`       | In-place file edits                  |
| `exec`       | Shell command execution              |
| `process`    | Background process management        |
| `apply_patch`| Multi-file patching                  |

**Insert mode** (`mainctrl off`) — the agent can write files, run commands,
and make changes freely.

Switch between them with `./scripts/mainctrl.sh on` and `./scripts/mainctrl.sh off`.

A lightweight OpenClaw plugin (`extensions/mainctrl`) hooks
`before_tool_call` and inspects every tool call. When the caller is
one of the `controlledAgents` and `mainctrl` is enabled, the above
tools are rejected with a delegation message.

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

### Blocked tool response

When a controlled agent calls a blocked tool, it receives:

> Delegate this work to a sub-agent instead.
> Use sessions_spawn to dispatch to coder, tester, auditor, or publicist.

The agent follows the [Agent behavior rule](#agent-behavior-rule) and
spawns a sub-agent to complete the work automatically.

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

### controlledAgents config

`controlledAgents` lists which agents are subject to tool blocking.
Example configs:

```json
{ "enabled": true, "controlledAgents": ["main"] }
```

```json
{ "enabled": true, "controlledAgents": ["main", "auditor"] }
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

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Blocking not working | `./scripts/mainctrl.sh status` — ensure safety is ON |
| Plugin not loaded | `openclaw plugins list` — ensure mainctrl is enabled |
| Agent still blocked after `off` | Restart the gateway |
| Sub-agent blocked too | Run `./scripts/mainctrl.sh agents main` to restrict to main only |

## Examples

What you can do with mainctrl:

### Control the safety switch

```bash
./scripts/mainctrl.sh on      # Block destructive tools — delegate mode
./scripts/mainctrl.sh off     # Allow all tools — free mode
./scripts/mainctrl.sh status  # Check current state
```

### Add or remove controlled agents

```bash
./scripts/mainctrl.sh agents main           # Control main only
./scripts/mainctrl.sh agents main auditor   # Add auditor to the list
./scripts/mainctrl.sh agents                # Clear the list (stops all blocking)
```

### Add or remove blocked tools

```bash
./scripts/mainctrl.sh tools                        # Show which tools are blocked
./scripts/mainctrl.sh tools write exec             # Block only write and exec
./scripts/mainctrl.sh tools write edit exec        # Block three
./scripts/mainctrl.sh tools write edit exec process apply_patch  # Block all five (default)
```

### Manage the plugin

```bash
./scripts/mainctrl.sh plugin install   # Install the companion plugin
./scripts/mainctrl.sh plugin remove    # Uninstall the plugin
```

## Verification

- [ ] Plugin installed: `./scripts/mainctrl.sh plugin install`
- [ ] Blocking active: `./scripts/mainctrl.sh status` shows safety ON
- [ ] Tool blocked: main agent exec/write/edit/process/apply_patch return block message
- [ ] Sub-agent unaffected: coder can still use write/exec
- [ ] Toggle works: `./scripts/mainctrl.sh off` then `./scripts/mainctrl.sh on` restores blocking
