// scope.mjs 모의 테스트(실제 hc·에이전트 없이 임시 폴더에서 CLI 실행). 실행: node --test .hc/scope.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseScope, overlaps } from './scope.mjs';

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
  const sent = (id) => fs.writeFileSync(path.join(root, '.hc/tasks', `${id}.env`), 'TARGET=t9\nTURN=1\nNUDGES=0\n');
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

test('보낸 작업ID로 다시 start 하면 거부, 보내기 전이면 덮어쓰기 허용', () => {
  const t = project();
  try {
    assert.equal(t.start('R', 'src/a.js').code, 0);
    assert.equal(t.start('R', 'src/a.js').code, 0);        // 전송 실패 후 같은 ID로 재시도
    t.sent('R');
    assert.equal(t.start('R', 'src/a.js').code, 1);
  } finally { t.cleanup(); }
});
