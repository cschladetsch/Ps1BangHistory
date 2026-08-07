#requires -Module Pester

BeforeAll {
    . "$PSScriptRoot\..\BangHistory.ps1"

    # Fixed, deterministic buffer for every test — avoids depending on the
    # real PSReadLine history file. Id is zero-based, oldest first, matching
    # Get-BangHistoryBuffer's contract.
    $script:FakeBuffer = @(
        [pscustomobject]@{ Id = 0; CommandLine = 'git status' }
        [pscustomobject]@{ Id = 1; CommandLine = 'vim server.config.json' }
        [pscustomobject]@{ Id = 2; CommandLine = 'docker run -d --name api-server -p 8080:80 nginx' }
        [pscustomobject]@{ Id = 3; CommandLine = 'git commit -m "fix bug"' }
        [pscustomobject]@{ Id = 4; CommandLine = 'docker build -t myapp:v1.2.3 .' }
        [pscustomobject]@{ Id = 5; CommandLine = 'git push origin mian' }
    )

    Mock Get-BangHistoryBuffer { return $script:FakeBuffer }
}

Describe 'Get-BangCommandLine' {
    It 'resolves @@ to the last command' {
        Get-BangCommandLine -Ref '@@' | Should -Be 'git push origin mian'
    }

    It 'resolves @-N to the Nth-previous command' {
        # buffer.Count = 6; @-1 => idx 5 (last), @-3 => idx 3
        Get-BangCommandLine -Ref '@-1' | Should -Be 'git push origin mian'
        Get-BangCommandLine -Ref '@-3' | Should -Be 'git commit -m "fix bug"'
    }

    It 'returns $null when @-N goes past the start of history' {
        Get-BangCommandLine -Ref '@-99' | Should -BeNullOrEmpty
    }

    It 'resolves @N to the absolute history Id' {
        Get-BangCommandLine -Ref '@2' | Should -Be 'docker run -d --name api-server -p 8080:80 nginx'
    }

    It 'resolves @[text] to the most recent command containing text anywhere' {
        Get-BangCommandLine -Ref '@[api-server]' | Should -Be 'docker run -d --name api-server -p 8080:80 nginx'
    }

    It 'resolves @word to the most recent command starting with word (prefix, not substring)' {
        # "git" prefix-matches both index 0 and 5; most recent wins
        Get-BangCommandLine -Ref '@git' | Should -Be 'git push origin mian'
    }

    It 'does not prefix-match a word that only appears mid-command' {
        # "server" is not a prefix of any command, only a substring of index 2
        Get-BangCommandLine -Ref '@server' | Should -BeNullOrEmpty
    }
}

Describe 'Select-BangWords' {
    BeforeAll {
        $script:Words = Split-BangWords -Line 'docker run -d --name api -p 8080:80 nginx'
    }

    It 'returns the whole line for an empty selector' {
        Select-BangWords -Words $Words -Selector '' | Should -Be ($Words -join ' ')
    }

    It '$ returns the last word' {
        Select-BangWords -Words $Words -Selector '$' | Should -Be 'nginx'
    }

    It '^ returns the first argument (word 1, not the command name)' {
        Select-BangWords -Words $Words -Selector '^' | Should -Be 'run'
    }

    It '* returns all arguments excluding the command name' {
        Select-BangWords -Words $Words -Selector '*' | Should -Be 'run -d --name api -p 8080:80 nginx'
    }

    It 'a plain integer K returns word K (0 = command name)' {
        Select-BangWords -Words $Words -Selector '0' | Should -Be 'docker'
        Select-BangWords -Words $Words -Selector '2' | Should -Be '-d'
    }

    It 'K* returns words K..end' {
        Select-BangWords -Words $Words -Selector '2*' | Should -Be '-d --name api -p 8080:80 nginx'
    }

    It 'A-B (hyphen) returns the inclusive word range' {
        Select-BangWords -Words $Words -Selector '1-3' | Should -Be 'run -d --name'
    }

    It 'gs/old/new/ replaces every occurrence' {
        Select-BangWords -Words $Words -Selector 'gs/nginx/apache/' | Should -Be 'docker run -d --name api -p 8080:80 apache'
    }
}

