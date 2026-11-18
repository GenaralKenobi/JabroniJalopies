// Collects the license notices of every library bundled into the website into dist/licenses.txt
// (shown from Settings → About). Their licenses require passing these notices on.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const seen = new Set();
const entries = [];

function visit(name) {
  if (seen.has(name)) return;
  seen.add(name);
  const dir = join(root, 'node_modules', name);
  if (!existsSync(join(dir, 'package.json'))) return;
  const info = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  const file = readdirSync(dir).find((f) => /^(licen[cs]e|copying|notice)(\..*)?$/i.test(f));
  entries.push({ name, version: info.version, license: info.license ?? 'see text', text: file ? readFileSync(join(dir, file), 'utf8').trim() : '' });
  for (const dep of Object.keys(info.dependencies ?? {})) visit(dep);
}

for (const dep of Object.keys(pkg.dependencies)) visit(dep);
entries.sort((a, b) => a.name.localeCompare(b.name));

const byText = new Map();
for (const e of entries) {
  const key = e.text || `${e.license} (no license file included)`;
  if (!byText.has(key)) byText.set(key, []);
  byText.get(key).push(`${e.name} ${e.version}`);
}
let out = 'Jabroni Jalopies (website) — open-source licenses\n\nThe website includes these open-source libraries:\n\n';
out += entries.map((e) => `- ${e.name} ${e.version} (${e.license})`).join('\n') + '\n';
for (const [text, names] of byText) out += `\n${'='.repeat(72)}\n${names.join(', ')}\n${'='.repeat(72)}\n\n${text}\n`;
writeFileSync(join(root, 'dist', 'licenses.txt'), out);
console.log(`licenses.txt: ${entries.length} packages`);
