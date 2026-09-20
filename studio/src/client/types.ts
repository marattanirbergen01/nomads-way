export type Role = 'admin' | 'writer' | 'historian' | 'media' | 'agent_script' | 'agent_media' | 'viewer';

export interface Me {
  id: number;
  login: string;
  name: string;
  role: Role;
  roleTitle: string;
  permissions: string[];
}

export interface Lang {
  kk: string;
  ru: string;
}

export interface Character {
  id: number;
  episode_id: string;
  char_id: string;
  sort: number;
  name_kk: string;
  name_ru: string;
  fiction: number;
  note: string | null;
  avatar: number;
  default_name: Lang | null;
  portrait: string | null;
}

export interface ChoiceOption {
  id: string;
  kk: string;
  ru: string;
  set: Record<string, number> | null;
  goto: string | null;
  art: string | null;
  reply: { kk: string; ru: string; emotion: string | null } | null;
}
export interface Choice {
  prompt: Lang;
  options: ChoiceOption[];
}

export interface Beat {
  id: number;
  scene_id: number;
  sort: number;
  kind: 'say' | 'choice';
  who: string | null;
  kk: string;
  ru: string;
  emotion: string | null;
  when_cond: string | null;
  choice: Choice | null;
  origin: 'human' | 'agent';
  needs_review: number;
  version: number;
  updated_by: number | null;
  updated_at: string;
}

export type SceneStatus = 'draft' | 'review' | 'text_ok' | 'media_ok' | 'ready';

export interface Scene {
  id: number;
  episode_id: string;
  scene_id: string;
  sort: number;
  art: string | null;
  art_when: { if: string; art: string }[] | null;
  layer: 'history' | 'personal' | null;
  covers: string[];
  title_kk: string | null;
  title_ru: string | null;
  pan: number | null;
  avatar_side: 'left' | 'right' | null;
  avatar_in_art: number;
  quiz: string[];
  note: string | null;
  status: SceneStatus;
  version: number;
  updated_by: number | null;
  updated_at: string;
  beats: Beat[];
}

export interface Question {
  id: number;
  q_id: string;
  sort: number;
  data: any;
  status: string;
}

export type EpisodeStatus = 'draft' | 'review' | 'approved' | 'published';

export interface Episode {
  id: string;
  season_id: string;
  slug: string;
  sort: number;
  title_kk: string;
  title_ru: string;
  era: string | null;
  topics: string[];
  final_test: any;
  status: EpisodeStatus;
  approved_by: string | null;
  revision: number;
  version: number;
  updated_at: string;
  characters: Character[];
  scenes: Scene[];
  questions: Question[];
  commentCounts: Record<string, number>;
  users: { id: number; name: string; role: Role }[];
}

export interface EpisodeSummary {
  id: string;
  season_id: string;
  title_kk: string;
  title_ru: string;
  era: string | null;
  status: EpisodeStatus;
  approved_by: string | null;
  scene_count: number;
  ready_count: number;
  open_comments: number;
  updated_at: string;
}

export interface Season {
  id: string;
  title_kk: string;
  title_ru: string;
  sort: number;
}

export interface Media {
  id: string;
  season_id: string;
  kind: string;
  status: 'missing' | 'draft' | 'approved';
  brief: string | null;
  seed: number | null;
  prompt_ref: string | null;
  prompt_text: string | null;
  file: string | null;
  upload: string | null;
  approved_by: string | null;
  generated: string | null;
  note: string | null;
  source: any;
  hasFile: boolean;
  version: number;
  updated_at: string;
}

export interface Comment {
  id: number;
  target_type: string;
  target_id: string;
  episode_id: string | null;
  author_id: number;
  author_name: string;
  author_role: Role;
  parent_id: number | null;
  body: string;
  resolved: number;
  created_at: string;
}

export interface PresenceEntry {
  userId: number;
  name: string;
  role: string;
  sceneId: number | null;
  editing: string | null;
}

export const EMOTIONS = ['calm', 'joy', 'alarm', 'sorrow'] as const;
export const EMOTION_TITLES: Record<string, string> = {
  calm: 'Спокойствие',
  joy: 'Радость',
  alarm: 'Тревога',
  sorrow: 'Печаль',
};

export const SCENE_STATUS_TITLES: Record<SceneStatus, string> = {
  draft: 'Черновик',
  review: 'На вычитке',
  text_ok: 'Текст утверждён',
  media_ok: 'Медиа готово',
  ready: 'Готова',
};
export const EPISODE_STATUS_TITLES: Record<EpisodeStatus, string> = {
  draft: 'Черновик',
  review: 'На утверждении',
  approved: 'Утверждена',
  published: 'Собрана',
};
export const ROLE_TITLES: Record<Role, string> = {
  admin: 'Админ',
  writer: 'Сценарист',
  historian: 'Историк',
  media: 'Медиа',
  agent_script: 'Агент-сценарий',
  agent_media: 'Агент-медиа',
  viewer: 'Наблюдатель',
};
