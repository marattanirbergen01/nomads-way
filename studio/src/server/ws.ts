// WebSocket: живые обновления и присутствие («кто в какой сцене»).
import { WebSocketServer, WebSocket } from 'ws';
import type { Server } from 'node:http';
import { sessionUser, type User } from './auth.js';

interface Client {
  ws: WebSocket;
  user: User;
  episodeId?: string;
  sceneId?: number | null;
  editing?: string | null; // 'beat:12' | 'scene:3'
}

const clients = new Set<Client>();

export type Event =
  | { type: 'episode.changed'; episodeId: string; what: string; by: number }
  | { type: 'episodes.changed' }
  | { type: 'media.changed'; seasonId: string; id?: string }
  | { type: 'comment'; episodeId: string | null; targetType: string; targetId: string }
  | { type: 'presence'; episodeId: string; users: PresenceEntry[] }
  | { type: 'build'; episodeId: string; line: string; running: boolean; ok?: boolean };

export interface PresenceEntry {
  userId: number;
  name: string;
  role: string;
  sceneId: number | null;
  editing: string | null;
}

export function broadcast(ev: Event, opts: { episodeId?: string } = {}) {
  const msg = JSON.stringify(ev);
  for (const c of clients) {
    if (opts.episodeId && c.episodeId !== opts.episodeId) continue;
    if (c.ws.readyState === WebSocket.OPEN) c.ws.send(msg);
  }
}

function presenceFor(episodeId: string): PresenceEntry[] {
  const seen = new Map<number, PresenceEntry>();
  for (const c of clients) {
    if (c.episodeId !== episodeId) continue;
    const prev = seen.get(c.user.id);
    // один человек в двух вкладках: показываем то, где он что-то редактирует
    if (!prev || c.editing) {
      seen.set(c.user.id, {
        userId: c.user.id,
        name: c.user.name,
        role: c.user.role,
        sceneId: c.sceneId ?? null,
        editing: c.editing ?? null,
      });
    }
  }
  return [...seen.values()];
}

export function pushPresence(episodeId: string) {
  broadcast({ type: 'presence', episodeId, users: presenceFor(episodeId) }, { episodeId });
}

export function attachWs(server: Server) {
  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    if (!req.url?.startsWith('/ws')) return;
    const cookie = req.headers.cookie ?? '';
    const m = cookie.match(/studio_session=([a-f0-9]+)/);
    const user = m ? sessionUser(m[1]) : undefined;
    if (!user) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      const client: Client = { ws, user };
      clients.add(client);
      ws.on('message', (raw) => {
        let msg: any;
        try {
          msg = JSON.parse(String(raw));
        } catch {
          return;
        }
        if (msg.type === 'presence') {
          const prevEp = client.episodeId;
          client.episodeId = msg.episodeId ?? undefined;
          client.sceneId = msg.sceneId ?? null;
          client.editing = msg.editing ?? null;
          if (prevEp && prevEp !== client.episodeId) pushPresence(prevEp);
          if (client.episodeId) pushPresence(client.episodeId);
        }
        if (msg.type === 'ping') ws.send('{"type":"pong"}');
      });
      ws.on('close', () => {
        clients.delete(client);
        if (client.episodeId) pushPresence(client.episodeId);
      });
    });
  });
}
