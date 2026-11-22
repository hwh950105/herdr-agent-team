// scope.mjs 모의 테스트(실제 hc·에이전트 없이 임시 폴더에서 CLI 실행). 실행: node --test .hc/scope.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseScope, overlaps, scan } from './scope.mjs';

const SCOPE = path.join(path.dirname(fileURLToPath(import.meta.url)), 'scope.mjs');

function project() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'scope-test-'));
  for (const d of ['src', 'test', 'public', '.hc/tasks', '.hc/reports', '.hc/qa', '.hc/docs']) fs.mkdirSync(path.join(root, d), { recursive: true });
  for (const p of ['src/a.js', 'src/ab.js', 'test/a.test.js', 'public/index.html', '.hc/docs/lead.md', 'README.md']) fs.writeFileSync(path.join(root, p), p);
  const run = (...args) => {
    const r = spawnSync(process.execPath, [SCOPE, ...args], { env: { ...process.env, HC_SCOPE_ROOT: root }, encoding: 'utf8' });
    return { code: r.status, out: r.stdout, err: r.stderr };
  };
  const body = (id, scopeLine) => { const p = path.join(root, '.hc/tasks', `${id}.body`); fs.writeFileSync(p, `목표: x\n담당 파일: ${scopeLine}\n완료 조건: y\n`); return p; };
  const start = (id, scopeLine, ...extra) => run('start', id, 't9', body(id, scopeLine), ...extra);
  const sent = (id) => {
    fs.writeFileSync(path.join(root, '.hc/tasks', `${id}.env`), 'TARGET=t9\nTURN=1\nNUDGES=0\n');
    assert.equal(run('sent', id).code, 0);
  };
  const report = (id, st) => fs.writeFileSync(path.join(root, '.hc/reports', `${id}.md`), `[hc-report] id=${id} status=${st}\n요약: x\n`);
  const write = (p, s = 'changed') => { fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true }); fs.writeFileSync(path.join(root, p), s); };
  return { root, run, start, sent, report, write, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('담당 파일 해석: 괄호 설명 제거, 없음, 공백 섞인 문장은 미적용', () => {
  const r = parseScope('담당 파일: src/server.js (src/ 아래 새 파일 추가 가능, src/db.js 제외), test/\n', os.tmpdir());
  assert.equal(r.status, 'applied');
  assert.deepEqual(r.entries, [{ p: 'src/server.js', dir: false }, { p: 'test', dir: true }]);
  assert.deepEqual(parseScope('담당 파일: 없음 (보고 파일만 쓴다)').entries, []);
  assert.equal(parseScope('담당 파일: 없음 (보고 파일만 쓴다)').status, 'applied');
  assert.equal(parseScope('담당 파일: C:\\x\\.hc\\qa\\v 폴더 안만 (설명)').status, 'unparsed');
  assert.equal(parseScope('담당 파일: ../밖/a.js').status, 'unparsed');
  assert.equal(parseScope('목표: 담당 파일 줄 없음').status, 'none');
});

test('절대 경로는 프로젝트 안이면 상대 경로로 바꾼다', () => {
  const root = path.join(os.tmpdir(), 'abs-root');
  const r = parseScope(`담당 파일: ${path.join(root, 'src', 'x.js')}, ${path.join(root, 'public')}\\`, root);
  assert.equal(r.status, 'applied');
  assert.deepEqual(r.entries.map((e) => e.p), ['src/x.js', 'public']);
  assert.equal(r.entries[1].dir, true);
});

test('겹침 판정: 접두사 문자열이 아니라 경로 단위, 대소문자 무시', () => {
  const e = (p, dir = false) => ({ p, dir });
  assert.equal(overlaps([e('src/a')], [e('src/ab')]), null);
  assert.ok(overlaps([e('src', true)], [e('src/a.js')]));
  assert.ok(overlaps([e('src/a.js')], [e('src/a.js')]));
  assert.equal(overlaps([e('src', true)], [e('srcx', true)]), null);
  assert.equal(overlaps([], [e('src', true)]), null);
  assert.ok(parseScope('담당 파일: SRC/A.js').entries[0].p === 'src/a.js');
});

test('시작 전 범위 겹침이면 거부(6), 겹치지 않으면 허용, release 후 허용', () => {
  const t = project();
  try {
    assert.equal(t.start('A', 'src/').code, 0);
    const b = t.start('B', 'src/a.js, public/');
    assert.equal(b.code, 6);
    assert.match(b.err, /범위 겹침/);
    assert.equal(t.start('C', 'public/, test/').code, 0);
    assert.equal(t.run('release', 'A', '재할당').code, 0);
    assert.equal(t.start('B2', 'src/a.js').code, 0);
  } finally { t.cleanup(); }
});

test('수정 재지시는 계열별 3회까지, 4번째는 거부(6). 이전 작업은 superseded 로 해제', () => {
  const t = project();
  try {
    assert.equal(t.start('F', 'src/a.js').code, 0); t.sent('F'); t.report('F', 'done');
    let prev = 'F';
    for (let n = 1; n <= 3; n++) {
      const r = t.start(`F${n}`, 'src/a.js', '--fix-of', prev);   // 같은 파일이지만 같은 계열이라 겹침 아님
      assert.equal(r.code, 0, r.err);
      assert.match(r.out, new RegExp(`자동 수정 ${n}/3`));
      t.sent(`F${n}`); t.report(`F${n}`, 'done');
      prev = `F${n}`;
    }
    const r4 = t.start('F4', 'src/a.js', '--fix-of', 'F3');
    assert.equal(r4.code, 6);
    assert.match(r4.err, /이미 3회/);
    const st = t.run('status').out;
    assert.match(st, /F\t.*released/);
    assert.match(st, /F3\t.*3\/3 ←F2/);
  } finally { t.cleanup(); }
});

test('verified 작업에는 --fix-of 불가', () => {
  const t = project();
  try {
    t.start('V', 'src/a.js'); t.sent('V'); t.report('V', 'done');
    assert.equal(t.run('verify', 'V').code, 0);
    assert.equal(t.start('V1', 'src/a.js', '--fix-of', 'V').code, 6);
  } finally { t.cleanup(); }
});

test('완료 후 변경 분류: 범위 안 0, 다른 작업 범위는 표시만, 범위 밖 7, 프로토콜 폴더는 무시', () => {
  const t = project();
  try {
    t.start('BE', 'src/, test/'); t.start('FE', 'public/');
    t.write('src/a.js'); t.write('test/new.test.js');
    t.write('.hc/qa/BE/shot.png'); t.write('.hc/reports/BE.md', '[hc-report] id=BE status=done');
    let r = t.run('check', 'BE');
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /변경 src\/a\.js +— 범위 안/);
    assert.match(r.out, /추가 test\/new\.test\.js +— 범위 안/);
    assert.doesNotMatch(r.out, /\.hc\/qa|\.hc\/reports/);
    t.write('public/index.html');
    r = t.run('check', 'BE');
    assert.equal(r.code, 0);
    assert.match(r.out, /public\/index\.html +— 다른 작업 범위\(FE\)/);
    t.write('.hc/docs/lead.md'); fs.rmSync(path.join(t.root, 'README.md'));
    r = t.run('check', 'BE');
    assert.equal(r.code, 7);
    assert.match(r.out, /변경 \.hc\/docs\/lead\.md +— 범위 밖/);
    assert.match(r.out, /삭제 README\.md +— 범위 밖/);
  } finally { t.cleanup(); }
});

