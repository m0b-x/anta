<#
.SYNOPSIS
  Runs the overnight review sessions one after another, each as its own
  `claude -p` run, and stops the chain at the first session that reports
  BLOCKED.

.DESCRIPTION
  The sessions are the blocks of docs/cloud-sync-phase-02-review-2026-10-26.md
  (A0, A1a .. A10) and docs/calendar-review-2026-10-26.md (B1 .. B8). Each run
  gets the kickoff line that record's section 0 shows, the model and effort
  its block names (Sonnet for the mechanical sessions A0, A9 and B8, Opus at
  high for every review and fix session), the repo's permission settings in
  `auto` mode, and its output copied to build\review-logs\<date>\<session>.log.
  Sessions run one at a time on purpose: `flutter test` runs one at a time
  and the fix sessions edit the tree.

.EXAMPLE
  tool\review\overnight.ps1 -Sessions A0,A1a,A1b,A1c,A2,A3a,A3b,A4,A5
  tool\review\overnight.ps1 -Sessions A6,A7,A8,A9 -Commit
  tool\review\overnight.ps1 -Sessions A2 -DryRun
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Sessions,
    [switch]$Commit,
    [switch]$DryRun,
    [string]$PermissionMode = 'auto'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$records = @{
    'A' = 'docs/cloud-sync-phase-02-review-2026-10-26.md'
    'B' = 'docs/calendar-review-2026-10-26.md'
}
# The mechanical sessions (a device pass, the gate, doc placement) run on
# Sonnet; every review and fix session on Opus at high (CLAUDE.md, "the budget").
$sonnetSessions = @('A0', 'A9', 'B8')

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$logDir = Join-Path $root "build\review-logs\$stamp"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# A night starts on a clean tree (record section 0.2): a review session reads
# HEAD, a fix session commits what it changed, and work left half-way by
# someone else would end up inside a fix commit or confuse the reviewers.
Push-Location $root
try { $dirty = @(git status --porcelain -- lib test test_driver tool/qa tool/firebase tool/release packages firestore.rules) } finally { Pop-Location }
if ($dirty.Count -gt 0) {
    Write-Host "!! The tree has uncommitted changes outside docs/:"
    $dirty | ForEach-Object { Write-Host "   $_" }
    if (-not $DryRun) { throw 'Commit or stash them first; the sessions expect a clean tree.' }
}

if ($Commit) {
    $grant = 'You may commit on main after the gate: one commit, a short natural subject, no ledger in the message.'
} else {
    $grant = 'Do not commit; end with a ready-to-run commit (paths and subject).'
}

# A print-mode run waits at most ten minutes (the CLI's default) for work
# still running in the background after the lead's last message, then ends
# the session with that work orphaned — and the Agent tool runs a subagent
# in the background whatever the agent does inside, so a lead waiting on a
# long qa-runner dies that way: A9 on 2026-10-28, mid device pass (the pass
# outlived it and finished green). One hour covers the three device suites
# in one agent call (about fifteen minutes) and a fix session's whole-suite
# runs; not 0 (indefinite), so a hung agent ends the session, not the night.
# Set here because the .cmd launchers strip every CLAUDE* variable before
# starting PowerShell.
$env:CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS = '3600000'

foreach ($session in $Sessions) {
    # An id is the block letter, one or two digits and an optional a/b/c suffix: A0, A1a, A10, B3b.
    if (-not ($session.Trim() -match '^(?i)([AB])(\d{1,2})([A-C])?$')) {
        throw "Unknown session '$session'; expected A0..A10 or B1..B8, with an optional a/b/c suffix."
    }
    $block = $Matches[1].ToUpper()
    $suffix = ''
    if ($Matches[3]) { $suffix = $Matches[3].ToLower() }
    $id = $block + $Matches[2] + $suffix
    $record = $records[$block]
    if ($sonnetSessions -contains $id) { $model = 'sonnet'; $effort = 'medium' }
    else { $model = 'opus'; $effort = 'high' }

    $prompt = "Run session $id of $record. Read its section 0 and the section 2 block for $id only, plus the sections that block names; then do what it says. The owner is asleep: never ask a question, take the lettered default and write it into the record. $grant Finish with the line SESSION ${id}: DONE, PARTIAL or BLOCKED and one sentence."
    $log = Join-Path $logDir "$id.log"

    Write-Host ""
    Write-Host "== $id  ($model / $effort)  $(Get-Date -Format 'HH:mm')  -> $log"
    if ($DryRun) {
        Write-Host "claude -p `"$prompt`" --model $model --effort $effort --permission-mode $PermissionMode --output-format text"
        continue
    }

    Push-Location $root
    try {
        # stdout goes to the console and to the log line by line; stderr stays
        # on the console (redirecting a native command's stderr in 5.1 wraps it
        # in error records and flips $? for nothing).
        & claude -p $prompt --model $model --effort $effort --permission-mode $PermissionMode --output-format text |
            ForEach-Object { Write-Host $_; Add-Content -LiteralPath $log -Value $_ -Encoding UTF8 }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $verdict = 'no SESSION line'
    if (Test-Path -LiteralPath $log) {
        $tail = (Get-Content -LiteralPath $log -Tail 8) -join "`n"
        if ($tail -match "SESSION\s+$id\s*:\s*(DONE|PARTIAL|BLOCKED)") { $verdict = $Matches[1] }
    }
    Write-Host "== $id ended: exit $code, $verdict  $(Get-Date -Format 'HH:mm')"
    if ($code -ne 0 -or $verdict -eq 'BLOCKED') {
        Write-Host "!! The chain stops here; read $log and the record's session log."
        break
    }
}
