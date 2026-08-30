#!/usr/bin/env bash
# Tests for release-notes.sh. Run from the repository root; the gate runs it.
set -uo pipefail
script=$(dirname "$0")/release-notes.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# expect_notes NAME TAG FILE EXPECTED: the script prints exactly EXPECTED.
expect_notes() {
  local got
  if got=$("$script" "$2" "$3" 2>"$tmp/err") && [ "$got" = "$4" ]; then ok "$1"; else bad "$1: got '$got' err '$(cat "$tmp/err")'"; fi
}
# expect_fail NAME TAG FILE SUBSTRING: the script fails and the message contains SUBSTRING.
expect_fail() {
  local err
  if "$script" "$2" "$3" >"$tmp/out" 2>"$tmp/err"; then bad "$1: succeeded with '$(cat "$tmp/out")'"; return; fi
  err=$(cat "$tmp/err")
  case "$err" in *"$4"*) ok "$1";; *) bad "$1: message '$err' lacks '$4'";; esac
}

cat > "$tmp/plain.md" <<'MD'
# Changelog

## [Unreleased]

## [1.2.3] - 2026-01-01

- one
- two

## [1.2.2] - 2025-12-01

- old

[Unreleased]: https://example/compare/v1.2.3...HEAD
[1.2.3]: https://example/compare/v1.2.2...v1.2.3
MD
expect_notes "plain section" v1.2.3 "$tmp/plain.md" $'- one\n- two'
expect_notes "tag without v" 1.2.3 "$tmp/plain.md" $'- one\n- two'
expect_fail "older tag than the top section" v1.2.2 "$tmp/plain.md" "top released section of $tmp/plain.md is 1.2.3, but the tag is v1.2.2"
expect_fail "unknown tag" v9.9.9 "$tmp/plain.md" "but the tag is v9.9.9"
expect_fail "missing file" v1.2.3 "$tmp/absent.md" "does not exist"

cat > "$tmp/pre.md" <<'MD'
## [Unreleased]

## [2.0.0-rc.1] - 2026-02-01

- candidate

## [1.2.3] - 2026-01-01

- one
MD
expect_notes "pre-release tag" v2.0.0-rc.1 "$tmp/pre.md" "- candidate"
expect_fail "release tag while a pre-release is on top" v1.2.3 "$tmp/pre.md" "top released section of $tmp/pre.md is 2.0.0-rc.1"

cat > "$tmp/build.md" <<'MD'
## [1.0.0+build.5] - 2026-03-01

- built
MD
expect_notes "build metadata tag" v1.0.0+build.5 "$tmp/build.md" "- built"

cat > "$tmp/dup.md" <<'MD'
## [1.2.3] - 2026-01-01

- first copy

## [1.2.3] - 2026-01-01

- second copy
MD
expect_fail "duplicated section" v1.2.3 "$tmp/dup.md" "has 2 sections headed [1.2.3], want exactly one"

cat > "$tmp/unreleased.md" <<'MD'
## [Unreleased]

- not yet

## [1.2.3] - 2026-01-01

- one
MD
expect_notes "Unreleased with content on top is skipped" v1.2.3 "$tmp/unreleased.md" "- one"

cat > "$tmp/empty.md" <<'MD'
## [1.2.3] - 2026-01-01

## [1.2.2] - 2025-12-01

- old
MD
expect_fail "empty section" v1.2.3 "$tmp/empty.md" "the 1.2.3 section of $tmp/empty.md is empty"

printf '# Changelog\n\nnothing released\n' > "$tmp/none.md"
expect_fail "no released section" v1.2.3 "$tmp/none.md" "has no released section"

# A body with no non-whitespace character is empty, whatever it is made of.
# A section of spaces or tabs used to be published as spaces or tabs.
printf '## [1.2.3] - 2026-01-01\n   \n\t\n## [1.2.2]\n\n- old\n' > "$tmp/spaces.md"
expect_fail "body of only spaces and tabs" v1.2.3 "$tmp/spaces.md" "the 1.2.3 section of $tmp/spaces.md is empty"

# CRLF. Carriage returns must not reach the body, and a section that is empty
# apart from them must be refused rather than published as bare returns.
printf '# Changelog\r\n\r\n## [1.2.3] - 2026-01-01\r\n\r\n- one\r\n- two\r\n\r\n## [1.2.2]\r\n\r\n- old\r\n' > "$tmp/crlf.md"
expect_notes "CRLF changelog" v1.2.3 "$tmp/crlf.md" $'- one\n- two'
printf '## [1.2.3] - 2026-01-01\r\n\r\n\r\n## [1.2.2]\r\n\r\n- old\r\n' > "$tmp/crlf_empty.md"
expect_fail "CRLF empty section" v1.2.3 "$tmp/crlf_empty.md" "the 1.2.3 section of $tmp/crlf_empty.md is empty"
printf '# Changelog\r\n\r\n## [1.2.3]\r\n\r\n- one\r\n\r\n## [1.2.3]\r\n\r\n- again\r\n' > "$tmp/crlf_dup.md"
expect_fail "CRLF duplicated section" v1.2.3 "$tmp/crlf_dup.md" "has 2 sections headed [1.2.3]"
printf '# Changelog\r\n\r\n## [1.2.3]\r\n\r\n- one\r\n' > "$tmp/crlf_top.md"
expect_fail "CRLF wrong top version" v1.2.2 "$tmp/crlf_top.md" "is 1.2.3, but the tag is v1.2.2"

