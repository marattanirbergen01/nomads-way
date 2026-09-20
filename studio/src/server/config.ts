import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

// .env читаем сами, чтобы не тянуть dotenv.
const here = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(here, '../..');
const envFile = path.join(studioRoot, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
  }
}

export const config = {
  port: Number(process.env.PORT ?? 8790),
  studioRoot,
  repoDir: path.resolve(studioRoot, process.env.REPO_DIR ?? '..'),
  dataDir: path.resolve(studioRoot, process.env.DATA_DIR ?? './data'),
  sessionSecret: process.env.SESSION_SECRET ?? 'dev-secret',
  isDev: process.env.NODE_ENV !== 'production',
};
export const contentDir = path.join(config.repoDir, 'content');
export const uploadsDir = path.join(config.dataDir, 'uploads');
fs.mkdirSync(uploadsDir, { recursive: true });
