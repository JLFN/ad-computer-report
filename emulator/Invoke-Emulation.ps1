<#
.SYNOPSIS
Runs ComputerReport.ps1 against invented Active Directory data, so the script
can be tried without a domain controller, without RSAT and without Windows.

.DESCRIPTION
Puts the stub ActiveDirectory module on the module path, defines a stub
Resolve-DnsName, and then runs the real ComputerReport.ps1 with the sample
input file. The script itself is not modified and no copy of it is made: it is
invoked exactly as it would be in production, with parameters.

Nothing here touches a network or a directory. The stub objects, the DNS
answers and the OU are all invented, so the report this produces is an
illustration of the script's behavior, not a source of truth about any
environment.

.PARAMETER OutputFile
Where to write the emulated CSV. Defaults to
examples/ComputerInformation.sample.csv next to the input file.

.PARAMETER RunNslookup
Pass the same switch through to the report script. Not useful in emulation on
Linux or macOS, because there is no nslookup.exe to run.

.EXAMPLE
pwsh ./emulator/Invoke-Emulation.ps1

.EXAMPLE
pwsh ./emulator/Invoke-Emulation.ps1 -OutputFile /tmp/report.csv
#>

[CmdletBinding()]
param(
    [string]$OutputFile,

    [switch]$RunNslookup
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ReportScript = Join-Path $ProjectRoot "ComputerReport.ps1"
$SampleInput = Join-Path $ProjectRoot "examples/ComputerList.sample.txt"
$StubModuleRoot = Join-Path $PSScriptRoot "stubs"

if (-not $OutputFile) {
    $OutputFile = Join-Path $ProjectRoot "examples/ComputerInformation.sample.csv"
}

foreach ($required in @($ReportScript, $SampleInput, $StubModuleRoot)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Emulation cannot start, missing: $required"
    }
}

Write-Host "Emulation mode: no directory and no DNS server are contacted." `
    -ForegroundColor Magenta
Write-Host ""

# The stub module must win over any real ActiveDirectory module, so prepend it.
$env:PSModulePath = $StubModuleRoot +
    [System.IO.Path]::PathSeparator +
    $env:PSModulePath

# The stub replaces the cmdlet of the same name, which only exists on Windows.
. (Join-Path $PSScriptRoot "stubs/Resolve-DnsName.ps1")

& $ReportScript `
    -InputFile $SampleInput `
    -OutputFile $OutputFile `
    -SearchBase "OU=Computers,OU=Company,DC=example,DC=com" `
    -RunNslookup:$RunNslookup

Write-Host ""
Write-Host "Emulated CSV written to:" -ForegroundColor Magenta
Write-Host $OutputFile -ForegroundColor Magenta
