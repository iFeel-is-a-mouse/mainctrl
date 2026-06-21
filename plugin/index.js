import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { homedir } from "node:os";

const STATE_FILE = resolve(homedir(), ".openclaw/workspace/skills/mainctrl/scripts/state.json");

const DEFAULT_BLOCKED_TOOLS = ["write", "edit", "exec", "process", "apply_patch"];
const DEFAULT_CONTROLLED_AGENTS = ["main"];

/**
 * Read current control state from the skill's state file.
 * Gracefully handles missing files and corrupted JSON by falling
 * back to permissive mode (enabled=false, no blocking).
 */
function readState() {
  try {
    if (!existsSync(STATE_FILE)) {
      return {
        enabled: false,
        controlledAgents: DEFAULT_CONTROLLED_AGENTS,
        blockedTools: DEFAULT_BLOCKED_TOOLS,
      };
    }
    const raw = readFileSync(STATE_FILE, "utf-8");
    const state = JSON.parse(raw);
    return {
      enabled: state.enabled !== false,
      controlledAgents: Array.isArray(state.controlledAgents) && state.controlledAgents.length > 0
        ? state.controlledAgents
        : DEFAULT_CONTROLLED_AGENTS,
      blockedTools: Array.isArray(state.blockedTools)
        ? state.blockedTools
        : DEFAULT_BLOCKED_TOOLS,
    };
  } catch {
    return {
      enabled: false,
      controlledAgents: DEFAULT_CONTROLLED_AGENTS,
      blockedTools: DEFAULT_BLOCKED_TOOLS,
    };
  }
}

const plugin = {
  id: "mainctrl",
  name: "mainctrl",
  description: "Runtime tool-access guard for OpenClaw agents. Intercepts destructive tool calls (write, edit, exec, process, apply_patch) before they execute, redirecting controlled agents to delegate via sub-agents. Configured via a companion skill (mainctrl.sh) — no agent config changes needed, no restart required for toggles.",

  register(e) {
    e.on?.("before_tool_call", (event, ctx) => {
      const state = readState();

      // When the safety is off (enabled=false), allow everything
      if (!state.enabled) return;

      // Only intercept for controlled agents
      if (!state.controlledAgents.includes(ctx.agentId || "")) return;

      // Block if the requested tool is on the blocked list
      if (state.blockedTools.includes(event.toolName)) {
        return {
          block: true,
          blockReason: "Delegate this work to a sub-agent instead. Use sessions_spawn to dispatch to coder, tester, auditor, or publicist.",
        };
      }
    });
  },
};

export default plugin;
