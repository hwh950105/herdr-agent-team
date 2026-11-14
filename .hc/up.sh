#!/usr/bin/env bash
# Codex·pi 하위 터미널을 띄운다. Herdr.app 안의 Claude 터미널에서 실행한다.
# 이름: <접두사>-codex, <접두사>-pi. 기존 자식은 작업 폴더·역할·상태를 확인한다.
# 전제: hc run 은 자식 터미널에 그 터미널 자신의 HC_TERMINAL_ID/HC_TERMINAL_SOCKET 을 넣어 준다.
#       (Codex 안에서 `echo $HC_TERMINAL_ID` 가 Codex 자기 주소인지로 확인할 수 있다)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# 프로젝트 접두사 18자, 전체 이름은 hc 제한(32자) 내. 남는 게 없으면 project
P=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9_-' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c1-18)
[ -n "$P" ] || P=project
if [ "${1:-}" = --prefix ] && [ "$#" -eq 1 ]; then
  printf '%s\n' "$P"
  exit 0
fi
[ "$#" -eq 0 ] || { echo "사용법: $0 [--prefix]" >&2; exit 1; }

for CMD in hc jq codex pi; do
  command -v "$CMD" >/dev/null || { echo "경고: 필요한 명령 없음: $CMD" >&2; exit 1; }
done
: "${HC_TERMINAL_ID:?Herdr.app 밖에서 실행 중입니다 (HC_TERMINAL_ID 없음)}"
ME=$HC_TERMINAL_ID
mkdir -p "$ROOT/.hc/reports"

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
  local target=$1 role=$2 reason=$3 data summary status
  data=$(hc get "$target") || { echo "경고: $target 조회 실패 ($reason)" >&2; return 1; }
  # hc get은 agent 대신 status.app을 제공한다(pi의 프로세스 이름은 node).
  summary=$(jq -r '"state=\(.state // "-") cwd=\(.foreground.cwd // "-") agent=\(.status.app // .agent // .foreground.name // "-") status=\(.status.state // "-")"' <<<"$data") || return 1
  if ! jq -e --arg root "$ROOT" --arg role "$role" '
    .state=="live" and .foreground.cwd==$root and
    (.status.app // .agent // .foreground.name)==$role' <<<"$data" >/dev/null; then
    echo "경고: $target 재사용·준비 조건 불일치 ($reason; $summary). hc read $target 으로 확인하세요." >&2
    return 1
  fi
  # Codex는 shell_environment_policy 로 받은 HC_TERMINAL_ID 가 자기 주소여야 보고가 제자리로 간다.
  # -c 바로 뒤의 값 중 이 키를 가진 설정만 본다. 하나 이상 있어야 하고 모두 자기 주소여야 한다.
  if [ "$role" = codex ] && ! jq -e --arg k 'shell_environment_policy.set.HC_TERMINAL_ID=' '
      .address as $a | (.foreground.argv // []) as $v
      | [range(0; ($v|length)-1) | select($v[.] == "-c") | $v[.+1] | select(startswith($k))] as $s
      | ($s|length) > 0 and all($s[]; . == ($k + "\"" + $a + "\""))' <<<"$data" >/dev/null; then
    echo "경고: $target 의 HC_TERMINAL_ID 주입값이 자기 주소와 다름 ($reason). Codex 보고가 엉뚱한 곳으로 갈 수 있습니다." >&2
    return 1
  fi
  status=$(jq -r '.status.state // "-"' <<<"$data") || return 1
  case "$status" in
    idle|done) ;;
    working) echo "$target 사용 중 ($reason)" >&2 ;;
    *) echo "경고: $target 점검 필요 ($reason; $summary). hc read $target 으로 확인하세요." >&2; return 1 ;;
  esac
}

# 기존 자식에 문제가 있으면 어느 역할도 새로 띄우지 않는다.
# mine 오류는 '없음'으로 보지 않고, 같은 역할 자식이 여럿이면 어느 것을 쓸지 모르므로 멈춘다.
EXISTING_codex= EXISTING_pi=
for ROLE in codex pi; do
  T=$(mine "$P-$ROLE") || { echo "경고: $ROLE 기존 터미널 조회 실패" >&2; exit 1; }
  if [ "$(printf '%s' "$T" | grep -c .)" -gt 1 ]; then
    echo "경고: $ROLE 하위 터미널이 여러 개입니다 ($(echo $T)). 하나만 남기고 다시 실행하세요." >&2
    exit 1
  fi
  if [ -n "$T" ]; then check_terminal "$T" "$ROLE" 재사용 || exit 1; fi
  printf -v "EXISTING_$ROLE" '%s' "$T"
done

STARTED=()
STARTED_ROLES=()

# Codex: 사용자 지시로 권한 우회 모드(승인 창 없음, 샌드박스 없음)로 띄운다.
#  --no-daemon        : hc 매뉴얼 필수 사항(없으면 명령이 hc 밖에서 실행됨)
#  --dangerously-bypass-approvals-and-sandbox : 승인·샌드박스 해제(사용자 승인 사항)
if [ -z "$EXISTING_codex" ]; then
  N=$(pick_name "$P-codex")
  hc run --bg --name "$N" --cwd "$ROOT" ${LABEL[@]+"${LABEL[@]}"} -- sh -c '
    exec codex --no-daemon --dangerously-bypass-approvals-and-sandbox \
      -c "shell_environment_policy.set.HC_TERMINAL_ID=\"$HC_TERMINAL_ID\"" \
      -c "shell_environment_policy.set.HC_TERMINAL_SOCKET=\"$HC_TERMINAL_SOCKET\""' >/dev/null
  STARTED+=("$N")
  STARTED_ROLES+=(codex)
fi

if [ -z "$EXISTING_pi" ]; then
  N=$(pick_name "$P-pi")
  hc run --bg --name "$N" --cwd "$ROOT" ${LABEL[@]+"${LABEL[@]}"} -- pi >/dev/null
  STARTED+=("$N")
  STARTED_ROLES+=(pi)
fi

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