test('verify: done 보고만, 범위 밖 변경 있으면 거부(7), 이후 범위 파일이 바뀌면 status 에 표시', () => {
  const t = project();
  try {
    t.start('W', 'src/a.js'); t.sent('W');
    assert.equal(t.run('verify', 'W').code, 6);          // 보고 전(working)
    t.report('W', 'failed');
    assert.equal(t.run('verify', 'W').code, 6);          // failed
    t.report('W', 'done'); t.write('README.md');
    assert.equal(t.run('verify', 'W').code, 7);          // 범위 밖 변경
    t.write('README.md', 'README.md');                     // 원래대로
    t.write('src/a.js');
    const v = t.run('verify', 'W', '테스트 통과');
    assert.equal(v.code, 0, v.err + v.out);
    assert.match(t.run('status').out, /W\tt9\tverified\t/);
    t.write('src/a.js', 'again');
    assert.match(t.run('status').out, /W\tt9\tverified\*/);
  } finally { t.cleanup(); }
});

test('범위 해석 불가면 경고 후 보내기는 허용, check 는 판정 불가(8)', () => {
  const t = project();
  try {
    const r = t.start('U', 'public 폴더 안만');
    assert.equal(r.code, 0);
    assert.match(r.err, /소유 검사 미적용/);
    t.write('public/index.html');
    assert.equal(t.run('check', 'U').code, 8);
    t.report('U', 'done');
    assert.equal(t.run('verify', 'U').code, 8);
    assert.equal(fs.existsSync(path.join(t.root, '.hc/tasks/U.verified.json')), false);
  } finally { t.cleanup(); }
});

