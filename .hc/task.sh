#!/usr/bin/env bash
# macOS: [hc-task] 보내기·기다리기·보고 확인을 한 곳에서 처리한다. Claude(지시하는 쪽)가 쓴다.
#   task.sh send  <대상> <작업ID>   표준입력의 지시문 본문에 머리줄과 '필수 마무리'를 붙여 보낸다
#   task.sh wait  <작업ID> [초]     대상의 그 차례가 끝날 때까지 기다린 뒤 보고 파일을 확인한다 (기본 1800초)
#   task.sh nudge <작업ID>          보고 없이 멈춘 대상에게 이어서 끝내고 보고하라고 다시 보낸다 (최대 2번)
# wait 종료 코드: 0 보고 있음 / 2 보고 누락(차례는 끝남) / 3 시간 초과(아직 작업 중, 완료 아님)
#                 4 점검 필요(blocked·종료 등. 보고 파일이 있어도 대상이 blocked면 4) / 1 사용법·조회 오류
# send·nudge 종료 코드: 0 보냄(차례 시작 확인) / 5 제출 여부 확인 필요 / 1 오류
#                      6 보내지 않음(담당 파일 범위 겹침, --fix-of 수정 한도 3회 초과 등)
#   task.sh send <대상> <작업ID> --fix-of <이전ID> < 본문   같은 문제의 수정 재지시. 계열별 최대 3회(scope.mjs)
#   task.sh check|verify|release|claim|status ...           범위 검사·verified 기록 (.hc/scope.mjs, lead.md 3절)
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
- 보고 없이 차례를 끝내지 않는다. 읽기 전용 지시에서도 2)는 실행한다. hc send 가 실패하면 1)의 파일은 그대로 두고 화면에 [hc-report] 전송 실패 라고 쓴다.
- 착수·진행 상황을 hc send 로 따로 알리지 않는다. 지시한 쪽에 보내는 메시지는 마지막 보고 한 번뿐이다.
EOF
}

state_of() { hc get "$1" | jq -r '.status.state // "-"'; }
turn_of() { hc get "$1" | jq -r '.turn // 0'; }

# 사람이 골라야 하는 창(권한·신뢰·명령 승인)이 현재 화면에 있으면 그 문구를 출력한다.
# Codex 첫 실행의 권한 선택 창은 떠 있어도 상태가 idle로 보이므로 상태만으로는 알 수 없다.
check_dialog() {
  local screen d
  screen=$(hc read "$1" 2>/dev/null) || die "$1 화면 조회 실패. 입력 전에 상태와 화면을 확인하세요"
  d=$(printf '%s\n' "$screen" | grep -o -E 'Update Model Permissions|Trust this folder|Do you trust the contents|Requesting permission for|Run this command\?' | head -1 || true)
  [ -z "$d" ] || die "$1 화면에 '$d' 창이 떠 있습니다. 사용자가 직접 고른 뒤 다시 보내세요"
}

confirm_submitted() {
  local t=$1 before=$2 end data s cur
  end=$((SECONDS+6))
  while [ "$SECONDS" -lt "$end" ]; do
    data=$(hc get "$t" 2>/dev/null) || return 1
    s=$(jq -r '.status.state // "-"' <<<"$data") || return 1
    cur=$(jq -r '.turn // 0' <<<"$data") || return 1
    case "$s" in working) return 0 ;; idle|done) ;; *) return 1 ;; esac
    [ "$cur" -le "$before" ] || return 0
    sleep 0.7
  done
  return 1
}

send_msg() { # 대상 메시지 → 전송 후 turn 출력
  local out
  out=$(hc send "$1" "$2") || die "$1 로 전송 실패"
  jq -r '.turn // empty' <<<"$out"
}

