/**
 * Pi telemetry: emit the same JSONL event stream the Claude Code hooks emit.
 *
 * Why this exists: 15% of hive's source history carries no model attribution at
 * all -- 65 commits touching .go/.js/.ts with no trailer naming what produced
 * them. Any metric keyed on model silently drops those, and the drop is not
 * random: it is whichever tool does not happen to volunteer a trailer. That
 * biases precisely the comparison the telemetry exists to make.
 *
 * Pi's extension surface is TypeScript events rather than stdin-JSON hooks, so
 * this is not a port of the shell hooks -- it is a second emitter writing the
 * same schema. One schema, several tools, which is the only arrangement where
 * the numbers can be compared.
 *
 * Install: copy to ~/.pi/agent/extensions/ (global) or .pi/extensions/
 * (project-local). scripts/telemetry/install-hooks.sh --pi does it for you.
 *
 * Schema (one JSON object per line, appended):
 *   ts, event, project, tool, model, session_id, agent_id, agent_type
 *
 * agent_type is null for pi: it has no named-subagent concept, and inventing a
 * name here would make pi's rows look like Claude Code's Task subagents when
 * they are a different thing. A null that means "not applicable" is worth more
 * than a label that means nothing.
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, basename } from "node:path";
import { execSync } from "node:child_process";
import { homedir } from "node:os";

type Ctx = {
  model?: unknown;
  cwd?: string;
  sessionManager?: { getSessionId?: () => string; getSessionFile?: () => string | undefined };
};

const LOG =
  (process.env.HIVESMITH_TELEMETRY_LOG ?? "") ||
  `${process.env.HIVESMITH_HOME ?? `${homedir()}/.hivesmith`}/telemetry/agent-events.jsonl`;

/** git toplevel basename, so events from every repo land in one stream tagged by project. */
function project(cwd?: string): string {
  try {
    const top = execSync("git rev-parse --show-toplevel", {
      cwd: cwd ?? process.cwd(), stdio: ["ignore", "pipe", "ignore"], encoding: "utf8",
    }).trim();
    return top ? basename(top) : "unknown";
  } catch {
    return "unknown";
  }
}

/** ctx.model is "the active model" but its shape is not contractual — never assume a string. */
function modelName(m: unknown): string | null {
  if (typeof m === "string") return m;
  if (m && typeof m === "object") {
    const o = m as Record<string, unknown>;
    for (const k of ["id", "name", "model", "slug"]) {
      if (typeof o[k] === "string") return o[k] as string;
    }
  }
  return null;
}

function emit(event: string, ctx: Ctx, extra: Record<string, unknown> = {}): void {
  // Telemetry must never be the reason a coding session fails. Every path here
  // swallows its own errors; a lost event is cheaper than a broken agent.
  try {
    const row = {
      ts: new Date().toISOString(),
      event,
      project: project(ctx?.cwd),
      tool: "pi",
      model: modelName(ctx?.model),
      session_id: ctx?.sessionManager?.getSessionId?.() ?? null,
      agent_id: null,
      agent_type: null,
      ...extra,
    };
    mkdirSync(dirname(LOG), { recursive: true });
    appendFileSync(LOG, JSON.stringify(row) + "\n");
  } catch {
    /* never surface telemetry failures into the session */
  }
}

export default function (pi: { on: (e: string, h: (ev: unknown, ctx: Ctx) => void) => void }) {
  pi.on("session_start", (ev, ctx) => {
    const reason = (ev as { reason?: string } | undefined)?.reason ?? null;
    emit("session_start", ctx, { reason });
  });

  pi.on("agent_start", (_ev, ctx) => emit("agent_start", ctx));

  pi.on("agent_end", (ev, ctx) => {
    // agent_end carries `messages` for the run. Record the count, not the
    // content: message bodies are the user's code and prompts, and telemetry
    // that quietly accumulates them is a liability rather than an asset.
    const messages = (ev as { messages?: unknown[] } | undefined)?.messages;
    emit("agent_stop", ctx, { messages: Array.isArray(messages) ? messages.length : null });
  });

  pi.on("session_shutdown", (_ev, ctx) => emit("session_shutdown", ctx));
}
