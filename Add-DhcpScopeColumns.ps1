<#
.SYNOPSIS
Adds the DHCP scope name and scope ID to each computer in a report produced by
ComputerReport.ps1.

.DESCRIPTION
Reads a computer report CSV, asks a Microsoft DHCP server for its IPv4 scopes,
and writes the same rows back with two extra columns saying which scope each
computer's IP address belongs to.

An address belongs to a scope when the address AND the scope's subnet mask
equals the scope identifier, and the address falls inside that scope's start
and end range. Every IP address on a row is tried in turn, so a computer that
resolved to several addresses matches if any of them is in a scope.

The script only reads from the DHCP server. Nothing is changed there.

Requires Windows, the DhcpServer PowerShell module (RSAT DHCP Server Tools on a
client, or run it on the server itself), and an account that may read the
scopes on the target server.

.PARAMETER InputFile
The CSV produced by ComputerReport.ps1. It must carry an IPAddress column.

.PARAMETER OutputFile
Where to write the enriched CSV. Defaults to the input file's name with
-Dhcp appended before the extension, in the same folder.

.PARAMETER DhcpServer
DNS name or IPv4 address of the DHCP server to query. The placeholder below is
from the documentation range and must be replaced with your own server.

.PARAMETER CsvDelimiter
Field separator for reading and writing the CSV. Must match the delimiter the
report was written with.

