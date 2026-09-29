# QA gate waiver

Recorded under the project guardrail for the QA-tester gate, because a waived
gate must never be silent.

**Project:** ad-computer-report
**Date:** 2026-09-29
**Decision:** the AI QA-tester gate is waived for this repository.
**Waived by:** the repository owner, explicitly, when the repository was
created. This is an operator decision, not an agent default.

## Scope of the waiver

The waiver covers this repository as it stands: one PowerShell script, one
emulation harness, documentation and sample data. It exists because this is a
lightweight, single-script project with no service, no API surface, no
database and no client, which is the case the guardrail names as eligible for
a recorded waiver.

The waiver does not extend to any future work that adds a runtime surface
worth testing end to end. If this repository grows a service, an API, a
scheduled job or a web client, the gate applies again and this file must be
replaced by a real QA report.

## What stands in for the gate

Two checks were run in place of a QA-tester pass, and their results are
reproducible by anyone with the repository:

1. Static analysis. PSScriptAnalyzer 1.25.0 reports no findings against
   `ComputerReport.ps1` other than `PSAvoidUsingWriteHost`, which is a style
   rule this script deliberately does not follow because its whole interface
   is coloured console output. Zero substantive findings.

2. A full execution of the script against the emulation harness, which
   exercises every branch: found and not found, resolved, no IPv4 record and
   lookup failure, a fully qualified name in the input list, a trailing dollar
   sign, a duplicate, a blank line, non-ASCII text, a multi-valued attribute, a
   binary attribute and a null attribute. The result is committed as
   `examples/ComputerInformation.sample.csv`.

## What is explicitly not covered

The script has never been executed against a real domain controller. Its
Active Directory calls are exercised only against the stub module in
`emulator/stubs`. Anything that depends on a live directory, a live DNS
server, or Windows PowerShell 5.1 remains an accepted, unverified risk.
