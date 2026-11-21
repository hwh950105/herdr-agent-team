# Windows용: Codex·agy 하위 터미널을 띄운다. Herdr 앱 안의 Claude 터미널에서 실행한다. (macOS는 up.sh)
# 사용법: powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1 [--prefix | --art codex|agy]
# --art: 이미지 생성 전용 <접두사>-art 를 그 에이전트로 함께 띄우거나 검사한다(필요할 때만).
# 이름: <접두사>-codex, <접두사>-agy. 기존 자식은 작업 폴더·역할·상태를 확인한다. 규칙은 up.sh와 같다.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

# 프로젝트 접두사 18자(up.sh와 같은 규칙). 남는 게 없으면 project
$RootForPrefix = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath.TrimEnd('\')
$P = (Split-Path -Leaf $RootForPrefix).ToLowerInvariant() -replace '[^a-z0-9_-]', '-' -replace '-+', '-'
$P = $P.Trim('-')
if ($P.Length -gt 18) { $P = $P.Substring(0, 18) }
if ($P -eq '') { $P = 'project' }
if ($Rest -and $Rest.Count -eq 1 -and $Rest[0] -eq '--prefix') { Write-Output $P; exit 0 }

. (Join-Path $PSScriptRoot 'hc.ps1')
$Art = ''
if ($Rest -and $Rest.Count -gt 0) {
  if ($Rest.Count -eq 2 -and $Rest[0] -eq '--art' -and $Rest[1] -in 'codex', 'agy') { $Art = $Rest[1] }
  else { Fail '사용법: up.ps1 [--prefix | --art codex|agy]' }
}
# 슬롯: 이름 접미사(Role)와 에이전트 종류(Kind)
$Slots = @([pscustomobject]@{ Role = 'codex'; Kind = 'codex' }, [pscustomobject]@{ Role = 'agy'; Kind = 'agy' })
if ($Art) { $Slots += [pscustomobject]@{ Role = 'art'; Kind = $Art } }

$Codex = Resolve-Program 'codex'; if (-not $Codex) { Fail '필요한 명령 없음: codex' }
$Agy = Resolve-Program 'agy'; if (-not $Agy) { Fail '필요한 명령 없음: agy' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine('경고: node 없음. 브라우저 QA(Playwright) 전에 설치하세요.') }
$Me = $Script:Me; $Root = $Script:Root
New-Item -ItemType Directory -Force -Path (Join-Path $Root '.hc\reports') | Out-Null

# 로컬 승인 값만 읽는다. 다른 줄은 실행·적용하지 않는다.
$CodexMode = 'sandbox'
$LocalEnv = Join-Path $Root '.hc\local.env'
if (Test-Path -LiteralPath $LocalEnv) {
  $Seen = 0
  foreach ($Line in Get-Content -LiteralPath $LocalEnv) {
    $Line = $Line.TrimEnd("`r")
    if ($Line.StartsWith('CODEX_MODE=')) {
      if ($Seen) { Fail '.hc\local.env의 CODEX_MODE 중복' }
      $Seen = 1
      $CodexMode = $Line.Substring('CODEX_MODE='.Length)
    }
  }
}
if ($CodexMode -ne 'sandbox' -and $CodexMode -ne 'bypass') { Fail '.hc\local.env의 CODEX_MODE는 sandbox 또는 bypass여야 합니다.' }

$R = Invoke-Hc @('ls', '--json')
if ($R.Code -ne 0 -or $null -eq $R.Json) { Fail "hc ls 조회 실패: $($R.Err)" }
$Terminals = @(Get-Field $R.Json 'terminals')

$Label = @()
$Where = Get-Field (Get-Terminal $Me) 'labels.where'
if ($Where) { $Label = @('--label', "where=$Where") }

# 충돌 회피 접미사가 붙은 이름도 다음 실행에서 재사용한다.
function Find-Mine([string]$Name) {
  $Stem = "$Name-$Me"
  @($Terminals | Where-Object {
      $N = "$(Get-Field $_ 'name')"
      "$(Get-Field $_ 'parent')" -eq $Me -and ($N -eq $Name -or $N -eq $Stem -or $N -match ('^' + [regex]::Escape($Stem) + '-[0-9]+$'))
    } | ForEach-Object { "$(Get-Field $_ 'address')" })
}
function Select-Name([string]$Base) {
  $Taken = @($Terminals | ForEach-Object { "$(Get-Field $_ 'name')" })
  $Name = $Base; $Index = 2
  if ($Taken -contains $Name) {
    $Name = "$Base-$Me"
    while ($Taken -contains $Name) { $Name = "$Base-$Me-$Index"; $Index++ }
  }
  if ($Name.Length -gt 32) { Fail "터미널 이름이 32자를 초과함: $Name" }
  return $Name
}

function Test-Terminal([string]$Target, [string]$Role, [string]$Reason) {
  $D = Get-Terminal $Target
  if ($null -eq $D) { [Console]::Error.WriteLine("경고: $Target 조회 실패 ($Reason)"); return $false }
  $State = "$(Get-Field $D 'state')"
  $Status = "$(Get-Field $D 'status.state')"; if (-not $Status) { $Status = '-' }
  $App = "$(Get-Field $D 'status.app')"
  $Fg = "$(Get-Field $D 'foreground.name')"
  $CwdRaw = "$(Get-Field $D 'foreground.cwd')"
  if (-not $CwdRaw -and $Reason -ne '재사용') { $CwdRaw = "$(Get-Field $D 'cwd')" }
  $Cwd = Get-NormPath $CwdRaw
  $Summary = "state=$State cwd=$CwdRaw app=$App fg=$Fg status=$Status"
  $Hint = if ($Status -eq '-') { ' 신뢰·권한 창일 수 있음.' } else { '' }
  # agy는 status.app이 antigravity다. 앱 감지가 늦으면 foreground 이름(codex.exe 등)으로 본다.
  $Want = if ($Role -eq 'agy') { 'antigravity' } else { 'codex' }
  # Windows의 npm 설치 Codex는 node.exe로 보이므로 argv에 codex 패키지·스크립트가 있는지도 본다.
  $Argv = (@(Get-Field $D 'foreground.argv') | ForEach-Object { "$_" }) -join ' '
  $FgRole = ($Fg -replace '\.(exe|cmd)$', '') -ieq $Role
  if ($Role -eq 'codex' -and $Argv -match '@openai[\\/]codex|[\\/]codex(\.js|\.exe)?(\s|$)') { $FgRole = $true }
  $RoleOk = ($App -eq $Want) -or (-not $App -and $FgRole)
  if ($State -ne 'live' -or -not $Cwd -or $Cwd -ine $Root -or -not $RoleOk) {
    [Console]::Error.WriteLine("경고: $Target 재사용·준비 조건 불일치 ($Reason; $Summary).$Hint hc read $Target --lines 60 으로 확인하세요.")
    return $false
  }
  switch ($Status) {
    { $_ -in 'idle', 'done' } {
      $Dlg = Find-Dialog $Target
      if ($Dlg) {
        [Console]::Error.WriteLine("경고: $Target 화면에 '$Dlg' 창이 떠 있습니다 ($Reason). 상태는 $Status 지만 입력하면 창에 들어갑니다. 사용자가 그 터미널에서 직접 고른 뒤 다시 실행하세요.")
        return $false
      }
      return $true
    }
    'working' {
      if ($Reason -eq '재사용') { [Console]::Error.WriteLine("$Target 사용 중 ($Reason)"); return $true }
      [Console]::Error.WriteLine("경고: $Target 신규 기동 준비 미완료 ($Reason; $Summary). hc read $Target --lines 60 으로 확인하세요.")
      return $false
    }
    default {
      [Console]::Error.WriteLine("경고: $Target 점검 필요 ($Reason; $Summary).$Hint hc read $Target --lines 60 으로 확인하세요.")
      return $false
    }
  }
}

# 기존 자식에 문제가 있으면 어느 역할도 새로 띄우지 않는다.
$Existing = @{}
foreach ($Slot in $Slots) {
  $Role = $Slot.Role
  $T = @(Find-Mine "$P-$Role")
  if ($T.Count -gt 1) { Fail "$Role 하위 터미널이 여러 개입니다 ($($T -join ' ')). 하나만 남기고 다시 실행하세요." }
  if ($T.Count -eq 1) {
    if (-not (Test-Terminal $T[0] $Slot.Kind '재사용')) {
      if ($Role -eq 'art') { [Console]::Error.WriteLine("참고: $($T[0]) 가 다른 에이전트로 떠 있으면, 자기가 띄운 터미널이므로 hc kill $($T[0]) 후 다시 실행하세요.") }
      exit 1
    }
  }
  $Existing[$Role] = if ($T.Count -eq 1) { $T[0] } else { '' }
}

$Started = @()
function Start-Child([string]$Role, [string]$Kind, [string[]]$Argv) {
  $N = Select-Name "$P-$Role"
  $Run = Invoke-Hc (@('run', '--bg', '--json', '--name', $N, '--cwd', $Root) + $Label + @('--') + $Argv)
  if ($Run.Code -ne 0) { Fail "$Role 기동 실패: $($Run.Err) $($Run.Text). 이번 실행에서 이미 띄운 터미널: $(if ($Script:Started) { $Script:Started.Name -join ' ' } else { '없음' })" }
  $Script:Started += [pscustomobject]@{ Name = $N; Role = $Kind }
}

# 기본은 샌드박스. .hc\local.env 값이 bypass일 때만 우회한다. --no-daemon은 hc 터미널 안에서 Codex를 유지하기 위해 필요하다.
# 샌드박스에서도 보고(hc send)가 되도록 herdr-core 소켓이 있는 폴더를 쓰기 허용에 넣는다(소켓이 파일 경로일 때).
function Get-CodexArgv {
  $A = @($Codex, '--no-daemon')
  if ($CodexMode -eq 'bypass') {
    $A += '--dangerously-bypass-approvals-and-sandbox'
  } else {
    $A += @('-s', 'workspace-write', '-a', 'never', '-c', 'sandbox_workspace_write.network_access=true')
    $Sock = "$env:HC_TERMINAL_SOCKET"
    if ($Sock -and -not $Sock.StartsWith('\\.\pipe\')) {
      $SockDir = Split-Path -Parent $Sock
      if ($SockDir -and (Test-Path -LiteralPath $SockDir -PathType Container)) { $A += @('--add-dir', $SockDir) }
    }
  }
  return ,$A
}
# agy 허용 목록: 사용자 설정 폴더(%APPDATA%\hc-agents)의 파일이 있으면 그것을, 없으면 공개 기본값(좁은 목록)을 쓴다.
# 넓힌 목록은 에이전트가 쓸 수 없는 프로젝트 밖에만 둔다. 프로젝트 안 파일은 샌드박스 에이전트도 고칠 수 있다.
function Get-AgyArgv {
  $Settings = Join-Path $Root '.hc\agy-settings.win.json'
  $UserFile = Join-Path $env:APPDATA 'hc-agents\agy-settings.win.json'
  if ($env:APPDATA -and (Test-Path -LiteralPath $UserFile)) {
    $Text = [IO.File]::ReadAllText($UserFile)
    if ($Text -match 'command\(\*\)|regex:\.\*\)') {
      [Console]::Error.WriteLine("경고: $UserFile 에 전체 허용 항목(command(*) 등)이 있어 쓰지 않습니다. 기본 목록으로 띄웁니다.")
    } else {
      $Settings = $UserFile
      [Console]::Error.WriteLine("참고: agy 허용 목록으로 사용자 설정 $UserFile 를 씁니다.")
    }
  }
  return ,@($Agy, '--settings', $Settings)
}

foreach ($Slot in $Slots) {
  if ($Existing[$Slot.Role]) { continue }
  $Argv = if ($Slot.Kind -eq 'codex') { Get-CodexArgv } else { Get-AgyArgv }
  Start-Child $Slot.Role $Slot.Kind $Argv
}

# 메시지에 의한 조기 반환은 역할별 총 60초 안에서 다시 기다린다.
$FailAny = $false
foreach ($S in $Started) {
  $Deadline = (Get-Date).AddSeconds(60)
  $Reason = 'timeout'
  while ($true) {
    $Left = [int][Math]::Floor(($Deadline - (Get-Date)).TotalSeconds)
    if ($Left -le 0) { break }
    $W = Invoke-Hc @('wait', $S.Name, '--json', '--timeout', "$Left")
    if ($W.Code -ne 0) { [Console]::Error.WriteLine("경고: $($S.Name) 대기 명령 실패: $($W.Err)"); $Reason = 'wait_failed'; $FailAny = $true; break }
    $Reason = "$(Get-Field $W.Json 'reason')"
    if (-not $Reason) { [Console]::Error.WriteLine("경고: $($S.Name) 대기 결과에 reason 없음"); $Reason = 'invalid_wait_result'; $FailAny = $true; break }
    if ($Reason -ne 'message') { break }
    $Reason = 'timeout'
  }
  if (-not (Test-Terminal $S.Name $S.Role $Reason)) { $FailAny = $true }
}

$R = Invoke-Hc @('ls', '--json')
foreach ($T in @(Get-Field $R.Json 'terminals')) {
  if ("$(Get-Field $T 'parent')" -eq $Me) {
    $St = Get-Field $T 'status'; if ($St -isnot [string]) { $St = Get-Field $St 'state' }; if (-not $St) { $St = '-' }
    Write-Output "$(Get-Field $T 'address') $(Get-Field $T 'name') $(Get-Field $T 'agent') $St"
  }
}
if ($FailAny) { exit 1 } else { exit 0 }
