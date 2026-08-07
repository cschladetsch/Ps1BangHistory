#requires -Module PSReadLine

# @ -based bash bang-history emulation for PowerShell.
#
# Supported syntax:
#   @@              last command                 (bash !!)
#   @$              last word of last command     (bash !$)
#   @*              all args of last command      (bash !*)
#   @-N             Nth-previous command           (bash !-N)
#   @-N:$           last word of Nth-previous cmd
#   @-N:^           first arg of Nth-previous cmd
#   @-N:*           all args of Nth-previous cmd
#   @-N:K           word K (0=command name) of Nth-previous cmd
#   @-N:A-B         word range A..B of Nth-previous cmd
#   @N              history event N by absolute Id, zero-based     (bash !N)
#   @N:$ / :^ / :* / :K / :A-B   same selectors, applied to event N
#   @[text]         most recent cmd containing "text"   (bash !?text?, substring anywhere)
#   @[text]:$ / :^ / :* / :K / :A-B   same selectors, applied to matched command
#   @word           most recent cmd starting with "word" (bash !word, prefix match)
#   @word:$ etc     same selectors, applied to the prefix-matched command
#   @-N:K*          words K..end of Nth-previous command (bash !-N:K*)
#   @@:gs/old/new/  last command with every "old" replaced by "new" (bash !!:gs/old/new/)
#                   note: neither "old" nor "new" may contain a literal "/"
#   ^old^new^       quick substitution: last command, first "old" replaced by "new", re-run
#
# @# (bash's "current typed line so far") is not supported — there's no
# reliable hook for the not-yet-submitted buffer text outside the Enter
# handler itself.
#
# Behaviour: pressing Enter on a line containing @ tokens expands them into
# the buffer and does NOT run the line (preview step). Press Enter again to
# actually execute. Dot-source this from $PROFILE.

function Split-BangWords {
    param([string]$Line)
    [regex]::Matches($Line, '(?:[^\s"'']+|"[^"]*"|''[^'']*'')+') |
        ForEach-Object { $_.Value }
}

function Select-BangWords {
    param([string[]]$Words, [string]$Selector)

    if (-not $Selector) { return ($Words -join ' ') }

    switch -regex ($Selector) {
        '^\$$' { return $Words[-1] }
        '^\^$' { return $Words[1] }
        '^\*$' { return ($Words[1..($Words.Count - 1)] -join ' ') }
        '^(\d+)\*$' {
            $k = [int]$Matches[1]
            return ($Words[$k..($Words.Count - 1)] -join ' ')
        }
        '^\d+$' { return $Words[[int]$Selector] }
        '^(\d+)-(\d+)$' {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            return ($Words[$a..$b] -join ' ')
        }
        '^gs/([^/]*)/([^/]*)/?$' {
            $findText = $Matches[1]; $replaceText = $Matches[2]
            return (($Words -join ' ') -replace [regex]::Escape($findText), $replaceText)
        }
        default { return ($Words -join ' ') }
    }
}

function Get-BangHistoryBuffer {
    <#
    .SYNOPSIS
        Returns the effective history buffer as an ordered array of
        objects with Id and CommandLine properties.
    .DESCRIPTION
        Reads PSReadLine's persisted history file when one is configured
        and present — this covers the current session AND every prior
        session, since PSReadLine appends to that file live as commands
        are entered. Falls back to the in-memory Get-History cmdlet (this
        session only) if no persisted file is available.

        Id is assigned sequentially by line position in the file, zero-based
        (the first-ever recorded command is Id 0), not PSReadLine's
        in-session history Id, since file-based entries span sessions and
        have no native Id of their own.

        Known limitation: PSReadLine encodes embedded newlines in
        multi-line history entries; this reads each file line as one
        command verbatim and does not decode that escaping.
    #>
    $path = $null
    try { $path = (Get-PSReadLineOption -ErrorAction Stop).HistorySavePath } catch {}

    if ($path -and (Test-Path -Path $path)) {
        $lines = @(Get-Content -Path $path -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 0) {
            $i = -1
            return $lines | ForEach-Object {
                $i++
                [pscustomobject]@{ Id = $i; CommandLine = $_ }
            }
        }
    }

    return Get-History
}

