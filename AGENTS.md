# Working in this repository

Guidance for contributors and for agents making changes here.

## What this is

A Windows-only PowerShell script, plus a cross-platform emulation harness. The
script is the product. The harness exists so the script can be run and reviewed
without a domain controller, without RSAT and without Windows.

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

1. Run `pwsh ./emulator/Invoke-Emulation.ps1` and confirm the summary
   reconciles: found equals resolved plus no-IPv4-record plus failed.
2. Run PSScriptAnalyzer (`Invoke-ScriptAnalyzer -Path ComputerReport.ps1`) and
   confirm no findings other than `PSAvoidUsingWriteHost`.
3. If the change affects the columns, update the sample output and the column
   documentation in `README.md`.
