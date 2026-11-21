# Windows 공용 함수: up.ps1·task.ps1이 dot-source(. .hc\hc.ps1)로 읽는다. 직접 실행하지 않는다.
# Herdr 앱(herdr-core)의 hc 명령을 PowerShell에서 안전하게 부르고 JSON 결과를 읽는다.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Fail([string]$Message) {
  [Console]::Error.WriteLine("경고: $Message")
  exit 1
}

# Windows PowerShell 5.1(과 7.2 이하)은 외부 프로그램 인자 속 큰따옴표를 이스케이프하지 않는다.
# 그 경우에만 Windows 명령줄 규칙(\" 와 그 앞 \ 두 배)으로 직접 바꿔서 넘긴다.
$Script:LegacyArgs = $true
$PassingVar = Get-Variable -Name PSNativeCommandArgumentPassing -ValueOnly -ErrorAction SilentlyContinue
if ($null -ne $PassingVar -and "$PassingVar" -ne 'Legacy') { $Script:LegacyArgs = $false }

function Protect-Arg([string]$S) {
  if (-not $Script:LegacyArgs) { return $S }
  $S = [regex]::Replace($S, '(\\*)"', { param($M) ($M.Groups[1].Value * 2) + '\"' })
  if ($S -match '\s') { $S = [regex]::Replace($S, '(\\+)$', '$1$1') }
  return $S
}

# hc 실행: 종료 코드, 표준 출력, 오류 출력, 파싱된 JSON을 돌려준다.
function Invoke-Hc([string[]]$HArgs) {
  $Safe = @($HArgs | ForEach-Object { Protect-Arg $_ })
  $Prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $Raw = & hc @Safe 2>&1 } finally { $ErrorActionPreference = $Prev }
  $Code = $LASTEXITCODE
  $Out = @(); $Err = @()
  foreach ($L in @($Raw)) { if ($L -is [System.Management.Automation.ErrorRecord]) { $Err += "$L" } else { $Out += "$L" } }
  $Text = $Out -join "`n"
  $Json = $null
  if ($Text.Trim()) { try { $Json = $Text | ConvertFrom-Json } catch {} }
  [pscustomobject]@{ Code = $Code; Text = $Text; Err = ($Err -join "`n"); Json = $Json }
}

# 점으로 구분한 경로의 값. 없으면 $null.
function Get-Field($Obj, [string]$Path) {
  $Cur = $Obj
  foreach ($Part in $Path.Split('.')) {
    if ($null -eq $Cur -or $Cur -is [string] -or $Cur -is [System.ValueType]) { return $null }
    $Prop = $Cur.PSObject.Properties[$Part]
    if ($null -eq $Prop) { return $null }
    $Cur = $Prop.Value
  }
  return $Cur
}

function Get-Terminal([string]$Target) {
  $R = Invoke-Hc @('get', $Target, '--json')
  if ($R.Code -ne 0 -or $null -eq $R.Json) { return $null }
  return $R.Json
}

# 상태(.status.state). 조회 실패는 'gone', 값 없음은 '-'.
function Get-State([string]$Target) {
  $D = Get-Terminal $Target
  if ($null -eq $D) { return 'gone' }
  $S = Get-Field $D 'status.state'
  if ($S) { return "$S" } else { return '-' }
}

# 경로를 비교용으로 정규화한다(실제 경로, 끝의 \ 제거). 없으면 빈 문자열.
function Get-NormPath([string]$Path) {
  if (-not $Path) { return '' }
  try { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath.TrimEnd('\') } catch { return '' }
}

# 사람이 골라야 하는 창(권한·신뢰·명령 승인)이 현재 화면에 떠 있으면 그 문구를, 없으면 $null.
# Codex 첫 실행의 권한 선택 창은 떠 있어도 상태가 idle로 보이므로 상태만으로는 알 수 없다.
$Script:DialogPatterns = @('Update Model Permissions', 'Trust this folder', 'Do you trust the contents', 'Requesting permission for', 'Run this command\?')
function Find-Dialog([string]$Target) {
  $R = Invoke-Hc @('read', $Target)
  if ($R.Code -ne 0) { return $null }
  foreach ($Pat in $Script:DialogPatterns) { if ($R.Text -match $Pat) { return ($Pat -replace '\\', '') } }
  return $null
}

# 실행 파일 전체 경로. npm 전역 설치는 .cmd 이므로 .exe → .cmd → .bat 순으로 찾는다.
function Resolve-Program([string]$Name) {
  $All = @(Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue)
  foreach ($Ext in '.exe', '.cmd', '.bat') {
    foreach ($C in $All) { if ([IO.Path]::GetExtension($C.Source) -ieq $Ext) { return $C.Source } }
  }
  return $null
}

if (-not (Get-Command hc -ErrorAction SilentlyContinue)) { Fail '필요한 명령 없음: hc (Herdr 앱 설치 시 함께 설치되는 herdr-core)' }
if (-not $env:HC_TERMINAL_ID) { Fail 'Herdr 앱 밖에서 실행 중입니다 (HC_TERMINAL_ID 없음). Herdr 앱 안의 터미널에서 Claude를 실행하세요.' }
$Script:Me = $env:HC_TERMINAL_ID
$Script:Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath.TrimEnd('\')
