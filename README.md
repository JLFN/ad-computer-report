# ad-computer-report

Collect information about a list of computers from Active Directory and export
one CSV row per computer, including the ones that could not be found.

You give it a text file with computer names. It looks each name up in a chosen
organizational unit, resolves the IPv4 address, and writes every Active
Directory attribute it can see into a semicolon-separated CSV that opens
cleanly in Excel.

Nothing is written to Active Directory. The script only reads.

## Why it exists

Answering "what is the state of these machines" usually turns into a pile of
one-off commands. This wraps that into a single pass that reports the whole
truth of what it found: a computer that is missing from the directory, a
computer with no IPv4 record, and a computer whose name does not resolve are
all reported as their own outcome instead of being quietly skipped.

## Requirements

- Windows, with the `ActiveDirectory` PowerShell module installed (RSAT:
  `Add-WindowsFeature RSAT-AD-PowerShell`, or the RSAT tools on a client).
- Windows PowerShell 5.1 or PowerShell 7.
- A user account that may read computer objects in the target OU.
- Working DNS resolution from the machine running the script.

## Quick start

1. Put the computer names in a text file, one per line:

   ```
   PC-001
   PC-002$
   pc-003.example.com
   ```

2. Run the script with the OU that holds your computers:

   ```powershell
   .\ComputerReport.ps1 `
       -InputFile C:\Temp\ComputerList.txt `
       -OutputFile C:\Temp\ComputerInformation.csv `
       -SearchBase "OU=Computers,OU=Company,DC=example,DC=com"
   ```

3. Open the CSV in Excel. The console output ends with a summary:

   ```
   Requested:              6
   Found in AD:            5
   Not found:              1
   DNS resolved:           3
   DNS no IPv4 record:     1
   DNS lookup failed:      1
   ```

The `SearchBase` value above is a placeholder. Replace `OU=Company` and
`DC=example,DC=com` with your own directory before running anything for real.

## Parameters

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-InputFile` | `C:\Temp\ComputerList.txt` | Text file with one computer name per line. |
| `-OutputFile` | `C:\Temp\ComputerInformation.csv` | CSV to write. Its folder is created when missing. |
| `-SearchBase` | `OU=Computers,OU=Company,DC=example,DC=com` | Distinguished name of the OU to search. Recursive. |
| `-CsvDelimiter` | `;` | Field separator. The default suits Swedish and most European Excel. |
| `-RunNslookup` | off | Also run `nslookup.exe` per computer and keep its raw text in an extra column. |

Run with no parameters to use the defaults, or pass `-?` for the built-in help.

## How a name is matched

The input file is normalised first: each line is trimmed, a trailing dollar
sign is removed (so `PC-002$` and `PC-002` are the same machine), blank lines
are dropped, and the remaining names are de-duplicated without regard to case.

Every computer in the OU is then loaded once, and a lookup table is built
containing two keys per computer: its Active Directory name and its DNS host
name. A line in your list may therefore be a short name like `PC-001`, a fully
qualified name like `pc-001.example.com`, or a mix of the two in the same file.

For each requested name the script then:

1. Finds the computer in the lookup table, or records that it is not in the OU.
2. Resolves the DNS host name, falling back to the computer name when the
   directory holds no DNS host name for it.
3. Keeps only the IPv4 (A) records, discards duplicates, and joins multiple
   addresses with a comma.
4. Copies every Active Directory attribute into its own column.

## Reading the CSV in Excel

The file is always written as UTF-8 with a byte-order mark, on every
PowerShell version, so non-ASCII characters (`Ångström`, `Malmö`) survive the
trip into Excel. Without the mark, Excel in a Swedish locale may show them as
garbage.

The default delimiter is a semicolon because that is the list separator in
Swedish and most European Excel installs. If your Excel expects a comma, pass
`-CsvDelimiter ","`.

