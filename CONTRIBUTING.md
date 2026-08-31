# Contributing to divisi

divisi schedules music against a clock a player is trusting to stay in sync.
Almost every rule below exists because a wrong answer here is audible, and
because the claims this addon makes about the engine have to be checkable.

## Development setup

You need Godot 4.4 or newer, and gdtoolkit for `gdformat` and `gdlint`:

```sh
pipx install gdtoolkit
```

(`pip install gdtoolkit` works too if you don't use pipx.) CI pins an exact
gdtoolkit release; see `.github/workflows/ci.yml` for the version, so a
mismatch can show up as a finding locally that CI does not report, or the
reverse. When that happens, CI's pinned version is the one that decides.

gdUnit4 is a dev dependency, not vendored into the repository. Download the
release your Godot version needs into the gitignored `addons/gdUnit4/`:

```sh
v=5.1.1   # gdUnit4 5.x for Godot 4.4; use 6.2.1 for Godot 4.7
curl -fsSL "https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v${v}.tar.gz" -o /tmp/gdunit4.tar.gz
mkdir -p addons/gdUnit4
tar xzf /tmp/gdunit4.tar.gz -C addons/gdUnit4 --strip-components=3 "gdUnit4-${v}/addons/gdUnit4"
chmod +x addons/gdUnit4/runtest.sh
```

gdUnit4 v6.x requires Godot 4.5 or newer, and the last v5.x release is the
newest one that still supports 4.4. There is no single gdUnit4 release that
covers both ends of this addon's own support matrix, so each leg of CI pins
the gdUnit4 release that actually runs on its Godot version. Match whichever
Godot version you're testing against locally.

## Running tests headless

A project's resources must be imported by the editor at least once before a
headless run can see them; skipping this is the usual cause of a run that
silently reports zero tests instead of running any.

```sh
godot --headless --path . --import --quit-after 1
godot --headless --path . -d --remote-debug tcp://127.0.0.1:0 \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode
```

That is not `runtest.sh`, deliberately. `runtest.sh` does not pass
`--headless`, so on a machine with no display Godot cannot create a
DisplayServer and dies before any test runs. The command above is what
`runtest.sh` builds, with `--headless` added, plus `--ignoreHeadlessMode`,
because gdUnit4 refuses to start under a headless display server unless it is
told that is deliberate. If you have a display, `./addons/gdUnit4/runtest.sh
-a test` works too, with `GODOT_BIN` exported.

Exit codes: `0` all tests passed, `100` the run ended in test failures, `101`
warnings only. Both failure codes are non-zero, so a failing run fails the
gate without any extra handling.

## Keep suite files small

gdUnit4 6.x abandons a suite file at its first failure. Every case after the red
one in that file is never run and never reported, so one broken assertion hides
however many real failures come after it, and the summary counts down from a
smaller total than the file actually holds. gdUnit4 5.x, which the Godot 4.4 leg
pins, runs the whole file, so the two legs can report different totals for the
same red change. Checked on both:

```
carry removed, divisi_player_crossfade_test.gd
  Godot 4.7.2 / gdUnit4 6.2.1: 1 test case  | 1 failures   (second case never ran)
  Godot 4.4.1 / gdUnit4 5.1.1: 2 tests cases | 3 failures
```

So split suites by subject rather than by class, and keep each file to a dozen
or so cases. The linter agrees for its own reasons: `gdlint` caps a class at
twenty public methods, which a suite file reaches at about eighteen cases.

There is a second reason to care. Showing that a new test really fails without
the change it guards means running that test on its own, and a file that abandons
itself early cannot show you the case you wanted to see.

## The gate

CI runs one job named `gate`, which requires a green result across the whole
Godot 4.4 / 4.7 test matrix. These are the commands it actually runs, and the
ones worth running yourself before you push:

```sh
gdformat --check $(git ls-files '*.gd')
gdlint $(git ls-files '*.gd')
godot --headless --path . -d --remote-debug tcp://127.0.0.1:0 \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode
git grep -nPI '\x{2014}|\x{2013}' -- .  # must find nothing
```

It also checks that `addons/divisi/plugin.cfg` exists with a plain `X.Y.Z`
version, and that the top section of `CHANGELOG.md` extracts cleanly for the
release workflow.

## The honesty rule for engine citations

Two rules, both non-negotiable.

**Any engine behaviour divisi relies on must be cited.** A comment at the top
of the file names the file and line and the engine version checked, so a
reviewer can check the claim without guessing which of several plausible
lines you meant. The real example, from `divisi_section.gd`:

```gdscript
## At runtime a section plays as one [AudioStreamSynchronized]. The engine does the mixing.
## It reads each layer's volume out of the resource on every mix chunk
## ([code]audio_stream_synchronized.cpp:231[/code] at 4.4-stable, [code]:232[/code] at
## 4.7.2-stable), so a volume written from script takes effect on the next chunk, and it
## starts every sub playback at the same position ([code]:196[/code] and [code]:197[/code]),
## so the layers are phase locked by the engine rather than by divisi.
```

If you add or change anything that leans on engine behaviour, verify it
against the tagged source at both `4.4-stable` and `4.7.2-stable` (or the
current matrix versions) before you cite it, not against memory or a blog
post.

**"Sample accurate" is not a claim divisi makes.** divisi describes its own
timing as frame accurate, latency compensated and drift free. The engine
cannot provide sample-accurate scheduling (see the README's engine facts
appendix), so those two words must never appear as a description of what
divisi does, in code, comments, docs, commit messages, release notes or a
store listing. They appear in this repository in exactly three places, and
all three are the same statement that divisi does not offer it: this
paragraph, the README's "what divisi does NOT do" table, and the header
comment of `divisi_clock.gd`. The gate does not enforce this one; reviewers
do.

## A note on .import files

The `.import` sidecars next to the demo audio carry the Loop setting and must stay committed:
without them the stems play once and the section stops. Texture `.import` files are different.
Godot 4.7 writes fields that 4.4 does not, so opening the project on one version after the
other rewrites `addons/divisi/icon.png.import` and `icon.svg.import` with no functional
change. Drop that from your diff rather than committing it. `docs/` carries a `.gdignore` so
the README images are not imported at all.

The same trap, in a different place: none of the ten `demo/sections/*.tres` files carries a
`uid=` in its `[gd_resource]` header. They load correctly without one, but the editor writes
one in the first time it saves any of them, so opening a section in the inspector and saving
produces a diff that changes nothing. Drop it, unless you are deliberately baking the uids in
across all ten at once.

## How tests are structured

Two shapes for the addon and one for the documentation. CI cannot hear any of
them.

**Pure arithmetic.** The `divisi_clock_*` suites, apart from
`divisi_clock_tick_test.gd`, drive `DivisiClock.advance_to()` and
`next_boundary()` by hand, with no `AudioStreamPlayer` and no audio device.
This is where beat and bar counting, rebasing, tempo changes, restore
sanitising and drift arithmetic should be pinned down, because a test here
needs nothing faked. `tick()` is the one path that reads a real device, and it
has a suite of its own for that reason.

**Player tests.** Tests that exercise `DivisiPlayer` run real playback under
the headless Dummy audio driver Godot uses in CI. They can assert on state
(`current_section`, `clock.position`, `layer_gains()`) but not on what
anything sounds like.

**The README's own snippet.** `divisi_readme_test.gd` pulls the quickstart out
of `README.md` and compiles it. A snippet nobody can paste is worse than no
snippet, and 0.1.0 shipped one that did not get past its parse.

Because CI cannot hear anything, audible behaviour, crossfade smoothness,
whether a stinger actually lands on the beat, whether the beat count is still
sitting on the music after ten minutes, is covered by a manual checklist a
human runs against the demo before a release. The pull request template's "If this touches the clock or
scheduling" section asks for this on any PR that touches timing.

## Commits

**Conventional Commits.** `type(scope): description`, lowercase, no trailing
full stop.

**One logical change per commit.** A commit that fixes a scheduling bug and
reformats an unrelated file is two commits.

**No em dashes or en dashes, anywhere.** Not in code, comments, docs, commit
messages or PR descriptions. Use a plain hyphen. The gate enforces it:

```sh
git grep -nPI '\x{2014}|\x{2013}'
```

That must find nothing.

## Pull requests

1. Branch, commit, push, open a PR.
2. Fill in `.github/pull_request_template.md`. The Verification section
   wants what you actually ran and its output, not "should work".
3. `gate` must be green.
4. New behaviour needs a test that fails without the change, and the failure has
   to have been seen. Revert the change in a scratch copy, run that test on its
   own, and put the red output in the PR. A test written after the fix, never
   run against the defect, certifies nothing: two of the regression tests in
   0.1.0 passed just as happily with the fix taken back out. If a case covers
   behaviour that already worked and has no defect to be red against, say so and
   show it catching a deliberate break instead.

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