test('수정 지시를 옛 작업에서 다시 분기하여 횟수를 우회할 수 없다', () => {
  const t = project();
  try {
    t.start('F', 'src/a.js'); t.sent('F'); t.report('F', 'failed');
    assert.equal(t.start('F1', 'src/a.js', '--fix-of', 'F').code, 0);
    t.sent('F1'); t.report('F1', 'failed');
    assert.equal(t.start('branch', 'src/a.js', '--fix-of', 'F').code, 6);
    assert.equal(t.start('F2', 'src/a.js', '--fix-of', 'F1').code, 0);
  } finally { t.cleanup(); }
});

test('보고 전에는 다른 대상으로 같은 계열의 수정 지시를 만들 수 없다', () => {
  const t = project();
  try {
    t.start('F', 'src/a.js'); t.sent('F');
    assert.equal(t.start('F1', 'src/a.js', '--fix-of', 'F').code, 6);
  } finally { t.cleanup(); }
});

test('병렬 작업을 순서대로 verify해도 먼저 완료된 작업의 정상 변경을 위반으로 보지 않는다', () => {
  const t = project();
  try {
    t.start('BE', 'src/'); t.start('FE', 'public/');
    t.write('src/a.js'); t.write('public/index.html');
    t.report('BE', 'done'); t.report('FE', 'done');
    assert.equal(t.run('verify', 'BE').code, 0);
    const result = t.run('verify', 'FE');
    assert.equal(result.code, 0, result.out + result.err);
  } finally { t.cleanup(); }
});

test('완료된 다른 작업의 검증 이후 변경은 면제하지 않는다', () => {
  const t = project();
  try {
    t.start('A', 'src/'); t.start('B', 'public/');
    t.write('src/a.js'); t.report('A', 'done');
    assert.equal(t.run('verify', 'A').code, 0);
    t.write('src/a.js', '검증 후 다시 변경'); t.report('B', 'done');
    assert.equal(t.run('check', 'B').code, 7);
    assert.equal(t.run('verify', 'B').code, 7);
  } finally { t.cleanup(); }
});

test('해제 시점의 정확한 변경만 병렬 작업에서 면제한다', () => {
  const t = project();
  try {
    t.start('A', 'src/'); t.start('B', 'public/');
    t.write('src/a.js');
    assert.equal(t.run('release', 'A', '확인 후 인수').code, 0);
    assert.equal(t.run('check', 'B').code, 0);
    t.write('src/a.js', '해제 후 다시 변경');
    assert.equal(t.run('check', 'B').code, 7);
  } finally { t.cleanup(); }
});

test('수정 지시의 전송 실패는 부모 예약을 해제하지 않고 재시도 기준선을 보존한다', () => {
  const t = project();
  try {
    t.start('F', 'src/a.js'); t.sent('F'); t.report('F', 'failed');
    assert.equal(t.start('F1', 'src/a.js', '--fix-of', 'F').code, 0);
    assert.equal(fs.existsSync(path.join(t.root, '.hc/tasks/F.released.json')), false);
    t.write('README.md');
    assert.equal(t.start('F1', 'src/a.js', '--fix-of', 'F').code, 0);
    assert.equal(t.run('check', 'F1').code, 7);
    t.sent('F1');
    assert.equal(fs.existsSync(path.join(t.root, '.hc/tasks/F.released.json')), true);
  } finally { t.cleanup(); }
});

