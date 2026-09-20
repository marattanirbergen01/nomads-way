// Экспорт серии из базы студии в content/ по docs/CONTENT_FORMAT.md.
// Пишет: episodes/<season>/<slug>.yaml, questions/<season>/<eNN>.yaml,
// media/<season>/manifest.yaml (слияние), sources/media.yaml (слияние),
// файлы медиа, загруженные через студию, и промпты.
import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { all, get } from './db.js';
import { contentDir, uploadsDir } from './config.js';
import { loadEpisode } from './service.js';
import { KIND_DIR } from './media.js';

const lang = (kk: string | null | undefined, ru: string | null | undefined, en?: string | null) => {
  const o: Record<string, string> = { kk: kk ?? '', ru: ru ?? '' };
  if (en) o.en = en;
  return o;
};

// Даты вида 2026-09-15 держим в кавычках, чтобы ни один парсер не превратил их в timestamp.
function stringifyList(list: any[]) {
  const y = new YAML.Document(list);
  YAML.visit(y, {
    Pair(_, pair: any) {
      const k = pair.key?.value;
      if ((k === 'generated' || k === 'date') && YAML.isScalar(pair.value) && pair.value.value != null) {
        pair.value.value = String(pair.value.value);
        pair.value.type = 'QUOTE_SINGLE';
      }
    },
  });
  return y.toString({ lineWidth: 0 });
}

export function episodeToYaml(episodeId: string): { doc: any; text: string } {
  const ep = loadEpisode(episodeId);
  const doc: any = {
    episode: ep.id,
    title: lang(ep.title_kk, ep.title_ru, (ep as any).title_en),
    topics: ep.topics,
  };
  if (ep.era) doc.era = ep.era;
  doc.approved_by = ep.approved_by ?? null;
  doc.characters = ep.characters.map((c) => {
    const o: any = { id: c.char_id, name: lang(c.name_kk, c.name_ru), fiction: !!c.fiction };
    if (c.note) o.note = c.note;
    if (c.avatar) o.avatar = true;
    if (c.default_name) o.default_name = c.default_name;
    if (c.portrait) o.portrait = c.portrait;
    return o;
  });
  doc.scenes = ep.scenes.map((s) => {
    const o: any = { id: s.scene_id };
    if (s.art) o.art = s.art;
    if (s.art_when?.length) o.art_when = s.art_when;
    if (s.layer) o.layer = s.layer;
    o.covers = s.covers;
    if (s.title_kk || s.title_ru) o.title = lang(s.title_kk, s.title_ru);
    if (s.pan != null) o.pan = s.pan;
    if (s.avatar_side) o.avatar = s.avatar_side;
    if (s.avatar_in_art) o.avatar_in_art = true;
    o.beats = s.beats.map((b) => {
      if (b.kind === 'say') {
        const say: any = { who: b.who, kk: b.kk, ru: b.ru };
        if (b.emotion) say.emotion = b.emotion;
        if (b.when_cond) say.when = b.when_cond;
        return { say };
      }
      const c = b.choice ?? { prompt: { kk: '', ru: '' }, options: [] };
      return {
        choice: {
          prompt: lang(c.prompt.kk, c.prompt.ru),
          options: c.options.map((op) => {
            const x: any = { id: op.id, kk: op.kk, ru: op.ru };
            if (op.reply && (op.reply.kk || op.reply.ru)) {
              x.reply = { kk: op.reply.kk, ru: op.reply.ru };
              if (op.reply.emotion) x.reply.emotion = op.reply.emotion;
            }
            if (op.set) x.set = op.set;
            if (op.goto) x.goto = op.goto;
            if (op.art) x.art = op.art;
            return x;
          }),
        },
      };
    });
    if (s.quiz.length) o.quiz = s.quiz;
    return o;
  });
  if (ep.final_test) doc.final_test = ep.final_test;

  const y = new YAML.Document(doc);
  // строчная запись для коротких словарей, как в исходных файлах
  YAML.visit(y, {
    Pair(_, pair: any) {
      const k = pair.key?.value;
      if (['title', 'name', 'prompt', 'set', 'default_name'].includes(k) && YAML.isMap(pair.value)) pair.value.flow = true;
      if (['topics', 'covers', 'quiz'].includes(k) && YAML.isSeq(pair.value)) pair.value.flow = true;
      if (k === 'art_when' && YAML.isSeq(pair.value)) for (const it of pair.value.items as any[]) if (YAML.isMap(it)) it.flow = true;
    },
  });
  const notes = ep.scenes.filter((s) => s.note).map((s) => `#   ${s.scene_id}: ${s.note!.replace(/\n/g, ' ')}`);
  const header =
    `# Серия ${ep.id} — создано студией (studio/), редакция ${ep.revision + 1}, ${new Date().toISOString().slice(0, 10)}.\n` +
    `# Источник правды для черновиков — студия; этот файл перезаписывается при сборке.\n` +
    (notes.length ? `# Заметки сценариста:\n${notes.join('\n')}\n` : '') +
    '\n';
  return { doc, text: header + y.toString({ lineWidth: 0, defaultStringType: 'PLAIN', defaultKeyType: 'PLAIN' }) };
}

