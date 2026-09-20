// `studio push`: агент (или человек) присылает YAML серии, студия вливает изменения
// на уровне реплик. Ничего не удаляет без replace: true. Все правки помечаются
// «предложено агентом», если пришли от агента.
import YAML from 'yaml';
import { all, get, run, transaction, j } from './db.js';
import { broadcast } from './ws.js';
import type { User } from './auth.js';
import { logActivity } from './service.js';
import { normEmotion, ensureSeason } from './importer.js';

const t = (v: any, l: 'kk' | 'ru') => (v && typeof v === 'object' ? (v[l] ?? '') : '');

interface Incoming {
  kind: 'say' | 'choice';
  who: string | null;
  kk: string;
  ru: string;
  emotion: string | null;
  when_cond: string | null;
  choice: any | null;
}

function parseBeat(b: any): Incoming | null {
  if (b.say) {
    const s = b.say;
    return { kind: 'say', who: s.who ?? null, kk: s.kk ?? '', ru: s.ru ?? '', emotion: normEmotion(s.emotion ?? s.emo), when_cond: s.when ?? null, choice: null };
  }
  if (b.choice) {
    const c = b.choice;
    return {
      kind: 'choice', who: null, kk: '', ru: '', emotion: null, when_cond: null,
      choice: {
        prompt: { kk: t(c.prompt, 'kk'), ru: t(c.prompt, 'ru') },
        options: (c.options ?? []).map((o: any) => ({
          id: o.id, kk: o.kk ?? '', ru: o.ru ?? '', set: o.set ?? null, goto: o.goto ?? null, art: o.art ?? null,
          reply: o.reply ? { kk: o.reply.kk ?? '', ru: o.reply.ru ?? '', emotion: normEmotion(o.reply.emotion) } : null,
        })),
      },
    };
  }
  return null;
}

const sameText = (a: Incoming, b: any) =>
  a.kind === b.kind && (a.kind === 'choice' ? JSON.stringify(a.choice) === JSON.stringify(JSON.parse(b.choice ?? 'null')) : a.who === b.who && (a.kk === b.kk || a.ru === b.ru));