test('verified 이후 담당 디렉터리에 새 파일이 생겨도 변경됨으로 표시한다', () => {
  const t = project();
  try {
    t.start('V', 'src/'); t.report('V', 'done');
    assert.equal(t.run('verify', 'V').code, 0);
    t.write('src/new.js');
    assert.match(t.run('status').out, /V\tt9\tverified\*/);
  } finally { t.cleanup(); }
});

test('다른 작업 ID의 보고를 현재 작업의 done으로 인정하지 않는다', () => {
  const t = project();
  try {
    t.start('V', 'src/');
    t.write('.hc/reports/V.md', '[hc-report] id=OTHER status=done');
    assert.equal(t.run('verify', 'V').code, 6);
  } finally { t.cleanup(); }
});

test('경로 별칭으로 소유 중복을 우회할 수 없다', () => {
  const t = project();
  try {
    assert.equal(t.start('A', 'src/').code, 0);
    assert.equal(t.start('B', '././src/a.js').code, 6);
    assert.equal(parseScope('담당 파일: src/*', t.root).status, 'unparsed');
  } finally { t.cleanup(); }
});

test('claim: Claude 직접 작업도 예약되어 겹침 검사·check 대상이 된다', () => {
  const t = project();
  try {
    assert.equal(t.run('claim', 'C1', 'src/a.js', 'README.md').code, 0);
    assert.equal(t.start('X', 'src/').code, 6);
    t.write('README.md');
    assert.equal(t.run('check', 'C1').code, 0);
    assert.equal(t.run('verify', 'C1').code, 0);
    assert.equal(t.start('X2', 'src/').code, 0);
  } finally { t.cleanup(); }
});

test('보낸 작업ID로 다시 start 하면 거부, 보내기 전 재시도는 기준선을 보존한다', () => {
  const t = project();
  try {
    assert.equal(t.start('R', 'src/a.js').code, 0);
    t.write('README.md');
    assert.equal(t.start('R', 'src/a.js').code, 0);        // 전송 실패 후 같은 ID로 재시도
    assert.equal(t.run('check', 'R').code, 7);
    assert.equal(t.start('R', 'public/').code, 1);
    t.sent('R');
    assert.equal(t.start('R', 'src/a.js').code, 1);
  } finally { t.cleanup(); }
});

test('verified claim ID를 새 범위로 재사용하지 않는다', () => {
  const t = project();
  try {
    assert.equal(t.run('claim', 'C', 'src/a.js').code, 0);
    assert.equal(t.run('verify', 'C').code, 0);
    assert.equal(t.run('claim', 'C', 'public/').code, 1);
  } finally { t.cleanup(); }
});

test('scope 직접 실행도 상위 경로 작업ID를 거부한다', () => {
  const t = project();
  try {
    assert.equal(t.run('claim', '../escape', 'src/').code, 1);
  } finally { t.cleanup(); }
});

test('디렉터리 열거 및 파일 읽기 오류를 빈 스냅샷으로 숨기지 않는다', (context) => {
  const t = project();
  try {
    const originalRead = fs.readdirSync;
    context.mock.method(fs, 'readdirSync', (dir, ...args) => {
      if (dir === path.join(t.root, 'src')) throw new Error('주입한 디렉터리 읽기 실패');
      return originalRead(dir, ...args);
    });
    assert.throws(() => scan(t.root), /디렉터리 읽기 실패/);
    context.mock.restoreAll();
    const originalOpen = fs.openSync;
    context.mock.method(fs, 'openSync', (file, ...args) => {
      if (file === path.join(t.root, 'src/a.js')) throw new Error('주입한 파일 읽기 실패');
      return originalOpen(file, ...args);
    });
    assert.throws(() => scan(t.root), /파일 읽기 실패/);
  } finally { context.mock.restoreAll(); t.cleanup(); }
});

test('손상된 소유 기록을 무시하고 겹치는 작업을 시작하지 않는다', () => {
  const t = project();
  try {
    t.start('A', 'src/');
    t.write('.hc/tasks/A.scope.json', '{broken');
    assert.equal(t.start('B', 'src/').code, 8);
  } finally { t.cleanup(); }
});

