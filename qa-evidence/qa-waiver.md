# QA gate waiver

Recorded under the project guardrail for the QA-tester gate, because a waived
gate must never be silent.

**Project:** ad-computer-report
**Date:** 2026-09-29
**Decision:** the AI QA-tester gate is waived for this repository.
**Waived by:** the repository owner, explicitly, when the repository was
created, and confirmed again on 2026-09-29 when the second script was merged.
This is an operator decision, not an agent default.

## Scope of the waiver

The waiver covers this repository as it stands: two PowerShell scripts
(`ComputerReport.ps1` and `Add-DhcpScopeColumns.ps1`), one emulation harness,
documentation and sample data. It exists because this remains a small,
script-only project with no service, no API surface, no database, no scheduled
job and no client, which is the case the guardrail names as eligible for a
recorded waiver. The number of scripts does not change that: what the gate
exists to catch is a runtime surface exercised end to end, and there is none
here beyond the two scripts themselves, both of which are executed in full by
the harness.

The waiver does not extend to any future work that adds a runtime surface
worth testing end to end. If this repository grows a service, an API, a
scheduled job or a web client, the gate applies again and this file must be
replaced by a real QA report.

## What stands in for the gate

These checks were run in place of a QA-tester pass, and every one of them is
reproducible by anyone with the repository:

1. Static analysis. PSScriptAnalyzer 1.25.0 reports no findings against either
   script other than `PSAvoidUsingWriteHost`, a style rule these scripts
   deliberately do not follow because their entire interface is coloured
   console output. Both parse with zero errors.

2. A full execution of both scripts through the emulation harness, which
   exercises every branch of the collection stage (found and not found,
   resolved, no IPv4 record, lookup failure, a fully qualified name, a trailing
   dollar sign, a duplicate, a blank line, non-ASCII text, a multi-valued
   attribute, a binary attribute, a null attribute) and of the enrichment stage
   (in a scope, in a scope but excluded, in no scope, and no address at all).

3. Boundary tests of the subnet arithmetic, run through the real enrichment
   script against the stub server rather than by inspecting the arithmetic: the
   last address in a range, the first address past it, an address one past the
   subnet, the last excluded address, the first address after an exclusion, the
   network address, the last assignable address, an address padded with spaces,
   a two-address row matching on its second address, and a non-`/24` mask.

4. Failure-path tests with a deliberately wrong stub module, each run with the
   other failure path left healthy so neither could mask the other: a scope
   object missing `SubnetMask` and an exclusion object missing `EndRange` both
   exit 1 with a message naming the missing property, and neither writes an
   output file.

## What is explicitly not covered

Neither script has ever been executed against a real domain controller or a
real DHCP server. Their directory and DHCP calls are exercised only against the
stub modules in `emulator/stubs`. Anything that depends on a live directory, a
live DHCP server, live DNS, or Windows PowerShell 5.1 remains an accepted,
unverified risk.

In particular, the exact property set that a live `Get-DhcpServerv4Scope` and
`Get-DhcpServerv4ExclusionRange` return is not documented by the vendor and is
not confirmed here; the enrichment infers those property names from the
parameter names of the corresponding `Add-` and `Remove-` cmdlets, and fails
loudly if they are wrong rather than guessing.
