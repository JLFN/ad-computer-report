<#
.SYNOPSIS
Collects Active Directory computer information for a list of computer names
and exports it to a CSV file.

.DESCRIPTION
Reads computer names from a text file, looks each one up in Active Directory
inside a chosen organizational unit, resolves the IPv4 address, and writes one
CSV row per requested computer with the AD attributes.

The script reports every requested computer, including the ones it could not
find, so the output always has one row per input line and the same columns in
every row.

Requires Windows PowerShell 5.1 or later on a Windows host with the
ActiveDirectory module (RSAT).

.PARAMETER InputFile
Text file with one computer name per line. Blank lines are skipped, a leading
or trailing space is trimmed, and a trailing dollar sign (the SamAccountName
form) is removed. Duplicates are collapsed, case insensitively.

.PARAMETER OutputFile
Path of the CSV file to write. The parent folder is created when missing.

.PARAMETER SearchBase
Distinguished name of the OU to search. The search is recursive.

.PARAMETER CsvDelimiter
Field separator for the CSV. The default, a semicolon, matches the list
separator used by Excel in Swedish and most European locales.

.PARAMETER RunNslookup
Also run nslookup.exe for each computer and keep its raw text in an extra
NslookupRaw column. Off by default: Resolve-DnsName already performs the
lookup, so running nslookup as well doubles the DNS work per computer.

.EXAMPLE
.\ComputerReport.ps1

Runs with the defaults: reads C:\Temp\ComputerList.txt and writes
C:\Temp\ComputerInformation.csv.

.EXAMPLE
.\ComputerReport.ps1 -InputFile .\computers.txt -OutputFile .\report.csv `
    -SearchBase "OU=Computers,OU=Company,DC=example,DC=com"

Collects the same information for a different OU and writes it to the current
directory.

.NOTES
The CSV is written as UTF-8 with a byte order mark on every PowerShell
version, so Excel reads non-ASCII characters correctly.
#>

#Requires -Modules ActiveDirectory
#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$InputFile = "C:\Temp\ComputerList.txt",

    [string]$OutputFile = "C:\Temp\ComputerInformation.csv",

    [string]$SearchBase = "OU=Computers,OU=Company,DC=example,DC=com",

    [string]$CsvDelimiter = ";",

    [switch]$RunNslookup
)

$ErrorActionPreference = "Stop"

# ================================================================
# COLUMN NAMES THE SCRIPT OWNS
# ================================================================
# AD attributes with these names are skipped as extra columns, so the
# left-hand columns always mean the same thing.

$FixedColumnNames = @(
    "ComputerName"
    "Description"
    "IPAddress"
    "DNSStatus"
    "ADStatus"
    "NslookupRaw"
)

# Bookkeeping properties the AD module adds to every object it returns.
$AdTrackingProperties = @(
    "PropertyNames"
    "AddedProperties"
    "RemovedProperties"
    "ModifiedProperties"
    "PropertyCount"
)

# UTF8 means UTF-8 with a BOM in Windows PowerShell 5.1, but UTF-8 without a
# BOM in PowerShell 6 and later. Excel needs the BOM to read a UTF-8 file as
# UTF-8, so ask for it explicitly on every host.
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $CsvEncoding = "utf8BOM"
}
else {
    $CsvEncoding = "UTF8"
}

# ================================================================
# LOAD ACTIVE DIRECTORY MODULE
# ================================================================

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Active Directory module could not be loaded." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ================================================================
# CHECK INPUT FILE
# ================================================================

if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Host "ERROR: Input file was not found:" -ForegroundColor Red
    Write-Host $InputFile -ForegroundColor Red
    exit 1
}

# Create the output folder if it does not exist.
$OutputFolder = Split-Path -Path $OutputFile -Parent

if ($OutputFolder -and -not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force |
        Out-Null
}

# ================================================================
# CHECK ACTIVE DIRECTORY OU
# ================================================================

try {
    Get-ADOrganizationalUnit `
        -Identity $SearchBase `
        -ErrorAction Stop |
        Out-Null
}
catch {
    Write-Host "ERROR: The following AD OU could not be found:" `
        -ForegroundColor Red

    Write-Host $SearchBase -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ================================================================
# READ COMPUTER LIST
# ================================================================

