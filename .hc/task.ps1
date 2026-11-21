# Windows: [hc-task] 보내기·기다리기·보고 확인을 한 곳에서 처리한다. Claude(지시하는 쪽)가 쓴다. (macOS는 task.sh)
#   task.ps1 send  <대상> <작업ID> <지시문파일>   지시문 본문 파일에 머리줄과 '필수 마무리'를 붙여 보낸다
#   task.ps1 wait  <작업ID> [초]                  대상의 그 차례가 끝날 때까지 기다린 뒤 보고 파일을 확인한다 (기본 1800초)
#   task.ps1 nudge <작업ID>                       보고 없이 멈춘 대상에게 이어서 끝내고 보고하라고 다시 보낸다 (최대 2번)
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File .hc\task.ps1 <명령> ...
# wait 종료 코드: 0 보고 있음 / 2 보고 누락(차례는 끝남) / 3 시간 초과(아직 작업 중, 완료 아님)
#                 4 점검 필요(blocked·종료 등. 보고 파일이 있어도 대상이 blocked면 4) / 1 사용법·조회 오류
# send·nudge 종료 코드: 0 보냄(차례 시작 확인) / 5 미제출(Enter를 2번 더 눌러도 차례가 시작되지 않음) / 1 오류
# 보고 메시지(hc send)는 빠질 수 있으므로 완료 판단은 보고 파일(.hc\reports\<작업ID>.md)로 한다.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$A)

. (Join-Path $PSScriptRoot 'hc.ps1')
$Me = $Script:Me; $Root = $Script:Root
$Tasks = Join-Path $Root '.hc\tasks'
$Reports = Join-Path $Root '.hc\reports'
New-Item -ItemType Directory -Force -Path $Tasks, $Reports | Out-Null
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Test-Id([string]$Id) { if ($Id -notmatch '^[A-Za-z0-9._-]+$') { Fail "작업ID는 영문·숫자·._- 만 쓸 수 있습니다: $Id" } }

# 받는 쪽(Windows의 Codex·agy) 셸은 PowerShell이므로 보고 명령은 작은따옴표로 감싼다.
function Get-Footer([string]$Id) {
  $Rp = Join-Path $Reports "$Id.md"
  return @"

[필수 마무리 — 차례를 끝내기 전 마지막 두 행동]
1) 보고 본문을 $Rp 파일에 UTF-8로 쓴다. 첫 줄은 [hc-report] id=$Id status=done|failed|blocked
   이어서 요약 / 변경 파일 / 검증(실행한 명령과 결과, 미검증 항목 포함) / 남은 위험.
2) 셸에서 실행: hc send $Me '[hc-report] id=$Id status=<상태> 요약: <한 줄> 상세: .hc/reports/$Id.md'
- 단계가 여러 개면 모든 단계를 끝낸 뒤 한 번만 보고한다. 단계 사이에서 차례를 끝내지 않는다.
- 끝까지 못 하면(막힘·실패·범위 밖·질문) 그 시점까지의 결과로 status=blocked 또는 failed 보고를 한다.
- 보고 없이 차례를 끝내지 않는다. hc send 가 실패해도 1)의 파일은 반드시 남긴다.
"@
}

function Send-Msg([string]$Target, [string]$Text) {   # 보내고 turn 을 돌려준다
  $R = Invoke-Hc @('send', '--json', $Target, $Text)
  if ($R.Code -ne 0) { Fail "$Target 로 전송 실패: $($R.Err) $($R.Text)" }
  $Turn = Get-Field $R.Json 'turn'
  if ($null -eq $Turn) { return -1 } else { return [int]$Turn }
}

# P6: Codex 등은 hc send 의 붙여넣기 뒤 Enter를 놓칠 때가 있다(입력란에 본문만 남음).
# 보낸 뒤 상대가 차례를 시작했는지(working 또는 turn 증가) 확인하고, 아니면 hc keys 로 Enter를 다시 누른다.
function Confirm-Submitted([string]$Target, [int]$Before) {
  for ($Try = 0; $Try -le 2; $Try++) {
    $Until = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $Until) {
      $D = Get-Terminal $Target
      if ($null -eq $D) { return $false }
      $S = "$(Get-Field $D 'status.state')"
      $Cur = Get-Field $D 'turn'; $Cur = if ($null -eq $Cur) { 0 } else { [int]$Cur }
      if ($S -eq 'working' -or $Cur -gt $Before) { return $true }
      if ($S -and $S -notin 'idle', 'done') { return $true }   # blocked 등은 wait 가 점검 필요로 알린다
      Start-Sleep -Milliseconds 700
    }
    if ($Try -lt 2) {
      [Console]::Error.WriteLine("알림: $Target 이(가) 지시를 시작하지 않아 Enter를 다시 누릅니다 ($($Try + 1)/2)")
      $null = Invoke-Hc @('keys', $Target, 'enter')
    }
  }
  return $false
}

