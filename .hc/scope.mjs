#!/usr/bin/env node
// 작업별 쓰기 범위 예약·변경 검사·검증 기록. 의존성 없음(Node 18+). task.ps1·task.sh 가 부르며 Claude만 쓴다.
//   start   <작업ID> <대상> <지시문파일> [--fix-of <이전ID>]   보내기 직전: 범위 겹침·수정 횟수 검사, 기준선 저장
//   claim   <작업ID> <경로>...                                Claude가 직접 고칠 파일을 예약(보내지 않음)
//   check   <작업ID>                                          기준선 이후 바뀐 파일을 범위별로 분류
//   verify  <작업ID> [메모]                                   check 통과 + 보고 done 이면 verified 기록
//   release <작업ID> <사유>                                   검증 없이 예약 해제(포기·재할당 등)
//   status                                                    모든 작업의 상태 표
// 종료 코드: 0 정상 / 1 사용법·오류 / 6 거부(범위 겹침·수정 한도·상태) / 7 범위 밖 변경 / 8 범위 해석 불가로 판정 불가
// 한계: 공유 폴더라 '누가' 바꿨는지는 알 수 없다. 진행 중인 어떤 작업의 범위에도 없는 변경만 위반으로 본다.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const MAX_FIX = 3;
const ROOT = process.env.HC_SCOPE_ROOT
  ? path.resolve(process.env.HC_SCOPE_ROOT)
  : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TASKS = path.join(ROOT, '.hc', 'tasks');
const REPORTS = path.join(ROOT, '.hc', 'reports');
// 프로토콜이 쓰는 공유 산출물과 대형 폴더만 뺀다(.hc 전체를 빼지 않는다: 스크립트·문서 변경은 감시).
const SKIP_PREFIX = ['.hc/tasks/', '.hc/reports/', '.hc/qa/', '.hc/art/'];
const SKIP_NAME = new Set(['.git', 'node_modules']);

const out = (s = '') => process.stdout.write(s + '\n');
const err = (s) => process.stderr.write(s + '\n');
class Refuse extends Error { constructor(m, code = 6) { super(m); this.code = code; } }

// ---------- 경로 ----------
const norm = (p) => p.normalize('NFC').toLowerCase();   // 대소문자만 다른 범위는 보수적으로 같은 것으로 본다
const under = (file, dir) => { const d = dir.replace(/\/$/, ''); return file === d || file.startsWith(d + '/'); };

