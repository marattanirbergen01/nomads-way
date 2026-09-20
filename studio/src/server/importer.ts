// Импорт серии из content/ (YAML по docs/CONTENT_FORMAT.md) в базу студии.
// Используется один раз для существующих серий и командой `studio push` от агентов.
import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { all, get, run, transaction, j } from './db.js';
import { contentDir } from './config.js';

export const EMOTIONS = ['calm', 'joy', 'alarm', 'sorrow'] as const;
export type Emotion = (typeof EMOTIONS)[number];

// В старом YAML встречается resolve — кадра нет, клиент показывает calm. Приводим к calm.
export function normEmotion(e: unknown): Emotion | null {
  if (!e || typeof e !== 'string') return null;
  if (e === 'resolve') return 'calm';
  return (EMOTIONS as readonly string[]).includes(e) ? (e as Emotion) : null;
}

const t = (v: any, lang: 'kk' | 'ru' | 'en') => (v && typeof v === 'object' ? (v[lang] ?? '') : '');

export interface ImportResult {
  episodeId: string;
  scenes: number;
  beats: number;
  questions: number;
  media: number;
}

export function findEpisodeFile(season: string, episodeId: string): string | undefined {
  const dir = path.join(contentDir, 'episodes', season);
  if (!fs.existsSync(dir)) return;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.yaml')) continue;
    const doc = YAML.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    if (doc?.episode === episodeId) return path.join(dir, f);
  }
}

export function ensureSeason(id: string) {
  if (!get('SELECT id FROM seasons WHERE id = ?', id)) {
    const n = Number(id.replace(/\D/g, '')) || 0;
    run(
      'INSERT INTO seasons(id, title_kk, title_ru, sort) VALUES (?, ?, ?, ?)',
      id,
      `${n}-маусым`,
      `Сезон ${n}`,
      n,
    );
  }
}