function Get-BangCommandLine {
    param([string]$Ref)

    $buffer = @(Get-BangHistoryBuffer)
    if ($buffer.Count -eq 0) { return $null }

    if ($Ref -eq '@@') {
        $h = $buffer[-1]
    }
    elseif ($Ref -match '^@-(\d+)$') {
        $n = [int]$Matches[1]
        $idx = $buffer.Count - $n
        if ($idx -lt 0) { return $null }
        $h = $buffer[$idx]
    }
    elseif ($Ref -match '^@(\d+)$') {
        $id = [int]$Matches[1]
        $h = $buffer | Where-Object { $_.Id -eq $id } | Select-Object -Last 1
    }
    elseif ($Ref -match '^@\[(.+)\]$') {
        $needle = $Matches[1]
        $h = $buffer | Where-Object { $_.CommandLine -like "*$needle*" } |
             Select-Object -Last 1
    }
    elseif ($Ref -match '^@([A-Za-z_][\w.\-\/]*)$') {
        $prefix = $Matches[1]
        $h = $buffer | Where-Object { $_.CommandLine -like "$prefix*" } |
             Select-Object -Last 1
    }
    else {
        return $null
    }

    if (-not $h) { return $null }
    return $h.CommandLine
}

function Show-BangHistoryHelp {
    <#
    .SYNOPSIS
        Prints a quick reference table of all @ bang-history tokens.
    .DESCRIPTION
        Run this directly at the prompt — it's a normal command, not a @
        token itself, so it isn't intercepted or expanded.
    .EXAMPLE
        Show-BangHistoryHelp
    #>
    $rows = @(
        [pscustomobject]@{ Token = '@@';             Meaning = 'last command';                              Bash = '!!' }
        [pscustomobject]@{ Token = '@$';              Meaning = 'last word of last command';                 Bash = '!$' }
        [pscustomobject]@{ Token = '@*';              Meaning = 'all args of last command';                  Bash = '!*' }
        [pscustomobject]@{ Token = '@-N';             Meaning = 'Nth-previous command';                      Bash = '!-N' }
        [pscustomobject]@{ Token = '@-N:$';           Meaning = 'last word of Nth-previous command';         Bash = '!-N:$' }
        [pscustomobject]@{ Token = '@-N:^';           Meaning = 'first arg of Nth-previous command';         Bash = '!-N:^' }
        [pscustomobject]@{ Token = '@-N:*';           Meaning = 'all args of Nth-previous command';          Bash = '!-N:*' }
        [pscustomobject]@{ Token = '@-N:K';           Meaning = 'word K (0=cmd name) of Nth-previous cmd';   Bash = '!-N:K' }
        [pscustomobject]@{ Token = '@-N:A-B';         Meaning = 'word range A..B of Nth-previous command';   Bash = '!-N:A-B' }
        [pscustomobject]@{ Token = '@-N:K*';          Meaning = 'words K..end of Nth-previous command';      Bash = '!-N:K*' }
        [pscustomobject]@{ Token = '@N';              Meaning = 'history event N by absolute Id';            Bash = '!N' }
        [pscustomobject]@{ Token = '@N:$ etc';        Meaning = 'same selectors, applied to event N';        Bash = '!N:$ etc' }
        [pscustomobject]@{ Token = '@[text]';         Meaning = 'most recent cmd containing text anywhere';  Bash = '!?text?' }
        [pscustomobject]@{ Token = '@[text]:$ etc';   Meaning = 'same selectors, applied to matched cmd';    Bash = '!text:$ etc' }
        [pscustomobject]@{ Token = '@word';           Meaning = 'most recent cmd starting with word';        Bash = '!word' }
        [pscustomobject]@{ Token = '@word:$ etc';     Meaning = 'same selectors, applied to matched cmd';    Bash = '!word:$ etc' }
        [pscustomobject]@{ Token = '@@:gs/old/new/';  Meaning = 'every "old" replaced by "new" (no / allowed in old/new)'; Bash = '!!:gs/old/new/' }
        [pscustomobject]@{ Token = '^old^new^';       Meaning = 'last command, first "old" replaced by "new"'; Bash = '^old^new^' }
    )

    $rows | Format-Table -AutoSize -Wrap

    Write-Host "Preview/confirm: Enter expands, Enter again runs. Ctrl+Z undoes a bad expansion." -ForegroundColor DarkGray
    Write-Host "Full docs: Get-Help Expand-BangHistory -Full" -ForegroundColor DarkGray
}

