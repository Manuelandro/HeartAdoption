import { build } from 'esbuild';
import { readFile, writeFile, mkdir, cp, rm, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve, join } from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const output = resolve(root, 'build/NeonFunction');
const cache = resolve(root, 'build/NeonAssets');
const lock = JSON.parse(await readFile(new URL('../package-lock.json', import.meta.url), 'utf8'));
await mkdir(cache, { recursive: true });
await rm(output, { recursive: true, force: true });
await mkdir(join(output, 'node_modules'), { recursive: true });
await build({
  entryPoints: [fileURLToPath(new URL('../src/neon-function.ts', import.meta.url))],
  outfile: join(output, 'index.mjs'), bundle: true, platform: 'node', target: 'node24', format: 'esm',
  external: ['sharp', 'pg-native'],
  banner: { js: "import{createRequire as __cr}from'node:module';import{fileURLToPath as __fu}from'node:url';import{dirname as __dn}from'node:path';const require=__cr(import.meta.url);const __filename=__fu(import.meta.url);const __dirname=__dn(__filename);" },
});

// Neon runs Linux ARM64/glibc. Use the exact prebuilt versions pinned in our lockfile,
// rather than shipping the Mac or Linux x64 addons from a developer/CI installation.
const packages = ['sharp', '@img/colour', 'detect-libc', 'semver', '@img/sharp-linux-arm64', '@img/sharp-libvips-linux-arm64'];
for (const name of packages) {
  const info = lock.packages[`node_modules/${name}`];
  if (!info?.resolved || !info.integrity?.startsWith('sha512-')) throw new Error(`Missing locked package: ${name}`);
  const tarball = join(cache, `${name.replaceAll('/', '-')}-${info.version}.tgz`);
  let bytes;
  try { bytes = await readFile(tarball); }
  catch {
    const response = await fetch(info.resolved);
    if (!response.ok) throw new Error(`Cannot download ${name}: ${response.status}`);
    bytes = Buffer.from(await response.arrayBuffer()); await writeFile(tarball, bytes);
  }
  const integrity = 'sha512-' + createHash('sha512').update(bytes).digest('base64');
  if (integrity !== info.integrity) throw new Error(`Integrity mismatch for ${name}`);
  const destination = join(output, 'node_modules', name);
  await mkdir(destination, { recursive: true });
  execFileSync('tar', ['-xzf', tarball, '--strip-components=1', '-C', destination]);
}
const archive = resolve(root, 'build/heart-adoption-function.zip');
await rm(archive, { force: true });
execFileSync('zip', ['-q', '-r', archive, '.'], { cwd: output });
const size = (await stat(archive)).size;
if (size > 32 * 1024 * 1024) throw new Error('Function archive exceeds the 32 MiB deployment limit.');
console.log(`Built ${archive} (${(size / 1024 / 1024).toFixed(2)} MiB), with checksum-verified Linux ARM64 image libraries.`);