/** Импорт одной серии из YAML-файла. Существующая серия полностью заменяется. */
export function importEpisodeFile(file: string, opts: { userId?: number } = {}): ImportResult {
  const doc = YAML.parse(fs.readFileSync(file, 'utf8'));
  const episodeId: string = doc.episode;
  const season = episodeId.split('e')[0];
  const slug = path.basename(file, '.yaml');
  ensureSeason(season);

  let beats = 0;
  transaction(() => {
    run('DELETE FROM episodes WHERE id = ?', episodeId);
    const epNum = Number(episodeId.split('e')[1]) || 0;
    run(
      `INSERT INTO episodes(id, season_id, slug, sort, title_kk, title_ru, title_en, era, topics, final_test, approved_by, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      episodeId, season, slug, epNum,
      t(doc.title, 'kk'), t(doc.title, 'ru'), doc.title?.en ?? null,
      doc.era ?? null, j(doc.topics ?? []), j(doc.final_test ?? null),
      doc.approved_by ?? null, doc.approved_by ? 'approved' : 'draft',
    );

    // avatar: true в старых YAML не проставлен — аватар игрока там зовётся aidar (см. DECISIONS 2026-09-07)
    const hasAvatar = (doc.characters ?? []).some((ch: any) => ch.avatar);
    (doc.characters ?? []).forEach((ch: any, i: number) => {
      const isAvatar = ch.avatar || (!hasAvatar && ch.id === 'aidar');
      run(
        `INSERT INTO characters(episode_id, char_id, sort, name_kk, name_ru, fiction, note, avatar, default_name, portrait)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        episodeId, ch.id, i, t(ch.name, 'kk'), t(ch.name, 'ru'),
        ch.fiction ? 1 : 0, ch.note ?? null, isAvatar ? 1 : 0, j(ch.default_name ?? null), ch.portrait ?? null,
      );
    });

    (doc.scenes ?? []).forEach((sc: any, i: number) => {
      const r = run(
        `INSERT INTO scenes(episode_id, scene_id, sort, art, art_when, layer, covers, title_kk, title_ru, pan, avatar_side, avatar_in_art, quiz, updated_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        episodeId, sc.id, i, sc.art ?? null, j(sc.art_when ?? null), sc.layer ?? null,
        j(sc.covers ?? []), sc.title ? t(sc.title, 'kk') : null, sc.title ? t(sc.title, 'ru') : null,
        sc.pan ?? null, sc.avatar ?? null, sc.avatar_in_art ? 1 : 0, j(sc.quiz ?? []), opts.userId ?? null,
      );
      const sceneRow = Number(r.lastInsertRowid);
      (sc.beats ?? []).forEach((b: any, k: number) => {
        if (b.say) {
          const s = b.say;
          run(
            `INSERT INTO beats(scene_id, sort, kind, who, kk, ru, emotion, when_cond, updated_by) VALUES (?, ?, 'say', ?, ?, ?, ?, ?, ?)`,
            sceneRow, k, s.who ?? null, s.kk ?? '', s.ru ?? '', normEmotion(s.emotion ?? s.emo), s.when ?? null, opts.userId ?? null,
          );
        } else if (b.choice) {
          const c = b.choice;
          const choice = {
            prompt: { kk: t(c.prompt, 'kk'), ru: t(c.prompt, 'ru') },
            options: (c.options ?? []).map((o: any) => ({
              id: o.id,
              kk: o.kk ?? '',
              ru: o.ru ?? '',
              set: o.set ?? null,
              goto: o.goto ?? null,
              art: o.art ?? null,
              reply: o.reply
                ? { kk: o.reply.kk ?? '', ru: o.reply.ru ?? '', emotion: normEmotion(o.reply.emotion) }
                : null,
            })),
          };
          run(
            `INSERT INTO beats(scene_id, sort, kind, choice, updated_by) VALUES (?, ?, 'choice', ?, ?)`,
            sceneRow, k, j(choice), opts.userId ?? null,
          );
        } else return;
        beats++;
      });
    });
  });

  const questions = importQuestions(season, episodeId);
  const media = importManifest(season);
  const scenes = (doc.scenes ?? []).length;
  return { episodeId, scenes, beats, questions, media };
}

export function importQuestions(season: string, episodeId: string): number {
  const epShort = episodeId.replace(/^s\d+/, ''); // e01
  const file = path.join(contentDir, 'questions', season, `${epShort}.yaml`);
  if (!fs.existsSync(file)) return 0;
  const list = YAML.parse(fs.readFileSync(file, 'utf8')) ?? [];
  transaction(() => {
    run('DELETE FROM questions WHERE episode_id = ?', episodeId);
    list.forEach((q: any, i: number) => {
      // en убираем везде: студия работает только с kk/ru
      const strip = (o: any) => {
        if (o && typeof o === 'object') {
          if ('en' in o && 'kk' in o) delete o.en;
          for (const k of Object.keys(o)) strip(o[k]);
        }
        return o;
      };
      run(
        `INSERT INTO questions(episode_id, q_id, sort, data, status) VALUES (?, ?, ?, ?, 'draft')`,
        episodeId, q.id, i, JSON.stringify(strip(q)),
      );
    });
  });
  return list.length;
}

export function importManifest(season: string): number {
  ensureSeason(season);
  const file = path.join(contentDir, 'media', season, 'manifest.yaml');
  if (!fs.existsSync(file)) return 0;
  const list = YAML.parse(fs.readFileSync(file, 'utf8')) ?? [];
  const sourcesFile = path.join(contentDir, 'sources', 'media.yaml');
  const sources: Record<string, any> = {};
  if (fs.existsSync(sourcesFile)) {
    for (const s of YAML.parse(fs.readFileSync(sourcesFile, 'utf8')) ?? []) sources[s.id] = s;
  }
  transaction(() => {
    for (const m of list) {
      let promptText: string | null = null;
      if (m.prompt_ref) {
        const p = path.join(contentDir, 'media', season, m.prompt_ref);
        if (fs.existsSync(p)) promptText = fs.readFileSync(p, 'utf8');
      }
      run(
        `INSERT INTO media(id, season_id, kind, status, brief, seed, prompt_ref, prompt_text, file, approved_by, generated, note, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, status=excluded.status, brief=excluded.brief, seed=excluded.seed,
           prompt_ref=excluded.prompt_ref, prompt_text=excluded.prompt_text, file=excluded.file, approved_by=excluded.approved_by,
           generated=excluded.generated, note=excluded.note, source=excluded.source, updated_at=datetime('now')`,
        m.id, season, m.kind ?? 'scene', m.status ?? 'missing', m.brief ?? null,
        m.seed ?? null, m.prompt_ref ?? null, promptText, m.file ?? null, m.approved_by ?? null,
        m.generated ? String(m.generated) : null, m.note ?? null, j(sources[m.id] ?? null),
      );
    }
  });
  return list.length;
}

/** Все серии из content/episodes/. */
export function importAll(opts: { userId?: number } = {}): ImportResult[] {
  const root = path.join(contentDir, 'episodes');
  const out: ImportResult[] = [];
  if (!fs.existsSync(root)) return out;
  for (const season of fs.readdirSync(root).sort()) {
    const dir = path.join(root, season);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const f of fs.readdirSync(dir).sort()) {
      if (f.endsWith('.yaml')) out.push(importEpisodeFile(path.join(dir, f), opts));
    }
  }
  return out;
}

export function episodeCount() {
  return all('SELECT id FROM episodes').length;
}
