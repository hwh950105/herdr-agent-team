# Herdr Agent Team: Herdr 멀티 에이전트 셋팅

[English](README.md) | **한국어**

[Herdr](https://herdr.dev) 앱 안에서 **Claude Code가 오케스트레이터**가 되어 **Codex**(구현·검증)와 **pi**(보조: 검색·lint·test 실행)를 하위 터미널로 띄우고, `hc` 명령으로 작업을 주고받는 공동 작업 폴더 템플릿입니다. 프로젝트 이름에 의존하지 않으므로 새 프로젝트에 파일을 그대로 복사해 씁니다.

```
사용자 ──▶ Claude (오케스트레이터)
             ├─ hc send ─▶ Codex (<접두사>-codex)   구현·테스트·디버깅
             └─ hc send ─▶ pi    (<접두사>-pi)      읽기·검색·검증 실행
                 ◀─ [hc-report] ─┘
```

## 파일 구성

| 파일 | 내용 |
|---|---|
| `AGENTS.md` | 세 에이전트 공통 규칙. 역할, `hc` 통신 프로토콜(지시·보고 형식), 파일 소유, 안전 규칙 |
| `CLAUDE.md` | Claude Code 전용 메모. `@AGENTS.md`를 불러온다 |
| `.hc/up.sh` | Codex·pi 하위 터미널을 띄우거나, 이미 떠 있는 것을 검사하는 스크립트 |
| `.hc/reports/` | 에이전트 보고서 폴더(git 제외) |

## 1. 필요한 프로그램 설치

macOS(Apple silicon) 기준입니다.

### Herdr 앱과 herdr-core(`hc`)

```bash
# Herdr 앱 (설치 중 herdr-core도 없으면 같이 설치된다)
curl -fsSL https://releases.herdr.dev/app/install.sh | sh
# 또는 https://releases.herdr.dev/app/Herdr.dmg 를 받아 Applications 로 옮긴다

# herdr-core 만 따로 설치·업데이트할 때
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
hc update
```

설치 확인:

```bash
hc --version          # 예: hc 0.1.20
hc --help             # 명령 목록 (맨 `hc` 는 터미널 선택 화면이 뜨므로 실행하지 않는다)
```

> 옛 CLI용 `herdr agent ...` / `herdr pane ...` 명령은 앱에 보이지 않는 다른 서버로 가므로 쓰지 않습니다. 항상 `hc`를 씁니다.

### 에이전트 CLI와 도구

```bash
brew install jq                                   # up.sh 가 사용
npm i -g @anthropic-ai/claude-code                # Claude Code
npm i -g @openai/codex@latest                     # Codex CLI
npm i -g @earendil-works/pi-coding-agent          # pi
```

각 CLI에 처음 한 번 로그인합니다(`claude`, `codex`, `pi`를 각각 실행).

> npm 설치가 `EACCES` 또는 "cache folder contains root-owned files" 오류로 실패하면 `sudo chown -R "$(id -u):$(id -g)" ~/.npm` 로 캐시 권한을 고칩니다.

## 2. 테마(레이아웃) 설치: bercail

화면 구성에는 Herdr 커뮤니티 레이아웃 **bercail**(작성자 simoncrypta)을 씁니다. 왼쪽 사이드바에 스페이스와 에이전트 목록이 있고, 가운데에 에이전트 터미널 데스크가 있는 구성입니다. 이 저장소에는 bercail 파일이 들어 있지 않으며, 원작자가 공유한 것을 Herdr 안에서 설치합니다.

1. Herdr 앱을 연다.
2. 브라우저에서 <https://herdr.dev/layouts> 를 열고 **bercail**을 찾는다.
3. 항목의 복사 버튼으로 설치 문장을 복사해, Herdr 안의 에이전트(예: Claude Code)에게 붙여 넣는다. 에이전트가 `~/.config/herdr-app/layouts/bercail.json`과 필요한 mod(`mods/bercail-agents/`, `mods/bercail-desk/`)를 추가한다. 기존 레이아웃은 그대로 남는다.
4. 레이아웃 전환: `ctrl-shift-l` 로 bercail을 고른다.
5. 다크 모드로 쓰려면 `~/.config/herdr-app/settings.json`에 `"appearance": "dark"`를 넣는다.

되돌리기: `ctrl-shift-l`로 원래 레이아웃을 고른다. 화면이 깨지면 `ctrl-alt-shift-escape`로 기본 레이아웃과 키 설정으로 복구한다. 레이아웃과 mod를 직접 고치는 방법은 Herdr가 만드는 `~/.config/herdr-app/AGENTS.md`에 있다.

## 3. 사용법

1. 이 저장소를 복사하거나 clone 한 폴더에서, **Herdr 앱 안의 터미널**로 Claude Code를 실행한다.

   ```bash
   echo $HC_TERMINAL_ID   # t2c 처럼 주소가 나와야 한다. 비어 있으면 Herdr 밖이다
   claude
   ```

2. Claude에게 일을 시키면, Claude가 필요할 때 `.hc/up.sh`를 실행해 하위 터미널을 띄운다.
   - 이름은 `<폴더명 정규화>-codex`, `<폴더명 정규화>-pi` (접두사는 `.hc/up.sh --prefix`로 확인)
   - 이미 떠 있으면 새로 띄우지 않고 폴더·역할·상태만 검사한다. 이상하면 경고하고 `exit 1`로 끝난다.
   - `up.sh`는 Claude만 실행한다. Codex·pi가 실행하면 하위 터미널이 중복으로 생긴다.
3. "Codex에게 시켜", "pi한테 검증시켜"처럼 말하면, Claude가 `AGENTS.md`의 `[hc-task]` 형식으로 지시하고 `[hc-report]` 보고를 받아 결과를 확인한 뒤 요약해 준다.

상태 확인:

```bash
hc ls | jq -r --arg me "$HC_TERMINAL_ID" \
  '.terminals[] | select(.parent==$me) | "\(.address) \(.name) \(.agent) \(.status // "-")"'
```

## ⚠️ Codex 권한 우회 모드에 대해

`.hc/up.sh`는 Codex를 `--dangerously-bypass-approvals-and-sandbox`(승인 창 없음, 샌드박스 없음)로 띄운다. 원작자의 환경에서 명시적으로 승인한 설정이다. **쓰기 전에 자기 환경에 맞는지 판단하라.**

- 이 모드에서는 Codex가 아무 파일이나 수정하고 아무 명령이나 실행할 수 있다. `AGENTS.md`의 담당 파일·삭제 금지 같은 규칙은 **에이전트가 지키는 약속일 뿐 도구가 막아 주지 않는다**.
- 격리되지 않은 내 컴퓨터에서 쓰기 싫다면 `.hc/up.sh`의 Codex 실행 줄을 샌드박스 모드로 바꾼다:

  ```sh
  exec codex --no-daemon -s workspace-write -a never \
    -c "sandbox_workspace_write.network_access=true" \
    -c "sandbox_workspace_write.writable_roots=[\"$HOME/.local/state/herdr-core\"]" \
    -c "shell_environment_policy.set.HC_TERMINAL_ID=\"$HC_TERMINAL_ID\"" \
    -c "shell_environment_policy.set.HC_TERMINAL_SOCKET=\"$HC_TERMINAL_SOCKET\""
  ```

  샌드박스 모드에서는 `.agents/`, `.codex/`, `.git/`이 읽기 전용이므로 공유 파일은 `.hc/`에 둔다. `up.sh`의 Codex 주소 검사는 그대로 동작한다.

## 내 환경에 맞게 고쳐 쓰기

이 저장소는 원작자 한 사람의 작업 방식에 맞춘 **출발점**입니다. 그대로 쓰기보다 자기 환경에 맞게 고쳐 쓰세요.

- **역할 분담:** `AGENTS.md` 1절의 표에서 에이전트별 역할·전문 분야·pi 금지 범위를 바꾼다. 에이전트를 빼거나(예: pi 없이) 더할 수 있다.
- **에이전트 종류와 실행 옵션:** `.hc/up.sh`의 `codex`/`pi` 실행 줄과 `command -v` 검사 목록, 역할 이름을 바꾼다. 다른 CLI 에이전트를 쓰려면 실행 줄을 추가하고 `check_terminal`의 역할 판정(`status.app`)을 맞춘다.
- **권한 수준:** 위 경고 절을 참고해 Codex를 샌드박스 모드로 돌리거나, 반대로 격리된 환경에서만 우회 모드를 쓴다. `AGENTS.md` 4절의 승인 기록은 **자기 환경의 결정으로 바꿔 적는다**.
- **언어:** `AGENTS.md`와 `CLAUDE.md`는 "모든 응답은 한국어"로 되어 있다. 다른 언어로 쓰려면 그 줄을 바꾼다.
- **보고 형식·폴더:** `[hc-task]`/`[hc-report]` 필드, 보고서 경로(`.hc/reports/`)는 팀 규칙에 맞게 바꿔도 된다. 바꿀 때는 `AGENTS.md`(공통 규칙) 한 곳만 고친다.
- **테마:** bercail 대신 Herdr 기본 레이아웃이나 herdr.dev의 다른 레이아웃을 써도 협업 기능에는 영향이 없다.

## 검증 범위

`.hc/up.sh`는 가짜 `hc`로 모의 검사를 했다(재사용, 폴더·역할·상태 불일치, 중복 터미널, Codex 주소 주입 불일치, `hc ls` 형식 오류, 신규 기동, 대기 중 메시지 조기 반환·시간 초과 등). 실제 동시 기동 경쟁, 부모 종료 시 하위 터미널 정리, 메시지 종단 전달은 실제 환경에서 따로 검증하지 않았다.
