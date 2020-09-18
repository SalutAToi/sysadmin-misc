# this will create a lab environemnent with a DC


# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# NOT TO BE USED IN PRODUCTION, TESTING ONLY
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# Define the Computer Name
$computerName = "dcname"

# Define the IPv4 Addressing
$IPv4Address = "10.0.42.100"
$IPv4Prefix = "24"
$IPv4DNS = "10.0.42.100"

$domainName  = "domain.com"
$netBIOSname = "domain"
$mode  = "WinThreshold"

$ipIF = (Get-NetAdapter).ifIndex




if ($args[0] -eq 1) {
    # Turn off IPv6 Random & Temporary IP Assignments
    Set-NetIPv6Protocol -RandomizeIdentifiers Disabled
    Set-NetIPv6Protocol -UseTemporaryAddresses Disabled

    # Turn off IPv6 Transition Technologies
    Set-Net6to4Configuration -State Disabled
    Set-NetIsatapConfiguration -State Disabled
    Set-NetTeredoConfiguration -Type Disabled

    # Add IPv4 Address, Gateway, and DNS
    New-NetIPAddress -InterfaceIndex $ipIF -IPAddress $IPv4Address -PrefixLength $IPv4Prefix
    Set-DNSClientServerAddress –interfaceIndex $ipIF –ServerAddresses $IPv4DNS

    # Rename the Computer, and Restart
    Rename-Computer -NewName $computerName -force
    Restart-Computer
}

if ($args[0] -eq 2) {
    Install-WindowsFeature AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools
    Import-Module ADDSDeployment
    $forestProperties = @{

        DomainName           = $domainName
        DomainNetbiosName    = $netBIOSname
        ForestMode           = $mode
        DomainMode           = $mode
        CreateDnsDelegation  = $false
        InstallDns           = $true
        DatabasePath         = "C:\Windows\NTDS"
        LogPath              = "C:\Windows\NTDS"
        SysvolPath           = "C:\Windows\SYSVOL"
        NoRebootOnCompletion = $false
        Force                = $true

    }
    Install-ADDSForest @forestProperties
}


if ($args[0] -eq 3) {
    Add-ADGroupMember -Identity "Remote Desktop Users" -Members "Domain Users"
    Set-ADDefaultDomainPasswordPolicy -MinPasswordAge 0 -MaxPasswordAge 0 -ComplexityEnabled $false -MinPasswordLength 0 -PasswordHistoryCount 0 -LockoutObservationWindow 0 -LockoutThreshold 0 -Identity $domainName
}