Describe 'Expand-BangHistory - documented token forms' {
    It 'expands @@ to the full last command' {
        Expand-BangHistory -Line '@@' | Should -Be 'git push origin mian'
    }

    It 'expands @$ (shorthand) to the last word of the last command' {
        Expand-BangHistory -Line 'git add @$' | Should -Be 'git add mian'
    }

    It 'expands @* (shorthand) to all args of the last command' {
        Expand-BangHistory -Line 'echo @*' | Should -Be 'echo push origin mian'
    }

    It 'expands @-N:$ to the last word of the Nth-previous command (a quoted arg stays one token, quotes included)' {
        Expand-BangHistory -Line '@-3:$' | Should -Be '"fix bug"'
    }

    It 'expands @-N:^ to the first argument of the Nth-previous command' {
        Expand-BangHistory -Line '@-3:^' | Should -Be 'commit'
    }

    It 'expands @-N:K to word K of the Nth-previous command' {
        Expand-BangHistory -Line '@-3:0' | Should -Be 'git'
    }

    It 'expands @-N:A-B (hyphen range) to that word range' {
        Expand-BangHistory -Line '@-3:0-1' | Should -Be 'git commit'
    }

    It 'expands @-N:K* to words K..end' {
        Expand-BangHistory -Line '@-3:1*' | Should -Be 'commit -m "fix bug"'
    }

    It 'expands @N to the absolute history event' {
        Expand-BangHistory -Line '@2' | Should -Be 'docker run -d --name api-server -p 8080:80 nginx'
    }

    It 'expands @[text]:$ against the matched command' {
        Expand-BangHistory -Line '@[api-server]:2' | Should -Be '-d'
    }

    It 'expands @word:$ against the prefix-matched command' {
        Expand-BangHistory -Line '@git:0' | Should -Be 'git'
    }

    It 'expands @@:gs/old/new/ across the whole last command' {
        Expand-BangHistory -Line '@@:gs/mian/main/' | Should -Be 'git push origin main'
    }

    It 'expands ^old^new^ against the last command' {
        Expand-BangHistory -Line '^mian^main^' | Should -Be 'git push origin main'
    }

    It 'leaves an unrecognized token untouched' {
        Expand-BangHistory -Line 'echo @nosuchprefix' | Should -Be 'echo @nosuchprefix'
    }
}

Describe 'Expand-BangHistory - malformed / non-standard forms (regression for the colon typo)' {
    It 'does NOT expand @:-3:$ (colon directly after @ is not a valid ref) — left untouched' {
        # This is the exact form that looks like it should work but doesn't:
        # refPattern requires @ to be immediately followed by @, -, a digit,
        # [ or a letter — a bare colon right after @ never matches.
        Expand-BangHistory -Line '@:-3:$' | Should -Be '@:-3:$'
    }

    It 'partially expands @-3:1:2 — only the valid @-3:1 prefix is recognized, trailing ":2" is left as literal text' {
        # Not all-or-nothing: the regex matches the longest valid token it can
        # find (@-3:1, selector "1"), expands that to word 1 of the command,
        # and passes the unrecognized ":2" through unchanged. A-B (hyphen) is
        # still the only valid way to express a word range.
        Expand-BangHistory -Line '@-3:1:2' | Should -Be 'commit:2'
    }
}

Describe 'Resolve-BangHistoryExpansion' {
    It 'returns the expanded text when the line contains a token' {
        Resolve-BangHistoryExpansion -Line '@@' | Should -Be 'git push origin mian'
    }

    It 'returns $null when the line is unchanged (plain command, no tokens)' {
        Resolve-BangHistoryExpansion -Line 'git status' | Should -BeNullOrEmpty
    }

    It 'returns $null (not the original text) for ^old^new^ style typos with no match' {
        Resolve-BangHistoryExpansion -Line 'echo hello' | Should -BeNullOrEmpty
    }
}

