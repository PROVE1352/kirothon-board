# Kiro PreToolUse 훅 (Windows). 0=통과, 2=차단. gate_hook.sh 와 같은 규칙.
$ErrorActionPreference = "SilentlyContinue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$raw = [Console]::In.ReadToEnd()
$cmds = New-Object System.Collections.ArrayList
function Walk($o) {
  if ($null -eq $o) { return }
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    foreach ($p in $o.PSObject.Properties) {
      $k = $p.Name.ToLower()
      if (($p.Value -is [string]) -and ($k -in "command","cmd","script","bash","shell")) { [void]$cmds.Add($p.Value) }
      elseif (($p.Value -is [array]) -and ($k -in "args","argv","command")) { [void]$cmds.Add(($p.Value -join " ")) }
      else { Walk $p.Value }
    }
  } elseif ($o -is [array]) { foreach ($v in $o) { Walk $v } }
}
$parsed = $null
try { $parsed = $raw | ConvertFrom-Json -ErrorAction Stop } catch {}
if ($null -ne $parsed) { Walk $parsed; $text = ($cmds -join "`n") } else { $text = $raw }
$probe = ($text -split "`n" | Where-Object { $_ -notmatch 'git\s+stash\s+push' }) -join "`n"
if ($probe -match '(^|[^\w./-])(git(\s+-\S+(\s+[^-\s]\S*)?)*\s+(commit|push)|gh\s+pr\s+(create|merge))([^\w-]|$)') {
  [Console]::Error.WriteLine("커밋·푸시는 사람이 직접 한다. 실행하지 말고 (1)스테이징할 파일 목록 (2)커밋 메시지에 적을 내용(무엇을·왜·영향 레인)만 채팅에 제안하라. 사람이 커밋하면 다음 작업으로 간다.")
  exit 2
}
if ($raw -match 'board\.(ps1|sh)' -or $raw -match 'adviser') { exit 0 }
$cache = Join-Path $env:TEMP ".board_gate"
$g = $null
if ((Test-Path $cache) -and (((Get-Date) - (Get-Item $cache).LastWriteTime).TotalSeconds -lt 20)) { $g = Get-Content $cache -Raw -Encoding UTF8 }
else {
  $g = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "board.ps1") gate 2>$null | Out-String).Trim()
  if (-not $g -or $g.StartsWith("err")) { exit 0 }   # fail-open
  Set-Content -Path $cache -Value $g -Encoding UTF8
}
if ($g -and $g.Trim().StartsWith("hold")) {
  [Console]::Error.WriteLine("상황판 정지 중: $($g.Trim()) - 쓰기·실행을 멈추고 board.ps1 wait 를 실행해 풀릴 때까지 기다려라.")
  exit 2
}
exit 0