$ComputerList = @(
    Get-Content -LiteralPath $InputFile -Encoding UTF8 |
        ForEach-Object {
            $_.Trim().TrimEnd('$')
        } |
        Where-Object {
            $_ -ne ""
        } |
        Sort-Object -Unique
)

if ($ComputerList.Count -eq 0) {
    Write-Host "ERROR: The input file is empty." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Computer information collection started." `
    -ForegroundColor Cyan

Write-Host "Input file: $InputFile"
Write-Host "Output file: $OutputFile"
Write-Host "Search OU: $SearchBase"
Write-Host "Computers requested: $($ComputerList.Count)"
Write-Host ""

# ================================================================
# LOAD ALL COMPUTERS FROM THE OU
# ================================================================

Write-Host "Loading computers from Active Directory..." `
    -ForegroundColor Cyan

try {
    $AllADComputers = @(
        Get-ADComputer `
            -Filter * `
            -SearchBase $SearchBase `
            -SearchScope Subtree `
            -Properties * `
            -ErrorAction Stop
    )
}
catch {
    Write-Host "ERROR: Failed to load computers from Active Directory." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "AD computers loaded: $($AllADComputers.Count)"
Write-Host ""

# ================================================================
# CREATE COMPUTER LOOKUP TABLE
# ================================================================
# Both the AD name and the DNS host name are keys, so a list may contain
# short names, fully qualified names, or a mix of the two.

$ComputerLookup = @{}

foreach ($ADComputer in $AllADComputers) {
    if ($ADComputer.Name) {
        $ComputerLookup[$ADComputer.Name.ToUpper()] = $ADComputer
    }

    if ($ADComputer.DNSHostName) {
        $ComputerLookup[$ADComputer.DNSHostName.ToUpper()] = $ADComputer
    }
}

# ================================================================
# GET ALL AVAILABLE AD PROPERTY NAMES
# ================================================================

$AllPropertyNames = @(
    $AllADComputers |
        ForEach-Object {
            $_.PSObject.Properties.Name
        } |
        Where-Object {
            $_ -notin $FixedColumnNames -and
            $_ -notin $AdTrackingProperties -and
            $_ -ne "Name"
        } |
        Sort-Object -Unique
)

# ================================================================
# PROCESS COMPUTERS
# ================================================================

$Results = [System.Collections.Generic.List[object]]::new()

$CurrentNumber = 0

foreach ($RequestedComputer in $ComputerList) {
    $CurrentNumber++

    Write-Host "[$CurrentNumber/$($ComputerList.Count)] Processing $RequestedComputer..." `
        -ForegroundColor Yellow

    $LookupName = $RequestedComputer.ToUpper()

    # Create the first columns in the CSV.
    $OutputRecord = [ordered]@{
        ComputerName = $RequestedComputer
        Description  = ""
        IPAddress    = ""
        DNSStatus    = ""
        ADStatus     = ""
    }

    if ($RunNslookup) {
        $OutputRecord["NslookupRaw"] = ""
    }

    if ($ComputerLookup.ContainsKey($LookupName)) {
        $ADComputer = $ComputerLookup[$LookupName]

        $OutputRecord["ComputerName"] = $ADComputer.Name
        $OutputRecord["Description"] = $ADComputer.Description
        $OutputRecord["ADStatus"] = "Found in target OU"

        # ========================================================
        # RUN NSLOOKUP
        # ========================================================

        if ($ADComputer.DNSHostName) {
            $DNSName = $ADComputer.DNSHostName
        }
        else {
            $DNSName = $ADComputer.Name
        }

        # Kept in its own try block: a problem with nslookup.exe must not
        # turn a successful Resolve-DnsName into "DNS lookup failed".
        if ($RunNslookup) {
            try {
                $NslookupOutput = @(
                    & nslookup.exe $DNSName 2>&1
                ) |
                    ForEach-Object {
                        $_.ToString()
                    }

                $OutputRecord["NslookupRaw"] = $NslookupOutput -join " | "
            }
            catch {
                $OutputRecord["NslookupRaw"] = "nslookup failed"
            }
        }

        try {
            # Resolve-DnsName provides a reliable structured result.
            $DNSResult = @(
                Resolve-DnsName `
                    -Name $DNSName `
                    -Type A `
                    -DnsOnly `
                    -ErrorAction Stop
            )

            $IPAddresses = @(
                $DNSResult |
                    Where-Object {
                        $_.Type -eq "A" -and $_.IPAddress
                    } |
                    Select-Object -ExpandProperty IPAddress `
                        -Unique
            )

            if ($IPAddresses.Count -gt 0) {
                $OutputRecord["IPAddress"] = $IPAddresses -join ", "
                $OutputRecord["DNSStatus"] = "Resolved"
            }
            else {
                $OutputRecord["IPAddress"] = ""
                $OutputRecord["DNSStatus"] = "No IPv4 address found"
            }
        }
        catch {
            $OutputRecord["IPAddress"] = ""
            $OutputRecord["DNSStatus"] = "DNS lookup failed"
        }

        # ========================================================
        # ADD ALL AD ATTRIBUTES
        # ========================================================

        foreach ($PropertyName in $AllPropertyNames) {
            $PropertyValue = $ADComputer.$PropertyName

            if ($null -eq $PropertyValue) {
                $OutputRecord[$PropertyName] = ""
            }
            elseif ($PropertyValue -is [byte[]]) {
                $OutputRecord[$PropertyName] = "<Binary data>"
            }
            elseif (
                $PropertyValue -is [System.Collections.IEnumerable] -and
                $PropertyValue -isnot [string]
            ) {
                $OutputRecord[$PropertyName] = (
                    $PropertyValue |
                        ForEach-Object {
                            $_.ToString()
                        }
                ) -join " | "
            }
            else {
                $OutputRecord[$PropertyName] = $PropertyValue.ToString()
            }
        }
    }
    else {
        $OutputRecord["ADStatus"] = "Computer not found in target OU"
        $OutputRecord["DNSStatus"] = "Not checked"

        # Add empty AD properties so every CSV row has the same columns.
        foreach ($PropertyName in $AllPropertyNames) {
            $OutputRecord[$PropertyName] = ""
        }
    }

    # Build the row by adding the columns one at a time, in order. A PSObject
    # keeps its members in the order they were added, so the CSV column order
    # is the same on every host, and the first columns are always the fixed
    # ones. This avoids relying on how a dictionary cast orders properties.
    $ResultObject = New-Object PSObject

    foreach ($ColumnName in $OutputRecord.Keys) {
        $ResultObject |
            Add-Member `
                -MemberType NoteProperty `
                -Name $ColumnName `
                -Value $OutputRecord[$ColumnName]
    }

    $Results.Add($ResultObject)
}

# ================================================================
# EXPORT UTF-8 CSV
# ================================================================

Write-Host ""
Write-Host "Exporting CSV file..." -ForegroundColor Cyan

try {
    $Results |
        Export-Csv `
            -LiteralPath $OutputFile `
            -Delimiter $CsvDelimiter `
            -Encoding $CsvEncoding `
            -NoTypeInformation `
            -Force
}
catch {
    Write-Host "ERROR: Could not write the CSV file." `
        -ForegroundColor Red

    Write-Host "Make sure the file is not open in Excel:" `
        -ForegroundColor Red

    Write-Host $OutputFile -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ================================================================
# SUMMARY
# ================================================================

$FoundCount = @(
    $Results |
        Where-Object {
            $_.ADStatus -eq "Found in target OU"
        }
).Count

$NotFoundCount = @(
    $Results |
        Where-Object {
            $_.ADStatus -eq "Computer not found in target OU"
        }
).Count

$ResolvedCount = @(
    $Results |
        Where-Object {
            $_.DNSStatus -eq "Resolved"
        }
).Count

$NoRecordCount = @(
    $Results |
        Where-Object {
            $_.DNSStatus -eq "No IPv4 address found"
        }
).Count

$DNSFailedCount = @(
    $Results |
        Where-Object {
            $_.DNSStatus -eq "DNS lookup failed"
        }
).Count

Write-Host ""
Write-Host "Finished successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Requested:              $($ComputerList.Count)"
Write-Host "Found in AD:            $FoundCount"
Write-Host "Not found:              $NotFoundCount"
Write-Host "DNS resolved:           $ResolvedCount"
Write-Host "DNS no IPv4 record:     $NoRecordCount"
Write-Host "DNS lookup failed:      $DNSFailedCount"
Write-Host ""
Write-Host "CSV file:" -ForegroundColor Green
Write-Host $OutputFile -ForegroundColor Green