export function questionsToYaml(episodeId: string) {
  const qs = all('SELECT data FROM questions WHERE episode_id = ? ORDER BY sort', episodeId).map((q) => JSON.parse(q.data));
  const y = new YAML.Document(qs);
  YAML.visit(y, {
    Pair(_, pair: any) {
      const k = pair.key?.value;
      if (YAML.isSeq(pair.value) && k === 'options') for (const it of pair.value.items as any[]) if (YAML.isMap(it)) it.flow = true;
    },
  });
  return `# Вопросы серии ${episodeId}. Формат — docs/CONTENT_FORMAT.md. Создано студией.\n\n` + y.toString({ lineWidth: 0 });
}

/** Что именно будет записано (без записи) — для предпросмотра и сборки. */
export function planExport(episodeId: string) {
  const ep = get('SELECT * FROM episodes WHERE id = ?', episodeId);
  if (!ep) throw new Error('Нет серии');
  const season = ep.season_id as string;
  const epShort = episodeId.replace(/^s\d+/, '');
  const files: { path: string; content?: string; copyFrom?: string }[] = [];
  files.push({ path: `content/episodes/${season}/${ep.slug}.yaml`, content: episodeToYaml(episodeId).text });
  files.push({ path: `content/questions/${season}/${epShort}.yaml`, content: questionsToYaml(episodeId) });

  // манифест: сливаем записи студии с существующим файлом по id
  const manifestPath = path.join(contentDir, 'media', season, 'manifest.yaml');
  const existing: any[] = fs.existsSync(manifestPath) ? YAML.parse(fs.readFileSync(manifestPath, 'utf8')) ?? [] : [];
  const byId = new Map(existing.map((m) => [m.id, m]));
  const media = all('SELECT * FROM media WHERE season_id = ? ORDER BY kind, id', season);
  for (const m of media) {
    const prev = byId.get(m.id) ?? {};
    const rec: any = {
      ...prev,
      id: m.id,
      kind: m.kind,
      status: m.status,
      brief: m.brief ?? prev.brief ?? '',
      seed: m.seed ?? null,
      prompt_ref: m.prompt_ref ?? prev.prompt_ref ?? `prompts/${KIND_DIR[m.kind] ?? 'scenes'}/${m.id}.md`,
      approved_by: m.approved_by ?? null,
      file: m.file ?? prev.file ?? null,
      generated: m.generated ?? prev.generated ?? null,
      note: m.note ?? prev.note ?? null,
    };
    byId.set(m.id, rec);
    // файл, загруженный через студию → в папку исходников
    if (m.upload) {
      const src = path.join(uploadsDir, m.upload);
      if (fs.existsSync(src) && m.file) files.push({ path: `content/media/${season}/${m.file}`, copyFrom: src });
    }
    // промпт пишем только если он изменился (у аватаров один файл на несколько кадров)
    if (m.prompt_text) {
      const rel = `content/media/${season}/${rec.prompt_ref}`;
      const abs = path.join(contentDir, '..', rel);
      const same = fs.existsSync(abs) && fs.readFileSync(abs, 'utf8') === m.prompt_text;
      if (!same && !files.some((f) => f.path === rel)) files.push({ path: rel, content: m.prompt_text });
    }
  }
  const manifestHeader = '# Иллюстрации сезона. status: missing | draft | approved. Обновляется студией при сборке.\n';
  files.push({ path: `content/media/${season}/manifest.yaml`, content: manifestHeader + stringifyList([...byId.values()]) });

  // источники медиа
  const sourcesPath = path.join(contentDir, 'sources', 'media.yaml');
  const srcExisting: any[] = fs.existsSync(sourcesPath) ? YAML.parse(fs.readFileSync(sourcesPath, 'utf8')) ?? [] : [];
  const srcById = new Map(srcExisting.map((s) => [s.id, s]));
  let srcChanged = false;
  for (const m of media) {
    if (!m.source) continue;
    const s = JSON.parse(m.source);
    if (JSON.stringify(srcById.get(m.id)) !== JSON.stringify(s)) srcChanged = true;
    srcById.set(m.id, s);
  }
  if (srcChanged) {
    const h = '# Происхождение каждого медиафайла. Нет записи — файл не идёт в сборку.\n# license: own-generation | cc-by | cc-by-sa | public-domain | licensed\n\n';
    files.push({ path: 'content/sources/media.yaml', content: h + stringifyList([...srcById.values()]) });
  }
  return { season, files };
}

