#!/usr/bin/env bash
# macOS용: Codex·agy 하위 터미널을 띄운다. Herdr.app 안의 Claude 터미널에서 실행한다. (Windows는 up.ps1)
# 이름: <접두사>-codex, <접두사>-agy. 기존 자식은 작업 폴더·역할·상태를 확인한다.
# --art codex|agy: 이미지 생성 전용 <접두사>-art 를 그 에이전트로 함께 띄우거나 검사한다(필요할 때만).
# 전제: hc run 은 자식 터미널에 그 터미널 자신의 HC_TERMINAL_ID/HC_TERMINAL_SOCKET 을 넣어 준다.
#       (Codex 안에서 `echo $HC_TERMINAL_ID` 가 Codex 자기 주소인지로 확인할 수 있다)
set -euo pipefail

ROOT=$(cd -P "$(dirname "$0")/.." && pwd -P)

# 프로젝트 접두사 18자, 전체 이름은 hc 제한(32자) 내. 남는 게 없으면 project
P=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9_-' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c1-18)
[ -n "$P" ] || P=project
if [ "${1:-}" = --prefix ] && [ "$#" -eq 1 ]; then
  printf '%s\n' "$P"
  exit 0
fi
ART=
case "$#:${1:-}" in
  0:) ;;
  2:--art)
    case "$2" in codex|agy) ART=$2 ;; *) echo "사용법: $0 [--prefix | --art codex|agy]" >&2; exit 1 ;; esac ;;
  *) echo "사용법: $0 [--prefix | --art codex|agy]" >&2; exit 1 ;;
esac
# 슬롯 = 이름 접미사:에이전트 종류
SLOTS="codex:codex agy:agy"
[ -z "$ART" ] || SLOTS="$SLOTS art:$ART"

for CMD in hc jq codex agy; do
  command -v "$CMD" >/dev/null || { echo "경고: 필요한 명령 없음: $CMD" >&2; exit 1; }
done
command -v ego-browser >/dev/null || echo "경고: ego-browser 없음. 브라우저 QA 전에 설치하세요." >&2
: "${HC_TERMINAL_ID:?Herdr.app 밖에서 실행 중입니다 (HC_TERMINAL_ID 없음)}"
: "${HC_TERMINAL_SOCKET:?HC_TERMINAL_SOCKET 없음: Herdr.app 실행 환경을 확인하세요}"
ME=$HC_TERMINAL_ID
mkdir -p "$ROOT/.hc/reports"

# 로컬 승인 값만 읽는다. 셸 코드나 다른 환경 변수는 실행·적용하지 않는다.
CODEX_MODE=sandbox
MODE_SEEN=0
if [ -f "$ROOT/.hc/local.env" ]; then
  while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE=${LINE%$'\r'}
    case "$LINE" in
      CODEX_MODE=*)
        [ "$MODE_SEEN" -eq 0 ] || { echo "경고: .hc/local.env의 CODEX_MODE 중복" >&2; exit 1; }
        MODE_SEEN=1
        CODEX_MODE=${LINE#CODEX_MODE=}
        ;;
    esac
  done < "$ROOT/.hc/local.env"
fi
case "$CODEX_MODE" in
  sandbox|bypass) ;;
  *) echo "경고: .hc/local.env의 CODEX_MODE는 sandbox 또는 bypass여야 합니다." >&2; exit 1 ;;
esac

TERMINALS=$(hc ls) || { echo "경고: hc ls 조회 실패" >&2; exit 1; }
jq -e '.terminals | type == "array"' <<<"$TERMINALS" >/dev/null || { echo "경고: hc ls 결과 형식 이상" >&2; exit 1; }

WHERE=$(hc get "$ME" | jq -r '.labels.where // empty')
LABEL=()
[ -n "$WHERE" ] && LABEL=(--label "where=$WHERE")

