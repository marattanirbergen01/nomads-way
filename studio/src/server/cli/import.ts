// npm run import            — все серии из content/
// npm run import -- s1e01   — одна серия
import { importAll, importEpisodeFile, findEpisodeFile } from '../importer.js';

const arg = process.argv[2];
if (arg) {
  const file = findEpisodeFile(arg.split('e')[0], arg);
  if (!file) {
    console.error('Серия не найдена в content/episodes:', arg);
    process.exit(1);
  }
  console.log(importEpisodeFile(file));
} else {
  for (const r of importAll()) console.log(r);
}
