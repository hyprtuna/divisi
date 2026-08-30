# Security policy

## Reporting a vulnerability

Report privately through GitHub Security Advisories:

https://github.com/hyprtuna/divisi/security/advisories/new

If that page is unavailable to you, open an issue using the "Security
contact" template. Do not put any details of the vulnerability in that
issue: say only that you have something to report, and you will be contacted
for the details.

Please do not open a public issue describing a vulnerability.

## Scope

divisi is an addon that runs inside your own game. It reads audio streams
you supply, and holds a dictionary in an autoload. It opens no sockets,
accepts no remote input, executes nothing it is given, and does not write to
disk.

The things worth scrutiny are:

- Resource loading of untrusted `.tres` section or layer files, if a game
  loads one from somewhere other than its own project.
- The `DivisiState` autoload's dictionary, and anything that could turn it
  into a vector, such as a game that feeds it externally supplied data
  rather than a `DivisiPlayer`'s own state.

## Supported versions

The most recent release is supported.
