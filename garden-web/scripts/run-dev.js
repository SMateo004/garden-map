/**
 * Wrapper for npm run dev: logs cwd and vite presence, then spawns vite.
 */
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';

const cwd = process.cwd();
const hasVite = fs.existsSync(path.join(cwd, 'node_modules', 'vite'));
const pkgName = (() => {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(cwd, 'package.json'), 'utf8'));
    return pkg.name || 'unknown';
  } catch {
    return 'unknown';
  }
})();

if (pkgName !== 'garden-web') {
  console.error('\n[GARDEN] No estás en el frontend. Para levantar la web ejecuta:\n  cd garden-web\n  npm run dev\n');
  console.error('(Ahora estás en:', cwd, '| package:', pkgName, ')\n');
  process.exit(1);
}
console.log('[GARDEN] Frontend (garden-web) — iniciando Vite en', cwd);

const child = spawn('npx', ['vite'], { stdio: 'inherit', shell: true, cwd });
child.on('exit', (code, signal) => {
  process.exit(code ?? (signal ? 1 : 0));
});
