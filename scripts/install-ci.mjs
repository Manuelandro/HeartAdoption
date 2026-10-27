import { spawnSync } from 'node:child_process';

// Keep failures visible in the check summary as well as the full runner log.
const result = spawnSync('npm', ['ci', '--no-audit', '--no-fund', ...process.argv.slice(2)], {
  cwd: new URL('../server/', import.meta.url),
  encoding: 'utf8',
  maxBuffer: 8 * 1024 * 1024,
});
process.stdout.write(result.stdout ?? '');
process.stderr.write(result.stderr ?? '');
if (result.status !== 0) {
  const message = `${result.error?.message ?? ''}\n${result.stderr ?? ''}\n${result.stdout ?? ''}`.trim().slice(0, 8000);
  const annotation = message.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
  console.error(`::error title=Dependency installation failed::${annotation}`);
}
process.exit(result.status ?? 1);
