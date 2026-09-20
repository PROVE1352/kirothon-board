# 윈도우 팀원용 1회 설치:  powershell -ExecutionPolicy Bypass -File .\setup.ps1 <레인> <팀토큰> [프로젝트 폴더]
param([Parameter(Mandatory=$true)][string]$Lane, [Parameter(Mandatory=$true)][string]$Token, [string]$Project = "")
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$URL = "https://board.193-123-163-215.sslip.io"
$DIR = Split-Path -Parent $PSCommandPath
$D = Join-Path $HOME ".kiro\skills\board"
New-Item -ItemType Directory -Force -Path $D | Out-Null
Copy-Item (Join-Path $DIR "skill\board\*.ps1") $D -Force
# SKILL.md 의 명령을 윈도우용으로 바꿔 설치
$call = 'powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\.kiro\skills\board\board.ps1'
$skill = Get-Content (Join-Path $DIR "skill\board\SKILL.md") -Raw -Encoding UTF8
$skill = $skill.Replace('~/.kiro/skills/board/board.sh', $call).Replace('board.sh', 'board.ps1')
[IO.File]::WriteAllText((Join-Path $D "SKILL.md"), $skill, (New-Object Text.UTF8Encoding($false)))
$envFile = Join-Path $HOME ".kirothon-board.env"
if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern '^TEAM_TOKEN=' -Quiet)) { Write-Output "팀장용 env 가 있어 덮어쓰지 않는다" }
else { [IO.File]::WriteAllText($envFile, "BOARD_URL=$URL`nBOARD_TOKEN=$Token`nBOARD_LANE=$Lane`n", (New-Object Text.UTF8Encoding($false))) }
$S = Join-Path $HOME ".kiro\settings"; New-Item -ItemType Directory -Force -Path $S | Out-Null
$perm = Join-Path $S "permissions.yaml"
if (Test-Path $perm) { Copy-Item $perm "$perm.bak-$(Get-Date -Format MMddHHmm)" -Force }
Copy-Item (Join-Path $DIR "kiro\settings\permissions.yaml") $perm -Force
if ($Project) {
  New-Item -ItemType Directory -Force -Path (Join-Path $Project ".kiro\steering"), (Join-Path $Project ".kiro\hooks") | Out-Null
  Copy-Item (Join-Path $DIR "steering\board.md") (Join-Path $Project ".kiro\steering\board.md") -Force
  Copy-Item (Join-Path $DIR "kiro\hooks\board-gate.windows.json") (Join-Path $Project ".kiro\hooks\board-gate.json") -Force
  Write-Output "프로젝트에 steering·hook 설치: $Project\.kiro\"
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $D "board.ps1") doctor $Project