Describe 'Split-BangWords - edge cases' {
    It 'collapses runs of multiple spaces between words' {
        (Split-BangWords -Line 'echo   foo   bar') -join '|' | Should -Be 'echo|foo|bar'
    }

    It 'returns nothing for an empty line' {
        Split-BangWords -Line '' | Should -BeNullOrEmpty
    }

    It 'returns nothing for a whitespace-only line' {
        Split-BangWords -Line '   ' | Should -BeNullOrEmpty
    }

    It 'glues a double-quoted chunk directly onto adjacent non-space text (no separating space)' {
        (Split-BangWords -Line 'echo foo"bar baz"')[1] | Should -Be 'foo"bar baz"'
    }

    It 'keeps a single-quoted argument as one token, quotes included' {
        (Split-BangWords -Line "echo 'hello world'")[1] | Should -Be "'hello world'"
    }

    It 'returns a single scalar token for a one-word line' {
        Split-BangWords -Line 'status' | Should -Be 'status'
    }

    It 'treats two separately-spaced quoted chunks as two distinct tokens' {
        (Split-BangWords -Line 'echo "a b" "c d"').Count | Should -Be 3
    }

    It 'ignores leading and trailing whitespace' {
        (Split-BangWords -Line '  git status  ') -join '|' | Should -Be 'git|status'
    }
}

Describe 'Select-BangWords - edge cases' {
    BeforeAll {
        $script:Words = Split-BangWords -Line 'docker run -d --name api -p 8080:80 nginx'
    }

    It 'selector 7 (last index) returns the last word, same as $' {
        Select-BangWords -Words $Words -Selector '7' | Should -Be 'nginx'
    }

    It 'selector 4 returns the word at that index' {
        Select-BangWords -Words $Words -Selector '4' | Should -Be 'api'
    }

    It '7* (K* at the last index) returns just that one word' {
        Select-BangWords -Words $Words -Selector '7*' | Should -Be 'nginx'
    }

    It '0* (K* from the start) returns the whole line' {
        Select-BangWords -Words $Words -Selector '0*' | Should -Be ($Words -join ' ')
    }

    It '0-7 (full range) returns the whole line' {
        Select-BangWords -Words $Words -Selector '0-7' | Should -Be ($Words -join ' ')
    }

    It 'a degenerate range A-A returns just that one word' {
        Select-BangWords -Words $Words -Selector '4-4' | Should -Be 'api'
    }

    It 'a mid-range A-B returns the inclusive slice' {
        Select-BangWords -Words $Words -Selector '3-5' | Should -Be '--name api -p'
    }

    It 'gs escapes regex metacharacters in the search text (literal "." not "any character")' {
        $words2 = Split-BangWords -Line 'docker build -t myapp:v1.2.3 .'
        Select-BangWords -Words $words2 -Selector 'gs/./X/' | Should -Be 'docker build -t myapp:v1X2X3 X'
    }

    It 'gs replaces every occurrence, not just the first' {
        Select-BangWords -Words $Words -Selector 'gs/-/_/' | Should -Be 'docker run _d __name api _p 8080:80 nginx'
    }
}

