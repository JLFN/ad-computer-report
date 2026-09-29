<#
Emulation only. This module stands in for the ActiveDirectory module that
ComputerReport.ps1 imports, so the script can be run end to end on a machine
that has no domain controller and no RSAT, including Linux and macOS.

It answers the two cmdlets the script calls:

  Get-ADOrganizationalUnit - accepts any identity, so the OU check passes.
  Get-ADComputer           - returns a fixed set of invented computers.

Nothing here talks to a network or a directory. The objects it returns carry
the same bookkeeping properties (PropertyNames, AddedProperties, and friends)
that the real AD module adds, so the script's column handling is exercised
the same way.
#>

function Get-ADOrganizationalUnit {
    param($Identity, $ErrorAction)
    [pscustomobject]@{ DistinguishedName = $Identity }
}

function New-AdComputerObject {
    param([hashtable]$Values)

    $row = @{
        PropertyNames      = @()
        AddedProperties    = @{}
        RemovedProperties  = @{}
        ModifiedProperties = @{}
        PropertyCount      = 0
    }

    foreach ($key in $Values.Keys) { $row[$key] = $Values[$key] }

    [pscustomobject]$row
}

function Get-ADComputer {
    param($Filter, $SearchBase, $SearchScope, $Properties, $ErrorAction)

    # PC-001: one address, reached through a CNAME. Non-ASCII text in the
    # description, to show that the CSV keeps its characters.
    New-AdComputerObject @{
        Name                   = "PC-001"
        DNSHostName            = "pc-001.example.com"
        Description            = "Reception - Ångströmsrummet, plan 2"
        DistinguishedName      = "CN=PC-001,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"11111111-1111-1111-1111-111111111111"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 11 Pro"
        OperatingSystemVersion = "10.0 (22631)"
        LastLogonDate          = [datetime]"2026-09-24T08:12:00"
        whenCreated            = [datetime]"2021-03-04T11:45:00"
        Enabled                = $true
        Location               = "Malmo"
        MemberOf               = @("CN=GG-Workstations,OU=Groups,DC=example,DC=com")
        ServicePrincipalNames  = @("HOST/PC-001", "HOST/pc-001.example.com")
    }

    # PC-002: two addresses, and a multi-valued attribute.
    New-AdComputerObject @{
        Name                   = "PC-002"
        DNSHostName            = "pc-002.example.com"
        Description            = "Ekonomi - Lisa Oberg"
        DistinguishedName      = "CN=PC-002,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"22222222-2222-2222-2222-222222222222"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 10 Enterprise"
        OperatingSystemVersion = "10.0 (19045)"
        LastLogonDate          = [datetime]"2026-09-29T07:03:00"
        whenCreated            = [datetime]"2019-11-18T09:20:00"
        Enabled                = $true
        Location               = "Helsingborg"
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }

    # PC-003: resolves to an IPv6 address only, so no A record is found.
    New-AdComputerObject @{
        Name                   = "PC-003"
        DNSHostName            = "pc-003.example.com"
        Description            = "Lager - vågstation, Övre gården"
        DistinguishedName      = "CN=PC-003,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"33333333-3333-3333-3333-333333333333"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 11 IoT Enterprise"
        OperatingSystemVersion = "10.0 (22631)"
        LastLogonDate          = [datetime]"2026-09-20T22:31:00"
        whenCreated            = [datetime]"2023-06-01T13:00:00"
        Enabled                = $true
        Location               = "Malmo"
        MemberOf               = @("CN=GG-Lager,OU=Groups,DC=example,DC=com")
        ServicePrincipalNames  = @("HOST/PC-003")
    }

    # PC-004: no DNS host name in the directory, so the script falls back to
    # the computer name; that name does not resolve. Also has no description.
    New-AdComputerObject @{
        Name                   = "PC-004"
        DNSHostName            = $null
        Description            = $null
        DistinguishedName      = "CN=PC-004,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"44444444-4444-4444-4444-444444444444"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows Server 2022 Standard"
        OperatingSystemVersion = "10.0 (20348)"
        LastLogonDate          = [datetime]"2026-01-02T04:00:00"
        whenCreated            = [datetime]"2020-08-14T15:30:00"
        Enabled                = $false
        Location               = $null
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }

    # PC-005: present in the OU but never requested, so it only shows up in
    # the "AD computers loaded" count.
    New-AdComputerObject @{
        Name                   = "PC-005"
        DNSHostName            = "pc-005.example.com"
        Description            = "Test"
        DistinguishedName      = "CN=PC-005,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"55555555-5555-5555-5555-555555555555"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 11 Pro"
        OperatingSystemVersion = "10.0 (22631)"
        LastLogonDate          = $null
        whenCreated            = [datetime]"2024-02-29T10:10:00"
        Enabled                = $true
        Location               = "Lund"
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }

    # PC-006: resolves to an address that is in no DHCP scope at all.
    New-AdComputerObject @{
        Name                   = "PC-006"
        DNSHostName            = "pc-006.example.com"
        Description            = "Konferens - utlanad dator"
        DistinguishedName      = "CN=PC-006,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"66666666-6666-6666-6666-666666666666"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 11 Pro"
        OperatingSystemVersion = "10.0 (22631)"
        LastLogonDate          = [datetime]"2026-05-11T09:00:00"
        whenCreated            = [datetime]"2022-10-05T08:00:00"
        Enabled                = $true
        Location               = "Lund"
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }

    # PC-007: resolves into a scope's subnet but inside its exclusion range.
    New-AdComputerObject @{
        Name                   = "PC-007"
        DNSHostName            = "pc-007.example.com"
        Description            = "Lager - skrivare"
        DistinguishedName      = "CN=PC-007,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"77777777-7777-7777-7777-777777777777"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 10 Enterprise"
        OperatingSystemVersion = "10.0 (19045)"
        LastLogonDate          = [datetime]"2026-09-28T14:20:00"
        whenCreated            = [datetime]"2020-01-20T12:00:00"
        Enabled                = $true
        Location               = "Malmo"
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }

    # PC-008: resolves into a scope whose subnet mask is not /24.
    New-AdComputerObject @{
        Name                   = "PC-008"
        DNSHostName            = "pc-008.example.com"
        Description            = "Testlab - klient"
        DistinguishedName      = "CN=PC-008,OU=Computers,OU=Company,DC=example,DC=com"
        ObjectGUID             = [guid]"88888888-8888-8888-8888-888888888888"
        ObjectSID              = [byte[]](1, 5, 0, 0)
        OperatingSystem        = "Windows 11 Enterprise"
        OperatingSystemVersion = "10.0 (22631)"
        LastLogonDate          = [datetime]"2026-09-25T16:45:00"
        whenCreated            = [datetime]"2024-04-02T10:30:00"
        Enabled                = $true
        Location               = "Lund"
        MemberOf               = $null
        ServicePrincipalNames  = $null
    }
}

Export-ModuleMember -Function Get-ADComputer, Get-ADOrganizationalUnit
