<#
Emulation only. Stands in for the Resolve-DnsName cmdlet, which exists on
Windows but not on Linux or macOS.

The answers are invented and chosen to cover the three outcomes the script
reports:

  a name that resolves            pc-001, pc-002
  a name with no IPv4 record      pc-003   (IPv6 only)
  a name that fails to resolve    everything else

pc-001 is also answered with a CNAME and a repeated A record, so the script's
record-type filter and its de-duplication are both exercised.
#>

function Resolve-DnsName {
    param($Name, $Type, [switch]$DnsOnly, $ErrorAction)

    switch -Wildcard ($Name) {
        "pc-001*" {
            [pscustomobject]@{ Name = $Name; Type = "CNAME"; NameHost = "pc-001.example.com" }
            [pscustomobject]@{ Name = $Name; Type = "A"; IPAddress = "10.10.1.11" }
            [pscustomobject]@{ Name = $Name; Type = "A"; IPAddress = "10.10.1.11" }
        }
        "pc-002*" {
            [pscustomobject]@{ Name = $Name; Type = "A"; IPAddress = "10.10.2.21" }
            [pscustomobject]@{ Name = $Name; Type = "A"; IPAddress = "10.10.2.22" }
        }
        "pc-003*" {
            [pscustomobject]@{ Name = $Name; Type = "AAAA"; IPAddress = "fd00::3a1" }
        }
        default {
            Write-Error "DNS name does not exist"
        }
    }
}
