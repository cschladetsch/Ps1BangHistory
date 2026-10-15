# PsBangHistory

Bash-style bang-history expansion for PowerShell, using `@` instead of `!` (since `!` isn't available as a bare sigil in PowerShell, and ~ clashes with $HOME).

## Syntax

| Token          | Meaning                                      | Bash equivalent |
|----------------|-----------------------------------------------|------------------|
| `@@`           | last command                                  | `!!`             |
| `@$`           | last word of last command                     | `!$`             |
| `@*`           | all args of last command                      | `!*`             |
| `@-N`          | Nth-previous command                          | `!-N`            |
| `@-N:$`        | last word of Nth-previous command             | `!-N:$`          |
| `@-N:^`        | first arg of Nth-previous command             | `!-N:^`          |
| `@-N:*`        | all args of Nth-previous command              | `!-N:*`          |
| `@-N:K`        | word K (0 = command name) of Nth-previous cmd | `!-N:K`          |
| `@-N:A-B`      | word range A..B of Nth-previous command       | `!-N:A-B`        |
| `@N`           | history event N by absolute Id                | `!N`             |
| `@N:$` etc     | same selectors, applied to event N            | `!N:$` etc       |
| `@[text]`      | most recent command containing `text` anywhere | `!?text?`       |
| `@[text]:$` etc | same selectors, applied to the matched command | `!text:$` etc   |
| `@word`        | most recent command *starting with* `word`   | `!word`          |
| `@word:$` etc  | same selectors, applied to the prefix-matched command | `!word:$` etc |
| `@-N:K*`       | words K..end of Nth-previous command          | `!-N:K*`         |
| `@@:gs/old/new/` | last command, every `old` replaced with `new` | `!!:gs/old/new/` |
| `^old^new^`    | last command, first `old` replaced with `new` | `^old^new^`      |

## Install

```powershell
. "C:\path\to\PsBangHistory\BangHistory.ps1"
```

Or add that line to `$PROFILE` to load on every session.

### Extracting the release archive on Windows

`Expand-Archive` only handles `.zip` — it will not open a `.tar.gz`. Use Windows' built-in `tar.exe` (bsdtar, shipped since Windows 10 1803) instead:

```powershell
tar xzf PsBangHistory.tar.gz -C .
```

Note this `tar.exe` doesn't support GNU-style `--overwrite`; it overwrites existing files by default, so just omit the flag.

## Testing

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Import-Module Pester -MinimumVersion 5.0.0 -Force
Invoke-Pester .\Tests -Output Detailed
```

Always invoke through `Invoke-Pester .\Tests`, not by running the test file directly — Windows ships an old Pester 3.4.0 under `Program Files` that predates the syntax used here, and direct invocation isn't the intended entry point in Pester 5 regardless.

## Help

Two ways to get the reference table without leaving the terminal:

```powershell
Show-BangHistoryHelp        # quick cheat-sheet table, printed directly
Get-Help Expand-BangHistory -Full   # full comment-based help with examples
```

Show-BangHistoryHelp` is a normal function call — type it exactly as shown, not as a `@` token, or it'll be treated as a history search instead of a help request.

## Behaviour

Pressing Enter on a line containing a `@` token expands it into the buffer and stops — it does not execute. Press Enter again on the now-expanded (token-free) line to run it. This is a deliberate preview/confirm step, not a bug.

**If an expansion resolves to the wrong thing**, press **Ctrl+Z** (PowerShell's default Undo binding) to revert the buffer back to exactly what you typed, fix the token, and try again.

Operates on PSReadLine's persisted history file when one exists — that covers commands from every prior session, not just this one, since PSReadLine appends to that file live as you type. Falls back to `Get-History` (session-only) if no persisted file is configured or found. Check your file with:

```powershell
(Get-PSReadLineOption).HistorySavePath
```

Bash's `!#` (the not-yet-submitted current line) has no equivalent here — there's no reliable hook into unsubmitted buffer text outside the Enter handler itself.

`gs/old/new/` — neither `old` nor `new` may contain a literal `/`, since `/` is the field delimiter.

## Demos

**Rerun the last command**
```powershell
PS> docker build -t myapp .
PS> @@
```

**Reuse an argument across a different command**
```powershell
PS> vim server.config.json
PS> git add @$
# expands to: git add server.config.json
```

**Reuse every argument from the last command**
```powershell
PS> docker run -d --name api -p 8080:80 nginx
PS> echo @*
# expands to: echo -d --name api -p 8080:80 nginx
```

**Search history and extract an argument**
```powershell
PS> docker run -d --name api-server -p 8080:80 nginx
PS> ...ten commands later...
PS> docker logs @[api-server]:2
```

**The safety net — preview before anything destructive runs**
```powershell
PS> rm -Recurse @-5:*
# buffer shows the fully expanded path before anything executes
# e.g. rm -Recurse -Force C:\builds\output\*
# only runs on the second Enter
```

**Absolute recall by history id**
```powershell
PS> Get-BangHistoryBuffer | Select-Object Id, CommandLine | Select-Object -Last 20
PS> @142
```
Note: this `Id` is line-position in the persisted history file, not the `Id` shown by `Get-History` — the two numbering schemes differ once `@N` is reading cross-session history. Always check ids via `Get-BangHistoryBuffer`, not `Get-History`.

**Quick fix a typo/detail and re-run without retyping the whole command**
```powershell
PS> git push origin mian
PS> ^mian^main^
# expands to: git push origin main
```

**Prefix match — bash's actual !string behavior**
```powershell
PS> git commit -m "fix bug"
PS> @git
# most recent command starting with "git" — not just containing it anywhere
```

**Global substitution across an entire command**
```powershell
PS> docker build -t myapp:v1.2.3 .
PS> @:gs/v1.2.3/v1.2.4/
# expands to: docker build -t myapp:v1.2.4 .
```

## License

MIT
## Brace Expansion Examples

Brace expansion generates arbitrary strings or file paths using pattern matching without invoking external commands.

### 1. Basic Sequence Expansion
Generate numbers or single-character ranges:

`ash
# Numeric sequences
echo {1..5}
# Output: 1 2 3 4 5

# Letter ranges
echo {a..e}
# Output: a b c d e

# Padded numbers
echo {01..05}
# Output: 01 02 03 04 05

# Stepped sequences
echo {0..10..2}
# Output: 0 2 4 6 8 10
Streamline directory structure creation and bulk file manipulation:

`ash
# Create directory trees in one command
mkdir -p project/{src,bin,docs,tests/{unit,integration}}

# Quick file backup
cp config.json{,.bak}
# Expands to: cp config.json config.json.bak