.EXAMPLE
.\Add-DhcpScopeColumns.ps1 -InputFile C:\Temp\ComputerInformation.csv `
    -DhcpServer 192.0.2.10

.EXAMPLE
.\Add-DhcpScopeColumns.ps1 -InputFile .\ComputerInformation.csv `
    -OutputFile .\ComputerInformation-Dhcp.csv -DhcpServer dhcp.example.com `
    -CsvDelimiter ";"

.NOTES
The two added columns are placed directly after IPAddress; every other column
keeps the position and the value it had in the input file.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputFile,

    [string]$OutputFile,

    [string]$DhcpServer = "192.0.2.10",

    [string]$CsvDelimiter = ";"
)

$ErrorActionPreference = "Stop"

# The scope name column also carries these status words when there is no
# single scope to name, so a missing scope can never be mistaken for a blank.
$StatusNoAddress = "No IP address to look up"
$StatusNoScope = "Not in any DHCP scope"
$StatusExcluded = "In scope but excluded"

# UTF8 means UTF-8 with a BOM in Windows PowerShell 5.1, but UTF-8 without a
# BOM in PowerShell 6 and later. Excel needs the BOM, so ask for it explicitly.
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $CsvEncoding = "utf8BOM"
}
else {
    $CsvEncoding = "UTF8"
}

# ================================================================
# HELPERS
# ================================================================

function ConvertTo-IPv4Number {
    <#
    Turns a dotted-quad address into the 32-bit number it stands for, so that
    subnet arithmetic is plain integer arithmetic. Throws on anything that is
    not four octets in 0..255, rather than silently returning a wrong number.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Address
    )

    $octets = $Address.Trim().Split('.')

    if ($octets.Count -ne 4) {
        throw "Not an IPv4 address: '$Address'"
    }

    [uint32]$value = 0

    foreach ($octet in $octets) {
        $number = 0

        if (-not [int]::TryParse($octet, [ref]$number)) {
            throw "Not an IPv4 address: '$Address'"
        }

        if ($number -lt 0 -or $number -gt 255) {
            throw "Not an IPv4 address: '$Address'"
        }

        $value = [uint32](($value * 256) + $number)
    }

    $value
}

function Get-RequiredProperty {
    <#
    Reads a property that must be there, and fails with a message naming what
    was found instead when it is not. The objects a real DHCP server returns are
    CIM instances whose exact property set the vendor documentation does not
    list, so a missing property must be a clear error rather than a confusing
    null reference or, worse, a silently empty answer.
    #>
    param(
        [Parameter(Mandatory)]
        $Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ($Object.PSObject.Properties.Name -notcontains $Name) {
        $found = ($Object.PSObject.Properties.Name | Sort-Object) -join ", "
        throw "$Context has no '$Name' property. Properties present: $found"
    }

    $Object.$Name
}

function Get-DhcpScopeTable {
    <#
    Reads every IPv4 scope and every exclusion range from the server into plain
    objects holding numbers, so the per-row matching below is cheap and cannot
    fail on a malformed address.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $scopes = @(
        Get-DhcpServerv4Scope -ComputerName $ComputerName -ErrorAction Stop
    )

    if ($scopes.Count -eq 0) {
        throw "The DHCP server '$ComputerName' returned no IPv4 scopes. Check the server name, that this is a Microsoft DHCP server, and that the account may read its scopes."
    }

    $exclusionsByScope = @{}

    foreach ($scope in $scopes) {
        $scopeIdText = Get-RequiredProperty `
            -Object $scope `
            -Name "ScopeId" `
            -Context "A scope on '$ComputerName'"

        $exclusions = @()

        try {
            $exclusions = @(
                Get-DhcpServerv4ExclusionRange `
                    -ComputerName $ComputerName `
                    -ScopeId $scope.ScopeId `
                    -ErrorAction Stop
            )
        }
        catch {
            # A scope with no exclusion range, or one the account may not read,
            # must not stop the whole run; the scope itself is still useful.
            $exclusions = @()
        }

        $exclusionsByScope[$scopeIdText.ToString()] = @(
            foreach ($exclusion in $exclusions) {
                # Read through Get-RequiredProperty so an unexpected exclusion
                # object is reported. Swallowing this would silently turn an
                # excluded address into an in-scope one.
                $startText = Get-RequiredProperty `
                    -Object $exclusion `
                    -Name "StartRange" `
                    -Context "An exclusion range on '$ComputerName'"

                $endText = Get-RequiredProperty `
                    -Object $exclusion `
                    -Name "EndRange" `
                    -Context "An exclusion range on '$ComputerName'"

                [pscustomobject]@{
                    Start = ConvertTo-IPv4Number -Address $startText.ToString()
                    End   = ConvertTo-IPv4Number -Address $endText.ToString()
                }
            }
        )
    }

    $table = @(
        foreach ($scope in $scopes) {
            $scopeIdValue = Get-RequiredProperty `
                -Object $scope `
                -Name "ScopeId" `
                -Context "A scope on '$ComputerName'"

            $maskValue = Get-RequiredProperty `
                -Object $scope `
                -Name "SubnetMask" `
                -Context "The scope $scopeIdValue on '$ComputerName'"

            $startValue = Get-RequiredProperty `
                -Object $scope `
                -Name "StartRange" `
                -Context "The scope $scopeIdValue on '$ComputerName'"

            $endValue = Get-RequiredProperty `
                -Object $scope `
                -Name "EndRange" `
                -Context "The scope $scopeIdValue on '$ComputerName'"

            $scopeIdText = $scopeIdValue.ToString()
            $mask = ConvertTo-IPv4Number -Address $maskValue.ToString()
            $scopeIdNumber = ConvertTo-IPv4Number -Address $scopeIdText

            # A scope may carry no name; the identifier is then the best label.
            $scopeName = $scope.Name
            if (-not $scopeName) {
                $scopeName = $scopeIdText
            }

            [pscustomobject]@{
                ScopeId    = $scopeIdText
                Name       = $scopeName
                Network    = $scopeIdNumber -band $mask
                Mask       = $mask
                Start      = ConvertTo-IPv4Number -Address $startValue.ToString()
                End        = ConvertTo-IPv4Number -Address $endValue.ToString()
                Exclusions = $exclusionsByScope[$scopeIdText]
            }
        }
    )

    $table
}

function Find-DhcpScope {
    <#
    Matches one address against the scope table. Returns an object saying which
    scope the address belongs to, and which of the three miss cases applies when
    it belongs to none.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Address,
        [Parameter(Mandatory)]
        [array]$ScopeTable
    )

    $number = ConvertTo-IPv4Number -Address $Address

    $inSubnet = @(
        $ScopeTable |
            Where-Object {
                ($number -band $_.Mask) -eq $_.Network
            }
    )

    if ($inSubnet.Count -eq 0) {
        return [pscustomobject]@{
            Name   = $StatusNoScope
            ScopeId = ""
        }
    }

    foreach ($scope in $inSubnet) {
        $isExcluded = @(
            $scope.Exclusions |
                Where-Object {
                    $number -ge $_.Start -and $number -le $_.End
                }
        ).Count -gt 0

        if ($isExcluded) {
            return [pscustomobject]@{
                Name   = $StatusExcluded
                ScopeId = $scope.ScopeId
            }
        }

        if ($number -ge $scope.Start -and $number -le $scope.End) {
            return [pscustomobject]@{
                Name   = $scope.Name
                ScopeId = $scope.ScopeId
            }
        }
    }

    # The address is in a scope's subnet but outside every start and end range
    # and outside every exclusion range: a static address in the same subnet.
    return [pscustomobject]@{
        Name   = $StatusNoScope
        ScopeId = ""
    }
}

# ================================================================
# CHECK INPUT FILE AND OUTPUT PATH
# ================================================================

if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Host "ERROR: Input file was not found:" -ForegroundColor Red
    Write-Host $InputFile -ForegroundColor Red
    exit 1
}

if (-not $OutputFile) {
    $inputFolder = Split-Path -Path $InputFile -Parent
    $inputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $inputExtension = [System.IO.Path]::GetExtension($InputFile)
    $outputName = "$inputBaseName-Dhcp$inputExtension"

    if ($inputFolder) {
        $OutputFile = Join-Path -Path $inputFolder -ChildPath $outputName
    }
    else {
        $OutputFile = $outputName
    }
}

$OutputFolder = Split-Path -Path $OutputFile -Parent

if ($OutputFolder -and -not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force |
        Out-Null
}

# ================================================================
# LOAD THE COMPUTER REPORT
# ================================================================

Write-Host ""
Write-Host "Adding DHCP scope columns." -ForegroundColor Cyan

try {
    $ComputerRows = @(
        Import-Csv `
            -LiteralPath $InputFile `
            -Delimiter $CsvDelimiter `
            -ErrorAction Stop
    )
}
catch {
    Write-Host "ERROR: Could not read the input CSV." -ForegroundColor Red
    Write-Host $InputFile -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

if ($ComputerRows.Count -eq 0) {
    Write-Host "ERROR: The input CSV has no data rows." -ForegroundColor Red
    exit 1
}

$InputColumns = @($ComputerRows[0].PSObject.Properties.Name)

if ($InputColumns -notcontains "IPAddress") {
    Write-Host "ERROR: The input CSV has no IPAddress column." -ForegroundColor Red
    Write-Host "This script expects the output of ComputerReport.ps1." `
        -ForegroundColor Red
    exit 1
}

Write-Host "Input file: $InputFile"
Write-Host "Output file: $OutputFile"
Write-Host "DHCP server: $DhcpServer"
Write-Host "Rows to enrich: $($ComputerRows.Count)"
Write-Host ""

# ================================================================
# READ THE DHCP SCOPES
# ================================================================

Write-Host "Reading IPv4 scopes from the DHCP server..." `
    -ForegroundColor Cyan

try {
    Import-Module DhcpServer -ErrorAction Stop
}
catch {
    Write-Host "ERROR: The DhcpServer module could not be loaded." `
        -ForegroundColor Red

    Write-Host "Install the DHCP Server Tools, or run this on the server:" `
        -ForegroundColor Red

    Write-Host "Install-WindowsFeature RSAT-DHCP" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

try {
    $ScopeTable = @(Get-DhcpScopeTable -ComputerName $DhcpServer)
}
catch {
    Write-Host "ERROR: Could not read the scopes from the DHCP server." `
        -ForegroundColor Red

    Write-Host $DhcpServer -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "Scopes loaded: $($ScopeTable.Count)"

foreach ($scope in $ScopeTable) {
    $exclusionCount = $scope.Exclusions.Count
    Write-Host "  $($scope.ScopeId)  $($scope.Name)  ($exclusionCount exclusion range(s))"
}

Write-Host ""

# ================================================================
# ADD THE SCOPE COLUMNS
# ================================================================

$Results = [System.Collections.Generic.List[object]]::new()

$MatchedCount = 0
$NoScopeCount = 0
$ExcludedCount = 0
$NoAddressCount = 0

foreach ($ComputerRow in $ComputerRows) {
    $IpCell = $ComputerRow.IPAddress

    $ScopeName = ""
    $ScopeId = ""

    if (-not $IpCell) {
        $ScopeName = $StatusNoAddress
        $NoAddressCount++
    }
    else {
        $Addresses = @(
            $IpCell -split "," |
                ForEach-Object {
                    $_.Trim()
                } |
                Where-Object {
                    $_ -ne ""
                }
        )

        if ($Addresses.Count -eq 0) {
            $ScopeName = $StatusNoAddress
            $NoAddressCount++
        }
        else {
            foreach ($Address in $Addresses) {
                try {
                    $Match = Find-DhcpScope `
                        -Address $Address `
                        -ScopeTable $ScopeTable
                }
                catch {
                    # A malformed address in the report must not stop the run.
                    continue
                }

                if ($Match.Name -eq $StatusNoScope) {
                    continue
                }

                $ScopeName = $Match.Name
                $ScopeId = $Match.ScopeId
                break
            }

            if (-not $ScopeName) {
                $ScopeName = $StatusNoScope
            }
        }
    }

    switch ($ScopeName) {
        $StatusExcluded { $ExcludedCount++ }
        $StatusNoScope { $NoScopeCount++ }
        $StatusNoAddress { }
        default { $MatchedCount++ }
    }

    # Rebuild the row in the input's own column order, inserting the two scope
    # columns straight after IPAddress so they sit next to the address they
    # describe. Every other value is copied unchanged.
    $OutputRecord = [ordered]@{}
    $Inserted = $false

    foreach ($ColumnName in $InputColumns) {
        $OutputRecord[$ColumnName] = $ComputerRow.$ColumnName

        if ($ColumnName -eq "IPAddress") {
            $OutputRecord["DhcpScopeName"] = $ScopeName
            $OutputRecord["DhcpScopeId"] = $ScopeId
            $Inserted = $true
        }
    }

    if (-not $Inserted) {
        $OutputRecord["DhcpScopeName"] = $ScopeName
        $OutputRecord["DhcpScopeId"] = $ScopeId
    }

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
# EXPORT
# ================================================================

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
    Write-Host "ERROR: Could not write the CSV file." -ForegroundColor Red

    Write-Host "Make sure the file is not open in Excel:" `
        -ForegroundColor Red

    Write-Host $OutputFile -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ================================================================
# SUMMARY
# ================================================================

Write-Host ""
Write-Host "Finished successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Rows:                   $($ComputerRows.Count)"
Write-Host "In a scope:             $MatchedCount"
Write-Host "In scope but excluded:  $ExcludedCount"
Write-Host "Not in any DHCP scope:  $NoScopeCount"
Write-Host "No IP address:          $NoAddressCount"
Write-Host ""
Write-Host "CSV file:" -ForegroundColor Green
Write-Host $OutputFile -ForegroundColor Green
