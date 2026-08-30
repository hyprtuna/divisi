## What this changes

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. Link an issue if there is one. -->

## Verification

<!--
What did you actually run? Paste the output. "Should work" is not verification.
-->

- [ ] `gdformat --check` is clean
- [ ] `gdlint` is clean
- [ ] gdUnit4 headless tests pass on Godot 4.4
- [ ] gdUnit4 headless tests pass on Godot 4.7
- [ ] No em or en dashes (`git grep -nP '\x{2014}|\x{2013}'` is empty)
- [ ] New behaviour has a test that fails without the change

## If this touches the clock or scheduling

- [ ] The engine behaviour relied on is cited in a comment, against upstream
      source or docs, with the engine version it was checked against
- [ ] The change was listened to on real hardware, not only tested
- [ ] The demo readout was watched for at least a minute: bar:beat stayed on
      the music and no beats were reported skipped