export function writeExport(repoDir: string, plan: ReturnType<typeof planExport>) {
  const written: string[] = [];
  for (const f of plan.files) {
    const target = path.join(repoDir, f.path);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    if (f.copyFrom) fs.copyFileSync(f.copyFrom, target);
    else fs.writeFileSync(target, f.content ?? '');
    written.push(f.path);
  }
  return written;
}

/** Проверки студии перед сборкой (до компилятора). */
export function preflight(episodeId: string) {
  const ep = loadEpisode(episodeId);
  const errors: string[] = [];
  const warnings: string[] = [];
  const media = new Map(all('SELECT * FROM media WHERE season_id = ?', ep.season_id).map((m) => [m.id, m]));
  if (!ep.approved_by) errors.push('Нет визы историка на серии (approved_by)');
  if (!ep.scenes.length) errors.push('В серии нет сцен');
  const avatar = ep.characters.find((c) => c.avatar)?.char_id;
  const sceneIds = new Set(ep.scenes.map((s) => s.scene_id));
  for (const s of ep.scenes) {
    const tag = `Сцена ${s.scene_id}`;
    if (s.status !== 'ready') errors.push(`${tag}: статус «${s.status}», нужен «ready»`);
    if (!s.art) errors.push(`${tag}: не задан кадр`);
    else {
      const m = media.get(s.art);
      if (!m) errors.push(`${tag}: кадр ${s.art} не заведён в медиа`);
      else if (m.status !== 'approved') errors.push(`${tag}: кадр ${s.art} не утверждён`);
      else if (!m.source) errors.push(`${tag}: у кадра ${s.art} нет записи источника`);
    }
    for (const a of s.art_when ?? []) {
      const m = media.get(a.art);
      if (!m || m.status !== 'approved') errors.push(`${tag}: кадр по условию ${a.art} не утверждён`);
    }
    s.beats.forEach((b, i) => {
      const bt = `${tag}, реплика ${i + 1}`;
      if (b.needs_review) warnings.push(`${bt}: предложение агента ещё не просмотрено`);
      if (b.kind === 'say') {
        if (!b.who) errors.push(`${bt}: не указан говорящий`);
        else if (!ep.characters.some((c) => c.char_id === b.who)) errors.push(`${bt}: персонажа ${b.who} нет в серии`);
        if (!b.kk.trim() || !b.ru.trim()) errors.push(`${bt}: пустой текст kk или ru`);
        if (b.emotion && b.who !== avatar) warnings.push(`${bt}: эмоция у не-аватара — клиент её не покажет`);
      } else {
        const c = b.choice;
        if (!c || c.options.length < 2) errors.push(`${bt}: у развилки меньше двух вариантов`);
        if (c && (!c.prompt.kk.trim() || !c.prompt.ru.trim())) errors.push(`${bt}: пустой вопрос развилки`);
        for (const o of c?.options ?? []) {
          if (!o.kk.trim() || !o.ru.trim()) errors.push(`${bt}: вариант «${o.id}» без текста`);
          if (o.goto && o.goto !== 'end' && !sceneIds.has(o.goto)) errors.push(`${bt}: вариант «${o.id}» ведёт в несуществующую сцену ${o.goto}`);
          if (o.art && media.get(o.art)?.status !== 'approved') errors.push(`${bt}: кадр варианта ${o.art} не утверждён`);
        }
      }
    });
    for (const q of s.quiz) if (!ep.questions.some((x) => x.q_id === q)) errors.push(`${tag}: вопроса ${q} нет`);
  }
  const open = get<{ n: number }>('SELECT COUNT(*) AS n FROM comments WHERE episode_id = ? AND resolved = 0 AND parent_id IS NULL', episodeId)?.n ?? 0;
  if (open) warnings.push(`Открытых комментариев: ${open}`);
  return { errors, warnings };
}
