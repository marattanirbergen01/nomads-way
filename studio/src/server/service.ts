// Чтение и изменение серии. Все правки идут через эти функции:
// проверка версии (оптимистическая блокировка), запись в activity, событие в WebSocket.
import { all, get, run, transaction, j, pj } from './db.js';
import { broadcast } from './ws.js';
import type { User } from './auth.js';
import { normEmotion } from './importer.js';
import type { Episode as EpisodeFull } from '../client/types.js';

export class ConflictError extends Error {
  constructor(public current: any) {
    super('conflict');
  }
}
export class NotFound extends Error {}

const AGENT_ROLES = new Set(['agent_script', 'agent_media']);

export function logActivity(
  user: User | null,
  episodeId: string | null,
  action: string,
  targetType: string | null,
  targetId: string | null,
  detail?: unknown,
) {
  run(
    'INSERT INTO activity(user_id, episode_id, action, target_type, target_id, detail) VALUES (?, ?, ?, ?, ?, ?)',
    user?.id ?? null, episodeId, action, targetType, targetId, j(detail ?? null),
  );
}

// ---------------------------------------------------------------- чтение
export function listEpisodes() {
  const seasons = all('SELECT * FROM seasons ORDER BY sort');
  const episodes = all(
    `SELECT e.*,
       (SELECT COUNT(*) FROM scenes s WHERE s.episode_id = e.id) AS scene_count,
       (SELECT COUNT(*) FROM scenes s WHERE s.episode_id = e.id AND s.status = 'ready') AS ready_count,
       (SELECT COUNT(*) FROM comments c WHERE c.episode_id = e.id AND c.resolved = 0 AND c.parent_id IS NULL) AS open_comments
     FROM episodes e ORDER BY e.season_id, e.sort`,
  ).map((e) => ({ ...e, topics: pj(e.topics, []) }));
  return { seasons, episodes };
}

export function loadEpisode(id: string): EpisodeFull {
  const ep = get('SELECT * FROM episodes WHERE id = ?', id);
  if (!ep) throw new NotFound();
  const characters = all('SELECT * FROM characters WHERE episode_id = ? ORDER BY sort', id).map((c) => ({
    ...c,
    default_name: pj(c.default_name, null),
  }));
  const scenes = all('SELECT * FROM scenes WHERE episode_id = ? ORDER BY sort', id).map((s) => ({
    ...s,
    art_when: pj(s.art_when, null),
    covers: pj(s.covers, []),
    quiz: pj(s.quiz, []),
    beats: all('SELECT * FROM beats WHERE scene_id = ? ORDER BY sort', s.id).map((b) => ({
      ...b,
      choice: pj(b.choice, null),
    })),
  }));
  const questions = all('SELECT * FROM questions WHERE episode_id = ? ORDER BY sort', id).map((q) => ({
    ...q,
    data: pj(q.data, {}),
  }));
  const commentCounts: Record<string, number> = {};
  for (const r of all<{ k: string; n: number }>(
    `SELECT target_type || ':' || target_id AS k, COUNT(*) AS n FROM comments
     WHERE episode_id = ? AND resolved = 0 AND parent_id IS NULL GROUP BY k`,
    id,
  )) commentCounts[r.k] = r.n;
  const users = all('SELECT id, name, role FROM users');
  return {
    ...ep,
    topics: pj(ep.topics, []),
    final_test: pj(ep.final_test, null),
    characters,
    scenes,
    questions,
    commentCounts,
    users,
  } as unknown as EpisodeFull;
}

export function loadMedia(seasonId: string): any[] {
  return all('SELECT * FROM media WHERE season_id = ? ORDER BY kind, id', seasonId).map((m) => ({
    ...m,
    source: pj(m.source, null),
  }));
}

// ---------------------------------------------------------------- сцены
function nextSceneSort(episodeId: string, afterSort: number | null) {
  // Вставляем после afterSort: сдвигаем всё, что дальше.
  if (afterSort === null) {
    const r = get<{ m: number }>('SELECT COALESCE(MAX(sort), -1) AS m FROM scenes WHERE episode_id = ?', episodeId);
    return (r?.m ?? -1) + 1;
  }
  run('UPDATE scenes SET sort = sort + 1 WHERE episode_id = ? AND sort > ?', episodeId, afterSort);
  return afterSort + 1;
}