record_send() {
  local id=$1 t=$2 msg=$3 n=$4 f before turn tmp data
  f="$TASKS/$id.env"
  data=$(hc get "$t") || die "$t 조회 실패"
  before=$(jq -er --arg target "$t" '
    select(.address == $target and .state == "live" and
      (.status.state == "idle" or .status.state == "done"))
    | (.turn // 0)' <<<"$data") || die "$t 에 작업을 보낼 수 있는 상태가 아닙니다"
  check_dialog "$t"
  if [ "$n" -eq 0 ]; then
    (set -C; printf 'TARGET=%s\nTURN=%s\nNUDGES=%s\nPENDING=1\n' "$t" "$before" "$n" > "$f") ||
      die "이미 전송 기록이 있는 작업입니다: $id"
  else
    tmp=$(mktemp "$f.XXXXXX")
    printf 'TARGET=%s\nTURN=%s\nNUDGES=%s\nPENDING=1\n' "$t" "$before" "$n" > "$tmp"
    mv "$tmp" "$f"
  fi
  turn=$(send_msg "$t" "$msg") || die "전송 여부 미확인: $id. 화면과 보고 파일을 먼저 확인하세요"
  confirm_submitted "$t" "$before" || {
    echo "제출 여부 미확인: $id. hc read $t --lines 40 으로 화면을 확인하세요."
    exit 5
  }
  tmp=$(mktemp "$f.XXXXXX")
  printf 'TARGET=%s\nTURN=%s\nNUDGES=%s\n' "$t" "$turn" "$n" > "$tmp"
  mv "$tmp" "$f"
}

cmd_send() {
  local fixof=""
  if [ $# -eq 4 ] && [ "$3" = "--fix-of" ]; then fixof=$4; check_id "$fixof"
  elif [ $# -ne 2 ]; then die "사용법: task.sh send <대상> <작업ID> [--fix-of <이전작업ID>] < 지시문본문"; fi
  local t=$1 id=$2 body s msg head name data
  check_id "$id"
  [ ! -e "$TASKS/$id.env" ] && [ ! -e "$REPORTS/$id.md" ] || die "이미 쓴 작업ID입니다: $id (새 작업ID를 쓰세요)"
  body=$(cat)
  [ -n "$body" ] || die "지시문 본문이 비었습니다"
  data=$(hc get "$t") || die "$t 조회 실패"
  s=$(jq -er 'select(.state == "live") | .status.state' <<<"$data") || die "$t 실행 상태 확인 실패"
  t=$(jq -er '.address | select(type == "string" and length > 0)' <<<"$data") || die "터미널 주소 확인 실패"
  case "$s" in
    idle|done) ;;
    working) die "$t 작업 중입니다. 먼저 끝나기를 기다리세요" ;;
    *) die "$t 상태=$s. hc read $t --lines 60 으로 화면을 확인하세요" ;;
  esac
  check_dialog "$t"
  # 쓰기 범위 예약(겹침·수정 횟수 검사, 기준선 저장). 거부되면 보내지 않는다. 수정 재지시면 머리말을 붙인다.
  if command -v node >/dev/null; then
    printf '%s
' "$body" > "$TASKS/$id.body"
    if [ -n "$fixof" ]; then
      head=$(node "$ROOT/.hc/scope.mjs" start "$id" "$t" "$TASKS/$id.body" --fix-of "$fixof") || { s=$?; echo "보내지 않음(scope 거부, 코드 $s): 위 메시지를 확인하세요."; exit "$s"; }
    else
      head=$(node "$ROOT/.hc/scope.mjs" start "$id" "$t" "$TASKS/$id.body") || { s=$?; echo "보내지 않음(scope 거부, 코드 $s): 위 메시지를 확인하세요."; exit "$s"; }
    fi
    [ -z "$head" ] || body=$(printf '%s
%s' "$head" "$body")
  elif [ -n "$fixof" ]; then die "node 가 없어 --fix-of 수정 횟수 검사를 할 수 없습니다"
  else echo "경고: node 없음. 쓰기 범위 검사 미적용으로 보냅니다." >&2; fi
  # art 터미널은 Codex·agy 어느 쪽이든 이미지 전용 역할임을 알린다. 주소(tN)로 받아도 이름으로 판정한다.
  name=$(hc get "$t" 2>/dev/null | jq -r '.name // empty' || true)
  case "$t $name" in
    *-art|*-art" "*|*-art-*) body=$(printf '[역할] 너는 이번 작업에서 이미지 생성 전용 art 에이전트다. AGENTS.md 1절의 art 금지를 따르고 이미지 파일만 만든다.\n%s' "$body") ;;
  esac
  # 브라우저 지시는 규칙 문서를 먼저 읽게 한다(AGENTS.md에는 요약만 있다).
  if grep -q -E '^[[:space:]]*브라우저:[[:space:]]*필요' <<<"$body"; then
    body=$(printf '[브라우저 검증] 시작 전에 %s 를 끝까지 읽고 그 규칙을 따른다.\n%s' "$ROOT/.hc/docs/browser-qa.md" "$body")
  fi
  msg=$(printf '[hc-task] id=%s from=%s\n%s\n%s' "$id" "$ME" "$body" "$(footer "$id")")
  printf '%s\n' "$msg" > "$TASKS/$id.md"   # 원문 보관: 다시 보낼 때 상대가 다시 읽을 수 있게
  record_send "$id" "$t" "$msg" 0
  if [ -f "$TASKS/$id.scope.json" ]; then
    node "$ROOT/.hc/scope.mjs" sent "$id" || { s=$?; echo '전송은 시도됐으나 예약 확정에 실패했습니다. 중복 전송하지 말고 기록과 화면을 확인하세요.'; exit "$s"; }
  fi
  echo "보냄: $t id=$id. 기다리기: .hc/task.sh wait $id"
}

# agy 작업이면 agy 로그에서 그 작업 구간의 명령 실행·승인 창·샌드박스 밖 실행 횟수를 세어 보여 준다(종료 코드와 무관).
# Auto 모드는 샌드박스 밖 실행을 사람이 아니라 검토 에이전트가 승인할 수 있어서, 보고만으로는 우회 여부를 알 수 없다.
# 승인 창 없이 샌드박스 밖 실행 = 명령 판정 수 - 샌드박스 실행 수 - 사람 승인 창 수 (로그 기반 추정, agy 1.5.14 기준).
agy_log_summary() { # 작업ID 대상
  # 구간: 이 작업의 [hc-task] 머리줄(nudge 포함)이 들어온 입력부터, 다른 [hc-task] 머리줄 입력 전까지.
  # 머리줄이 아닌 입력(예: 사람이 직접 친 말)은 같은 작업의 이어짐으로 보고 구간을 닫지 않는다.
  local id=$1 t=$2 app dir log f key
  app=$(hc get "$t" 2>/dev/null | jq -r '.status.app // empty' 2>/dev/null) || return 0
  [ "$app" = antigravity ] || return 0
  dir=${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log}
  [ -d "$dir" ] || return 0
  key="[hc-task] id=$id from="
  log=
  for f in "$dir"/cli-*.log; do   # 경로에 공백이 있어도 파일 단위로 다룬다
    [ -f "$f" ] || continue
    awk -v key="$key" '/HandleUserInput/ && index($0, key) { found = 1; exit } END { exit !found }' "$f" 2>/dev/null || continue
    if [ -z "$log" ] || [ "$f" -nt "$log" ]; then log=$f; fi
  done
  if [ -z "$log" ]; then echo "agy 로그: $id 기록을 찾지 못했습니다 ($dir)"; return 0; fi
  awk -v key="$key" -v lf="$log" '
    /HandleUserInput/ && index($0, "[hc-task] id=") > 0 { inside = (index($0, key) > 0) }
    !inside { next }
    /Monitor agy_tool_safety FINISHED/ && !/reason="(allowed_tool|unsupported_tool)/ { cmd++ }
    /escapable binaries=/ { sb++ }
    /Surfacing tool confirmation/ { ask++ }
    END {
      out = cmd - sb - ask; if (out < 0) out = 0
      printf "agy 로그(추정): 명령 %d회, 샌드박스 안 %d회, 사람 승인 창 %d회, 승인 창 없이 샌드박스 밖 실행 %d회 — %s\n", cmd, sb, ask, out, lf
      if (out > 0) print "  ↳ 승인 창 없이 샌드박스 밖에서 실행된 명령은 Auto 검토 에이전트가 승인한 것입니다(사람이 승인한 실행은 승인 창 수에 따로 셉니다). 필요하면 로그의 BypassSandbox 줄을 확인하세요."
    }' "$log" || true
}

cmd_wait() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "사용법: task.sh wait <작업ID> [초]"
  local id=$1 limit=${2:-1800} f t turn deadline data s cur r
  check_id "$id"
  f="$TASKS/$id.env"
  [ -f "$f" ] || die "보낸 기록이 없습니다: $id"
  t=$(get_var TARGET "$f"); turn=$(get_var TURN "$f")
  if [ "$(get_var PENDING "$f")" = 1 ]; then
    echo "점검 필요: $id 제출 여부 미확인. $REPORTS/$id.md 및 hc read $t --lines 40 을 확인하세요"
    exit 4
  fi
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
    # blocked 검사를 차례 종료 판정보다 먼저 한다. 승인 창에서 멈춘 것을 '보고 누락'으로 오판하지 않게.
    case "$s" in
      working|idle|done) ;;
      *) echo "점검 필요: $t 상태=$s (승인·신뢰 창일 수 있음). hc read $t --lines 60 으로 보고 사용자에게 알리세요"; agy_log_summary "$id" "$t"; exit 4 ;;
    esac
    if [ "$s" != working ] && [ "$cur" -gt "$turn" ]; then break; fi
    r=$((deadline-SECONDS))
    [ "$r" -gt 0 ] || { echo "시간 초과: $t 아직 끝나지 않았습니다(완료 아님). 다시 .hc/task.sh wait $id"; exit 3; }
    if [ "$s" = working ]; then
      hc wait "$t" --timeout "$(( r < 300 ? r : 300 ))" >/dev/null 2>&1 || true
    else
      sleep 2   # 아직 지시를 받기 전(차례가 넘어가기 전)
    fi
  done
  if [ -s "$REPORTS/$id.md" ]; then
    local first report_id
    first=$(head -1 "$REPORTS/$id.md")
    first=${first#$'\xef\xbb\xbf'}
    report_id=$(printf '%s\n' "$first" | sed -nE 's/^\[hc-report\] id=([A-Za-z0-9._-]+) status=(done|failed|blocked)([[:space:]].*)?$/\1/p')
    if [ "$report_id" != "$id" ]; then
      echo "점검 필요: 보고 헤더 또는 작업 ID 불일치. 파일: $REPORTS/$id.md"
      exit 4
    fi
    echo "보고 있음: $first"
    echo "파일: $REPORTS/$id.md"
    agy_log_summary "$id" "$t"
    # 보고 파일을 쓴 뒤 보고 명령 승인 창 등에서 멈춘 경우를 구분한다.
    s=$(state_of "$t" 2>/dev/null || echo gone)
    case "$s" in
      idle|done) exit 0 ;;
      *) echo "점검 필요: 보고 파일은 있지만 $t 상태=$s (보고 명령 승인 창일 수 있음). hc read $t --lines 40 으로 보고 사용자에게 알리세요"; exit 4 ;;
    esac
  fi
  echo "보고 누락: $t 의 차례가 끝났지만 $REPORTS/$id.md 가 없습니다. 화면 마지막 부분:"
  hc read "$t" --lines 40 2>/dev/null | grep -v '^[[:space:]]*$' | tail -15 || true
  agy_log_summary "$id" "$t"
  echo "→ 화면에 결과만 남기고 멈춘 것입니다. .hc/task.sh nudge $id 로 이어서 끝내고 보고하라고 보내세요."
  exit 2
}

