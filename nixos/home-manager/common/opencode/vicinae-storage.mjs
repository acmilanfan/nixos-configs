import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const execute = promisify(execFile);
const OPENCODE = "opencode"; // Replaced with the Nix package path when building the extension.

export function createRequest(opencode = OPENCODE) {
  let ready;
  return async (route, { method = "GET", query = {}, body } = {}) => {
    // Let the official CLI ensure/discover the service. Then use the published
    // Service.Info registration contract for cheap authenticated HTTP calls.
    // Passwords remain in private runtime files and are never passed on argv.
    if (!ready) {
      ready = execute(opencode, ["api", "GET", "/api/info"], { timeout: 60000 })
        .catch((error) => { ready = undefined; throw error; });
    }
    await ready;
    const file = join(process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "opencode", "service.json");
    const service = JSON.parse(await readFile(file, "utf8"));
    const url = new URL(route, service.url);
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, String(value));
    const headers = { "content-type": "application/json" };
    if (service.password) headers.authorization = `Basic ${Buffer.from(`opencode:${service.password}`).toString("base64")}`;
    const response = await fetch(url, {
      method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`OpenCode HTTP ${response.status}: ${detail.slice(0, 300)}`);
    }
    if (response.status === 204) return;
    return response.json();
  };
}

function toSession(session) {
  return { ...session, directory: session.location.directory, title: session.title || session.slug };
}

export function transcriptEntry(message, sessionID) {
  const info = {
    id: message.id, sessionID, role: ["user", "shell"].includes(message.type) ? "user" : "assistant",
    time: message.time, agent: message.agent, modelID: message.model?.id,
    providerID: message.model?.providerID, cost: message.cost, tokens: message.tokens, finish: message.finish,
  };
  const text = message.type === "compaction" ? `[Compaction]\n${message.summary || ""}`
    : message.type === "shell" ? `$ ${message.command}\n[${message.status}${message.exit === undefined ? "" : `; exit ${message.exit}`}]\n${message.output?.output || ""}`
    : message.text || "";
  const content = message.type === "assistant" ? message.content || [] : [{ type: "text", text }];
  const parts = content.map((part, index) => ({
    id: `${message.id}-${index}`, messageID: message.id, sessionID, type: part.type,
    ...(part.text === undefined ? {} : { text: part.text }),
    ...(part.type !== "tool" ? {} : {
      tool: part.name,
      state: {
        status: part.state?.status, input: part.state?.input,
        output: (part.state?.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n")
          || part.state?.error?.message || "",
      },
    }),
  })).filter((part) => part.type === "tool" || part.text);
  return { message: info, parts };
}

async function visibleSessions() {
  try {
    const { stdout } = await execute("tmux", ["list-panes", "-a", "-F", "#{@opencode-session}"]);
    return stdout.split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

export function createStorage(request, visible = visibleSessions) {
  async function pages(route, query = {}, order = "desc") {
    const rows = [];
    const seen = new Set();
    let cursor;
    do {
      const page = await request(route, { query: { ...query, limit: 200, ...(cursor ? { cursor } : { order }) } });
      if (!Array.isArray(page.data)) throw new Error("OpenCode returned an invalid page");
      rows.push(...page.data);
      const next = page.cursor?.next;
      if (!next) break;
      if (seen.has(next)) throw new Error("OpenCode returned a repeated pagination cursor");
      seen.add(next);
      cursor = next;
    } while (true);
    return rows;
  }
  async function loadSessions(query = {}) {
    return (await pages("/api/session", query)).filter((s) => !s.parentID).map(toSession);
  }
  async function loadTranscript(sessionID) {
    const messages = await pages(`/api/session/${encodeURIComponent(sessionID)}/message`, {}, "asc");
    return messages.map((m) => transcriptEntry(m, sessionID)).filter((entry) => entry.parts.length);
  }
  async function deleteSession(session) {
    await request(`/api/session/${encodeURIComponent(session.id)}`, { method: "DELETE" });
  }
  return {
    async checkDatabase() {
      try {
        const info = await request("/api/info");
        if (!info.version?.startsWith("2.")) return "This extension requires OpenCode v2.";
        return null;
      } catch (error) {
        return `Could not connect to OpenCode v2: ${error.message}`;
      }
    },
    async loadProjects() {
      return (await request("/api/project")).map((project) => ({
        ...project, worktree: project.canonical, vcs: project.vcs || null, name: project.name || null,
      }));
    },
    loadSessions, loadTranscript, deleteSession,
    async deleteAllProjectSessions(projectID) {
      // The API recursively removes children and updates all connected clients.
      for (const session of await loadSessions({ project: projectID })) await deleteSession(session);
    },
    async searchSessions(keyword, limit = 30) {
      const phrase = keyword.toLowerCase().trim();
      if (!phrase) return [];
      const words = phrase.split(/\s+/).filter((word) => word.length >= 2);
      const sessions = (await loadSessions()).filter((s) => !s.time.archived);
      const matches = [];
      let index = 0;
      // Search content through the public message API, with bounded concurrency.
      await Promise.all(Array.from({ length: Math.min(4, sessions.length) }, async () => {
        while (index < sessions.length) {
          const session = sessions[index++];
          const transcript = await loadTranscript(session.id);
          const title = session.title.toLowerCase();
          const content = transcript.flatMap((e) => e.parts.map((p) => p.text || JSON.stringify(p.state?.input || {})))
            .join("\n").toLowerCase();
          let score = (title.includes(phrase) ? 10 : 0) + (content.includes(phrase) ? 5 : 0);
          if (words.length > 1) for (const word of words) score += (title.includes(word) ? 3 : 0) + (content.includes(word) ? 1 : 0);
          if (score) matches.push({ session, score });
        }
      }));
      return matches.sort((a, b) => b.score - a.score || b.session.time.updated - a.session.time.updated)
        .slice(0, limit).map((m) => m.session);
    },
    async getOpenSessions() {
      const [active, open] = await Promise.all([request("/api/session/active"), visible()]);
      return [...new Set([...Object.keys(active.data), ...open])]
        .map((id) => ({ id, liveness: active.data[id] ? "active" : "open" }));
    },
  };
}

const storage = createStorage(createRequest());
export const { checkDatabase, loadProjects, loadSessions, loadTranscript, deleteSession,
  deleteAllProjectSessions, searchSessions, getOpenSessions } = storage;