Describe 'Get-BangCommandLine - edge cases' {
    It '@0 resolves the first (oldest) history entry by absolute id' {
        Get-BangCommandLine -Ref '@0' | Should -Be 'git status'
    }

    It '@5 resolves the last (newest) history entry by absolute id' {
        Get-BangCommandLine -Ref '@5' | Should -Be 'git push origin mian'
    }

    It '@N returns $null for an id beyond the end of history' {
        Get-BangCommandLine -Ref '@6' | Should -BeNullOrEmpty
    }

    It 'prefix matching is case-insensitive' {
        Get-BangCommandLine -Ref '@GIT' | Should -Be 'git push origin mian'
    }

    It 'prefix matching returns $null when no command starts with that prefix' {
        Get-BangCommandLine -Ref '@xyz' | Should -BeNullOrEmpty
    }

    It '@[text] substring search returns the most recent of several matches' {
        # "git" appears as a substring in three different entries; last one wins
        Get-BangCommandLine -Ref '@[git]' | Should -Be 'git push origin mian'
    }

    It '@-N at exactly buffer.Count resolves the oldest entry (boundary case)' {
        Get-BangCommandLine -Ref '@-6' | Should -Be 'git status'
    }

    It '@-N one past buffer.Count returns $null' {
        Get-BangCommandLine -Ref '@-7' | Should -BeNullOrEmpty
    }

    It '@-0 (zero offset) returns $null, not the newest entry' {
        Get-BangCommandLine -Ref '@-0' | Should -BeNullOrEmpty
    }
}

Describe 'Expand-BangHistory - multiple and adjacent tokens' {
    It 'expands two independent tokens separated by other text' {
        Expand-BangHistory -Line 'diff @-3:$ @-1:$' | Should -Be 'diff "fix bug" mian'
    }

    It 'expands two tokens with no separating space, concatenating the results' {
        Expand-BangHistory -Line 'echo @-3:^@-3:$' | Should -Be 'echo commit"fix bug"'
    }

    It 'expands the same token twice, independently, in one line' {
        Expand-BangHistory -Line '@@ && @@' | Should -Be 'git push origin mian && git push origin mian'
    }

    It 'expands a token sandwiched between literal words' {
        Expand-BangHistory -Line 'run: @-3:0 now' | Should -Be 'run: git now'
    }

    It 'expands a $ shorthand and an explicit-selector token together' {
        Expand-BangHistory -Line 'mv @$ @-3:0' | Should -Be 'mv mian git'
    }

    It 'expands a * shorthand and an absolute-id token together' {
        Expand-BangHistory -Line 'echo @* then @2' | Should -Be 'echo push origin mian then docker run -d --name api-server -p 8080:80 nginx'
    }

    It 'quick-sub ^old^new (no trailing caret) works the same as the trailing-caret form' {
        Expand-BangHistory -Line '^mian^main' | Should -Be 'git push origin main'
    }

    It 'quick-sub with an empty replacement removes the text, leaving the surrounding spaces' {
        Expand-BangHistory -Line '^origin^^' | Should -Be 'git push  mian'
    }
}

Describe 'Expand-BangHistory - real-world gotchas' {
    It 'leaves an email address alone when the part after @ matches no command prefix' {
        Expand-BangHistory -Line 'contact user@example.com for help' | Should -Be 'contact user@example.com for help'
    }

    It 'DOES expand a trailing @N in a word like a branch name, with no inserted space — a real footgun' {
        # "feature@2" is read as literal text "feature" + token "@2", which
        # resolves to the full text of history event 2 with no separator.
        Expand-BangHistory -Line 'checkout feature@2' | Should -Be 'checkout featuredocker run -d --name api-server -p 8080:80 nginx'
    }

    It 'DOES expand @word inside ordinary prose if the word happens to prefix-match history' {
        Expand-BangHistory -Line 'please @git it' | Should -Be 'please git push origin mian it'
    }

    It 'a bare @ with nothing valid following it is left untouched' {
        Expand-BangHistory -Line 'foo @ bar' | Should -Be 'foo @ bar'
    }
}

