#!/usr/bin/env bash
# Prints the CHANGELOG section for a release tag, for use as the release body.
#
#   release-notes.sh vX.Y.Z[-pre][+build] [CHANGELOG.md] > notes.md
#
# Fails when the CHANGELOG has no "## [X.Y.Z]" section for the tag, when it
# has more than one, or when the top released section is a different version:
# a tag whose notes were not written is not published with somebody else's.
set -euo pipefail

tag=${1:?usage: release-notes.sh vX.Y.Z [CHANGELOG.md]}
changelog=${2:-CHANGELOG.md}
# Only a lowercase v is stripped. An uppercase "V1.2.3" therefore keeps its V,
# never matches a section heading, and is refused by the comparison below.
# That is the right answer reached indirectly: every tag in this repository is
# lowercase, so there is nothing to gain from accepting the other spelling.
version=${tag#v}

if [ ! -f "$changelog" ]; then
  echo "release-notes: $changelog does not exist" >&2
  exit 1
fi

# Carriage returns are removed once, up front. A CHANGELOG saved with CRLF
# line endings otherwise puts a \r at the end of every published line, and
# defeats every emptiness check below, because a line holding one carriage
# return is not an empty line.
body=$(tr -d '\r' < "$changelog")

# A fence that is never closed makes every line after it content, so the
# section would run past its own end and be published carrying the next
# release's notes. There is no safe guess about where the author meant it to
# close, so the release is refused instead. Fences are recognised wherever
# they are indented to: a heading inside an indented block is an example, and
# reading it as the end of the section silently truncated the notes.
if printf '%s\n' "$body" | awk '
  /^[[:blank:]]*(```|~~~)/ { fence = !fence }
  END { exit fence ? 0 : 1 }
'; then
  echo "release-notes: $changelog has a code fence that is never closed" >&2
  exit 1
fi

# A released heading is "## [<semver>]", where semver may carry a pre-release
# or build suffix. "## [Unreleased]" is not one.
heading='^## \[[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]*)?\]'
top=$(printf '%s\n' "$body" | grep -m1 -oE "$heading" | sed -e 's/^## \[//' -e 's/\]$//' || true)
if [ -z "$top" ]; then
  echo "release-notes: $changelog has no released section" >&2
  exit 1
fi
if [ "$top" != "$version" ]; then
  echo "release-notes: the top released section of $changelog is $top, but the tag is $tag" >&2
  exit 1
fi

# Headings are counted where they are headings: at the start of a line and
# outside a fenced code block. Counting the string anywhere on a line made a
# release note that quotes its own heading in prose look like a second copy
# of the section, which blocked a legitimate release.
count=$(printf '%s\n' "$body" | awk -v v="$version" '
  /^[[:blank:]]*(```|~~~)/ { fence = !fence; next }
  !fence && index($0, "## [" v "]") == 1 { n++ }
  END { print n + 0 }
')
if [ "$count" -ne 1 ]; then
  echo "release-notes: $changelog has $count sections headed [$version], want exactly one" >&2
  exit 1
fi

# Everything between the section heading and the next heading or the link
# definitions at the end of the file. A fenced code block inside the section
# is content: a "## [" or a "[x]: url" line inside one is an example, not the
# end of the section, and treating it as the end silently truncated the notes.
notes=$(printf '%s\n' "$body" | awk -v v="$version" '
  /^[[:blank:]]*(```|~~~)/ { fence = !fence; if (on) print; next }
  !fence && on && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  !fence && index($0, "## [" v "]") == 1 { on = 1; next }
  on { print }
')

# Trim blank lines from both ends, where a line of only spaces or tabs is
# blank. A section holding nothing but whitespace was published as whitespace.
notes=$(printf '%s\n' "$notes" | awk '
  { line[NR] = $0; if ($0 ~ /[^[:space:]]/) { if (!first) first = NR; last = NR } }
  END { for (i = first; i <= last; i++) print line[i] }
')
if [ -z "$notes" ]; then
  echo "release-notes: the $version section of $changelog is empty" >&2
  exit 1
fi
printf '%s\n' "$notes"
