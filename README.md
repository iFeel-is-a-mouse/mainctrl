# mainctrl

Stop `main` from shooting itself in the foot.

I kept telling main "don't write code yourself" — and it kept ignoring me. `tools.deny` seemed like the answer, but it had two fatal flaws: deny rules cascade to sub-agents, so coder gets blocked too. And changing the config meant a restart, which is the last thing you want when main's mid-flow. So I built mainctrl: a way to pull main back to its senses anytime it tries to do someone else's job.

mainctrl blocks destructive tool calls for agents you choose. By default it watches `main` — the agent that orchestrates, not executes. When `main` tries to write a file or run a shell command, mainctrl says no and tells it to delegate to a sub-agent instead.

It's a `before_tool_call` hook, not a `tools.deny` rule. The difference matters: `tools.deny` cascades to sub-agents — block `write` on `main` and suddenly `coder` can't write either. mainctrl checks who's calling and only intercepts the agents you've named. Sub-agents keep full access.

## Plugin + Skill

mainctrl is two independent parts that work together:

- **Plugin** (`plugin/index.js`) — a `before_tool_call` hook that actually
  intercepts tool calls. Reads `state.json` on every invocation.
  Installed via `./scripts/mainctrl.sh plugin install`.
  Part of OpenClaw's plugin system.
- **Skill** (`skills/mainctrl/`) — the management side. Provides the CLI
  script (`mainctrl.sh`) for control and the agent behavior instructions
  (SKILL.md) for when blocking fires.
  Part of OpenClaw's skill system.

**Why two parts?** The plugin does the actual interception — it's the runtime
hook that blocks tool calls. But a plugin has no management interface. The
skill fills that gap: the CLI script lets you toggle safety on/off, change
controlled agents, and inspect state. Together they form a complete system.

**How they communicate:** Both talk through `scripts/state.json`. The skill's
CLI writes this file; the plugin reads it. No sockets, no RPC, no restarts.
A single synchronous filesystem read per tool call.

**Both must be installed.** Install the plugin without the skill and you have
no way to control the switches. Install the skill without the plugin and
nothing gets intercepted.



## Install

mainctrl is two parts that work together:

| Part | What it does | Install |
|------|-------------|---------|
| Plugin | Runtime hook — intercepts tool calls | `./scripts/mainctrl.sh plugin install` |
| Skill | CLI + agent instructions — manages the plugin | Already installed (you're looking at it) |

**Both are required.** The plugin without the skill has no management interface;
the skill without the plugin has nothing to control.

The skill comes with a script that installs the plugin for you:
```bash
./scripts/mainctrl.sh plugin install       # installs the companion plugin
openclaw gateway restart                    # activate the plugin
```

Verify installation:
```bash
./scripts/mainctrl.sh status
```

Should show `safety: OFF (all tools passthrough)`. Turn it on:
```bash
./scripts/mainctrl.sh on
```

**From ClawHub** (when published):
```bash
openclaw plugins install clawhub:mainctrl
openclaw skills install clawhub:mainctrl
```

## Use

```bash
./scripts/mainctrl.sh on          # start blocking
./scripts/mainctrl.sh off         # emergency off — everything passes through
./scripts/mainctrl.sh status      # see what's happening

./scripts/mainctrl.sh agents main auditor   # control more agents
./scripts/mainctrl.sh agents                # stop controlling all agents

./scripts/mainctrl.sh tools                 # see what's blocked
./scripts/mainctrl.sh tools write exec      # only block write and exec
```

`status` prints:

```
mainctrl status:
  safety:            ON  (blocking is active)
  controlled agents: main

  Tool          Status
  ------------  --------
  write           BLOCKED
  edit            BLOCKED
  exec            BLOCKED
  process         BLOCKED
  apply_patch     BLOCKED
```

## What gets blocked

Five tools by default: `write`, `edit`, `exec`, `process`, `apply_patch`. These mutate files or run commands. Read-only tools always pass through.

When a call gets blocked, the agent sees:

> Delegate this work to a sub-agent instead. Use sessions_spawn to dispatch to coder, tester, auditor, or publicist.

The expectation is the agent reports the block and spawns a sub-agent immediately — no asking for permission, no waiting.

## How it works

Mainctrl gives the agent two modes, like vi's V and I:

**Visual mode** (`mainctrl on`) — the agent can inspect, search, and read,
but cannot modify anything. Every destructive tool call is blocked.

**Insert mode** (`mainctrl off`) — the agent can write files, run commands,
and make changes freely.

Switch between them with `./scripts/mainctrl.sh on` and `./scripts/mainctrl.sh off`.

Every tool call hits the hook. Three checks, one file read:

1. `enabled` true? No → let it through.
2. Caller is a controlled agent? No (it's a sub-agent) → let it through.
3. Tool is on the blocked list? Yes → block with the delegation message. No → let it through.

State lives in `scripts/state.json`:

```json
{
  "enabled": false,
  "controlledAgents": ["main"],
  "blockedTools": ["write", "edit", "exec", "process", "apply_patch"]
}
```

Changes take effect on the next tool call. The plugin reads this file on every invocation — one synchronous filesystem read, basically free. If the file is missing or the JSON is broken, the plugin falls back to permissive mode (everything allowed). Nothing crashes.

## Why not just `tools.deny`?

Two practical reasons.

`tools.deny` is static config. Changing it means editing YAML or JSON, then restarting the gateway. `./scripts/mainctrl.sh off` works on the next call. During development you flip this switch constantly — restarting every time would be painful.

`tools.deny` inherits to sub-agents. If `main` can't `write`, `coder` loses it too. That's correct for security isolation, but mainctrl isn't about isolation — it's about workflow enforcement. `main` delegates, `coder` executes. The plugin checks `agentId` and only intercepts the ones you name.

## Files

```
projects/mainctrl/
├── SKILL.md                 # agent-facing instructions
├── scripts/
│   ├── mainctrl.sh          # CLI: on, off, status, agents, tools, plugin
│   └── state.json           # runtime config — CLI writes, plugin reads
└── plugin/
    ├── index.js             # before_tool_call hook
    ├── package.json
    └── openclaw.plugin.json
```

The plugin and CLI share `state.json`. That's the entire communication channel — no sockets, no RPC, no config reload. Just a file.
