// Медиа: где лежит файл кадра и как его отдать в браузер.
// Порядок поиска: загруженное через студию (DATA_DIR/uploads/<season>/) →
// упакованное out/ в content/media/<season>/ → исходник в content/media/<season>/<kind>/.
import fs from 'node:fs';
import path from 'node:path';
import { contentDir, uploadsDir } from './config.js';
import { get, run, j } from './db.js';
import { broadcast } from './ws.js';
import { logActivity } from './service.js';
import type { User } from './auth.js';

const EXT = ['.jpg', '.jpeg', '.png', '.webp'];

export function resolveMediaFile(season: string, id: string): string | undefined {
  if (!/^[a-z0-9_]+$/i.test(id) || !/^s\d+$/.test(season)) return;
  const mediaRoot = path.join(contentDir, 'media', season);
  const candidates: string[] = [];
  for (const e of EXT) candidates.push(path.join(uploadsDir, season, id + e));
  const outDirs = ['', 'avatars', 'characters'];
  for (const d of outDirs) for (const e of EXT) candidates.push(path.join(mediaRoot, 'out', d, id + e));
  const srcDirs = ['scenes', 'backgrounds', 'maps', 'avatars', 'characters', 'app'];
  for (const d of srcDirs) for (const e of EXT) candidates.push(path.join(mediaRoot, d, id + e));
  return candidates.find((p) => fs.existsSync(p));
}

export function hasMediaFile(season: string, id: string) {
  return !!resolveMediaFile(season, id);
}

export const KIND_DIR: Record<string, string> = {
  scene: 'scenes',
  cover: 'backgrounds',
  banner: 'backgrounds',
  map: 'maps',
  avatar: 'avatars',
  character: 'characters',
  icon: 'app',
};

const MEDIA_FIELDS = new Set(['kind', 'status', 'brief', 'seed', 'prompt_text', 'approved_by', 'note', 'source', 'generated']);

export function upsertMedia(user: User, seasonId: string, id: string, patch: Record<string, any>) {
  if (!/^[a-z0-9_]+$/.test(id)) throw new Error('id медиа: латиница, цифры, _');
  const cur = get('SELECT * FROM media WHERE id = ?', id);
  if (!cur) {
    const kind = patch.kind ?? 'scene';
    run(
      `INSERT INTO media(id, season_id, kind, status, brief, prompt_ref) VALUES (?, ?, ?, 'missing', ?, ?)`,
      id, seasonId, kind, patch.brief ?? null, `prompts/${KIND_DIR[kind] ?? 'scenes'}/${id}.md`,
    );
  }
  const sets: string[] = [];
  const vals: any[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (!MEDIA_FIELDS.has(k)) continue;
    sets.push(`${k} = ?`);
    vals.push(k === 'source' ? j(v) : v ?? null);
  }
  if (sets.length) {
    sets.push('version = version + 1', "updated_at = datetime('now')");
    vals.push(id);
    run(`UPDATE media SET ${sets.join(', ')} WHERE id = ?`, ...vals);
  }
  logActivity(user, null, cur ? 'media.update' : 'media.create', 'media', id, { fields: Object.keys(patch) });
  broadcast({ type: 'media.changed', seasonId, id });
}

export async function saveUpload(user: User, seasonId: string, id: string, file: File) {
  if (!/^[a-z0-9_]+$/.test(id)) throw new Error('id медиа: латиница, цифры, _');
  const ext = path.extname(file.name).toLowerCase() || '.png';
  if (!EXT.includes(ext)) throw new Error('Только jpg/png/webp');
  const dir = path.join(uploadsDir, seasonId);
  fs.mkdirSync(dir, { recursive: true });
  // старые загрузки с другим расширением убираем, чтобы не было двух версий
  for (const e of EXT) {
    const p = path.join(dir, id + e);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  const target = path.join(dir, id + ext);
  fs.writeFileSync(target, Buffer.from(await file.arrayBuffer()));
  const cur = get('SELECT * FROM media WHERE id = ?', id);
  const kind = cur?.kind ?? (id.startsWith('avatar_') ? 'avatar' : id.startsWith('char_') ? 'character' : id.startsWith('map_') ? 'map' : id.startsWith('cover_') ? 'cover' : 'scene');
  if (!cur) {
    run(
      `INSERT INTO media(id, season_id, kind, status, prompt_ref) VALUES (?, ?, ?, 'draft', ?)`,
      id, seasonId, kind, `prompts/${KIND_DIR[kind]}/${id}.md`,
    );
  }
  run(
    `UPDATE media SET upload = ?, file = ?, status = CASE WHEN status = 'missing' THEN 'draft' ELSE status END,
       generated = COALESCE(generated, date('now')), version = version + 1, updated_at = datetime('now') WHERE id = ?`,
    `${seasonId}/${id}${ext}`, `${KIND_DIR[kind]}/${id}${ext}`, id,
  );
  logActivity(user, null, 'media.upload', 'media', id, { file: file.name, size: file.size });
  broadcast({ type: 'media.changed', seasonId, id });
}

export function deleteMedia(user: User, id: string) {
  const cur = get('SELECT * FROM media WHERE id = ?', id);
  if (!cur) return;
  const used = get('SELECT scene_id FROM scenes WHERE art = ? OR art_when LIKE ?', id, `%"${id}"%`);
  if (used) throw new Error(`Кадр используется в сцене ${used.scene_id}`);
  run('DELETE FROM media WHERE id = ?', id);
  if (cur.upload) {
    const p = path.join(uploadsDir, cur.upload);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  logActivity(user, null, 'media.delete', 'media', id);
  broadcast({ type: 'media.changed', seasonId: cur.season_id, id });
}