export function pushYaml(user: User, episodeId: string, yamlText: string, opts: { replace?: boolean; questionsYaml?: string } = {}) {
  const doc = YAML.parse(yamlText);
  if (!doc || doc.episode !== episodeId) throw new Error(`В YAML episode: ${doc?.episode}, ожидалось ${episodeId}`);
  const agent = user.role.startsWith('agent');
  const report: string[] = [];
  const ep = get('SELECT * FROM episodes WHERE id = ?', episodeId);
  const season = episodeId.split('e')[0];
  ensureSeason(season);

  transaction(() => {
    if (!ep) {
      run(
        `INSERT INTO episodes(id, season_id, slug, sort, title_kk, title_ru, era, topics, final_test) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        episodeId, season, `e${episodeId.split('e')[1]}_${(doc.slug ?? 'new')}`, Number(episodeId.split('e')[1]) || 0,
        t(doc.title, 'kk'), t(doc.title, 'ru'), doc.era ?? null, j(doc.topics ?? []), j(doc.final_test ?? null),
      );
      report.push(`создана серия ${episodeId}`);
    } else {
      const patch: string[] = [];
      const vals: any[] = [];
      if (doc.title && (t(doc.title, 'kk') !== ep.title_kk || t(doc.title, 'ru') !== ep.title_ru)) {
        patch.push('title_kk = ?', 'title_ru = ?');
        vals.push(t(doc.title, 'kk'), t(doc.title, 'ru'));
      }
      if (doc.era !== undefined && doc.era !== ep.era) { patch.push('era = ?'); vals.push(doc.era); }
      if (doc.topics && JSON.stringify(doc.topics) !== ep.topics) { patch.push('topics = ?'); vals.push(j(doc.topics)); }
      if (doc.final_test && JSON.stringify(doc.final_test) !== ep.final_test) { patch.push('final_test = ?'); vals.push(j(doc.final_test)); }
      if (patch.length) {
        run(`UPDATE episodes SET ${patch.join(', ')}, updated_at = datetime('now') WHERE id = ?`, ...vals, episodeId);
        report.push('шапка серии обновлена');
      }
    }

    // персонажи: добавляем и обновляем, не удаляем
    for (const [i, ch] of (doc.characters ?? []).entries()) {
      const cur = get('SELECT * FROM characters WHERE episode_id = ? AND char_id = ?', episodeId, ch.id);
      if (!cur) {
        run(
          `INSERT INTO characters(episode_id, char_id, sort, name_kk, name_ru, fiction, note, avatar, default_name, portrait) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          episodeId, ch.id, i, t(ch.name, 'kk'), t(ch.name, 'ru'), ch.fiction ? 1 : 0, ch.note ?? null, ch.avatar ? 1 : 0, j(ch.default_name ?? null), ch.portrait ?? null,
        );
        report.push(`персонаж ${ch.id} добавлен`);
      } else if (t(ch.name, 'kk') !== cur.name_kk || t(ch.name, 'ru') !== cur.name_ru || (ch.note ?? null) !== cur.note) {
        run('UPDATE characters SET name_kk = ?, name_ru = ?, note = ? WHERE id = ?', t(ch.name, 'kk'), t(ch.name, 'ru'), ch.note ?? null, cur.id);
        report.push(`персонаж ${ch.id} обновлён`);
      }
    }

    const dbScenes = all('SELECT * FROM scenes WHERE episode_id = ? ORDER BY sort', episodeId);
    const yamlIds = new Set((doc.scenes ?? []).map((s: any) => s.id));
    let sort = 0;
    for (const sc of doc.scenes ?? []) {
      let scene = dbScenes.find((s) => s.scene_id === sc.id);
      if (!scene) {
        const r = run(
          `INSERT INTO scenes(episode_id, scene_id, sort, art, art_when, layer, covers, title_kk, title_ru, pan, avatar_side, avatar_in_art, quiz, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          episodeId, sc.id, sort, sc.art ?? null, j(sc.art_when ?? null), sc.layer ?? null, j(sc.covers ?? []),
          sc.title ? t(sc.title, 'kk') : null, sc.title ? t(sc.title, 'ru') : null, sc.pan ?? null, sc.avatar ?? null, sc.avatar_in_art ? 1 : 0, j(sc.quiz ?? []), user.id,
        );
        scene = get('SELECT * FROM scenes WHERE id = ?', Number(r.lastInsertRowid));
        report.push(`сцена ${sc.id}: создана`);
      } else {
        const fields: Record<string, any> = {
          art: sc.art ?? null, art_when: j(sc.art_when ?? null), layer: sc.layer ?? null, covers: j(sc.covers ?? []),
          title_kk: sc.title ? t(sc.title, 'kk') : null, title_ru: sc.title ? t(sc.title, 'ru') : null,
          pan: sc.pan ?? null, avatar_side: sc.avatar ?? null, avatar_in_art: sc.avatar_in_art ? 1 : 0, quiz: j(sc.quiz ?? []), sort,
        };
        const changed = Object.keys(fields).filter((k) => (scene![k] ?? null) !== (fields[k] ?? null));
        if (changed.length) {
          run(
            `UPDATE scenes SET ${changed.map((k) => `${k} = ?`).join(', ')}, version = version + 1, updated_at = datetime('now'), updated_by = ? WHERE id = ?`,
            ...changed.map((k) => fields[k]), user.id, scene.id,
          );
          if (changed.some((k) => k !== 'sort')) report.push(`сцена ${sc.id}: ${changed.filter((k) => k !== 'sort').join(', ')}`);
        }
      }
      sort++;

      // реплики: сначала точные совпадения, потом позиционные того же типа/говорящего, остальное — вставка
      const incoming = (sc.beats ?? []).map(parseBeat).filter(Boolean) as Incoming[];
      const dbBeats = all('SELECT * FROM beats WHERE scene_id = ? ORDER BY sort', scene!.id);
      const matched = new Map<number, any>(); // index in incoming → db beat
      const used = new Set<number>();
      incoming.forEach((inc, i) => {
        const hit = dbBeats.find((b) => !used.has(b.id) && sameText(inc, b));
        if (hit) { matched.set(i, hit); used.add(hit.id); }
      });
      incoming.forEach((inc, i) => {
        if (matched.has(i)) return;
        const hit = dbBeats[i] && !used.has(dbBeats[i].id) && dbBeats[i].kind === inc.kind && (inc.kind === 'choice' || dbBeats[i].who === inc.who) ? dbBeats[i] : undefined;
        if (hit) { matched.set(i, hit); used.add(hit.id); }
      });
      let added = 0, updated = 0, removed = 0;
      incoming.forEach((inc, i) => {
        const hit = matched.get(i);
        if (hit) {
          const diff =
            hit.kk !== inc.kk || hit.ru !== inc.ru || (hit.emotion ?? null) !== inc.emotion || (hit.when_cond ?? null) !== inc.when_cond ||
            (hit.who ?? null) !== inc.who || JSON.stringify(JSON.parse(hit.choice ?? 'null')) !== JSON.stringify(inc.choice);
          if (diff || hit.sort !== i) {
            run(
              `UPDATE beats SET who = ?, kk = ?, ru = ?, emotion = ?, when_cond = ?, choice = ?, sort = ?, ${diff ? `origin = ?, needs_review = ?, version = version + 1, updated_at = datetime('now'), updated_by = ?,` : ''} id = id WHERE id = ?`,
              inc.who, inc.kk, inc.ru, inc.emotion, inc.when_cond, j(inc.choice), i,
              ...(diff ? [agent ? 'agent' : 'human', agent ? 1 : 0, user.id] : []), hit.id,
            );
            if (diff) updated++;
          }
        } else {
          run(
            `INSERT INTO beats(scene_id, sort, kind, who, kk, ru, emotion, when_cond, choice, origin, needs_review, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            scene!.id, i, inc.kind, inc.who, inc.kk, inc.ru, inc.emotion, inc.when_cond, j(inc.choice), agent ? 'agent' : 'human', agent ? 1 : 0, user.id,
          );
          added++;
        }
      });
      for (const b of dbBeats) {
        if (used.has(b.id)) continue;
        if (opts.replace) { run('DELETE FROM beats WHERE id = ?', b.id); removed++; }
        else { run('UPDATE beats SET sort = ? WHERE id = ?', 1000 + b.sort, b.id); report.push(`  ⚠ ${sc.id}: реплика «${(b.ru || b.kk).slice(0, 40)}» есть в студии, но нет в YAML — оставлена в конце (replace, чтобы удалить)`); }
      }
      // нормализуем sort
      all('SELECT id FROM beats WHERE scene_id = ? ORDER BY sort', scene!.id).forEach((b, k) => run('UPDATE beats SET sort = ? WHERE id = ?', k, b.id));
      if (added || updated || removed) report.push(`сцена ${sc.id}: реплик добавлено ${added}, изменено ${updated}, удалено ${removed}`);
    }
    for (const s of dbScenes) if (!yamlIds.has(s.scene_id)) report.push(`⚠ сцена ${s.scene_id} есть в студии, но нет в YAML — не тронута`);

    if (opts.questionsYaml) {
      const list = YAML.parse(opts.questionsYaml) ?? [];
      run('DELETE FROM questions WHERE episode_id = ?', episodeId);
      list.forEach((q: any, i: number) => {
        const strip = (o: any) => { if (o && typeof o === 'object') { if ('en' in o && 'kk' in o) delete o.en; for (const k of Object.keys(o)) strip(o[k]); } return o; };
        run(`INSERT INTO questions(episode_id, q_id, sort, data) VALUES (?, ?, ?, ?)`, episodeId, q.id, i, JSON.stringify(strip(q)));
      });
      report.push(`вопросы: заменены (${list.length})`);
    }
    run("UPDATE episodes SET updated_at = datetime('now') WHERE id = ?", episodeId);
  });

  logActivity(user, episodeId, 'episode.push', 'episode', episodeId, { report: report.slice(0, 30) });
  broadcast({ type: 'episode.changed', episodeId, what: 'push', by: user.id }, { episodeId });
  broadcast({ type: 'episodes.changed' });
  return report;
}
