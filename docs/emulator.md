# The emulation harness

`emulator/` exists so the script can be run and inspected without a domain
controller, without RSAT and without Windows. It is also what produced
`examples/ComputerInformation.sample.csv`.

## Running it

```bash
pwsh ./emulator/Invoke-Emulation.ps1
```

Optional arguments:

| Argument | Purpose |
| --- | --- |
| `-OutputFile <path>` | Write the CSV somewhere else. Defaults to `examples/ComputerInformation.sample.csv`. |
| `-RunNslookup` | Pass the switch through to the report script. Not useful off Windows, where there is no `nslookup.exe`. |

## What it does

`Invoke-Emulation.ps1` does four things and nothing else:

1. Prepends `emulator/stubs` to `PSModulePath`, so the stub `ActiveDirectory`
   module shadows any real one.
2. Dot-sources `emulator/stubs/Resolve-DnsName.ps1`, defining a function of the
   same name as the Windows cmdlet, which functions take precedence over.
3. Invokes the real `ComputerReport.ps1` with `-InputFile`, `-OutputFile` and
   `-SearchBase`. The script is never edited, copied or rewritten: it is
   called exactly the way it is called in production, with parameters.
4. Prints where the emulated CSV went.

Because the script is invoked rather than modified, the emulation cannot drift
away from the real code path. If the script changes its parameters, this
harness fails loudly instead of silently testing a stale copy.

## The stubs

`emulator/stubs/ActiveDirectory/ActiveDirectory.psm1` answers the two cmdlets
the script calls:

- `Get-ADOrganizationalUnit` accepts any identity, so the OU check always
  passes. This is deliberate: the emulation is not testing whether an OU
  exists, it is testing what the script does with the computers.
- `Get-ADComputer` returns five invented computers.

The invented computers are chosen to cover the branches the script has:

| Computer | What it exercises |
| --- | --- |
| `PC-001` | Resolves through a CNAME, with a repeated A record, so the record-type filter and the de-duplication both run. Non-ASCII text in its description. |
| `PC-002` | Two IPv4 addresses, joined with a comma. No multi-valued attributes, so those cells are empty. |
| `PC-003` | Resolves to an IPv6 address only, so the script reports no IPv4 record. |
| `PC-004` | No DNS host name in the directory, so the fallback to the computer name runs, and that name does not resolve. Also has null attributes. |
| `PC-005` | Present in the OU but never requested, so it appears only in the loaded count. |

Each object also carries the bookkeeping properties the real module adds
(`PropertyNames`, `AddedProperties`, `RemovedProperties`, `ModifiedProperties`,
`PropertyCount`), so the script's habit of skipping those as columns is
exercised rather than assumed.

`emulator/stubs/Resolve-DnsName.ps1` invents the DNS answers: `pc-001` and
`pc-002` resolve, `pc-003` has only a AAAA record, and everything else fails.
It raises a real error for the failing names, so the script's `catch` block is
what produces `DNS lookup failed`.

## Extending the sample data

Add a computer to the `Get-ADComputer` function in the stub module and a
matching line in `examples/ComputerList.sample.txt`, then run the harness
again. Keep the stub's answers and the DNS stub consistent with each other, or
a name will resolve to something the directory does not know about.

To emulate a directory where the OU check fails, make
`Get-ADOrganizationalUnit` throw.

## What the emulation does not prove

- It says nothing about whether your real OU exists, or whether your account
  may read it.
- The attribute set is invented and small. A real
  `Get-ADComputer -Properties *` returns far more attributes, so a real CSV is
  much wider than the sample.
- The DNS answers are invented, so the resolved, unresolved and IPv6-only
  cases are illustrations, not measurements of your DNS.
- It runs on PowerShell 7. The script's Windows PowerShell 5.1 path, including
  its encoding branch, is not exercised here.