Describe 'Expand-BangHistory - gs and quick-sub edge cases' {
    It 'gs with search text that does not appear leaves the command unchanged' {
        Expand-BangHistory -Line '@@:gs/nonexistent/x/' | Should -Be 'git push origin mian'
    }

    It 'gs on an absolute-id ref escapes "." correctly' {
        Expand-BangHistory -Line '@4:gs/./_/' | Should -Be 'docker build -t myapp:v1_2_3 _'
    }

    It 'gs matching is case-insensitive (PowerShell -replace default)' {
        Expand-BangHistory -Line '@2:gs/NGINX/apache/' | Should -Be 'docker run -d --name api-server -p 8080:80 apache'
    }

    It 'gs replaces every occurrence across the whole command, not just the first' {
        Expand-BangHistory -Line '@2:gs/-/_/' | Should -Be 'docker run _d __name api_server _p 8080:80 nginx'
    }

    It 'quick-sub ^old^new^ replaces only the FIRST occurrence, unlike gs' {
        # "i" appears in "git", "origin", and "mian" — only the one in "git" changes
        Expand-BangHistory -Line '^i^I^' | Should -Be 'gIt push origin mian'
    }

    It 'gs can target a search string that includes its own leading space to avoid a leftover double space' {
        Expand-BangHistory -Line '@@:gs/ mian//' | Should -Be 'git push origin'
    }
}

Describe 'Resolve-BangHistoryExpansion - additional cases' {
    It 'returns expanded text for a K-selector token' {
        Resolve-BangHistoryExpansion -Line '@-3:0' | Should -Be 'git'
    }

    It 'returns $null when the only @ present fails to resolve to anything' {
        Resolve-BangHistoryExpansion -Line 'echo @nosuchcmd' | Should -BeNullOrEmpty
    }

    It 'returns expanded text for the quick-sub ^old^new^ form' {
        Resolve-BangHistoryExpansion -Line '^mian^main^' | Should -Be 'git push origin main'
    }

    It 'returns $null for an email address (mirrors the Expand-BangHistory gotcha test)' {
        Resolve-BangHistoryExpansion -Line 'user@example.com' | Should -BeNullOrEmpty
    }
}

