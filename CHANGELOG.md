# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-29

### Added

- `ComputerReport.ps1`, which collects Active Directory information for a list
  of computer names and exports one CSV row per requested computer.
- A parameter block, so the input file, output file, search base, delimiter and
  the optional nslookup pass are set on the command line instead of by editing
  the script.
- An emulation harness under `emulator/` that runs the real script against
  invented Active Directory objects and DNS answers, with no domain controller,
  no RSAT and no Windows required.
- `examples/ComputerList.sample.txt` and the emulated output
  `examples/ComputerInformation.sample.csv`.
- Documentation: this file, `README.md`, `docs/emulator.md`, and the recorded
  decision about the QA gate in `qa-evidence/qa-waiver.md`.

### Fixed

- The CSV is now written as UTF-8 with a byte-order mark on every PowerShell
  version. Previously the encoding depended on the host: `-Encoding UTF8`
  produces a mark in Windows PowerShell 5.1 but not in PowerShell 6 and later,
  so a run under PowerShell 7 produced a file that Excel could misread.
- The summary now accounts for every computer it found. A computer that
  resolved to no IPv4 record was counted in neither the resolved nor the failed
  total, so the numbers did not add up.
- `nslookup.exe` is no longer run and discarded. It was invoked once per
  computer and its output was thrown away, and because it shared a `try` block
  with the real lookup, a problem with it could mislabel a successful
  resolution as a DNS failure. It is now off by default and, when enabled, its
  raw output is kept in a `NslookupRaw` column in its own error scope.
- Rows are collected in a list rather than by appending to an array, which
  copied the whole array on every iteration.
- The output folder check no longer fails when the output path has no folder
  part, which made `New-Item` receive an empty path.
- The row object is now built by adding one property per column in order, so
  the column order does not depend on how a dictionary is cast to an object.