function Expand-BangHistory {
    <#
    .SYNOPSIS
        Expands @ bang-history tokens in a line of PowerShell input.

    .DESCRIPTION
        Bash-style bang-history expansion for PowerShell, using @ as the
        sigil instead of ! (which PowerShell reserves as a logical operator).
        See Show-BangHistoryHelp for the full token/selector reference table.

    .PARAMETER Line
        The raw input line, possibly containing one or more @ tokens.

    .EXAMPLE
        Expand-BangHistory -Line '@@'
        Expands to the full text of the last executed command.

    .EXAMPLE
        Expand-BangHistory -Line 'git add @$'
        Expands @$ to the last word of the last command, leaving the rest
        of the line untouched.

    .EXAMPLE
        Expand-BangHistory -Line 'echo @*'
        Expands @* to every argument (excluding the command name itself)
        of the last command.

    .EXAMPLE
        Expand-BangHistory -Line '@[docker]:^'
        Finds the most recent command containing "docker" and returns its
        first argument.

    .LINK
        Show-BangHistoryHelp
    #>
    param([string]$Line)

    # Quick substitution: ^old^new^ (or ^old^new) operates on the entire
    # last command, replacing the first occurrence of "old" with "new",
    # then previews the result exactly like every other token — bash's !!
    # implied re-run happens on the user's confirming second Enter, not here.
    if ($Line -match '^\^([^\^]+)\^([^\^]*)\^?$') {
        $findText = $Matches[1]; $replaceText = $Matches[2]
        $last = Get-BangCommandLine -Ref '@@'
        if ($last) {
            $rx = [regex]::new([regex]::Escape($findText))
            return $rx.Replace($last, $replaceText, 1)   # first occurrence only
        }
        return $Line
    }

    # normalize the !$-equivalent and !*-equivalent shorthands first
    $Line = $Line -replace '@\$', '@@:$'
    $Line = $Line -replace '@\*', '@@:*'

    $refPattern = '@@|@-\d+|@\d+|@\[[^\]]+\]|@[A-Za-z_][\w.\-\/]*'
    $selPattern = '\$|\^|\*|\d+\*|\d+(?:-\d+)?|gs/[^/]*/[^/]*/?'
    $pattern = "(?<ref>$refPattern)(?::(?<sel>$selPattern))?"

    $result = [regex]::Replace($Line, $pattern, {
        param($m)
        $ref = $m.Groups['ref'].Value
        $sel = $m.Groups['sel'].Value

        $cmd = Get-BangCommandLine -Ref $ref
        if (-not $cmd) { return $m.Value }   # no match, leave token untouched

        $words = Split-BangWords -Line $cmd
        return (Select-BangWords -Words $words -Selector $sel)
    })

    return $result
}

function Resolve-BangHistoryExpansion {
    <#
    .SYNOPSIS
        Decides what an Enter press should do with the current buffer line.
    .DESCRIPTION
        Returns the expanded text if Line contains a bang-history token that
        resolves to something different, or $null if Enter should just
        accept the line as typed.

        This exists as its own function, called by both the Enter key
        handler and by tests, specifically so the two can't drift apart.
        The key handler used to gate on "does Line contain a literal @"
        before bothering to call Expand-BangHistory — a reasonable-looking
        optimization that quietly broke ^old^new^, which contains no @ at
        all. That token type resolved correctly in Expand-BangHistory the
        whole time; the guard in front of it just never let it through in
        a real session. Routing both callers through one decision function
        makes that class of divergence impossible: whatever
        Expand-BangHistory recognizes, the key handler acts on.
    #>
    param([string]$Line)
    $expanded = Expand-BangHistory -Line $Line
    if ($expanded -ne $Line) { return $expanded }
    return $null
}

try {
    Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $expanded = Resolve-BangHistoryExpansion -Line $line
        if ($null -ne $expanded) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $expanded)
            return
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}
catch {
    # Non-interactive host (e.g. CI test runner) — key handler registration
    # isn't meaningful there. The Expand-BangHistory / Get-BangCommandLine
    # functions above are still defined and testable.
    Write-Verbose "Skipped PSReadLine key handler registration: $_"
}