test('링크를 통한 소유 범위 우회는 판정 불가로 중단한다', () => {
  const t = project();
  try {
    fs.symlinkSync(path.join(t.root, 'src'), path.join(t.root, 'alias'), process.platform === 'win32' ? 'junction' : 'dir');
    assert.equal(parseScope('담당 파일: alias/a.js', t.root).status, 'unparsed');
    assert.equal(t.start('L', 'src/').code, 8);
  } finally { t.cleanup(); }
});

test('하드 링크 파일도 검사 가능한 일반 파일로 취급하지 않는다', () => {
  const t = project();
  try {
    fs.linkSync(path.join(t.root, 'src/a.js'), path.join(t.root, 'public/alias.js'));
    assert.equal(t.start('L', 'src/').code, 8);
  } finally { t.cleanup(); }
});

test('Unicode 정규화로 같은 이름이 되는 별개 파일은 조용히 덮어쓰지 않는다', (context) => {
  const t = project();
  try {
    t.write('src/\u00e9.js', '첫 번째 파일');
    t.write('src/e\u0301.js', '두 번째 파일');
    if (fs.readdirSync(path.join(t.root, 'src')).filter((name) => name.normalize('NFC') === '\u00e9.js').length < 2) {
      context.skip('파일시스템이 Unicode 정규화 별칭을 같은 파일로 취급함');
      return;
    }
    assert.equal(t.start('NFC', 'src/').code, 8);
  } finally { t.cleanup(); }
});

test('읽는 도중 계속 바뀌는 파일은 검사를 멈추지 않고 unstable 표식으로 기록한다', (context) => {
  const t = project();
  try {
    t.write('data/app.db-wal', 'wal');
    const target = path.join(t.root, 'data/app.db-wal');
    const originalStat = fs.statSync;
    let n = 0;
    context.mock.method(fs, 'statSync', (file, ...args) => {
      const st = originalStat(file, ...args);
      return file === target ? { ...st, nlink: st.nlink, size: st.size, ctimeMs: st.ctimeMs, mtimeMs: st.mtimeMs + n++ } : st;
    });
    const snap = scan(t.root);
    assert.match(snap['data/app.db-wal'], /^unstable:/);
    assert.match(snap['src/a.js'], /^[0-9a-f]{40}$/);
  } finally { context.mock.restoreAll(); t.cleanup(); }
});

// 크기·mtime 은 고정하고 ctime 만 stat 마다 바꾸는 preload. 매 scan 의 unstable 표식이 같은 문자열이 된다(표식 충돌).
function collidingProject(rel) {
  const t = project();
  t.write(rel, 'aa');
  const target = path.join(t.root, rel);
  const preload = path.join(t.root, '.hc/tasks/unstable-preload.mjs');
  fs.writeFileSync(preload, `import fs from 'node:fs';
const target = ${JSON.stringify(target)}; const orig = fs.statSync; let n = 0;
fs.statSync = (p, ...a) => { const s = orig(p, ...a); if (String(p) !== target) return s;
  return Object.assign(Object.create(Object.getPrototypeOf(s)), s, { mtimeMs: 10, ctimeMs: n++ }); };
`);
  const run = (...args) => {
    const r = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, SCOPE, ...args], { env: { ...process.env, HC_SCOPE_ROOT: t.root }, encoding: 'utf8' });
    return { code: r.status, out: r.stdout, err: r.stderr };
  };
  const start = (id, scopeLine) => {
    const b = path.join(t.root, '.hc/tasks', `${id}.body`);
    fs.writeFileSync(b, `목표: x\n담당 파일: ${scopeLine}\n완료 조건: y\n`);
    return run('start', id, 't9', b);
  };
  return { ...t, run, start };
}

test('unstable 표식이 같은 문자열이어도 미소유 변경을 놓치지 않는다', () => {
  const t = collidingProject('data/app.log');
  try {
    assert.equal(t.start('U', 'src/a.js').code, 0);
    assert.match(JSON.parse(fs.readFileSync(path.join(t.root, '.hc/tasks/U.scope.json'), 'utf8')).baseline['data/app.log'], /^unstable:2:10$/);
    t.write('data/app.log', 'bb');
    const r = t.run('check', 'U');
    assert.equal(r.code, 7, r.out + r.err);
    assert.match(r.out, /data\/app\.log/);
  } finally { t.cleanup(); }
});

