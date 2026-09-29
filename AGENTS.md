# Working in this repository

Guidance for contributors and for agents making changes here.

## What this is

A pair of Windows-only PowerShell scripts, plus a cross-platform emulation
harness. The scripts are the product: `ComputerReport.ps1` collects Active
Directory computer information into a CSV, and `Add-DhcpScopeColumns.ps1` adds
DHCP scope columns to that CSV. The harness exists so both can be run and
reviewed without a domain controller, without a DHCP server, without RSAT and
without Windows.

## Non-negotiables

- Keep the emulator working. `emulator/Invoke-Emulation.ps1` invokes
  `ComputerReport.ps1` with parameters rather than copying or rewriting it, so
  the emulation cannot drift from the real code path. If you add, rename or
  remove a parameter, update the harness in the same change and re-run it. A
  broken parameter binding must fail loudly there rather than silently testing
  a stale copy.
- Never commit real directory data. `.gitignore` excludes the production input
  and output filenames and re-includes only the invented sample files. Keep
  that arrangement, and read `examples/` before committing anything that came
  from a live environment.
- The sample output is generated, not hand-written. Regenerate it with
  `pwsh ./emulator/Invoke-Emulation.ps1` instead of editing
  `examples/ComputerInformation.sample.csv`.
- Write plain text. No emoji, in code, comments, documentation or commit
  messages.
- Never make a script's own parameter mandatory, meaning one in the `param`
  block at the top of the file. A mandatory parameter stops the script and asks
  for it interactively, which breaks unattended use from a scheduled task or a
  pipeline and is a poor first run besides. Give the parameter a default, and
  where there is no sensible default, such as the DHCP server address, check for
  it and fail with a message that says what to pass. Both scripts must run to a
  clear error, never to a prompt, when invoked with no arguments.
- Parameters of helper functions inside a script are a separate case and may
  stay mandatory. The script always supplies them, so their absence is a
  programming error rather than a user error, and being mandatory makes that
  error loud.

## Conventions

- Commits follow Conventional Commits: `type(scope): subject`, imperative
  mood, lowercase, no trailing period, at most 72 characters, followed by a
  body covering summary, context, scope, verification and known limitations.
- Branching is Git Flow style: `dev` is the integration branch and `main` is
  production. Work lands on a short-lived branch and reaches `main` through a
  reviewed pull request.
- PowerShell style: four-space indentation, parameters continued with a
  trailing backtick, `Write-Host` for console output. Static analysis flags
  `Write-Host`; that finding is accepted here, because the script's entire
  interface is coloured console output.

## Session continuity

Session-continuity artifacts for this project, the handoff and the memory
entry, are kept outside this repository because they record machine-local
state. A future session on the owning machine reaches them through the project
memory entry rather than through this file.

## Before calling a change done

1. Run `pwsh ./emulator/Invoke-Emulation.ps1` and confirm both summaries
   reconcile: in the report, found equals resolved plus no-IPv4-record plus
   failed; in the enrichment, the rows total equals in-a-scope plus excluded
   plus not-in-any-scope plus no-IP-address.
2. Run PSScriptAnalyzer (`Invoke-ScriptAnalyzer -Path <script>`) on every
   changed script and confirm no findings other than `PSAvoidUsingWriteHost`.
3. If the change affects the columns, regenerate both sample CSVs and update the
   column documentation in `README.md`. The scope columns belong immediately
   after `IPAddress`; keep them there.
4. If a change touches the subnet arithmetic, run the boundary cases: the last
   address in a range, the first address past it, an address one past the
   subnet, and a non-`/24` mask.
