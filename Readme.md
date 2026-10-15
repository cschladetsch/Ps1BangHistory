# Ps1BangHistory

`Ps1BangHistory` brings Bash-style bang (`!`) history expansion and token selection to PowerShell environments—using `@` syntax to avoid conflicts with PowerShell's native logical NOT operator (`!`).

## Features

- **Bang Token Expansion**: Full support for history recall (`@@`, `@-N`, `@N`, `@[text]`, `@word`).
- **Word & Range Selectors**: Extract specific arguments (`^`, `$`, `*`, `K`, `K*`, `A-B`).
- **Quick & Global Substitution**: Search and replace using `^old^new^` or `@@:gs/old/new/`.
- **Interactive Integration**: Seamless PSReadLine integration for inline expansion before execution.

---

## Token Reference

| Syntax | Bash Equivalent | Description |
| :--- | :--- | :--- |
| `@@` | `!!` | Last command in history |
| `@-N` | `!-N` | Nth-previous command in history |
| `@N` | `!N` | Absolute history event ID N |
| `@[text]` | `!?text?` | Most recent command containing `text` |
| `@word` | `!word` | Most recent command starting with `word` |
| `@$` | `!$` | Last argument of last command |
| `@*` | `!*` | All arguments of last command (excluding command name) |
| `@-N:^` | `!-N:^` | First argument of Nth-previous command |
| `@-N:K` | `!-N:K` | K-th argument (0 = command name) |
| `@-N:K*` | `!-N:K*` | Arguments K through end |
| `@-N:A-B` | `!-N:A-B` | Inclusive argument range from A to B |
| `^old^new^` | `^old^new` | Replace first occurrence of `old` with `new` on last command |
| `@@:gs/old/new/` | `!!:gs/old/new/` | Global replace all occurrences of `old` with `new` |

---

## Interactive Examples

### 1. Argument Extraction (`@$`, `@-1:1*`)
```powershell
# Inspect a file, then open it in NeoVim
Get-ChildItem .\README.md
nvim @$
# Expands to: nvim .\README.md

# Reuse arguments with a different command
Write-Output "Alpha" "Beta" "Gamma"
Write-Host @-1:1*
# Expands to: Write-Host "Alpha" "Beta" "Gamma"

