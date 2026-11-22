import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

function fixture(state = 'idle') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-task-test-'));
  const dir = path.join(root, '.hc');
  fs.mkdirSync(path.join(dir, 'reports'), { recursive: true });
  fs.copyFileSync(new URL('./task.sh', import.meta.url), path.join(dir, 'task.sh'));
  fs.writeFileSync(path.join(dir, 'scope.mjs'), '');
  fs.writeFileSync(path.join(root, 'hc'), `#!/bin/bash
case "$1" in
  read) [ "$MOCK_READ_FAIL" = yes ] && exit 1; exit 0 ;;
  get)
    if [ "$MOCK_SEND_OK" = working ] && [ -s "$MOCK_CALLS" ]; then MOCK_STATE=working; fi
    printf '{"address":"t1","state":"live","status":{"state":"%s","app":"%s"},"turn":7}\\n' "$MOCK_STATE" "$MOCK_APP" ;;
  send)
    printf 'send %s\\n' "$2" >> "$MOCK_CALLS"
    [ -n "$MOCK_SEND_OK" ] || exit 1
    printf '{"turn":7}\\n'
    ;;

  keys) echo keys >> "$MOCK_CALLS" ;;
esac
`, { mode: 0o700 });
  const calls = path.join(root, 'calls');
  fs.writeFileSync(calls, '');
  function run(args, extra = {}) {
    return spawnSync('/bin/bash', [path.join(dir, 'task.sh'), ...args], {
      input: '담당 파일: 없음\n', encoding: 'utf8',
      env: { ...process.env, PATH: root + ':' + process.env.PATH, HC_TERMINAL_ID: 't2',
        MOCK_CALLS: calls, MOCK_STATE: state, ...extra },
    });
  }
  return { dir, calls: () => fs.readFileSync(calls, 'utf8'), run };
}

test('전송 실패 후 같은 작업 ID는 재전송되지 않는다', () => {
  const f = fixture();
  assert.equal(f.run(['send', 'alias', 'abc']).status, 1);
  assert.equal(f.run(['wait', 'abc', '0']).status, 4);
  assert.equal(f.run(['send', 'alias', 'abc']).status, 1);
  assert.equal(f.calls(), 'send t1\n');
});

test('화면 조회 실패 시 전송하지 않는다', () => {
  const f = fixture();
  assert.equal(f.run(['send', 'alias', 'abc'], { MOCK_READ_FAIL: 'yes' }).status, 1);
  assert.equal(f.calls(), '');
});

test('다른 작업 ID의 보고는 점검 필요로 처리한다', () => {
  const f = fixture();
  fs.mkdirSync(path.join(f.dir, 'tasks'));
  fs.writeFileSync(path.join(f.dir, 'tasks/abc.env'), 'TARGET=t1\nTURN=7\nNUDGES=0\n');
  fs.writeFileSync(path.join(f.dir, 'reports/abc.md'), '[hc-report] id=abcd status=done\n');
  assert.equal(f.run(['wait', 'abc', '0']).status, 4);
});

test('제출 확인이 지연되면 Enter를 보내지 않고 점검 상태를 남긴다', () => {
  const f = fixture();
  assert.equal(f.run(['send', 'alias', 'abc'], { MOCK_SEND_OK: 'yes' }).status, 5);
  assert.equal(f.run(['nudge', 'abc']).status, 1);
  assert.equal(f.calls(), 'send t1\n');
});

test('올바른 보고 파일은 알림 없이도 수신 처리한다', () => {
  const f = fixture();
  fs.mkdirSync(path.join(f.dir, 'tasks'));
  fs.writeFileSync(path.join(f.dir, 'tasks/abc.env'), 'TARGET=t1\nTURN=7\nNUDGES=0\n');
  fs.writeFileSync(path.join(f.dir, 'reports/abc.md'), '\uFEFF[hc-report] id=abc status=done\r\n');
  assert.equal(f.run(['wait', 'abc', '0']).status, 0);
  assert.equal(f.run(['nudge', 'abc']).status, 1);
  assert.equal(f.calls(), '');
});

test('실제 주소로 한 번 보내고 작업 시작이 확인되면 보낸 기록을 확정한다', () => {
  const f = fixture();
  assert.equal(f.run(['send', 'alias', 'abc'], { MOCK_SEND_OK: 'working' }).status, 0);
  assert.equal(f.calls(), 'send t1\n');
  assert.equal(fs.readFileSync(path.join(f.dir, 'tasks/abc.env'), 'utf8'),
    'TARGET=t1\nTURN=7\nNUDGES=0\n');
});

test('agy 로그는 실제 작업 입력이 있는 파일을 집계한다', () => {
  const f = fixture();
  fs.mkdirSync(path.join(f.dir, 'tasks'));
  fs.writeFileSync(path.join(f.dir, 'tasks/abc.env'), 'TARGET=t1\nTURN=7\nNUDGES=0\n');
  fs.writeFileSync(path.join(f.dir, 'reports/abc.md'), '[hc-report] id=abc status=done\n');
  const older = path.join(f.dir, 'cli-original.log');
  fs.writeFileSync(older, 'HandleUserInput [hc-task] id=abc from=t2\nMonitor agy_tool_safety FINISHED\n');
  fs.utimesSync(older, new Date(0), new Date(0));
  fs.writeFileSync(path.join(f.dir, 'cli-newer.log'), '출력에서 [hc-task] id=abc from=t2 인용\n');
  const result = f.run(['wait', 'abc', '0'], { AGY_LOG_DIR: f.dir, MOCK_APP: 'antigravity' });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /명령 1회.*cli-original\.log/);
});