Describe 'Show-BangHistoryHelp' {
    It 'does not throw when invoked' {
        { Show-BangHistoryHelp } | Should -Not -Throw
    }

    It 'is registered as a callable command' {
        Get-Command Show-BangHistoryHelp -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Select-BangWords - single-word array quirks' {
    BeforeAll {
        $script:OneWord = Split-BangWords -Line 'ls'
        $script:TwoWords = Split-BangWords -Line 'git status'
    }

    It '* on a one-word array produces a leading-space artifact (PowerShell''s 1..0 descending range)' {
        # Words.Count-1 = 0, so the code evaluates $Words[1..0], which
        # PowerShell expands to the descending sequence (1,0) rather than an
        # empty range. Indexing [1] is out of bounds ($null), [0] is 'ls'.
        Select-BangWords -Words $OneWord -Selector '*' | Should -Be ' ls'
    }

    It '1* on a one-word array hits the same descending-range artifact' {
        Select-BangWords -Words $OneWord -Selector '1*' | Should -Be ' ls'
    }

    It '^ on a one-word array returns $null (no word at index 1)' {
        Select-BangWords -Words $OneWord -Selector '^' | Should -BeNullOrEmpty
    }

    It '$ on a one-word array still returns that word' {
        Select-BangWords -Words $OneWord -Selector '$' | Should -Be 'ls'
    }

    It '0 on a one-word array returns the command name' {
        Select-BangWords -Words $OneWord -Selector '0' | Should -Be 'ls'
    }

    It '0* on a one-word array returns just that word, no artifact' {
        Select-BangWords -Words $OneWord -Selector '0*' | Should -Be 'ls'
    }

    It 'an out-of-range plain integer selector returns $null' {
        Select-BangWords -Words $TwoWords -Selector '9' | Should -BeNullOrEmpty
    }

    It 'an unrecognized selector falls through to the default case (whole line)' {
        Select-BangWords -Words $TwoWords -Selector 'zzz' | Should -Be 'git status'
    }

    It 'a leading zero in a numeric selector is parsed as decimal, not octal' {
        $words = Split-BangWords -Line 'docker run -d --name api -p 8080:80 nginx'
        Select-BangWords -Words $words -Selector '07' | Should -Be 'nginx'
    }

    It 'gs replaces a whole word that matches the search text exactly' {
        Select-BangWords -Words $TwoWords -Selector 'gs/status/state/' | Should -Be 'git state'
    }
}

Describe 'Split-BangWords - more tokenizing edge cases' {
    It 'a tab character also separates words' {
        (Split-BangWords -Line "git`tstatus") -join '|' | Should -Be 'git|status'
    }

    It 'unquoted text glued directly AFTER a quoted chunk still combines into one token' {
        (Split-BangWords -Line 'echo "foo bar"baz')[1] | Should -Be '"foo bar"baz'
    }

    It 'quote-text-quote glues into a single token across three pieces' {
        (Split-BangWords -Line 'echo "a"mid"b"')[1] | Should -Be '"a"mid"b"'
    }

    It 'an empty pair of quotes still counts as its own token' {
        (Split-BangWords -Line 'echo ""').Count | Should -Be 2
    }

    It 'a newline between words is treated the same as a space' {
        (Split-BangWords -Line "git`nstatus") -join '|' | Should -Be 'git|status'
    }

    It 'a punctuation-only line with no letters still tokenizes as one word' {
        Split-BangWords -Line '---' | Should -Be '---'
    }

    It 'a literal backslash inside a quoted argument is preserved as-is (no escaping logic)' {
        (Split-BangWords -Line 'echo "C:\path\to\file"')[1] | Should -Be '"C:\path\to\file"'
    }

    It 'double- and single-quoted tokens in the same line are each their own word' {
        (Split-BangWords -Line "echo `"a`" 'b'").Count | Should -Be 3
    }

    It 'an unterminated quote is silently dropped, not kept as a literal character' {
        # No closing " means the quoted-string alternative can never match, and
        # the excluded-character class can't consume a bare quote either — so
        # the stray " matches nothing and is simply skipped.
        (Split-BangWords -Line 'echo "unterminated')[1] | Should -Be 'unterminated'
    }
}

Describe 'Get-BangCommandLine - more edge cases' {
    It 'when two commands share a prefix, the most recent one wins' {
        Get-BangCommandLine -Ref '@docker' | Should -Be 'docker build -t myapp:v1.2.3 .'
    }

    It 'a prefix with no matching command at all returns $null, even if syntactically valid' {
        Get-BangCommandLine -Ref '@_nope' | Should -BeNullOrEmpty
    }

    It 'prefix matching allows a literal dot in the prefix text' {
        Get-BangCommandLine -Ref '@vim' | Should -Be 'vim server.config.json'
    }

    It '@[text] with a uniquely-matching substring returns that one entry' {
        Get-BangCommandLine -Ref '@[server.config]' | Should -Be 'vim server.config.json'
    }

    It '@[text] treats an embedded "*" as a -like wildcard, not literal text — a real gotcha' {
        # "docker*nginx" never appears literally, but as a wildcard pattern
        # "*docker*nginx*" it matches anything starting with docker and
        # ending in nginx somewhere later.
        Get-BangCommandLine -Ref '@[docker*nginx]' | Should -Be 'docker run -d --name api-server -p 8080:80 nginx'
    }

    It '@[text] treats an embedded "?" as a single-character wildcard too' {
        Get-BangCommandLine -Ref '@[gi?]' | Should -Be 'git push origin mian'
    }

    It 'a ref that matches no branch at all (bare @) returns $null' {
        Get-BangCommandLine -Ref '@' | Should -BeNullOrEmpty
    }

    It 'empty brackets @[] match no branch and return $null' {
        Get-BangCommandLine -Ref '@[]' | Should -BeNullOrEmpty
    }

    It 'a prefix ref may syntactically include a slash, even with nothing to match' {
        Get-BangCommandLine -Ref '@a/b' | Should -BeNullOrEmpty
    }
}

Describe 'Expand-BangHistory - more combinations' {
    It '@N:* is not touched by the @* shorthand normalization step' {
        Expand-BangHistory -Line '@0:*' | Should -Be 'status'
    }

    It '@N:$ resolves correctly on a short two-word command' {
        Expand-BangHistory -Line '@0:$' | Should -Be 'status'
    }

    It '@N:^ resolves correctly on a short two-word command' {
        Expand-BangHistory -Line '@0:^' | Should -Be 'status'
    }

    It 'a @$ shorthand and a separate @N token combine in one line' {
        Expand-BangHistory -Line 'diff @$ @0' | Should -Be 'diff mian git status'
    }

    It 'two @$ shorthand tokens in one line both resolve independently' {
        Expand-BangHistory -Line '@$ @$' | Should -Be 'mian mian'
    }

    It 'a full 0-7 range on an 8-word command reconstructs the whole line' {
        Expand-BangHistory -Line '@2:0-7' | Should -Be 'docker run -d --name api-server -p 8080:80 nginx'
    }

    It 'K* mid-range on a longer command returns words K..end' {
        Expand-BangHistory -Line '@2:5*' | Should -Be '-p 8080:80 nginx'
    }

    It 'a prefix-match ref combined with a word-range selector' {
        Expand-BangHistory -Line '@docker:0-1' | Should -Be 'docker build'
    }

    It 'a substring-match ref combined with the $ selector' {
        Expand-BangHistory -Line '@[myapp]:$' | Should -Be '.'
    }

    It 'an unresolved token next to a resolved one — only the resolvable one expands' {
        Expand-BangHistory -Line '@nosuch @0' | Should -Be '@nosuch git status'
    }

    It 'two explicit absolute-id refs to same-prefix commands both resolve independently' {
        Expand-BangHistory -Line '@2:0 vs @4:0' | Should -Be 'docker vs docker'
    }
}

Describe 'Resolve-BangHistoryExpansion - more cases' {
    It 'returns expanded text for a range-selector token' {
        Resolve-BangHistoryExpansion -Line '@2:0-1' | Should -Be 'docker run'
    }

    It 'returns $null for a line with only an unresolved prefix ref' {
        Resolve-BangHistoryExpansion -Line '@nosuchcmd2' | Should -BeNullOrEmpty
    }

    It 'returns expanded text when two shorthand tokens are both present' {
        Resolve-BangHistoryExpansion -Line '@$ @$' | Should -Be 'mian mian'
    }

    It 'returns $null for a bare @ with nothing valid following it' {
        Resolve-BangHistoryExpansion -Line 'user @ here' | Should -BeNullOrEmpty
    }

    It 'still expands the branch-name gotcha case — Resolve adds no extra safety' {
        Resolve-BangHistoryExpansion -Line 'checkout feature@2' | Should -Be 'checkout featuredocker run -d --name api-server -p 8080:80 nginx'
    }

    It 'returns $null for a plain command with no tokens at all' {
        Resolve-BangHistoryExpansion -Line 'ls -la' | Should -BeNullOrEmpty
    }

    It 'quick-sub on a match in the middle of the command still works via Resolve' {
        Resolve-BangHistoryExpansion -Line '^push^pull^' | Should -Be 'git pull origin mian'
    }
}

Describe 'Show-BangHistoryHelp - output content' {
    It 'produces non-empty output' {
        (Show-BangHistoryHelp | Out-String).Trim().Length | Should -BeGreaterThan 0
    }

    It 'includes the Token column header' {
        (Show-BangHistoryHelp | Out-String) | Should -Match 'Token'
    }

    It 'includes the Bash column header' {
        (Show-BangHistoryHelp | Out-String) | Should -Match 'Bash'
    }

    It 'includes the Meaning column header' {
        (Show-BangHistoryHelp | Out-String) | Should -Match 'Meaning'
    }
}