cmd_nudge() {
  [ $# -eq 1 ] || die "사용법: task.sh nudge <작업ID>"
  local id=$1 f t n s msg turn cur
  check_id "$id"
  f="$TASKS/$id.env"
  [ -f "$f" ] || die "보낸 기록이 없습니다: $id"
  [ ! -s "$REPORTS/$id.md" ] || die "이미 보고 파일이 있습니다: $REPORTS/$id.md"
  [ "$(get_var PENDING "$f")" != 1 ] || die "제출 여부 미확인: $id. 화면을 먼저 확인하세요"
  t=$(get_var TARGET "$f"); n=$(get_var NUDGES "$f")
  turn=$(get_var TURN "$f")
  cur=$(turn_of "$t") || die "$t 차례 조회 실패"
  [ "$cur" -gt "${turn:--1}" ] || die "이전 차례의 종료를 확인하지 못했습니다: $id"
  [ "${n:-0}" -lt 2 ] || die "이미 2번 다시 보냈습니다. 화면을 확인하고 사용자에게 알리세요 (hc read $t --lines 100)"
  s=$(state_of "$t") || die "$t 조회 실패"
  case "$s" in
    idle|done) ;;
    *) die "$t 상태=$s. 다시 보낼 수 없습니다" ;;
  esac
  check_dialog "$t"
  msg=$(printf '[hc-task] id=%s from=%s (이어서)\n이 작업의 보고 파일이 아직 없다. 원래 지시 원문은 %s 에 있다. 그 지시의 남은 단계가 있으면 이어서 끝까지 하고, 이미 끝났으면 바로 보고한다.\n%s' "$id" "$ME" "$TASKS/$id.md" "$(footer "$id")")
  record_send "$id" "$t" "$msg" "$(( ${n:-0} + 1 ))"
  echo "다시 보냄: $t id=$id. 기다리기: .hc/task.sh wait $id"
}

case "${1:-}" in
  send) shift; cmd_send "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  nudge) shift; cmd_nudge "$@" ;;
  check|verify|release|claim|status)
    # 범위 검사·검증 기록은 scope.mjs 하나가 맡는다(Windows task.ps1 과 같은 구현).
    command -v node >/dev/null || die "node 가 필요합니다"
    exec node "$ROOT/.hc/scope.mjs" "$@" ;;
  *) die "사용법: task.sh send <대상> <작업ID> [--fix-of <이전ID>] < 본문 | wait <작업ID> [초] | nudge <작업ID> | check|verify|release|claim|status ..." ;;
esac