# 충돌 회피 접미사가 붙은 이름도 다음 실행에서 재사용한다.
mine() { jq -r --arg me "$ME" --arg n "$1" --arg stem "$1-$ME" '
  [.terminals[] | select(.parent==$me) | select(.name==$n or .name==$stem or
    ((.name // "") | startswith($stem+"-") and (ltrimstr($stem+"-") | test("^[0-9]+$"))))]
  | .[].address' <<<"$TERMINALS"; }
pick_name() {
  local name=$1 index=2
  if jq -e --arg n "$name" 'any(.terminals[]; .name==$n)' <<<"$TERMINALS" >/dev/null; then
    name="$1-$ME"
    while jq -e --arg n "$name" 'any(.terminals[]; .name==$n)' <<<"$TERMINALS" >/dev/null; do
      name="$1-$ME-$index"
      index=$((index+1))
    done
  fi
  [ "${#name}" -le 32 ] || { echo "경고: 터미널 이름이 32자를 초과함: $name" >&2; return 1; }
  printf '%s\n' "$name"
}

check_terminal() {
  local target=$1 role=$2 reason=$3 data summary status cwd hint key expected dialog
  data=$(hc get "$target") || { echo "경고: $target 조회 실패 ($reason)" >&2; return 1; }
  # agy는 foreground.name이 agy여도 status.app은 antigravity다.
  summary=$(jq -r '"state=\(.state // "-") cwd=\(.foreground.cwd // "-") agent=\(.status.app // .agent // .foreground.name // "-") status=\(.status.state // "-")"' <<<"$data") || return 1
  status=$(jq -r '.status.state // "-"' <<<"$data") || return 1
  hint=
  [ "$status" != - ] || hint=" 신뢰·권한 창일 수 있음."
  cwd=$(jq -r '.foreground.cwd // empty' <<<"$data") || return 1
  if [ -z "$cwd" ] && [ "$reason" != 재사용 ]; then
    cwd=$(jq -r '.cwd // empty' <<<"$data") || return 1
  fi
  if [ -n "$cwd" ]; then cwd=$(cd -P "$cwd" 2>/dev/null && pwd -P) || cwd=; fi
  if ! jq -e --arg root "$ROOT" --arg cwd "$cwd" --arg role "$role" '
    .state=="live" and $cwd==$root and
    (if $role=="agy" then .status.app=="antigravity"
     else (.status.app // .agent // .foreground.name)==$role end)' <<<"$data" >/dev/null; then
    echo "경고: $target 재사용·준비 조건 불일치 ($reason; $summary).$hint hc read $target 으로 확인하세요." >&2
    return 1
  fi
  # 각 -c 주입값이 하나 이상 있고, 같은 키의 모든 값이 현재 통신 대상과 같아야 한다.
  if [ "$role" = codex ]; then
    for key in HC_TERMINAL_ID HC_TERMINAL_SOCKET; do
      expected=$HC_TERMINAL_SOCKET
      if [ "$key" = HC_TERMINAL_ID ]; then expected=$(jq -r '.address' <<<"$data") || return 1; fi
      if ! jq -e --arg k "shell_environment_policy.set.$key=" --arg expected "$expected" '
          (.foreground.argv // []) as $v
          | [range(0; ($v|length)-1) | select($v[.] == "-c") | $v[.+1] | select(startswith($k))] as $s
          | ($s|length) > 0 and all($s[]; . == ($k + "\"" + $expected + "\""))' <<<"$data" >/dev/null; then
        echo "경고: $target 의 $key 주입값 불일치 ($reason). Codex 보고가 엉뚱한 곳으로 갈 수 있습니다." >&2
        return 1
      fi
    done
  fi
  case "$status" in
    idle|done)
      # Codex 첫 실행의 권한 선택 창은 떠 있어도 idle로 보인다. 현재 화면에 사람이 골라야 하는 창이 있으면 멈춘다.
      dialog=$(hc read "$target" 2>/dev/null | grep -o -E 'Update Model Permissions|Trust this folder|Do you trust the contents|Requesting permission for|Run this command\?' | head -1 || true)
      if [ -n "$dialog" ]; then
        echo "경고: $target 화면에 '$dialog' 창이 떠 있습니다 ($reason). 사용자가 그 터미널에서 직접 고른 뒤 다시 실행하세요." >&2
        return 1
      fi
      ;;
    working)
      if [ "$reason" = 재사용 ]; then
        echo "$target 사용 중 ($reason)" >&2
      else
        echo "경고: $target 신규 기동 준비 미완료 ($reason; $summary). hc read $target 으로 확인하세요." >&2
        return 1
      fi
      ;;
    *) echo "경고: $target 점검 필요 ($reason; $summary).$hint hc read $target 으로 확인하세요." >&2; return 1 ;;
  esac
}

# 기존 자식에 문제가 있으면 어느 역할도 새로 띄우지 않는다.
# mine 오류는 '없음'으로 보지 않고, 같은 역할 자식이 여럿이면 어느 것을 쓸지 모르므로 멈춘다.
EXISTING_codex= EXISTING_agy= EXISTING_art=
for SLOT in $SLOTS; do
  ROLE=${SLOT%%:*} KIND=${SLOT#*:}
  T=$(mine "$P-$ROLE") || { echo "경고: $ROLE 기존 터미널 조회 실패" >&2; exit 1; }
  if [ "$(printf '%s' "$T" | grep -c .)" -gt 1 ]; then
    echo "경고: $ROLE 하위 터미널이 여러 개입니다 ($(echo $T)). 하나만 남기고 다시 실행하세요." >&2
    exit 1
  fi
  if [ -n "$T" ]; then
    if ! check_terminal "$T" "$KIND" 재사용; then
      [ "$ROLE" != art ] || echo "참고: $T 가 다른 에이전트로 떠 있으면, 자기가 띄운 터미널이므로 hc kill $T 후 다시 실행하세요." >&2
      exit 1
    fi
  fi
  printf -v "EXISTING_$ROLE" '%s' "$T"
done

STARTED=()
STARTED_ROLES=()
start_failed() {
  echo "경고: $1 기동 실패. 이번 실행에서 이미 띄운 터미널: ${STARTED[*]:-없음}" >&2
  exit 1
}

# 기본은 샌드박스. 이 프로젝트에서 승인한 .hc/local.env 값이 bypass일 때만 우회한다.
# --no-daemon은 hc 터미널 안에서 Codex를 유지하기 위해 필요하다.
start_codex() { # 이름
  hc run --bg --name "$1" --cwd "$ROOT" ${LABEL[@]+"${LABEL[@]}"} -- sh -c '
    if [ "$1" = bypass ]; then
      set -- --dangerously-bypass-approvals-and-sandbox
    else
      set -- -s workspace-write -a never \
        -c "sandbox_workspace_write.network_access=true" \
        -c "sandbox_workspace_write.writable_roots=[\"$HOME/.local/state/herdr-core\"]"
    fi
    exec codex --no-daemon "$@" \
      -c "shell_environment_policy.set.HC_TERMINAL_ID=\"$HC_TERMINAL_ID\"" \
      -c "shell_environment_policy.set.HC_TERMINAL_SOCKET=\"$HC_TERMINAL_SOCKET\""' sh "$CODEX_MODE" >/dev/null
}
# agy 허용 목록: 사용자 설정 폴더의 파일이 있으면 그것을, 없으면 공개 기본값(좁은 목록)을 쓴다.
# 넓힌 목록은 에이전트가 쓸 수 없는 프로젝트 밖(사용자 설정 폴더)에만 둔다. 프로젝트 안 파일은 샌드박스 에이전트도 고칠 수 있다.
AGY_SETTINGS="$ROOT/.hc/agy-settings.mac.json"
AGY_USER="${XDG_CONFIG_HOME:-$HOME/.config}/hc-agents/agy-settings.mac.json"
if [ -f "$AGY_USER" ]; then
  if grep -q -E 'command\(\*\)|regex:\.\*\)' "$AGY_USER"; then
    echo "경고: $AGY_USER 에 전체 허용 항목(command(*) 등)이 있어 쓰지 않습니다. 기본 목록으로 띄웁니다." >&2
  else
    AGY_SETTINGS=$AGY_USER
    echo "참고: agy 허용 목록으로 사용자 설정 $AGY_USER 를 씁니다." >&2
  fi
fi
start_agy() { # 이름
  hc run --bg --name "$1" --cwd "$ROOT" ${LABEL[@]+"${LABEL[@]}"} -- agy --settings "$AGY_SETTINGS" >/dev/null
}

for SLOT in $SLOTS; do
  ROLE=${SLOT%%:*} KIND=${SLOT#*:}
  E="EXISTING_$ROLE"
  [ -z "${!E}" ] || continue
  N=$(pick_name "$P-$ROLE") || start_failed "$ROLE"
  "start_$KIND" "$N" || start_failed "$ROLE"
  STARTED+=("$N")
  STARTED_ROLES+=("$KIND")
done

# 메시지에 의한 조기 반환은 역할별 총 60초 안에서 다시 기다린다.
FAIL=0
I=0
for N in ${STARTED[@]+"${STARTED[@]}"}; do
  DEADLINE=$((SECONDS+60))
  REASON=timeout
  while :; do
    REMAINING=$((DEADLINE-SECONDS))
    [ "$REMAINING" -gt 0 ] || break
    if ! RESULT=$(hc wait "$N" --timeout "$REMAINING"); then
      echo "경고: $N 대기 명령 실패" >&2
      REASON=wait_failed
      FAIL=1
      break
    fi
    if ! REASON=$(jq -er '.reason | select(type == "string")' <<<"$RESULT"); then
      echo "경고: $N 대기 결과에 reason 없음" >&2
      REASON=invalid_wait_result
      FAIL=1
      break
    fi
    [ "$REASON" = message ] || break
    REASON=timeout
  done
  check_terminal "$N" "${STARTED_ROLES[$I]}" "$REASON" || FAIL=1
  I=$((I+1))
done

hc ls | jq -r --arg me "$ME" \
  '.terminals[] | select(.parent==$me) | "\(.address) \(.name) \(.agent) \(.status // "-")"'
exit $FAIL
