# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-29

### Added

- `Add-DhcpScopeColumns.ps1`, which reads the report produced by
  `ComputerReport.ps1`, asks a Microsoft DHCP server which IPv4 scope each
  address belongs to, and writes the rows back with `DhcpScopeName` and
  `DhcpScopeId` placed straight after `IPAddress`.
- Scope matching by subnet: an address belongs to a scope when the address ANDed
  with the scope's subnet mask equals the scope identifier and the address falls
  inside that scope's start and end range. Exclusion ranges are read too, so an
  address that sits in a scope's subnet but is excluded from it is reported as
  such instead of being counted as in-scope.
- Every address on a row is tried in turn, so a computer that resolved to
  several addresses matches if any one of them is in a scope.
- Three distinct values for the scope column when nothing matches, so a failed
  lookup cannot be mistaken for an empty one: `No IP address to look up`,
  `Not in any DHCP scope`, and `In scope but excluded`.
- A `DhcpServer` stub module for the emulation harness, with four invented
  scopes shaped to cover a plain scope, an exclusion range and a non-`/24` mask.
- Three more invented computers in the sample data, covering an address in no
  scope, an address in an exclusion range, and an address in a non-`/24` scope.

### Changed

- The enrichment validates the property names it reads from the DHCP server
  before using them. The vendor documentation for the scope and exclusion
  cmdlets names the returned CIM class but does not list its properties, so a
  wrong assumption would otherwise surface as a null-reference error, or worse,
  as a silently empty answer for an excluded address. A missing property now
  fails with a message naming the property and listing the ones actually
  present, and no output file is written.
- `emulator/Invoke-Emulation.ps1` now runs both stages and writes two sample
  CSVs, so the enrichment is emulated as well as the collection.
- `examples/ComputerInformation.sample.csv` was regenerated: the sample now
  contains nine rows instead of six, because three computers were added to
  exercise the scope matching.
- `docs/emulator.md`, `README.md` and `AGENTS.md` document the second script,
  the new columns and the boundary cases the change must not break.

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
