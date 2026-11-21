#!/usr/bin/env bash
# macOS: [hc-task] 보내기·기다리기·보고 확인을 한 곳에서 처리한다. Claude(지시하는 쪽)가 쓴다.
#   task.sh send  <대상> <작업ID>   표준입력의 지시문 본문에 머리줄과 '필수 마무리'를 붙여 보낸다
#   task.sh wait  <작업ID> [초]     대상의 그 차례가 끝날 때까지 기다린 뒤 보고 파일을 확인한다 (기본 1800초)
#   task.sh nudge <작업ID>          보고 없이 멈춘 대상에게 이어서 끝내고 보고하라고 다시 보낸다 (최대 2번)
# wait 종료 코드: 0 보고 있음 / 2 보고 누락(차례는 끝남) / 3 시간 초과(아직 작업 중, 완료 아님)
#                 4 점검 필요(blocked·종료 등) / 1 사용법·조회 오류
# 보고 메시지(hc send)는 빠질 수 있으므로 완료 판단은 보고 파일(.hc/reports/<작업ID>.md)로 한다.
set -euo pipefail

ROOT=$(cd -P "$(dirname "$0")/.." && pwd -P)
TASKS="$ROOT/.hc/tasks"
REPORTS="$ROOT/.hc/reports"

die() { echo "경고: $*" >&2; exit 1; }
check_id() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "작업ID는 영문·숫자·._- 만 쓸 수 있습니다: $1"; }
get_var() { sed -n "s/^$1=//p" "$2" | head -1; }

for CMD in hc jq; do command -v "$CMD" >/dev/null || die "필요한 명령 없음: $CMD"; done
: "${HC_TERMINAL_ID:?Herdr.app 밖에서 실행 중입니다 (HC_TERMINAL_ID 없음)}"
ME=$HC_TERMINAL_ID
mkdir -p "$TASKS" "$REPORTS"

footer() {
  cat <<EOF

[필수 마무리 — 차례를 끝내기 전 마지막 두 행동]
1) 보고 본문을 $REPORTS/$1.md 파일에 쓴다. 첫 줄은 [hc-report] id=$1 status=done|failed|blocked
   이어서 요약 / 변경 파일 / 검증(실행한 명령과 결과, 미검증 항목 포함) / 남은 위험.
2) 셸에서 실행: hc send $ME "[hc-report] id=$1 status=<상태> 요약: <한 줄> 상세: .hc/reports/$1.md"
- 단계가 여러 개면 모든 단계를 끝낸 뒤 한 번만 보고한다. 단계 사이에서 차례를 끝내지 않는다.
- 끝까지 못 하면(막힘·실패·범위 밖·질문) 그 시점까지의 결과로 status=blocked 또는 failed 보고를 한다.
- 보고 없이 차례를 끝내지 않는다. hc send 가 실패해도 1)의 파일은 반드시 남긴다.
EOF
}

state_of() { hc get "$1" | jq -r '.status.state // "-"'; }

send_msg() { # 대상 메시지 → 전송 후 turn 출력
  local out
  out=$(hc send "$1" "$2") || die "$1 로 전송 실패"
  jq -r '.turn // empty' <<<"$out"
}

cmd_send() {
  [ $# -eq 2 ] || die "사용법: task.sh send <대상> <작업ID> < 지시문본문"
  local t=$1 id=$2 body s turn msg
  check_id "$id"
  [ ! -e "$TASKS/$id.env" ] && [ ! -e "$REPORTS/$id.md" ] || die "이미 쓴 작업ID입니다: $id (새 작업ID를 쓰세요)"
  body=$(cat)
  [ -n "$body" ] || die "지시문 본문이 비었습니다"
  s=$(state_of "$t") || die "$t 조회 실패"
  case "$s" in
    idle|done) ;;
    working) die "$t 작업 중입니다. 먼저 끝나기를 기다리세요" ;;
    *) die "$t 상태=$s. hc read $t --lines 60 으로 화면을 확인하세요" ;;
  esac
  msg=$(printf '[hc-task] id=%s from=%s\n%s\n%s' "$id" "$ME" "$body" "$(footer "$id")")
  printf '%s\n' "$msg" > "$TASKS/$id.md"   # 원문 보관: 다시 보낼 때 상대가 다시 읽을 수 있게
  turn=$(send_msg "$t" "$msg")
  printf 'TARGET=%s\nTURN=%s\nNUDGES=0\n' "$t" "$turn" > "$TASKS/$id.env"
  echo "보냄: $t id=$id (turn=$turn). 기다리기: .hc/task.sh wait $id"
}

