$BaseGroupPath = "CN=Access Control,CN=Security groups,OU=Corp,DC=domain,dc=com"
$GroupScope = "DomainLocal"

$Shares = @(
    @{
        name     = "configuration files";
        location = "F:\IT administration\configuration files";
        server   = "server-name";
        hidden = $true
    },
    @{
        name     = "software deployment";
        location = "F:\IT administration\software deployment";
        server   = "server-name";
        hidden = $true
    }
)

function Check-Requirements () {


    if (! (Get-Module -ListAvailable -Name NTFSSecurity)) {
        $exit = $true
        Write-Host "You're missing Powershell module NTFSSecurity. Please install"
    }

    if (! (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $exit = $true
        Write-Host "You're missing Powershell module ActiveDirectory. Please install"
    }

    if ($exit -eq $true) {
        exit
    }


}

function Get-UNCpath ($Path, $Server) {

    $PathPartial = $Path -replace ":", "$"
    $UNCPath = "\\" + $Server + "\$PathPartial"

    return $UNCPath
}

function Create-Path ($Path) {

    $PathExists = Test-Path $Path

    if ($PathExists -eq $false) {
        Write-Host "The path does not exist.`n Creating $Path"
        New-Item -ItemType Directory -Path $Path
    }
    
}

function Get-ShareName ($Name, $Hidden) {

    if ($Hidden -eq $true) {
        $ShareName = $Name + "$"
    }
    else {
        $ShareName = $Name
    }

    return $ShareName
}


Check-Requirements
Import-Module NTFSSecurity,ActiveDirectory


foreach ($Share in $Shares) {
    
    $RemoteSession = New-CimSession -ComputerName $Share.server

    $UNCPath = Get-UNCpath $Share.location $Share.server
    Create-Path $UNCPath

    $ShareName = Get-ShareName $Share.name $Share.hidden

    $ROGroupName = "SHR_" + $Share.name + "_RO"
    $RWGroupName = "SHR_" + $Share.name + "_RW"

    
    Write-Host 'creating groups'
    New-ADGroup -Path $BaseGroupPath -Name $ROGroupName -GroupScope $GroupScope -GroupCategory "Security"
    New-ADGroup -Path $BaseGroupPath -Name $RWGroupName -GroupScope $GroupScope -GroupCategory "Security"

    $ROGroup = "domain\" + $ROGroupName
    $RWGroup = "domain\" + $RWGroupName

    Write-Host 'creating share'
    New-SmbShare -CimSession $RemoteSession -Name $ShareName -Path $Share.location -FullAccess "Authenticated Users"

    # inheritance is disabled and inherited permissions are transformed in effective ones
    Write-Host 'disabling inheritance'
    Disable-NTFSAccessInheritance $UNCPath

    # removes all ACE of the server user
    Write-Host 'removing users perms'
    Get-NTFSAccess -Account 'BUILTIN\Users' -Path $UNCPath | Remove-NTFSAccess

    Write-Host 'adding access to group'
    Add-NTFSAccess -Account $ROGroup -Path $UNCPath -AccessRights ReadAndExecute,ListDirectory,Read
    Add-NTFSAccess -Account $RWGroup -Path $UNCPath -AccessRights ReadAndExecute,ListDirectory,Read,Modify,Write


}