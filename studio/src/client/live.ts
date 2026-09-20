// Одно WebSocket-соединение на вкладку. Подписчики получают события сервера;
// присутствие («я в сцене N, правлю реплику M») отправляем отсюда же.
import { useEffect, useState } from 'react';

type Listener = (ev: any) => void;
const listeners = new Set<Listener>();
let ws: WebSocket | null = null;
let presence: any = null;
let retry = 1000;
let online = false;
const onlineListeners = new Set<(v: boolean) => void>();

function setOnline(v: boolean) {
  online = v;
  onlineListeners.forEach((l) => l(v));
}

export function connectLive() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onopen = () => {
    retry = 1000;
    setOnline(true);
    if (presence) ws?.send(JSON.stringify({ type: 'presence', ...presence }));
  };
  ws.onmessage = (m) => {
    let ev: any;
    try {
      ev = JSON.parse(m.data);
    } catch {
      return;
    }
    listeners.forEach((l) => l(ev));
  };
  ws.onclose = () => {
    setOnline(false);
    ws = null;
    setTimeout(connectLive, retry);
    retry = Math.min(retry * 2, 15000);
  };
  ws.onerror = () => ws?.close();
}

export function disconnectLive() {
  const s = ws;
  ws = null;
  s?.close();
}

export function setPresence(p: { episodeId: string | null; sceneId?: number | null; editing?: string | null }) {
  presence = p;
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'presence', ...p }));
}

export function useLive(handler: Listener, deps: unknown[] = []) {
  useEffect(() => {
    listeners.add(handler);
    return () => {
      listeners.delete(handler);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}

export function useOnline() {
  const [v, setV] = useState(online);
  useEffect(() => {
    onlineListeners.add(setV);
    return () => {
      onlineListeners.delete(setV);
    };
  }, []);
  return v;
}

// keep-alive, чтобы прокси не рвали соединение
setInterval(() => {
  if (ws?.readyState === WebSocket.OPEN) ws.send('{"type":"ping"}');
}, 25000);