export function createScene(user: User, episodeId: string, input: { scene_id: string; after?: number | null }) {
  if (!/^[a-z0-9_]+$/.test(input.scene_id)) throw new Error('id сцены: латиница, цифры, _');
  if (get('SELECT id FROM scenes WHERE episode_id = ? AND scene_id = ?', episodeId, input.scene_id))
    throw new Error('Сцена с таким id уже есть');
  return transaction(() => {
    const afterSort =
      input.after != null ? get<{ sort: number }>('SELECT sort FROM scenes WHERE id = ?', input.after)?.sort ?? null : null;
    const sort = nextSceneSort(episodeId, afterSort);
    const r = run(
      'INSERT INTO scenes(episode_id, scene_id, sort, updated_by) VALUES (?, ?, ?, ?)',
      episodeId, input.scene_id, sort, user.id,
    );
    const id = Number(r.lastInsertRowid);
    touchEpisode(episodeId);
    logActivity(user, episodeId, 'scene.create', 'scene', String(id), { scene_id: input.scene_id });
    broadcast({ type: 'episode.changed', episodeId, what: 'scene', by: user.id }, { episodeId });
    return id;
  });
}

const SCENE_FIELDS = new Set([
  'scene_id', 'art', 'art_when', 'layer', 'covers', 'title_kk', 'title_ru', 'pan',
  'avatar_side', 'avatar_in_art', 'quiz', 'note', 'status',
]);
const JSON_SCENE_FIELDS = new Set(['art_when', 'covers', 'quiz']);

export function updateScene(user: User, sceneId: number, patch: Record<string, any>, version: number | undefined) {
  const cur = get('SELECT * FROM scenes WHERE id = ?', sceneId);
  if (!cur) throw new NotFound();
  if (version !== undefined && cur.version !== version) throw new ConflictError(cur);
  const sets: string[] = [];
  const vals: any[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (!SCENE_FIELDS.has(k)) continue;
    sets.push(`${k} = ?`);
    vals.push(JSON_SCENE_FIELDS.has(k) ? j(v) : k === 'avatar_in_art' ? (v ? 1 : 0) : v ?? null);
  }
  if (!sets.length) return cur.version;
  sets.push('version = version + 1', "updated_at = datetime('now')", 'updated_by = ?');
  vals.push(user.id, sceneId);
  run(`UPDATE scenes SET ${sets.join(', ')} WHERE id = ?`, ...vals);
  touchEpisode(cur.episode_id);
  logActivity(user, cur.episode_id, 'scene.update', 'scene', String(sceneId), { fields: Object.keys(patch) });
  broadcast({ type: 'episode.changed', episodeId: cur.episode_id, what: 'scene', by: user.id }, { episodeId: cur.episode_id });
  return cur.version + 1;
}

export function deleteScene(user: User, sceneId: number) {
  const cur = get('SELECT * FROM scenes WHERE id = ?', sceneId);
  if (!cur) throw new NotFound();
  transaction(() => {
    run('DELETE FROM scenes WHERE id = ?', sceneId);
    run('UPDATE scenes SET sort = sort - 1 WHERE episode_id = ? AND sort > ?', cur.episode_id, cur.sort);
  });
  touchEpisode(cur.episode_id);
  logActivity(user, cur.episode_id, 'scene.delete', 'scene', String(sceneId), { scene_id: cur.scene_id });
  broadcast({ type: 'episode.changed', episodeId: cur.episode_id, what: 'scene', by: user.id }, { episodeId: cur.episode_id });
}

export function reorderScenes(user: User, episodeId: string, ids: number[]) {
  transaction(() => {
    ids.forEach((id, i) => run('UPDATE scenes SET sort = ? WHERE id = ? AND episode_id = ?', i, id, episodeId));
  });
  touchEpisode(episodeId);
  logActivity(user, episodeId, 'scene.reorder', null, null, { ids });
  broadcast({ type: 'episode.changed', episodeId, what: 'scene', by: user.id }, { episodeId });
}

