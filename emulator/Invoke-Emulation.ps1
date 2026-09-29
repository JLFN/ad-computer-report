<#
.SYNOPSIS
Runs the scripts in this repository against invented data, so they can be tried
without a domain controller, without a DHCP server, without RSAT and without
Windows.

.DESCRIPTION
Puts stub ActiveDirectory and DhcpServer modules on the module path, defines a
stub Resolve-DnsName, and then runs the real scripts with the sample input:

  1. ComputerReport.ps1            collects the computers into a CSV
  2. Add-DhcpScopeColumns.ps1      adds the DHCP scope columns to that CSV

Neither script is modified and no copy of either is made: they are invoked
exactly as they would be in production, with parameters.

Nothing here touches a network, a directory or a DHCP server. The computers,
their attributes, the DNS answers, the OU and the DHCP scopes are all invented,
so the output illustrates the scripts' behavior and says nothing about any real
environment.

.PARAMETER OutputFile
Where to write the collected CSV. Defaults to
examples/ComputerInformation.sample.csv.

.PARAMETER DhcpOutputFile
Where to write the enriched CSV. Defaults to
examples/ComputerInformation-Dhcp.sample.csv.

.PARAMETER RunNslookup
Pass the same switch through to the report script. Not useful in emulation on
Linux or macOS, because there is no nslookup.exe to run.

.EXAMPLE
pwsh ./emulator/Invoke-Emulation.ps1

.EXAMPLE
pwsh ./emulator/Invoke-Emulation.ps1 -OutputFile /tmp/report.csv -DhcpOutputFile /tmp/report-dhcp.csv
#>

[CmdletBinding()]
param(
    [string]$OutputFile,

    [string]$DhcpOutputFile,

    [switch]$RunNslookup
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ReportScript = Join-Path $ProjectRoot "ComputerReport.ps1"
$DhcpScript = Join-Path $ProjectRoot "Add-DhcpScopeColumns.ps1"
$SampleInput = Join-Path $ProjectRoot "examples/ComputerList.sample.txt"
$StubModuleRoot = Join-Path $PSScriptRoot "stubs"

if (-not $OutputFile) {
    $OutputFile = Join-Path $ProjectRoot "examples/ComputerInformation.sample.csv"
}

if (-not $DhcpOutputFile) {
    $DhcpOutputFile = Join-Path $ProjectRoot "examples/ComputerInformation-Dhcp.sample.csv"
}

foreach ($required in @($ReportScript, $DhcpScript, $SampleInput, $StubModuleRoot)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Emulation cannot start, missing: $required"
    }
}

Write-Host "Emulation mode: no directory, no DHCP server and no DNS server are contacted." `
    -ForegroundColor Magenta
Write-Host ""

# The stub modules must win over any real ones, so prepend the stub root.
$env:PSModulePath = $StubModuleRoot +
    [System.IO.Path]::PathSeparator +
    $env:PSModulePath

# The stub replaces the cmdlet of the same name, which only exists on Windows.
. (Join-Path $PSScriptRoot "stubs/Resolve-DnsName.ps1")

Write-Host "Stage 1 of 2: collecting computer information." -ForegroundColor Magenta
Write-Host ""

& $ReportScript `
    -InputFile $SampleInput `
    -OutputFile $OutputFile `
    -SearchBase "OU=Computers,OU=Company,DC=example,DC=com" `
    -RunNslookup:$RunNslookup

Write-Host ""
Write-Host "Stage 2 of 2: adding DHCP scope columns." -ForegroundColor Magenta
Write-Host ""

& $DhcpScript `
    -InputFile $OutputFile `
    -OutputFile $DhcpOutputFile `
    -DhcpServer "192.0.2.10"

Write-Host ""
Write-Host "Emulated CSVs written to:" -ForegroundColor Magenta
Write-Host $OutputFile -ForegroundColor Magenta
Write-Host $DhcpOutputFile -ForegroundColor Magenta