cmd_wait() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "사용법: task.sh wait <작업ID> [초]"
  local id=$1 limit=${2:-1800} f t turn deadline data s cur r
  check_id "$id"
  f="$TASKS/$id.env"
  [ -f "$f" ] || die "보낸 기록이 없습니다: $id"
  t=$(get_var TARGET "$f"); turn=$(get_var TURN "$f")
  [ -n "$turn" ] || turn=-1
  deadline=$((SECONDS+limit))
  while :; do
    if [ -s "$REPORTS/$id.md" ]; then
      # 보고 파일이 먼저 생겨도 그 차례가 끝날 때까지는 기다린다(마무리 중일 수 있음).
      s=$(state_of "$t" 2>/dev/null || echo gone)
      [ "$s" = working ] || break
    fi
    data=$(hc get "$t" 2>/dev/null) || { echo "점검 필요: $t 조회 실패(종료됐을 수 있음). hc ls --all 로 확인하세요"; exit 4; }
    s=$(jq -r '.status.state // "-"' <<<"$data")
    cur=$(jq -r '.turn // 0' <<<"$data")
    if [ "$s" != working ] && [ "$cur" -gt "$turn" ]; then break; fi
    case "$s" in
      working|idle|done) ;;
      *) echo "점검 필요: $t 상태=$s (승인·신뢰 창일 수 있음). hc read $t --lines 60 으로 보고 사용자에게 알리세요"; exit 4 ;;
    esac
    r=$((deadline-SECONDS))
    [ "$r" -gt 0 ] || { echo "시간 초과: $t 아직 끝나지 않았습니다(완료 아님). 다시 .hc/task.sh wait $id"; exit 3; }
    if [ "$s" = working ]; then
      hc wait "$t" --timeout "$(( r < 300 ? r : 300 ))" >/dev/null 2>&1 || true
    else
      sleep 2   # 아직 지시를 받기 전(차례가 넘어가기 전)
    fi
  done
  if [ -s "$REPORTS/$id.md" ]; then
    echo "보고 있음: $(head -1 "$REPORTS/$id.md")"
    echo "파일: $REPORTS/$id.md"
    exit 0
  fi
  echo "보고 누락: $t 의 차례가 끝났지만 $REPORTS/$id.md 가 없습니다. 화면 마지막 부분:"
  hc read "$t" --lines 40 2>/dev/null | grep -v '^[[:space:]]*$' | tail -15 || true
  echo "→ 화면에 결과만 남기고 멈춘 것입니다. .hc/task.sh nudge $id 로 이어서 끝내고 보고하라고 보내세요."
  exit 2
}

cmd_nudge() {
  [ $# -eq 1 ] || die "사용법: task.sh nudge <작업ID>"
  local id=$1 f t n s turn msg
  check_id "$id"
  f="$TASKS/$id.env"
  [ -f "$f" ] || die "보낸 기록이 없습니다: $id"
  [ ! -s "$REPORTS/$id.md" ] || die "이미 보고 파일이 있습니다: $REPORTS/$id.md"
  t=$(get_var TARGET "$f"); n=$(get_var NUDGES "$f")
  [ "${n:-0}" -lt 2 ] || die "이미 2번 다시 보냈습니다. 화면을 확인하고 사용자에게 알리세요 (hc read $t --lines 100)"
  s=$(state_of "$t") || die "$t 조회 실패"
  case "$s" in
    idle|done) ;;
    *) die "$t 상태=$s. 다시 보낼 수 없습니다" ;;
  esac
  msg=$(printf '[hc-task] id=%s from=%s (이어서)\n이 작업의 보고 파일이 아직 없다. 원래 지시 원문은 %s 에 있다. 그 지시의 남은 단계가 있으면 이어서 끝까지 하고, 이미 끝났으면 바로 보고한다.\n%s' "$id" "$ME" "$TASKS/$id.md" "$(footer "$id")")
  turn=$(send_msg "$t" "$msg")
  printf 'TARGET=%s\nTURN=%s\nNUDGES=%s\n' "$t" "$turn" "$(( ${n:-0} + 1 ))" > "$f"
  echo "다시 보냄($(( ${n:-0} + 1 ))/2): $t id=$id. 기다리기: .hc/task.sh wait $id"
}

case "${1:-}" in
  send) shift; cmd_send "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  nudge) shift; cmd_nudge "$@" ;;
  *) die "사용법: task.sh send <대상> <작업ID> < 본문 | wait <작업ID> [초] | nudge <작업ID>" ;;
esac