# A fenced code block is content. A heading or a link definition inside one is
# an example, and treating it as the end of the section silently dropped
# everything after it.
cat > "$tmp/fence_heading.md" <<'MD'
## [1.2.3] - 2026-01-01

- before the fence

```
## [9.9.9] - 1999-01-01
```

- after the fence

## [1.2.2]

- old
MD
expect_notes "heading inside a fence" v1.2.3 "$tmp/fence_heading.md" \
  $'- before the fence\n\n```\n## [9.9.9] - 1999-01-01\n```\n\n- after the fence'

cat > "$tmp/fence_link.md" <<'MD'
## [1.2.3] - 2026-01-01

- before the fence

```
[example]: https://example.invalid/x
```

- after the fence

[1.2.3]: https://example/compare/v1.2.2...v1.2.3
MD
expect_notes "link definition inside a fence" v1.2.3 "$tmp/fence_link.md" \
  $'- before the fence\n\n```\n[example]: https://example.invalid/x\n```\n\n- after the fence'

# Tilde fences are fences too.
cat > "$tmp/fence_tilde.md" <<'MD'
## [1.2.3] - 2026-01-01

~~~
## [9.9.9]
~~~

- after
MD
expect_notes "tilde fence" v1.2.3 "$tmp/fence_tilde.md" $'~~~\n## [9.9.9]\n~~~\n\n- after'

# A duplicate heading inside a fence is an example, not a second section.
cat > "$tmp/fence_dup.md" <<'MD'
## [1.2.3] - 2026-01-01

```
## [1.2.3]
```

- real content
MD
expect_notes "a heading inside a fence is not a second section" v1.2.3 "$tmp/fence_dup.md" \
  $'```\n## [1.2.3]\n```\n\n- real content'

# Counting the string anywhere on a line made a note that quotes its own
# heading in prose look like a second copy, which blocked the release.
cat > "$tmp/prose.md" <<'MD'
## [1.2.3] - 2026-01-01

- the section headed `## [1.2.3]` is written by hand
MD
expect_notes "a heading quoted in prose is not a second section" v1.2.3 "$tmp/prose.md" \
  '- the section headed `## [1.2.3]` is written by hand'

# An indented fence is a fence. Matching only at column 1 let a heading
# inside an indented block end the section, and the notes were published
# truncated to whatever came before it.
cat > "$tmp/fence_indented.md" <<'MD'
## [1.2.3] - 2026-01-01

- before the fence

    ```
## [9.9.9] - 1999-01-01
    ```

- after the fence

## [1.2.2] - 2025-12-01

- old
MD
expect_notes "an indented fence is a fence" v1.2.3 "$tmp/fence_indented.md" \
  $'- before the fence\n\n    ```\n## [9.9.9] - 1999-01-01\n    ```\n\n- after the fence'

# The same block, counted: a duplicate heading inside an indented fence is an
# example, not a second section, and must not block the release.
cat > "$tmp/fence_indented_dup.md" <<'MD'
## [1.2.3] - 2026-01-01

  ~~~
## [1.2.3]
  ~~~

- real content
MD
expect_notes "a heading inside an indented fence is not a second section" v1.2.3 "$tmp/fence_indented_dup.md" \
  $'  ~~~\n## [1.2.3]\n  ~~~\n\n- real content'

# A fence nobody closed swallows every section below it. Publishing an older
# release's notes under this tag is worse than publishing nothing.
cat > "$tmp/fence_unclosed.md" <<'MD'
## [1.2.3] - 2026-01-01

- one

```
## [1.2.2] - 2025-12-01

- old
MD
expect_fail "an unclosed fence" v1.2.3 "$tmp/fence_unclosed.md" "code fence that is never closed"

cat > "$tmp/fence_unclosed_indented.md" <<'MD'
## [1.2.3] - 2026-01-01

- one

    ~~~
- two
MD
expect_fail "an unclosed indented fence" v1.2.3 "$tmp/fence_unclosed_indented.md" "code fence that is never closed"

# A real duplicate is still a duplicate, fences and prose notwithstanding.
cat > "$tmp/real_dup.md" <<'MD'
## [1.2.3] - 2026-01-01

- first

## [1.2.3] - 2026-01-01

- second
MD
expect_fail "a real duplicate outside any fence" v1.2.3 "$tmp/real_dup.md" "has 2 sections headed [1.2.3]"

# An uppercase V keeps its V, matches no heading, and is refused. Recorded so
# that a change to the tag handling cannot quietly start accepting it.
expect_fail "uppercase V tag" V1.2.3 "$tmp/plain.md" "but the tag is V1.2.3"

# And the repository's own CHANGELOG, which is what the gate runs.
top=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]*)?\]' CHANGELOG.md | sed -e 's/^## \[//' -e 's/\]$//')
if "$script" "v$top" CHANGELOG.md >/dev/null 2>"$tmp/err"; then
  ok "the repository's own top section extracts"
else
  bad "the repository's own top section: $(cat "$tmp/err")"
fi

exit $fail