test('unstable 파일이 담긴 verified 는 status 에서 항상 이후 변경됨으로 표시한다', () => {
  const t = collidingProject('data/app.log');
  try {
    assert.equal(t.run('claim', 'V', 'data/').code, 0);
    const v = t.run('verify', 'V', '근거');
    assert.equal(v.code, 0, v.out + v.err);
    assert.match(v.out, /경고: 계속 바뀌던 파일 data\/app\.log/);
    t.write('data/app.log', 'cc');
    assert.match(t.run('status').out, /V\t[^\n]*verified\*/);
  } finally { t.cleanup(); }
});

test('해제된 작업의 unstable 표식과 같아도 이후 변경을 그 작업 변경으로 면제하지 않는다', () => {
  const t = collidingProject('data/app.log');
  try {
    assert.equal(t.start('T', 'src/a.js').code, 0);
    assert.equal(t.run('claim', 'P', 'data/').code, 0);
    assert.equal(t.run('release', 'P', '테스트').code, 0);
    t.write('data/app.log', 'dd');
    const r = t.run('check', 'T');
    assert.equal(r.code, 7, r.out + r.err);
    assert.doesNotMatch(r.out, /다른 작업 범위\(P\)/);
  } finally { t.cleanup(); }
});

test('실행 중 프로세스가 쓰는 파일이 있어도 send 예약은 되고, 미예약이면 미소유 변경 7·예약하면 0', async () => {
  const t = project();
  const log = path.join(t.root, 'data/app.log');
  t.write('data/app.log', 'x'.repeat(1 << 20));
  const writer = spawn(process.execPath, ['-e',
    `const fs=require('fs');const p=process.argv[1];setInterval(()=>{for(let i=0;i<50;i++)fs.appendFileSync(p,'line\\n')},1)`,
    log], { stdio: 'ignore' });
  let exited = false;
  const exit = new Promise((r) => { writer.once('exit', () => { exited = true; r(); }); writer.once('error', () => { exited = true; r(); }); });
  // 고정 sleep 대신 실제로 파일이 커질 때까지 기다린다(제한 10초, writer 가 먼저 끝나면 즉시 실패).
  const grows = async () => {
    const s0 = fs.statSync(log).size;
    for (const end = Date.now() + 10000; Date.now() < end;) {
      if (exited) throw new Error('writer 가 먼저 종료됨');
      if (fs.statSync(log).size > s0) return;
      await new Promise((r) => setTimeout(r, 20));
    }
    throw new Error('writer 가 10초 안에 쓰지 않음');
  };
  try {
    await grows();
    assert.equal(t.start('W1', 'src/a.js').code, 0);
    await grows();
    assert.equal(t.run('check', 'W1').code, 7);
    assert.equal(t.run('release', 'W1', 'test').code, 0);
    assert.equal(t.start('W2', 'data/').code, 0);
    await grows();
    assert.equal(t.run('check', 'W2').code, 0);
  } finally {
    if (!exited) writer.kill();
    await Promise.race([exit, new Promise((r) => setTimeout(r, 5000).unref())]);
    t.cleanup();
  }
});

test('예약 기록을 저장한 뒤 임시 파일을 남기지 않는다', () => {
  const t = project();
  try {
    assert.equal(t.run('claim', 'A', 'src/').code, 0);
    assert.equal(t.run('release', 'A', '작업 중단').code, 0);
    assert.deepEqual(fs.readdirSync(path.join(t.root, '.hc/tasks')).sort(), [
      'A.released.json',
      'A.scope.json',
    ]);
  } finally { t.cleanup(); }
});

test('남은 임시 파일은 현황과 새 예약에서 무시한다', () => {
  const t = project();
  try {
    t.write('.hc/tasks/x.scope.json.123.abc.tmp', '{broken');
    const status = t.run('status');
    assert.equal(status.code, 0);
    assert.match(status.out, /예약 기록 없음/);
    assert.equal(t.start('B', 'src/').code, 0);
    assert.equal(t.run('status').code, 0);
  } finally { t.cleanup(); }
});
