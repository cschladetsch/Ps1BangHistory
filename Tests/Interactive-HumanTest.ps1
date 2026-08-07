<#
Interactive-HumanTest.ps1

The Pester suite (BangHistory.Tests.ps1) exhaustively checks the pure
functions (Expand-BangHistory, Select-BangWords, Get-BangCommandLine)
against a mocked history buffer. It CANNOT exercise the one part of this
tool that's actually interactive: the Set-PSReadLineKeyHandler binding on
Enter — the preview-before-execute behavior, Ctrl+Z revert, and real
(not mocked) PSReadLine history.

This script walks you through that, one step at a time, using
$host.EnterNestedPrompt() so each step gets a real prompt with the real
key handler active. Type `exit` to leave the nested prompt and return to
the checklist after each step.

Usage:
    .\Tests\Interactive-HumanTest.ps1
#>

$bangHistoryPath = Join-Path $PSScriptRoot '..\BangHistory.ps1'
if (-not (Test-Path $bangHistoryPath)) {
    Write-Host "Can't find BangHistory.ps1 at $bangHistoryPath — run this from Tests\, or edit the path at the top of this script." -ForegroundColor Red
    return
}
. $bangHistoryPath

if ($Host.Name -notmatch 'ConsoleHost') {
    Write-Host "This needs a real interactive console (not the ISE or a non-interactive runner)." -ForegroundColor Yellow
    return
}

$script:results = [System.Collections.Generic.List[pscustomobject]]::new()

function Show-Step {
    param(
        [int]$Number,
        [string]$Title,
        [string[]]$Instructions
    )
    Write-Host ""
    Write-Host "===== Step $Number`: $Title =====" -ForegroundColor Cyan
    foreach ($line in $Instructions) {
        Write-Host "  $line" -ForegroundColor Gray
    }
    Write-Host "  (Do this now. Type 'exit' when done to come back here.)" -ForegroundColor DarkGray
    Write-Host ""
    $host.EnterNestedPrompt()

    $verdict = Read-Host "  Did it behave as expected? (y/n)"
    $note = $null
    if ($verdict -notmatch '^y') {
        $note = Read-Host "  What happened instead?"
    }
    $script:results.Add([pscustomobject]@{
        Step   = $Number
        Title  = $Title
        Passed = ($verdict -match '^y')
        Note   = $note
    })
}

Write-Host "PsBangHistory — interactive walkthrough" -ForegroundColor Green
Write-Host "This tests the live key handler, not just the parsing logic." -ForegroundColor Gray

Show-Step -Number 0 -Title 'Seed a known history' -Instructions @(
    'Type each of these EXACTLY, pressing Enter once after each (no @ tokens here, so each',
    'should run immediately, not preview):'
    '  echo status'
    '  echo server.config.json'
    '  echo run -d --name api-server -p 8080:80 nginx'
    '  echo commit -m "fix bug"'
    '  echo build -t myapp:v1.2.3 .'
    '  echo push origin mian'
    'The last one (push origin mian) should be the most recent thing in your history now.'
)

Show-Step -Number 1 -Title 'Preview does NOT execute on the first Enter' -Instructions @(
    "Type: @@"
    "Press Enter ONCE."
    "Expected: the buffer replaces itself with 'echo push origin mian' — but nothing"
    "runs yet (no 'push origin mian' printed to the screen). If you saw output already,"
    "that's a fail — the whole preview/confirm design has broken."
)

Show-Step -Number 2 -Title 'Second Enter actually executes' -Instructions @(
    "Continuing from Step 1: the buffer should still show 'echo push origin mian',"
    "un-expanded (no @ tokens left in it). Press Enter again."
    "Expected: it runs for real and prints 'push origin mian'."
)

Show-Step -Number 3 -Title 'Ctrl+Z reverts a bad-looking expansion' -Instructions @(
    "Type: @-3:$"
    "Press Enter once — buffer should preview as: `"fix bug`""
    "Now press Ctrl+Z (PowerShell's default Undo)."
    "Expected: the buffer reverts back to the literal text @-3:$ you typed, not the"
    "expansion and not an empty line. Clear the line (Escape) when done."
)

Show-Step -Number 4 -Title 'Multiple tokens expand together in one preview' -Instructions @(
    "Type: echo @$ and @2"
    "Press Enter once."
    "Expected preview: echo mian and echo run -d --name api-server -p 8080:80 nginx"
    "(both tokens resolved in the same pass). Press Enter again to run it, or Escape to skip."
)

Show-Step -Number 5 -Title 'gs/// global substitution' -Instructions @(
    "Type: @@:gs/mian/main/"
    "Press Enter once."
    "Expected preview: echo push origin main"
    "Press Enter again to confirm it runs."
)

Show-Step -Number 6 -Title 'Quick-sub ^old^new^ (no @ involved at all)' -Instructions @(
    "Type: ^mian^main^"
    "Press Enter once."
    "Expected preview: echo push origin main"
    "Press Enter again to confirm it runs."
)

Show-Step -Number 7 -Title 'Cross-check against the real (not mocked) history buffer' -Instructions @(
    "Run: Get-BangHistoryBuffer | Select-Object Id, CommandLine | Select-Object -Last 6"
    "Note the Id shown next to 'echo run -d --name api-server -p 8080:80 nginx'."
    "Now type @<that id> and press Enter once."
    "Expected: the preview matches that exact command line from the table."
)

Show-Step -Number 8 -Title 'Show-BangHistoryHelp is never treated as a token' -Instructions @(
    "Type: Show-BangHistoryHelp"
    "Press Enter once."
    "Expected: it runs immediately (no preview step) and prints the reference table,"
    "since the line contains no @ and no leading ^."
)

Show-Step -Number 9 -Title 'Gotcha check: an email-like string is left alone' -Instructions @(
    "Type: echo user@example.com"
    "Press Enter once."
    "Expected: the line is untouched (no expansion), since nothing in your history"
    "starts with 'example.com'. Press Enter again to actually run it."
)

Show-Step -Number 10 -Title 'Gotcha check: a trailing @N DOES get mangled — this is real, not a mock artifact' -Instructions @(
    "Type: echo demo@2"
    "Press Enter once."
    "Expected: '@2' gets silently replaced with the FULL text of history event 2,"
    "glued directly onto 'demo' with no space — e.g. 'echo demoecho run -d --name",
    "api-server -p 8080:80 nginx'. This confirms the branch-name-style footgun found",
    "in the Pester suite is real in an actual session, not just a mocking artifact."
    "Press Escape to clear the line rather than running that."
)

Write-Host ""
Write-Host "===== Summary =====" -ForegroundColor Cyan
$script:results | Format-Table Step, Title, Passed -AutoSize

$failed = $script:results | Where-Object { -not $_.Passed }
if ($failed) {
    Write-Host "$($failed.Count) step(s) did not behave as expected:" -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host "  Step $($f.Step) ($($f.Title)): $($f.Note)" -ForegroundColor Red
    }
} else {
    Write-Host "All steps behaved as expected." -ForegroundColor Green
}