// ---------------------------------------------------------------- реплики
export function createBeat(
  user: User,
  sceneId: number,
  input: { kind: 'say' | 'choice'; after?: number | null; who?: string },
) {
  const scene = get('SELECT * FROM scenes WHERE id = ?', sceneId);
  if (!scene) throw new NotFound();
  return transaction(() => {
    let sort: number;
    if (input.after != null) {
      const a = get<{ sort: number }>('SELECT sort FROM beats WHERE id = ?', input.after);
      sort = (a?.sort ?? -1) + 1;
      run('UPDATE beats SET sort = sort + 1 WHERE scene_id = ? AND sort >= ?', sceneId, sort);
    } else {
      const m = get<{ m: number }>('SELECT COALESCE(MAX(sort), -1) AS m FROM beats WHERE scene_id = ?', sceneId);
      sort = (m?.m ?? -1) + 1;
    }
    const agent = AGENT_ROLES.has(user.role);
    const choice =
      input.kind === 'choice'
        ? { prompt: { kk: '', ru: '' }, options: [{ id: 'a', kk: '', ru: '', set: null, goto: null, art: null, reply: null }, { id: 'b', kk: '', ru: '', set: null, goto: null, art: null, reply: null }] }
        : null;
    const r = run(
      `INSERT INTO beats(scene_id, sort, kind, who, choice, origin, needs_review, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      sceneId, sort, input.kind, input.who ?? null, j(choice), agent ? 'agent' : 'human', agent ? 1 : 0, user.id,
    );
    const id = Number(r.lastInsertRowid);
    touchEpisode(scene.episode_id);
    logActivity(user, scene.episode_id, 'beat.create', 'beat', String(id), { scene: scene.scene_id });
    broadcast({ type: 'episode.changed', episodeId: scene.episode_id, what: 'beat', by: user.id }, { episodeId: scene.episode_id });
    return id;
  });
}

const BEAT_FIELDS = new Set(['who', 'kk', 'ru', 'emotion', 'when_cond', 'choice', 'needs_review']);

export function updateBeat(user: User, beatId: number, patch: Record<string, any>, version: number | undefined) {
  const cur = get('SELECT b.*, s.episode_id, s.scene_id AS scene_code FROM beats b JOIN scenes s ON s.id = b.scene_id WHERE b.id = ?', beatId);
  if (!cur) throw new NotFound();
  if (version !== undefined && cur.version !== version) throw new ConflictError({ ...cur, choice: pj(cur.choice, null) });
  const sets: string[] = [];
  const vals: any[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (!BEAT_FIELDS.has(k)) continue;
    sets.push(`${k} = ?`);
    if (k === 'choice') vals.push(j(v));
    else if (k === 'emotion') vals.push(normEmotion(v));
    else if (k === 'needs_review') vals.push(v ? 1 : 0);
    else vals.push(v ?? null);
  }
  if (!sets.length) return cur.version;
  const agent = AGENT_ROLES.has(user.role);
  if (agent && !('needs_review' in patch)) {
    sets.push("origin = 'agent'", 'needs_review = 1');
  } else if (!agent && !('needs_review' in patch)) {
    // человек отредактировал — предложение агента считается просмотренным
    sets.push('needs_review = 0');
  }
  sets.push('version = version + 1', "updated_at = datetime('now')", 'updated_by = ?');
  vals.push(user.id, beatId);
  run(`UPDATE beats SET ${sets.join(', ')} WHERE id = ?`, ...vals);
  touchEpisode(cur.episode_id);
  logActivity(user, cur.episode_id, 'beat.update', 'beat', String(beatId), { scene: cur.scene_code, fields: Object.keys(patch) });
  broadcast({ type: 'episode.changed', episodeId: cur.episode_id, what: 'beat', by: user.id }, { episodeId: cur.episode_id });
  return cur.version + 1;
}

export function deleteBeat(user: User, beatId: number) {
  const cur = get('SELECT b.*, s.episode_id, s.scene_id AS scene_code FROM beats b JOIN scenes s ON s.id = b.scene_id WHERE b.id = ?', beatId);
  if (!cur) throw new NotFound();
  transaction(() => {
    run('DELETE FROM beats WHERE id = ?', beatId);
    run('UPDATE beats SET sort = sort - 1 WHERE scene_id = ? AND sort > ?', cur.scene_id, cur.sort);
  });
  touchEpisode(cur.episode_id);
  logActivity(user, cur.episode_id, 'beat.delete', 'beat', String(beatId), { scene: cur.scene_code, text: cur.ru || cur.kk });
  broadcast({ type: 'episode.changed', episodeId: cur.episode_id, what: 'beat', by: user.id }, { episodeId: cur.episode_id });
}

export function reorderBeats(user: User, sceneId: number, ids: number[]) {
  const scene = get('SELECT * FROM scenes WHERE id = ?', sceneId);
  if (!scene) throw new NotFound();
  transaction(() => {
    ids.forEach((id, i) => run('UPDATE beats SET sort = ? WHERE id = ? AND scene_id = ?', i, id, sceneId));
  });
  touchEpisode(scene.episode_id);
  logActivity(user, scene.episode_id, 'beat.reorder', 'scene', String(sceneId), { ids });
  broadcast({ type: 'episode.changed', episodeId: scene.episode_id, what: 'beat', by: user.id }, { episodeId: scene.episode_id });
}

// ---------------------------------------------------------------- персонажи и серия
export function upsertCharacter(user: User, episodeId: string, ch: Record<string, any>) {
  if (!/^[a-z0-9_]+$/.test(ch.char_id ?? '')) throw new Error('id персонажа: латиница, цифры, _');
  const sortRow = get<{ m: number }>('SELECT COALESCE(MAX(sort), -1) AS m FROM characters WHERE episode_id = ?', episodeId);
  run(
    `INSERT INTO characters(episode_id, char_id, sort, name_kk, name_ru, fiction, note, avatar, default_name, portrait)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(episode_id, char_id) DO UPDATE SET name_kk=excluded.name_kk, name_ru=excluded.name_ru, fiction=excluded.fiction,
       note=excluded.note, avatar=excluded.avatar, default_name=excluded.default_name, portrait=excluded.portrait`,
    episodeId, ch.char_id, (sortRow?.m ?? -1) + 1, ch.name_kk ?? '', ch.name_ru ?? '', ch.fiction ? 1 : 0,
    ch.note ?? null, ch.avatar ? 1 : 0, j(ch.default_name ?? null), ch.portrait ?? null,
  );
  touchEpisode(episodeId);
  logActivity(user, episodeId, 'character.upsert', 'character', ch.char_id);
  broadcast({ type: 'episode.changed', episodeId, what: 'character', by: user.id }, { episodeId });
}

export function deleteCharacter(user: User, episodeId: string, charId: string) {
  run('DELETE FROM characters WHERE episode_id = ? AND char_id = ?', episodeId, charId);
  touchEpisode(episodeId);
  logActivity(user, episodeId, 'character.delete', 'character', charId);
  broadcast({ type: 'episode.changed', episodeId, what: 'character', by: user.id }, { episodeId });
}

const EPISODE_FIELDS = new Set(['title_kk', 'title_ru', 'era', 'topics', 'final_test', 'status', 'approved_by', 'slug']);

export function updateEpisode(user: User, episodeId: string, patch: Record<string, any>) {
  const cur = get('SELECT * FROM episodes WHERE id = ?', episodeId);
  if (!cur) throw new NotFound();
  const sets: string[] = [];
  const vals: any[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (!EPISODE_FIELDS.has(k)) continue;
    sets.push(`${k} = ?`);
    vals.push(k === 'topics' || k === 'final_test' ? j(v) : v ?? null);
  }
  if (!sets.length) return;
  sets.push('version = version + 1', "updated_at = datetime('now')");
  vals.push(episodeId);
  run(`UPDATE episodes SET ${sets.join(', ')} WHERE id = ?`, ...vals);
  logActivity(user, episodeId, 'episode.update', 'episode', episodeId, { fields: Object.keys(patch) });
  broadcast({ type: 'episode.changed', episodeId, what: 'episode', by: user.id }, { episodeId });
  broadcast({ type: 'episodes.changed' });
}

export function createEpisode(user: User, input: { season_id: string; number: number; slug: string; title_kk: string; title_ru: string }) {
  const id = `${input.season_id}e${String(input.number).padStart(2, '0')}`;
  if (get('SELECT id FROM episodes WHERE id = ?', id)) throw new Error(`Серия ${id} уже есть`);
  if (!/^[a-z0-9_]+$/.test(input.slug)) throw new Error('slug: латиница, цифры, _');
  run(
    'INSERT INTO episodes(id, season_id, slug, sort, title_kk, title_ru, topics) VALUES (?, ?, ?, ?, ?, ?, ?)',
    id, input.season_id, `e${String(input.number).padStart(2, '0')}_${input.slug}`, input.number, input.title_kk, input.title_ru, '[]',
  );
  // Рассказчик и аватар есть в каждой серии.
  run(`INSERT INTO characters(episode_id, char_id, sort, name_kk, name_ru, fiction) VALUES (?, 'narrator', 0, 'Баяншы', 'Рассказчик', 0)`, id);
  run(`INSERT INTO characters(episode_id, char_id, sort, name_kk, name_ru, fiction, avatar, note) VALUES (?, 'aidar', 1, 'Айдар', 'Айдар', 1, 1, 'Аватар игрока. В репликах по имени не называть.')`, id);
  logActivity(user, id, 'episode.create', 'episode', id);
  broadcast({ type: 'episodes.changed' });
  return id;
}

export function createSeason(user: User, input: { id: string; title_kk: string; title_ru: string }) {
  if (!/^s\d+$/.test(input.id)) throw new Error('id сезона вида s2');
  if (get('SELECT id FROM seasons WHERE id = ?', input.id)) throw new Error('Сезон уже есть');
  run('INSERT INTO seasons(id, title_kk, title_ru, sort) VALUES (?, ?, ?, ?)', input.id, input.title_kk, input.title_ru, Number(input.id.slice(1)));
  logActivity(user, null, 'season.create', 'season', input.id);
  broadcast({ type: 'episodes.changed' });
}

function touchEpisode(episodeId: string) {
  run("UPDATE episodes SET updated_at = datetime('now') WHERE id = ?", episodeId);
}

// ---------------------------------------------------------------- комментарии
export function listComments(targetType: string, targetId: string) {
  return all(
    `SELECT c.*, COALESCE(u.name, '(удалён)') AS author_name, COALESCE(u.role, 'viewer') AS author_role FROM comments c LEFT JOIN users u ON u.id = c.author_id
     WHERE c.target_type = ? AND c.target_id = ? ORDER BY c.id`,
    targetType, targetId,
  );
}
export function listEpisodeComments(episodeId: string, onlyOpen: boolean) {
  return all(
    `SELECT c.*, COALESCE(u.name, '(удалён)') AS author_name, COALESCE(u.role, 'viewer') AS author_role FROM comments c LEFT JOIN users u ON u.id = c.author_id
     WHERE c.episode_id = ? ${onlyOpen ? 'AND c.resolved = 0' : ''} ORDER BY c.id`,
    episodeId,
  );
}

function episodeOfTarget(targetType: string, targetId: string): string | null {
  switch (targetType) {
    case 'episode':
      return targetId;
    case 'scene':
      return get<{ episode_id: string }>('SELECT episode_id FROM scenes WHERE id = ?', Number(targetId))?.episode_id ?? null;
    case 'beat':
      return get<{ episode_id: string }>('SELECT s.episode_id FROM beats b JOIN scenes s ON s.id = b.scene_id WHERE b.id = ?', Number(targetId))?.episode_id ?? null;
    case 'question':
      return get<{ episode_id: string }>('SELECT episode_id FROM questions WHERE id = ?', Number(targetId))?.episode_id ?? null;
    default:
      return null;
  }
}

export function addComment(user: User, input: { target_type: string; target_id: string; body: string; parent_id?: number | null }) {
  const body = input.body.trim();
  if (!body) throw new Error('Пустой комментарий');
  const episodeId = episodeOfTarget(input.target_type, input.target_id);
  const r = run(
    'INSERT INTO comments(target_type, target_id, episode_id, author_id, parent_id, body) VALUES (?, ?, ?, ?, ?, ?)',
    input.target_type, input.target_id, episodeId, user.id, input.parent_id ?? null, body,
  );
  logActivity(user, episodeId, 'comment.add', input.target_type, input.target_id, { body: body.slice(0, 120) });
  broadcast({ type: 'comment', episodeId, targetType: input.target_type, targetId: input.target_id });
  return Number(r.lastInsertRowid);
}

export function resolveComment(user: User, id: number, resolved: boolean) {
  const c = get('SELECT * FROM comments WHERE id = ?', id);
  if (!c) throw new NotFound();
  run('UPDATE comments SET resolved = ? WHERE id = ?', resolved ? 1 : 0, id);
  logActivity(user, c.episode_id, resolved ? 'comment.resolve' : 'comment.reopen', c.target_type, c.target_id);
  broadcast({ type: 'comment', episodeId: c.episode_id, targetType: c.target_type, targetId: c.target_id });
}

export function deleteComment(user: User, id: number) {
  const c = get('SELECT * FROM comments WHERE id = ?', id);
  if (!c) throw new NotFound();
  if (c.author_id !== user.id && user.role !== 'admin') throw new Error('Можно удалять только свои');
  run('DELETE FROM comments WHERE id = ?', id);
  broadcast({ type: 'comment', episodeId: c.episode_id, targetType: c.target_type, targetId: c.target_id });
}

// ---------------------------------------------------------------- лента
export function listActivity(episodeId: string, limit = 100) {
  return all(
    `SELECT a.*, u.name AS user_name, u.role AS user_role FROM activity a LEFT JOIN users u ON u.id = a.user_id
     WHERE a.episode_id = ? ORDER BY a.id DESC LIMIT ?`,
    episodeId, limit,
  ).map((a) => ({ ...a, detail: pj(a.detail, null) }));
}