One caveat worth knowing: date attributes such as `LastLogonDate` and
`whenCreated` are written in the culture of the machine that ran the script.
On an American-locale host that is `9/24/2026 8:12:00 AM`; on a Swedish host it
is written the Swedish way. Excel then has to guess, and it can guess wrong.
If those columns matter to you, read them as text or reformat them after
import.

## The columns

The first five columns always mean the same thing, on every row:

| Column | Meaning |
| --- | --- |
| `ComputerName` | The Active Directory name of the computer, once it is found. |
| `Description` | The directory description attribute. |
| `IPAddress` | The IPv4 addresses found, comma separated. Empty when there are none. |
| `DNSStatus` | `Resolved`, `No IPv4 address found`, `DNS lookup failed`, or `Not checked`. |
| `ADStatus` | `Found in target OU` or `Computer not found in target OU`. |

Everything after those is one column per Active Directory attribute, sorted
alphabetically. The set is whatever the directory returns for the computers in
the OU, so the width of the file depends on your environment. Multi-valued
attributes are joined with ` | `. Attributes holding binary data are written
as `<Binary data>`. Missing attributes are left empty.

Rows for computers that were not found still carry every column, empty, so the
sheet has a uniform shape and can be filtered as a whole.

## Adding the DHCP scope of each address

`Add-DhcpScopeColumns.ps1` reads the CSV that `ComputerReport.ps1` produced,
asks a Microsoft DHCP server which IPv4 scope each address belongs to, and
writes the rows back with two extra columns placed straight after `IPAddress`.

```powershell
.\Add-DhcpScopeColumns.ps1 `
    -InputFile C:\Temp\ComputerInformation.csv `
    -OutputFile C:\Temp\ComputerInformation-Dhcp.csv `
    -DhcpServer 192.0.2.10
```

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-InputFile` | required | The CSV from `ComputerReport.ps1`. Must carry an `IPAddress` column. |
| `-OutputFile` | the input name with `-Dhcp` appended | Where to write the enriched CSV. |
| `-DhcpServer` | `192.0.2.10` (a placeholder) | DNS name or IPv4 address of the DHCP server. Replace it. |
| `-CsvDelimiter` | `;` | Must match the delimiter the report was written with. |

This half needs the `DhcpServer` PowerShell module (`Install-WindowsFeature
RSAT-DHCP`, or run the script on the DHCP server itself) and an account that may
read the scopes there. It only reads: nothing is changed on the server. It talks
to the Windows DHCP service, so it cannot read scopes from a router, a firewall
or a Linux DHCP server.

The two added columns:

| Column | Meaning |
| --- | --- |
| `DhcpScopeName` | The scope's name, or one of the status words below. |
| `DhcpScopeId` | The scope's identifier, such as `10.10.1.0`. Empty when nothing matched. |

An address belongs to a scope when the address ANDed with the scope's subnet
mask equals the scope identifier, and the address lies inside that scope's start
and end range. Every address on a row is tried in turn, so a computer that
resolved to several addresses matches if any one of them is in a scope.

When nothing matches, `DhcpScopeName` says which case it is, so an empty cell
can never be mistaken for a scope that failed to load:

- `No IP address to look up` — the report recorded no address for that computer, usually because DNS did not resolve it.
- `Not in any DHCP scope` — an address was found, but no scope on the server manages it.
- `In scope but excluded` — the address lies in a scope's subnet but inside an exclusion range. `DhcpScopeId` still names the scope, so an excluded address shows which scope it belongs to.

One case is worth knowing about because it looks like a contradiction: an
address inside a scope's subnet but outside its start and end range, such as the
network address itself or a static server address above the range, is reported
as `Not in any DHCP scope`. That is deliberate. Such an address is in the same
subnet as the scope but is not one the scope hands out, which is a different
thing from an address the scope excludes from its own range.

## Trying it without a domain

`emulator/` runs the real scripts against invented data, so you can see exactly
what the output looks like before pointing anything at a real environment. It
needs no domain controller, no DHCP server, no RSAT and not even Windows:

```bash
pwsh ./emulator/Invoke-Emulation.ps1
```

It runs both stages and writes two committed files you can also just read:
`examples/ComputerInformation.sample.csv` (the report) and
`examples/ComputerInformation-Dhcp.sample.csv` (the same report with the scope
columns). The sample input is `examples/ComputerList.sample.txt`. See
[docs/emulator.md](docs/emulator.md) for how the harness works and how to
extend it.

Nothing in the emulator touches a network, a directory or a DHCP server. The
computers, their attributes, the DNS answers, the OU and the DHCP scopes are all
invented, so the output illustrates the scripts' behavior and says nothing about
any real environment. A real run will have many more attribute columns than the
samples, because a real directory returns far more attributes per computer.

## Known behavior and limitations

- Two rows can be identical. If your list contains both the short name and the
  fully qualified name of the same computer, both lines match the same
  directory object and produce two identical rows, because the row is created
  per requested line and `ComputerName` is replaced by the directory's name.
  De-duplicating the input file does not catch this, because `PC-001` and
  `pc-001.example.com` are different strings. Keep one form per computer in
  the list if you want one row per machine.
- Date formats follow the culture of the machine that ran the script, as
  described above.
- Empty cells come in two forms in the raw text: a missing directory attribute
  exports as an unquoted empty field, while a blank the script set itself
  exports as `""`. Excel shows both as empty.
- The script loads every computer in the OU with all attributes before it
  starts. On a large OU that is the slowest part of the run, and it also means
  the script needs read access to the whole OU, not just to the computers you
  listed.
- `-RunNslookup` doubles the DNS work per computer. It is off by default for
  that reason.
- The script requires a live domain controller. It has not been tested against
  a real directory by its author's tooling; see
  [qa-evidence/qa-waiver.md](qa-evidence/qa-waiver.md).

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Active Directory module could not be loaded` | RSAT is not installed, or you are not on Windows. |
| `The following AD OU could not be found` | `-SearchBase` is wrong, or it still holds the placeholder `OU=Company`. |
| `Could not write the CSV file` | The CSV is open in Excel. Close it and rerun. |
| Every row says `Computer not found in target OU` | The OU is right but the computers are not in it, or the names do not match their directory names. |
| Every row says `DNS lookup failed` | The machine's DNS is not resolving these names. |
| `The DhcpServer module could not be loaded` | RSAT DHCP tools are missing, or you are not on Windows. |
| `Could not read the scopes from the DHCP server` | Wrong `-DhcpServer`, the server is not Microsoft DHCP, or the account may not read its scopes. |

## Privacy and scope

The only network traffic is DNS resolution of the names in your list, plus the
LDAP traffic of the directory query itself. Those names, and the presence of
the machines, are therefore visible to your DNS servers and your domain
controller, which is the same exposure as querying them by hand.

The output file contains directory attributes, which can include internal
names and descriptions. The `.gitignore` here excludes the production input
and output filenames so that real data cannot be committed by accident, and it
re-includes only the invented sample files. If you adapt this script, check
what your own output does before you commit it anywhere.

## Repository layout

```
ComputerReport.ps1                            collects the computer information
Add-DhcpScopeColumns.ps1                      adds the DHCP scope columns to that report
emulator/Invoke-Emulation.ps1                 runs both scripts against invented data
emulator/stubs/                               stand-ins for ActiveDirectory, DhcpServer and Resolve-DnsName
examples/ComputerList.sample.txt              sample input
examples/ComputerInformation.sample.csv       emulated report
examples/ComputerInformation-Dhcp.sample.csv  the same report with scope columns
docs/emulator.md                              how the emulation harness works
qa-evidence/qa-waiver.md                      the recorded decision about the QA gate
CHANGELOG.md                                  release history
```

## License

MIT. See [LICENSE](LICENSE).