function Read-Env([string]$Id) {
  $F = Join-Path $Tasks "$Id.env"
  if (-not (Test-Path -LiteralPath $F)) { Fail "보낸 기록이 없습니다: $Id" }
  $H = @{}
  foreach ($L in Get-Content -LiteralPath $F) { $i = $L.IndexOf('='); if ($i -gt 0) { $H[$L.Substring(0, $i)] = $L.Substring($i + 1) } }
  return $H
}
function Write-Env([string]$Id, [string]$Target, [int]$Turn, [int]$Nudges) {
  [IO.File]::WriteAllText((Join-Path $Tasks "$Id.env"), "TARGET=$Target`nTURN=$Turn`nNUDGES=$Nudges`n", $Utf8)
}
function Test-Report([string]$Rp) { (Test-Path -LiteralPath $Rp) -and (Get-Item -LiteralPath $Rp).Length -gt 0 }

$Cmd = if ($A -and $A.Count -ge 1) { $A[0] } else { '' }
switch ($Cmd) {
  'send' {
    if ($A.Count -ne 4) { Fail '사용법: task.ps1 send <대상> <작업ID> <지시문파일>' }
    $T = $A[1]; $Id = $A[2]; $BodyFile = $A[3]
    Test-Id $Id
    if ((Test-Path -LiteralPath (Join-Path $Tasks "$Id.env")) -or (Test-Path -LiteralPath (Join-Path $Reports "$Id.md"))) { Fail "이미 쓴 작업ID입니다: $Id (새 작업ID를 쓰세요)" }
    if (-not (Test-Path -LiteralPath $BodyFile)) { Fail "지시문 파일이 없습니다: $BodyFile" }
    $Body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $BodyFile).ProviderPath, [Text.Encoding]::UTF8).TrimEnd()
    if (-not $Body) { Fail '지시문 본문이 비었습니다' }
    $S = Get-State $T
    if ($S -eq 'working') { Fail "$T 작업 중입니다. 먼저 끝나기를 기다리세요" }
    if ($S -ne 'idle' -and $S -ne 'done') { Fail "$T 상태=$S. hc read $T --lines 60 으로 화면을 확인하세요" }
    $Dlg = Find-Dialog $T; if ($Dlg) { Fail "$T 화면에 '$Dlg' 창이 떠 있습니다. 보내면 본문이 창에 입력됩니다. 사용자가 직접 고른 뒤 다시 보내세요" }
    # 브라우저 지시는 규칙 문서를 먼저 읽게 한다(AGENTS.md에는 요약만 있다).
    if ($Body -match '(?m)^\s*브라우저:\s*필요') { $Body = "[브라우저 검증] 시작 전에 $(Join-Path $Root '.hc\docs\browser-qa.md') 를 끝까지 읽고 그 규칙을 따른다.`n$Body" }
    $Msg = "[hc-task] id=$Id from=$Me`n$Body`n$(Get-Footer $Id)"
    [IO.File]::WriteAllText((Join-Path $Tasks "$Id.md"), $Msg, $Utf8)   # 원문 보관: 다시 보낼 때 상대가 다시 읽을 수 있게
    $Before = Get-Field (Get-Terminal $T) 'turn'; $Before = if ($null -eq $Before) { 0 } else { [int]$Before }
    $Turn = Send-Msg $T $Msg
    Write-Env $Id $T $Turn 0
    if (-not (Confirm-Submitted $T $Before)) {
      Write-Output "미제출: $T 에 본문은 보냈지만 차례가 시작되지 않았습니다. hc read $T --lines 40 으로 입력란을 확인하세요."
      exit 5
    }
    Write-Output "보냄: $T id=$Id (turn=$Turn). 기다리기: task.ps1 wait $Id"
    exit 0
  }
  'wait' {
    if ($A.Count -lt 2 -or $A.Count -gt 3) { Fail '사용법: task.ps1 wait <작업ID> [초]' }
    $Id = $A[1]; Test-Id $Id
    $Limit = if ($A.Count -eq 3) { [int]$A[2] } else { 1800 }
    $E = Read-Env $Id
    $T = $E['TARGET']; $Turn = if ($E['TURN']) { [int]$E['TURN'] } else { -1 }
    $Rp = Join-Path $Reports "$Id.md"
    $Deadline = (Get-Date).AddSeconds($Limit)
    while ($true) {
      if (Test-Report $Rp) {
        # 보고 파일이 먼저 생겨도 그 차례가 끝날 때까지는 기다린다(마무리 중일 수 있음).
        if ((Get-State $T) -ne 'working') { break }
      }
      $D = Get-Terminal $T
      if ($null -eq $D) { Write-Output "점검 필요: $T 조회 실패(종료됐을 수 있음). hc ls --all 로 확인하세요"; exit 4 }
      $S = "$(Get-Field $D 'status.state')"; if (-not $S) { $S = '-' }
      $Cur = Get-Field $D 'turn'; $Cur = if ($null -eq $Cur) { 0 } else { [int]$Cur }
      if ($S -ne 'working' -and $Cur -gt $Turn) { break }
      if ($S -notin 'working', 'idle', 'done') { Write-Output "점검 필요: $T 상태=$S (승인·신뢰 창일 수 있음). hc read $T --lines 60 으로 보고 사용자에게 알리세요"; exit 4 }
      $Left = [int][Math]::Floor(($Deadline - (Get-Date)).TotalSeconds)
      if ($Left -le 0) { Write-Output "시간 초과: $T 아직 끝나지 않았습니다(완료 아님). 다시 task.ps1 wait $Id"; exit 3 }
      if ($S -eq 'working') { $null = Invoke-Hc @('wait', $T, '--json', '--timeout', "$([Math]::Min($Left, 300))") }
      else { Start-Sleep -Seconds 2 }   # 아직 지시를 받기 전(차례가 넘어가기 전)
    }
    if (Test-Report $Rp) {
      Write-Output "보고 있음: $(Get-Content -LiteralPath $Rp -TotalCount 1 -Encoding UTF8)"
      Write-Output "파일: $Rp"
      # P8: 보고 파일을 쓴 뒤 보고 명령 승인 창 등에서 멈춘 경우를 구분한다.
      $S = Get-State $T
      if ($S -notin 'idle', 'done') {
        Write-Output "점검 필요: 보고 파일은 있지만 $T 상태=$S (보고 명령 승인 창일 수 있음). hc read $T --lines 40 으로 보고 사용자에게 알리세요"
        exit 4
      }
      exit 0
    }
    Write-Output "보고 누락: $T 의 차례가 끝났지만 $Rp 가 없습니다. 화면 마지막 부분:"
    $R = Invoke-Hc @('read', $T, '--lines', '40')
    @($R.Text -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 15) | ForEach-Object { Write-Output $_ }
    Write-Output "→ 화면에 결과만 남기고 멈춘 것입니다. task.ps1 nudge $Id 로 이어서 끝내고 보고하라고 보내세요."
    exit 2
  }
  'nudge' {
    if ($A.Count -ne 2) { Fail '사용법: task.ps1 nudge <작업ID>' }
    $Id = $A[1]; Test-Id $Id
    $E = Read-Env $Id
    $T = $E['TARGET']; $N = if ($E['NUDGES']) { [int]$E['NUDGES'] } else { 0 }
    $Rp = Join-Path $Reports "$Id.md"
    if (Test-Report $Rp) { Fail "이미 보고 파일이 있습니다: $Rp" }
    if ($N -ge 2) { Fail "이미 2번 다시 보냈습니다. 화면을 확인하고 사용자에게 알리세요 (hc read $T --lines 100)" }
    $S = Get-State $T
    if ($S -ne 'idle' -and $S -ne 'done') { Fail "$T 상태=$S. 다시 보낼 수 없습니다" }
    $Dlg = Find-Dialog $T; if ($Dlg) { Fail "$T 화면에 '$Dlg' 창이 떠 있습니다. 보내면 본문이 창에 입력됩니다. 사용자가 직접 고른 뒤 다시 보내세요" }
    $Orig = Join-Path $Tasks "$Id.md"
    $Msg = "[hc-task] id=$Id from=$Me (이어서)`n이 작업의 보고 파일이 아직 없다. 원래 지시 원문은 $Orig 에 있다. 그 지시의 남은 단계가 있으면 이어서 끝까지 하고, 이미 끝났으면 바로 보고한다.`n$(Get-Footer $Id)"
    $Before = Get-Field (Get-Terminal $T) 'turn'; $Before = if ($null -eq $Before) { 0 } else { [int]$Before }
    $Turn = Send-Msg $T $Msg
    Write-Env $Id $T $Turn ($N + 1)
    if (-not (Confirm-Submitted $T $Before)) { Write-Output "미제출: $T 에 다시 보냈지만 차례가 시작되지 않았습니다. hc read $T --lines 40 으로 확인하세요."; exit 5 }
    Write-Output "다시 보냄($($N + 1)/2): $T id=$Id. 기다리기: task.ps1 wait $Id"
    exit 0
  }
  default { Fail '사용법: task.ps1 send <대상> <작업ID> <지시문파일> | wait <작업ID> [초] | nudge <작업ID>' }
}