/** '담당 파일:' 줄을 경로 목록으로 바꾼다. 해석이 안 되면 status='unparsed'(검사 미적용). */
export function parseScope(body, root = ROOT) {
  const m = body.match(/^[ \t]*담당 파일[ \t]*:[ \t]*(.*)$/m);
  if (!m) return { status: 'none', entries: [], raw: '' };
  const raw = m[1].trim();
  let text = raw;
  for (let prev = ''; prev !== text;) { prev = text; text = text.replace(/\([^()]*\)/g, ' '); }   // 괄호 설명 제거
  const entries = [];
  for (let tok of text.split(/[,，、]/)) {
    tok = tok.trim().replace(/^[`'"]+|[`'"]+$/g, '');
    if (!tok || /^(없음|none|-)$/i.test(tok)) continue;
    if (/\s|[*?\[\]{}]/.test(tok)) return { status: 'unparsed', entries: [], raw };
    let p = tok.replace(/\\/g, '/');
    const isAbs = /^[A-Za-z]:\//.test(p) || p.startsWith('/');
    if (isAbs) {
      const rel = path.relative(root, path.resolve(p)).replace(/\\/g, '/');
      if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) return { status: 'unparsed', entries: [], raw };
      p = rel + (tok.endsWith('/') || tok.endsWith('\\') ? '/' : '');
    }
    p = p.replace(/^\.\//, '');
    if (!p || p.split('/').includes('..')) return { status: 'unparsed', entries: [], raw };
    let dir = p.endsWith('/');
    if (!dir) { try { dir = fs.statSync(path.join(root, p)).isDirectory(); } catch {} }
    p = path.relative(root, path.resolve(root, p)).replace(/\\/g, '/');
    if (!p || p === '..' || p.startsWith('../') || path.isAbsolute(p)) return { status: 'unparsed', entries: [], raw };
    let ancestor = root;
    for (const part of p.split('/')) {
      ancestor = path.join(ancestor, part);
      if (fs.existsSync(ancestor) && fs.lstatSync(ancestor).isSymbolicLink()) return { status: 'unparsed', entries: [], raw };
    }
    entries.push({ p: norm(p.replace(/\/+$/, '')), dir });
  }
  return { status: 'applied', entries, raw };
}

export function overlaps(a, b) {
  for (const x of a) for (const y of b) {
    if (x.p === y.p || (x.dir && under(y.p, x.p)) || (y.dir && under(x.p, y.p))) return `${x.p}${x.dir ? '/' : ''} ↔ ${y.p}${y.dir ? '/' : ''}`;
  }
  return null;
}
const covers = (entries, file) => { const n = norm(file); return entries.some((e) => e.p === n || (e.dir && under(n, e.p))); };
const ownedSnapshot = (rec, now) => Object.fromEntries(
  [...new Set([...Object.keys(rec.baseline), ...Object.keys(now)])]
    .filter((k) => covers(rec.scope.entries, k)).map((k) => [k, now[k] ?? null]),
);

// ---------- 파일 스냅샷 ----------
export function scan(root = ROOT) {
  const snap = {};
  const seen = new Map();
  const walk = (abs, rel) => {
    const names = fs.readdirSync(abs, { withFileTypes: true });
    for (const d of names) {
      if (SKIP_NAME.has(d.name)) continue;
      const r = rel ? `${rel}/${d.name}` : d.name;
      const key = r;   // 실제 경로를 보존하고 소유 비교용 정규화와 분리한다.
      if (SKIP_PREFIX.some((s) => (norm(key) + '/').startsWith(s))) continue;
      const canonical = norm(key);
      if (seen.has(canonical)) throw new Refuse(`정규화하면 같은 경로가 되는 파일을 검사할 수 없습니다: ${seen.get(canonical)} ↔ ${key}`, 8);
      seen.set(canonical, key);
      const a = path.join(abs, d.name);
      if (d.isSymbolicLink()) throw new Refuse(`링크 대상의 변경은 검사할 수 없습니다: ${r}`, 8);
      else if (d.isDirectory()) walk(a, r);
      else if (d.isFile()) {
        const before = fs.statSync(a);
        if (before.nlink > 1) throw new Refuse(`하드 링크 파일은 소유 경계를 검사할 수 없습니다: ${r}`, 8);
        const hash = crypto.createHash('sha1');
        const fd = fs.openSync(a, 'r');
        try {
          const buffer = Buffer.allocUnsafe(512 * 1024);
          let size;
          while ((size = fs.readSync(fd, buffer, 0, buffer.length, null)) > 0) hash.update(buffer.subarray(0, size));
        } finally { fs.closeSync(fd); }
        const after = fs.statSync(a);
        if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw new Refuse(`검사 도중 파일이 변경됐습니다: ${r}`, 8);
        snap[key] = hash.digest('hex');
      }
    }
  };
  walk(root, '');
  return snap;
}

// ---------- 작업 기록 ----------
const f = (id, ext) => path.join(TASKS, `${id}.${ext}`);
const readJson = (p) => {
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch { throw new Refuse(`기록을 읽을 수 없습니다: ${p}`, 8); }
};
const writeJson = (p, o) => { fs.mkdirSync(TASKS, { recursive: true }); fs.writeFileSync(p, JSON.stringify(o, null, 1)); };
const load = (id) => readJson(f(id, 'scope.json'));
const isDone = (id) => fs.existsSync(f(id, 'verified.json')) || fs.existsSync(f(id, 'released.json'));

export function reportStatus(id) {
  try {
    const first = fs.readFileSync(path.join(REPORTS, `${id}.md`), 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/, 1)[0];
    const m = first.match(/^\[hc-report\] id=([A-Za-z0-9._-]+) status=(done|failed|blocked)(?:\s|$)/);
    return m && m[1] === id ? m[2] : 'unknown';
  } catch { return null; }
}
export function stateOf(rec) {
  if (fs.existsSync(f(rec.id, 'released.json'))) return 'released';
  if (fs.existsSync(f(rec.id, 'verified.json'))) return 'verified';
  if (rec.kind === 'claim') return 'working';
  const r = reportStatus(rec.id);
  if (r) return r;
  return fs.existsSync(f(rec.id, 'env')) ? 'working' : 'pending';
}
function allRecords() {
  let names = [];
  if (fs.existsSync(TASKS)) names = fs.readdirSync(TASKS);
  return names.filter((n) => n.endsWith('.scope.json')).map((n) => readJson(path.join(TASKS, n))).filter(Boolean)
    .sort((a, b) => (a.startedAt < b.startedAt ? -1 : 1));
}
const active = (exceptRoot) => allRecords().filter((r) => !isDone(r.id) && r.root !== exceptRoot);

function reserve({ id, target, body, fixOf, kind }) {
  if (fs.existsSync(f(id, 'env'))) throw new Refuse(`이미 보낸 작업ID입니다: ${id}`, 1);
  const scope = parseScope(body);
  const existing = load(id);
  if (existing) {
    if (isDone(id) || reportStatus(id) || existing.target !== target || existing.fixOf !== (fixOf || null) || JSON.stringify(existing.scope) !== JSON.stringify(scope)) throw new Refuse(`이미 예약된 작업ID입니다: ${id}`, 1);
    return { root: existing.root, attempt: existing.attempt };
  }
  let root = id, attempt = 0;
  if (fixOf) {
    const old = load(fixOf);
    if (!old) throw new Refuse(`--fix-of 대상 기록이 없습니다: ${fixOf}`, 1);
    if (fs.existsSync(f(fixOf, 'verified.json'))) throw new Refuse(`${fixOf} 는 이미 verified 입니다. 새 문제면 --fix-of 없이 새 작업으로 보내세요.`);
    const family = allRecords().filter((r) => r.root === old.root);
    const latest = family.reduce((a, b) => a.attempt >= b.attempt ? a : b);
    if (latest.id !== fixOf) throw new Refuse(`수정은 계열의 마지막 작업 ${latest.id} 에서만 이어갈 수 있습니다.`);
    if (!['done', 'failed', 'blocked'].includes(reportStatus(fixOf))) throw new Refuse(`${fixOf} 의 최종 보고를 먼저 확인하세요.`);
    root = old.root; attempt = old.attempt + 1;
    if (attempt > MAX_FIX) {
      throw new Refuse(`중단: ${root} 계열의 자동 수정이 이미 ${MAX_FIX}회입니다(${fixOf} 까지). 더 재지시하지 말고 원인과 시도 내역을 사용자에게 보고하세요.`);
    }
  }
  if (scope.status === 'applied') {
    const hits = [];
    for (const r of active(root)) {
      if (r.id === id || r.scope.status !== 'applied') continue;
      const o = overlaps(scope.entries, r.scope.entries);
      if (o) hits.push(`  ${r.id} (${r.target}, ${stateOf(r)}): ${o}`);
    }
    if (hits.length) throw new Refuse(`범위 겹침: ${id} 의 담당 파일이 진행 중인 작업과 겹칩니다. 순서를 나누거나 범위를 조정하세요.\n${hits.join('\n')}`);
  } else {
    err(`경고: ${id} 의 담당 파일을 경로로 해석할 수 없어 소유 검사 미적용(${scope.status}). 형식: "담당 파일: src/a.js, test/" (괄호 설명 가능)`);
  }
  writeJson(f(id, 'scope.json'), { id, target, kind: kind || 'task', root, fixOf: fixOf || null, attempt, scope, baseline: scan(), startedAt: new Date().toISOString() });
  return { root, attempt };
}

/** 기준선 이후 변경을 분류한다. */
export function classify(id) {
  const rec = load(id);
  if (!rec) throw new Refuse(`예약 기록이 없습니다: ${id} (task send 로 보낸 작업이 아니거나 scope.mjs 가 없던 때의 작업)`, 1);
  const now = scan();
  const keys = new Set([...Object.keys(rec.baseline), ...Object.keys(now)]);
  const others = allRecords().map((r) => {
    const ended = readJson(f(r.id, 'verified.json')) || readJson(f(r.id, 'released.json'));
    return { r, ended };
  }).filter(({ r, ended }) => r.id !== id && r.scope.status === 'applied' && (!ended || ended.at >= rec.startedAt));
  const rows = [];
  for (const k of [...keys].sort()) {
    const a = rec.baseline[k], b = now[k];
    if (a === b) continue;
    const kindOf = a === undefined ? '추가' : b === undefined ? '삭제' : '변경';
    let where;
    if (rec.scope.status === 'applied' && covers(rec.scope.entries, k)) where = 'own';
    else {
      const o = others.filter(({ r, ended }) => covers(r.scope.entries, k) &&
        (!ended || (Object.hasOwn(ended.hashes || {}, k) && ended.hashes[k] === (now[k] ?? null))))
        .map(({ r }) => r.id);
      where = o.length ? `other:${o.join(',')}` : 'unowned';
    }
    rows.push({ file: k, kind: kindOf, where });
  }
  return { rec, rows, now };
}

function cmdCheck(id, { quiet, classified } = {}) {
  const { rec, rows } = classified || classify(id);
  const lines = [`검사: ${id} (${rec.target}) 범위=${rec.scope.status === 'applied' ? rec.scope.entries.map((e) => e.p + (e.dir ? '/' : '')).join(', ') || '(없음)' : '미적용'}`];
  if (!rows.length) lines.push('  기준선 이후 바뀐 파일 없음');
  for (const r of rows) {
    const tag = r.where === 'own' ? '범위 안' : r.where === 'unowned' ? '범위 밖 ✗' : `다른 작업 범위(${r.where.slice(6)})`;
    lines.push(`  ${r.kind} ${r.file}  — ${tag}`);
  }
  const unowned = rows.filter((r) => r.where === 'unowned').length;
  let code = 0;
  if (rec.scope.status !== 'applied') { lines.push('판정 불가: 담당 파일을 해석할 수 없어 범위 검사를 할 수 없습니다(직접 diff로 확인).'); code = 8; }
  else if (unowned) { lines.push(`범위 밖 변경 ${unowned}건: 통합을 멈추고 누가 바꿨는지 확인하세요(공유 폴더라 변경자는 도구로 알 수 없음).`); code = 7; }
  else lines.push('범위 밖 변경 없음.');
  const text = lines.join('\n');
  fs.writeFileSync(f(id, 'check.txt'), text + '\n');
  if (!quiet) out(text);
  return code;
}

function cmdVerify(id, note) {
  const rec = load(id);
  if (!rec) throw new Refuse(`예약 기록이 없습니다: ${id}`, 1);
  const st = stateOf(rec);
  if (st === 'verified' || st === 'released') throw new Refuse(`${id} 는 이미 ${st} 입니다.`);
  if (rec.kind !== 'claim' && st !== 'done') throw new Refuse(`${id} 의 보고 상태가 ${st} 입니다. done 보고만 verified 로 기록할 수 있습니다.`);
  const classified = classify(id);
  const code = cmdCheck(id, { classified });
  if (code !== 0) throw new Refuse(`범위 검사가 통과하지 않아 verified 로 기록하지 않습니다.`, code);
  const hashes = ownedSnapshot(rec, classified.now);
  writeJson(f(id, 'verified.json'), { at: new Date().toISOString(), note: note || '', scopeChecked: code === 0, hashes });
  out(`verified: ${id}`);
  return 0;
}

function cmdStatus() {
  const recs = allRecords();
  if (!recs.length) { out('예약 기록 없음'); return 0; }
  const now = scan();
  out('작업ID\t대상\t상태\t수정\t범위');
  for (const r of recs) {
    let st = stateOf(r);
    if (st === 'verified') {
      const v = readJson(f(r.id, 'verified.json'));
      const current = ownedSnapshot(r, now);
      const keys = new Set([...Object.keys(current), ...Object.keys(v?.hashes || {})]);
      if (!v || [...keys].some((k) => current[k] !== v.hashes[k])) st = 'verified*(이후 변경됨)';
    }
    const fix = r.attempt ? `${r.attempt}/${MAX_FIX} ←${r.fixOf}` : '-';
    const sc = r.scope.status === 'applied' ? r.scope.entries.map((e) => e.p + (e.dir ? '/' : '')).join(', ') || '(없음)' : '미적용';
    out(`${r.id}\t${r.target}\t${st}\t${fix}\t${sc}`);
  }
  return 0;
}

// ---------- CLI ----------
function main(argv) {
  const [cmd, ...a] = argv;
  if (cmd && cmd !== 'status') {
    if (!a[0] || !/^[A-Za-z0-9._-]+$/.test(a[0]) || a[0] === '.' || a[0] === '..') throw new Refuse('작업ID는 영문·숫자·._- 조합이어야 합니다.', 1);
    const fixIndex = a.indexOf('--fix-of');
    if (fixIndex >= 0 && (!/^[A-Za-z0-9._-]+$/.test(a[fixIndex + 1] || '') || ['.', '..'].includes(a[fixIndex + 1]))) throw new Refuse('--fix-of 작업ID가 올바르지 않습니다.', 1);
  }
  const need = (n, u) => { if (a.length < n) throw new Refuse(`사용법: scope.mjs ${u}`, 1); };
  switch (cmd) {
    case 'start': {
      need(3, 'start <작업ID> <대상> <지시문파일> [--fix-of <이전ID>]');
      const [id, target, file] = a;
      const i = a.indexOf('--fix-of'); const fixOf = i >= 0 ? a[i + 1] : null;
      if (i >= 0 && !fixOf) throw new Refuse('--fix-of 뒤에 이전 작업ID가 필요합니다', 1);
      const body = fs.readFileSync(file, 'utf8');
      const { root, attempt } = reserve({ id, target, body, fixOf });
      if (fixOf) out(`[수정 재지시] 이전 작업: ${fixOf} (같은 계열 ${root} 의 자동 수정 ${attempt}/${MAX_FIX}회째). 이전 지시: .hc/tasks/${fixOf}.md / 이전 보고: .hc/reports/${fixOf}.md. 이전에 시도한 방법을 반복하지 말고, 마지막 회차에 확신이 없으면 추측 수정 대신 blocked 로 보고한다.`);
      return 0;
    }
    case 'claim': {
      need(2, 'claim <작업ID> <경로>...');
      const [id, ...paths] = a;
      reserve({ id, target: 'claude', body: `담당 파일: ${paths.join(', ')}`, kind: 'claim' });
      out(`예약: ${id} (Claude 직접 작업) ${paths.join(', ')}`);
      return 0;
    }
    case 'sent': {
      need(1, 'sent <작업ID> (task 스크립트 내부용)');
      const rec = load(a[0]);
      if (!rec || !fs.existsSync(f(rec.id, 'env'))) throw new Refuse('전송 기록이 있어야 확정할 수 있습니다.', 1);
      if (rec.fixOf && !isDone(rec.fixOf)) {
        const old = load(rec.fixOf);
        writeJson(f(rec.fixOf, 'released.json'), { at: new Date().toISOString(), reason: `superseded by ${rec.id}`, hashes: ownedSnapshot(old, scan()) });
      }
      return 0;
    }
    case 'check': need(1, 'check <작업ID>'); return cmdCheck(a[0]);
    case 'verify': need(1, 'verify <작업ID> [메모]'); return cmdVerify(a[0], a.slice(1).join(' '));
    case 'release': {
      need(2, 'release <작업ID> <사유>');
      if (!load(a[0])) throw new Refuse(`예약 기록이 없습니다: ${a[0]}`, 1);
      if (isDone(a[0])) throw new Refuse(`${a[0]} 는 이미 끝난 예약입니다.`);
      const rec = load(a[0]);
      writeJson(f(a[0], 'released.json'), { at: new Date().toISOString(), reason: a.slice(1).join(' '), hashes: ownedSnapshot(rec, scan()) });
      out(`해제: ${a[0]}`);
      return 0;
    }
    case 'status': return cmdStatus();
    default: throw new Refuse('사용법: scope.mjs start|claim|check|verify|release|status ...', 1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = main(process.argv.slice(2)); }
  catch (e) { err(e instanceof Refuse ? e.message : `오류: ${e.stack || e}`); process.exitCode = e instanceof Refuse ? e.code : 1; }
}
