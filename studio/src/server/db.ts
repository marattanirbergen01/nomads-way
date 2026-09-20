// SQLite через встроенный node:sqlite — без нативных зависимостей.
// Одна база-файл в DATA_DIR/studio.db; бэкап = копия файла.
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';

fs.mkdirSync(config.dataDir, { recursive: true });
export const db = new DatabaseSync(path.join(config.dataDir, 'studio.db'));
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');
db.exec('PRAGMA busy_timeout = 5000');

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  login TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL,                -- admin | writer | historian | media | agent_script | agent_media | viewer
  password_hash TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS api_tokens (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS seasons (
  id TEXT PRIMARY KEY,                -- s1
  title_kk TEXT NOT NULL DEFAULT '',
  title_ru TEXT NOT NULL DEFAULT '',
  sort INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS episodes (
  id TEXT PRIMARY KEY,                -- s1e01
  season_id TEXT NOT NULL REFERENCES seasons(id),
  slug TEXT NOT NULL,                 -- e01_shu_boyynda → имя файла YAML
  sort INTEGER NOT NULL DEFAULT 0,
  title_kk TEXT NOT NULL DEFAULT '',
  title_ru TEXT NOT NULL DEFAULT '',
  title_en TEXT,                      -- только сохраняем из старого YAML, в UI нет
  era TEXT,
  topics TEXT NOT NULL DEFAULT '[]',  -- JSON
  final_test TEXT,                    -- JSON {single, context}
  status TEXT NOT NULL DEFAULT 'draft',       -- draft | review | approved | published
  approved_by TEXT,
  revision INTEGER NOT NULL DEFAULT 0,        -- номер последней собранной редакции
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS characters (
  id INTEGER PRIMARY KEY,
  episode_id TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  char_id TEXT NOT NULL,
  sort INTEGER NOT NULL DEFAULT 0,
  name_kk TEXT NOT NULL DEFAULT '',
  name_ru TEXT NOT NULL DEFAULT '',
  fiction INTEGER NOT NULL DEFAULT 0,
  note TEXT,
  avatar INTEGER NOT NULL DEFAULT 0,
  default_name TEXT,                  -- JSON {kk, ru}
  portrait TEXT,                      -- media id
  UNIQUE(episode_id, char_id)
);

CREATE TABLE IF NOT EXISTS scenes (
  id INTEGER PRIMARY KEY,
  episode_id TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  scene_id TEXT NOT NULL,             -- sc010
  sort INTEGER NOT NULL DEFAULT 0,
  art TEXT,
  art_when TEXT,                      -- JSON [{if, art}]
  layer TEXT,                         -- history | personal | null
  covers TEXT NOT NULL DEFAULT '[]',  -- JSON [fact ids]
  title_kk TEXT, title_ru TEXT,
  pan INTEGER,
  avatar_side TEXT,                   -- left | right | null
  avatar_in_art INTEGER NOT NULL DEFAULT 0,
  quiz TEXT NOT NULL DEFAULT '[]',    -- JSON [question ids]
  note TEXT,                          -- заметка сценариста (в YAML идёт комментарием)
  status TEXT NOT NULL DEFAULT 'draft',       -- draft | review | text_ok | media_ok | ready
  version INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_at TEXT DEFAULT (datetime('now')),
  UNIQUE(episode_id, scene_id)
);

CREATE TABLE IF NOT EXISTS beats (
  id INTEGER PRIMARY KEY,
  scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
  sort INTEGER NOT NULL DEFAULT 0,
  kind TEXT NOT NULL,                 -- say | choice
  who TEXT,
  kk TEXT NOT NULL DEFAULT '',
  ru TEXT NOT NULL DEFAULT '',
  emotion TEXT,                       -- calm | joy | alarm | sorrow
  when_cond TEXT,
  choice TEXT,                        -- JSON {prompt:{kk,ru}, options:[...]}
  origin TEXT NOT NULL DEFAULT 'human',       -- human | agent
  needs_review INTEGER NOT NULL DEFAULT 0,    -- правка агента, человек ещё не смотрел
  version INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS beats_scene ON beats(scene_id, sort);

CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY,
  episode_id TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  q_id TEXT NOT NULL,
  sort INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL,                 -- JSON: полная запись вопроса по CONTENT_FORMAT
  status TEXT NOT NULL DEFAULT 'draft',
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT DEFAULT (datetime('now')),
  UNIQUE(episode_id, q_id)
);

CREATE TABLE IF NOT EXISTS media (
  id TEXT PRIMARY KEY,                -- art_s1e01_010, avatar_01_zhylqyshy_calm …
  season_id TEXT NOT NULL REFERENCES seasons(id),
  kind TEXT NOT NULL,                 -- scene | avatar | character | map | cover | banner | icon
  status TEXT NOT NULL DEFAULT 'missing',     -- missing | draft | approved
  brief TEXT,
  seed INTEGER,
  prompt_ref TEXT,
  prompt_text TEXT,
  file TEXT,                          -- относительный путь в content/media/<season>/ (scenes/x.png)
  upload TEXT,                        -- файл в DATA_DIR/uploads, если загружен через студию
  approved_by TEXT,
  generated TEXT,
  note TEXT,
  source TEXT,                        -- JSON запись для sources/media.yaml
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY,
  target_type TEXT NOT NULL,          -- episode | scene | beat | question | media
  target_id TEXT NOT NULL,
  episode_id TEXT,                    -- для выборки «все комментарии серии»
  author_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  parent_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  resolved INTEGER NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS comments_target ON comments(target_type, target_id);
CREATE INDEX IF NOT EXISTS comments_episode ON comments(episode_id);

CREATE TABLE IF NOT EXISTS activity (
  id INTEGER PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  episode_id TEXT,
  action TEXT NOT NULL,
  target_type TEXT, target_id TEXT,
  detail TEXT,                        -- JSON
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS activity_episode ON activity(episode_id, id);

CREATE TABLE IF NOT EXISTS revisions (
  id INTEGER PRIMARY KEY,
  episode_id TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  number INTEGER NOT NULL,
  snapshot TEXT NOT NULL,             -- JSON всей серии на момент сборки
  commit_hash TEXT,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TEXT DEFAULT (datetime('now'))
);
`;
db.exec(schema);

// --- маленькие помощники --------------------------------------------------
type Row = Record<string, any>;

export function all<T = Row>(sql: string, ...params: any[]): T[] {
  return db.prepare(sql).all(...params) as T[];
}
export function get<T = Row>(sql: string, ...params: any[]): T | undefined {
  return db.prepare(sql).get(...params) as T | undefined;
}
export function run(sql: string, ...params: any[]) {
  return db.prepare(sql).run(...params);
}
export function transaction<T>(fn: () => T): T {
  db.exec('BEGIN');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
export const j = (v: unknown) => (v === undefined || v === null ? null : JSON.stringify(v));
export const pj = <T = any>(s: string | null | undefined, fallback: T): T =>
  s ? (JSON.parse(s) as T) : fallback;
