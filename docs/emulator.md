# The emulation harness

`emulator/` exists so both scripts in this repository can be run and inspected
without a domain controller, without a DHCP server, without RSAT and without
Windows. It is also what produced `examples/ComputerInformation.sample.csv` and
`examples/ComputerInformation-Dhcp.sample.csv`.

## Running it

```bash
pwsh ./emulator/Invoke-Emulation.ps1
```

Optional arguments:

| Argument | Purpose |
| --- | --- |
| `-OutputFile <path>` | Write the collected CSV somewhere else. Defaults to `examples/ComputerInformation.sample.csv`. |
| `-DhcpOutputFile <path>` | Write the enriched CSV somewhere else. Defaults to `examples/ComputerInformation-Dhcp.sample.csv`. |
| `-RunNslookup` | Pass the switch through to the report script. Not useful off Windows, where there is no `nslookup.exe`. |

## What it does

`Invoke-Emulation.ps1` does five things and nothing else:

1. Prepends `emulator/stubs` to `PSModulePath`, so the stub `ActiveDirectory`
   and `DhcpServer` modules shadow any real ones.
2. Dot-sources `emulator/stubs/Resolve-DnsName.ps1`, defining a function of the
   same name as the Windows cmdlet, which functions take precedence over.
3. Invokes the real `ComputerReport.ps1` with `-InputFile`, `-OutputFile` and
   `-SearchBase`.
4. Invokes the real `Add-DhcpScopeColumns.ps1` on the CSV that step 3 produced.
5. Prints where both CSVs went.

Neither script is ever edited, copied or rewritten: they are called exactly the
way they are called in production, with parameters. Because of that, the
emulation cannot drift away from the real code paths. If a script renames a
parameter, this harness fails loudly instead of silently testing a stale copy.

## The stubs

### emulator/stubs/ActiveDirectory

Answers the two cmdlets `ComputerReport.ps1` calls.

- `Get-ADOrganizationalUnit` accepts any identity, so the OU check always
  passes. This is deliberate: the emulation is not testing whether an OU
  exists, it is testing what the script does with the computers.
- `Get-ADComputer` returns eight invented computers.

The invented computers are chosen to cover the branches the script has:

| Computer | What it exercises |
| --- | --- |
| `PC-001` | Resolves through a CNAME, with a repeated A record, so the record-type filter and the de-duplication both run. Non-ASCII text in its description. |
| `PC-002` | Two IPv4 addresses, joined with a comma. No multi-valued attributes, so those cells are empty. |
| `PC-003` | Resolves to an IPv6 address only, so the report says no IPv4 record exists. |
| `PC-004` | No DNS host name in the directory, so the fallback to the computer name runs, and that name does not resolve. Also has null attributes. |
| `PC-005` | Present in the OU but never requested, so it appears only in the loaded count. |
| `PC-006` | Resolves to an address that is in no DHCP scope at all. |
| `PC-007` | Resolves into a scope's subnet but inside that scope's exclusion range. |
| `PC-008` | Resolves into a scope whose subnet mask is not `/24`, so the subnet arithmetic is exercised rather than assumed. |

Each object also carries the bookkeeping properties the real module adds
(`PropertyNames`, `AddedProperties`, `RemovedProperties`, `ModifiedProperties`,
`PropertyCount`), so the script's habit of skipping those as columns is
exercised rather than assumed.

### emulator/stubs/Resolve-DnsName

Invents the DNS answers: `pc-001`, `pc-002`, `pc-006`, `pc-007` and `pc-008`
resolve, `pc-003` has only a AAAA record, and everything else fails. It raises a
real error for the failing names, so the script's `catch` block is what produces
`DNS lookup failed`.

### emulator/stubs/DhcpServer

Answers the two cmdlets `Add-DhcpScopeColumns.ps1` calls, and invents four
scopes:

| Scope | Name | Why it is shaped that way |
| --- | --- | --- |
| `10.10.1.0/24` | Office-Malmo | A plain scope, matching the sample's `10.10.1.11`. |
| `10.10.2.0/24` | Office-Helsingborg | Matches the sample's `10.10.2.21` and `.22`, where the first address matches. |
| `10.10.3.0/24` | Lager | Carries the exclusion range `10.10.3.1` to `10.10.3.10`, so the sample's `10.10.3.5` is in the subnet but not assignable. |
| `10.20.0.0/22` | Testlab | A non-`/24` mask, so the mask arithmetic cannot pass by accident. |

## Extending the sample data

Add a computer to the `Get-ADComputer` function in the stub module, a matching
DNS answer in the DNS stub, and a line in `examples/ComputerList.sample.txt`,
then run the harness again. Keep the three stubs consistent with each other, or
a name will resolve to an address the directory never mentioned.

To emulate a directory where the OU check fails, make
`Get-ADOrganizationalUnit` throw. To emulate a DHCP server that cannot be read,
make `Get-DhcpServerv4Scope` throw.

## What the emulation does not prove

- It says nothing about whether your real OU or your real scopes exist, whether
  your account may read them, or whether the DHCP server is reachable.
- The attribute set is invented and small. A real
  `Get-ADComputer -Properties *` returns far more attributes, so a real report
  is much wider than the sample.
- The DNS answers and the scopes are invented, so the resolved, unresolved,
  IPv6-only, excluded and out-of-scope cases are illustrations, not measurements
  of your environment.
- It runs on PowerShell 7. The Windows PowerShell 5.1 path, including the
  encoding branch, is not exercised here.
