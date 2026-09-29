<#
Emulation only. Stands in for the DhcpServer module that Add-DhcpScopeColumns.ps1
imports, so the enrichment can be run without a DHCP server and without Windows.

It answers the two cmdlets the script calls:

  Get-DhcpServerv4Scope          - returns four invented IPv4 scopes.
  Get-DhcpServerv4ExclusionRange - returns one invented exclusion range.

Nothing here talks to a network or a server. The scopes are chosen to exercise
the matching logic rather than to describe any real network:

  10.10.1.0/24  Office-Malmo         plain, matches the sample's 10.10.1.11
  10.10.2.0/24  Office-Helsingborg   matches the sample's 10.10.2.21 and .22
  10.10.3.0/24  Lager                carries an exclusion range, so 10.10.3.5
                                     is in the subnet but not assignable
  10.20.0.0/22  Testlab              a non-/24 mask, so the subnet arithmetic
                                     is exercised rather than assumed
#>

function Get-DhcpServerv4Scope {
    param($ComputerName, $ScopeId, $ErrorAction)

    [pscustomobject]@{
        ScopeId    = [ipaddress]"10.10.1.0"
        Name       = "Office-Malmo"
        SubnetMask = [ipaddress]"255.255.255.0"
        StartRange = [ipaddress]"10.10.1.1"
        EndRange   = [ipaddress]"10.10.1.254"
        State      = "Active"
    }

    [pscustomobject]@{
        ScopeId    = [ipaddress]"10.10.2.0"
        Name       = "Office-Helsingborg"
        SubnetMask = [ipaddress]"255.255.255.0"
        StartRange = [ipaddress]"10.10.2.1"
        EndRange   = [ipaddress]"10.10.2.254"
        State      = "Active"
    }

    [pscustomobject]@{
        ScopeId    = [ipaddress]"10.10.3.0"
        Name       = "Lager"
        SubnetMask = [ipaddress]"255.255.255.0"
        StartRange = [ipaddress]"10.10.3.1"
        EndRange   = [ipaddress]"10.10.3.254"
        State      = "Active"
    }

    [pscustomobject]@{
        ScopeId    = [ipaddress]"10.20.0.0"
        Name       = "Testlab"
        SubnetMask = [ipaddress]"255.255.252.0"
        StartRange = [ipaddress]"10.20.0.10"
        EndRange   = [ipaddress]"10.20.3.200"
        State      = "Active"
    }
}

function Get-DhcpServerv4ExclusionRange {
    param($ComputerName, $ScopeId, $ErrorAction)

    # Only the Lager scope excludes anything.
    if ($ScopeId -and $ScopeId.ToString() -ne "10.10.3.0") {
        return
    }

    [pscustomobject]@{
        ScopeId    = [ipaddress]"10.10.3.0"
        StartRange = [ipaddress]"10.10.3.1"
        EndRange   = [ipaddress]"10.10.3.10"
    }
}

Export-ModuleMember -Function Get-DhcpServerv4Scope, Get-DhcpServerv4ExclusionRange
