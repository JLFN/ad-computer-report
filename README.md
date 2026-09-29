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

## Trying it without a domain

`emulator/` runs the real script against invented data, so you can see exactly
what the output looks like before pointing it at anything real. It needs no
domain controller, no RSAT and not even Windows:

```bash
pwsh ./emulator/Invoke-Emulation.ps1
```

It writes `examples/ComputerInformation.sample.csv`, which is committed, so you
can also just read that file. The sample input is
`examples/ComputerList.sample.txt`. See [docs/emulator.md](docs/emulator.md)
for how the harness works and how to extend it.

Nothing in the emulator touches a network or a directory. The computers, their
attributes, the DNS answers and the OU are all invented, and the emulated
report describes that invented directory, not any real one.

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
ComputerReport.ps1                  the script
emulator/Invoke-Emulation.ps1       runs the script against invented data
emulator/stubs/                     stand-ins for ActiveDirectory and Resolve-DnsName
examples/ComputerList.sample.txt    sample input
examples/ComputerInformation.sample.csv   emulated output
docs/emulator.md                    how the emulation harness works
qa-evidence/qa-waiver.md            the recorded decision about the QA gate
CHANGELOG.md                        release history
```

## License

MIT. See [LICENSE](LICENSE).
