# kirothon-board Windows client (PowerShell 5.1+). 설정: ~\.kirothon-board.env
#   board.ps1 read | status|done|blocked|ask|human|note "내용" | gate | wait | idle | ip | doctor [프로젝트 폴더]
param([Parameter(Position=0)][string]$Cmd = "read", [Parameter(Position=1)][string]$A1 = "", [Parameter(Position=2)][string]$A2 = "")
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$envFile = Join-Path $HOME ".kirothon-board.env"
$cfg = @{}
if (Test-Path $envFile) { Get-Content $envFile -Encoding UTF8 | ForEach-Object { if ($_ -match '^(BOARD_[A-Z]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() } } }
foreach ($k in "BOARD_URL","BOARD_TOKEN","BOARD_LANE") { $v = [Environment]::GetEnvironmentVariable($k); if ($v) { $cfg[$k] = $v } }
foreach ($k in "BOARD_URL","BOARD_TOKEN","BOARD_LANE") { if (-not $cfg[$k]) { Write-Error "$k 없음 - setup.ps1 을 먼저 실행"; exit 1 } }
$URL = $cfg.BOARD_URL; $LANE = $cfg.BOARD_LANE
$H = @{ Authorization = "Bearer $($cfg.BOARD_TOKEN)" }

function Req([string]$method, [string]$path, $payload = $null) {
  # 본문은 UTF-8 바이트로 보내고, 응답도 바이트로 받아 UTF-8로 푼다 (PS 5.1 의 인코딩 추측을 피함)
  $r = [Net.HttpWebRequest]::Create($URL + $path)
  $r.Method = $method; $r.Timeout = 10000; $r.UserAgent = "kirothon-board-ps/1"
  $r.Headers.Add("Authorization", $H.Authorization)
  if ($null -ne $payload) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
    $r.ContentType = "application/json"; $r.ContentLength = $bytes.Length
    $s = $r.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
  }
  try { $resp = $r.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response; if ($null -eq $resp) { throw } }
  $code = [int]$resp.StatusCode
  $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
  $text = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
  return @{ code = $code; text = $text }
}
function Show($r) { Write-Output $r.text.TrimEnd(); if ($r.code -ge 400) { exit 1 } }
function Gate { $r = Req GET "/gate?lane=$LANE"; if ($r.code -ne 200) { return "err $($r.code) $($r.text.Trim())" }; return $r.text.Trim() }
function LastId { $r = Req GET "/events"; $e = $r.text | ConvertFrom-Json; if ($e -and $e.Count) { return $e[-1].id } else { return 0 } }

switch ($Cmd) {
  "read"  { Show (Req GET "/board?lane=$LANE") }
  "ip"    { Show (Req GET "/ip") }
  { $_ -in "status","done","blocked","ask","human","note" } {
    if (-not $A1) { Write-Error "내용 필요"; exit 1 }
    Show (Req POST "/post" @{ lane = $LANE; kind = $Cmd; text = $A1 })
  }
  "gate"  { $g = Gate; Write-Output $g; if (-not $g.StartsWith("go")) { exit 3 } }
  "wait"  {
    for ($i = 0; $i -lt 120; $i++) {
      try { $g = Gate } catch { $g = "hold (네트워크 오류)" }
      if ($g.StartsWith("go")) { Write-Output "go - 재개. board.ps1 read 로 지시 확인"; exit 0 }
      Start-Sleep -Seconds 15
    }
    Write-Output "30분째 정지: $g"; exit 3
  }
  "idle"  {
    $since = LastId
    for ($i = 0; $i -lt 40; $i++) {
      try {
        $evs = (Req GET "/events?since=$since").text | ConvertFrom-Json
        foreach ($e in $evs) { if (($e.kind -in "order","hold") -and ($e.to -in $LANE,"all")) {
          Write-Output "새 지시: #$($e.id) $($e.kind) ($($e.lane)): $($e.text)"; Write-Output "-> board.ps1 read 로 전체 확인 후 진행"; exit 0 } }
      } catch {}
      Start-Sleep -Seconds 15
    }
    Write-Output "10분간 새 지시 없음 - 사람에게 다음 할 일을 묻거나 idle 을 다시 실행"; exit 0
  }
  "doctor" {
    $bad = 0; $D = Join-Path $HOME ".kiro\skills\board"
    foreach ($f in "SKILL.md","board.ps1","gate_hook.ps1","auto_report.ps1") { if (-not (Test-Path (Join-Path $D $f))) { Write-Output "X 스킬 파일 없음: $D\$f -> setup.ps1 다시"; $bad = 1 } }
    if (-not $bad) { Write-Output "OK board 스킬 설치됨 ($D)" }
    Write-Output "OK 내 레인: $LANE"
    try { $r = Req GET "/gate?lane=$LANE"; $c = $r.code } catch { $c = 0 }
    switch ($c) { 200 { Write-Output "OK 상황판 연결 (토큰·IP 통과)" }
      403 { Write-Output "X IP 미등록 -> 이 IP를 팀장에게: $((Req GET '/ip').text.Trim())"; $bad = 1 }
      401 { Write-Output "X 토큰 틀림 -> setup.ps1 <레인> <토큰> 다시"; $bad = 1 }
      default { Write-Output "X 상황판 서버에 못 닿음 (HTTP $c)"; $bad = 1 } }
    $perm = Join-Path $HOME ".kiro\settings\permissions.yaml"
    if ((Test-Path $perm) -and (Select-String -Path $perm -Pattern "git commit" -Quiet)) { Write-Output "OK 오토모드 + 커밋/푸시 차단 (permissions.yaml)" } else { Write-Output "X permissions.yaml 에 커밋 차단 없음 -> setup.ps1 다시"; $bad = 1 }
    '{"command":"git commit -m x"}' | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $D "gate_hook.ps1") 2>$null | Out-Null
    if ($LASTEXITCODE -eq 2) { Write-Output "OK 훅 스크립트가 git commit 을 막음" } else { Write-Output "X 훅 스크립트 이상 (exit $LASTEXITCODE)"; $bad = 1 }
    if ($A1) {
      foreach ($p in ".kiro\hooks\board-gate.json",".kiro\steering\board.md") { if (Test-Path (Join-Path $A1 $p)) { Write-Output "OK 프로젝트: $p" } else { Write-Output "X 프로젝트에 $p 없음 -> setup.ps1 <레인> <토큰> $A1"; $bad = 1 } }
    } else { Write-Output "i  프로젝트 훅·steering 은 저장소 받은 뒤: board.ps1 doctor <프로젝트 폴더>" }
    if ($bad) { exit 1 } else { Write-Output "-> 전부 정상. Kiro에 '상황판 읽어' 를 쳐서 마지막 확인" }
  }
  default { Get-Content $PSCommandPath -Encoding UTF8 | Select-Object -Skip 1 -First 1; exit 1 }
}
