# Kiro AgentStop 훅 (Windows): 새 커밋이 있으면 상황판에 자동 보고. 실패는 조용히 무시.
$ErrorActionPreference = "SilentlyContinue"
try { [Console]::In.ReadToEnd() | Out-Null } catch {}
$gd = (git rev-parse --git-dir 2>$null); if (-not $gd) { exit 0 }
$head = (git rev-parse --short HEAD 2>$null); if (-not $head) { exit 0 }
$mark = Join-Path $gd ".board_last_reported"
$last = ""; if (Test-Path $mark) { $last = (Get-Content $mark -Raw).Trim() }
if ($last -eq $head) { exit 0 }
$n = 1; if ($last) { $c = (git rev-list --count "$last..HEAD" 2>$null); if ($c) { $n = $c } }
$subj = (git log -1 --pretty=%s); if ($subj.Length -gt 120) { $subj = $subj.Substring(0,120) }
$stat = ((git diff --stat HEAD~1 2>$null) | Select-Object -Last 1); if ($stat) { $stat = $stat.Trim() }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "board.ps1") status "auto: 커밋 ${n}개, 최신 $head $subj [$stat]" | Out-Null
if ($LASTEXITCODE -eq 0) { Set-Content -Path $mark -Value $head -NoNewline }
exit 0
