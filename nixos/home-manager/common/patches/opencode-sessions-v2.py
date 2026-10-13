"""Replace the pinned Raycast extension's v1 SDK/SQL storage with v2 APIs."""
import json
from pathlib import Path
import sys

source, opencode = sys.argv[1:]
storage = Path("src/lib/storage.ts")
clients = Path("src/lib/clients.ts")
if "FROM session" not in storage.read_text() or "createOpencode" not in clients.read_text():
    sys.exit("opencode-sessions v1 source changed; review the v2 patch")

adapter = Path(source).read_text().replace(
    'const OPENCODE = "opencode";', f"const OPENCODE = {json.dumps(opencode)};", 1
)
Path("src/lib/opencode-v2.mjs").write_text(adapter)
Path("src/lib/opencode-v2.d.mts").write_text("""import type { Project, Session, TranscriptEntry } from '../types';
export function checkDatabase(): Promise<string | null>;
export function loadProjects(): Promise<Project[]>;
export function loadSessions(): Promise<Session[]>;
export function loadTranscript(sessionID: string): Promise<TranscriptEntry[]>;
export function deleteSession(session: Session): Promise<void>;
export function deleteAllProjectSessions(projectID: string): Promise<void>;
export function searchSessions(keyword: string, limit?: number): Promise<Session[]>;
export function getOpenSessions(): Promise<Array<{id: string; liveness: 'active' | 'open'}>>;
""")
storage.write_text("""export {
  checkDatabase, loadProjects, loadSessions, loadTranscript, deleteSession,
  deleteAllProjectSessions, searchSessions, getOpenSessions,
} from './opencode-v2.mjs';
export type SessionLiveness = 'active' | 'open';
export interface OpenSession { id: string; liveness: SessionLiveness }
""")
clients.write_text("""import { loadTranscript } from './storage';

// Preserve the two calls used by useSessions without starting a v1 server.
export async function getClient() {
  return {
    session: {
      // OpenCode v2 has no TodoWrite tool or todo endpoint.
      todo: async (_input: { sessionID: string }) => ({ data: [] }),
      messages: async ({ sessionID, limit }: { sessionID: string; limit: number }) => ({
        data: (await loadTranscript(sessionID)).slice(-limit).map(entry => ({
          info: entry.message, parts: entry.parts,
        })),
      }),
    },
  };
}
""")

# v2 deletes sessions through its API; projects themselves remain known to it.
actions = Path("src/components/SessionActions.tsx")
actions.write_text(actions.read_text().replace(
    "The project will no longer appear in the list.", "The project's sessions will be removed."
))
print("patched opencode-sessions storage and activity client for OpenCode v2")
