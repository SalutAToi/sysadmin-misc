# This script was designed by Cater Care to handle local admin password change
# AUTHOR : Christophe BAHIN

# It check for the existence of a local admin with a designated name, creates it if non existent
# generates a secure random password of a given length a apply it to the designated local admin
# it then stores that password in a registry key as value for Datto RMM to recover
# Datto will send it to its database as a user defined field and delete the value

# adding the .NET class containing the method to generate passwords
Add-Type -AssemblyName 'System.Web'

# specifications for local account
$PasswordLength = 25
$PasswordAmountOfSpecialCharacters = 0
$LocalAdminName = "localadmin"

# datto registry settings
$DattoRegistryPath = "HKLM:\SOFTWARE\CentraStage"
$DattoCustomField = "Custom3"

function Get-Context { 
    # Will get os version to determine if the script run as legacy (win 7, 8, ...) or normal (w10)

    $OSName = (Get-WMIObject win32_operatingsystem).name

    # using a regex match to check if windows 10
    if ($OSName -Match 'Microsoft Windows 10') {
        return $False
    }
    else { return $True }
}

function Handle-LocalAdminAccount {
    # Will return the localadmin account as an object if it exists, or create it and return it
    # if it does not

    if ($LocalAdminAccount =  Get-LocalUser -Name $LocalAdminName -ErrorAction SilentlyContinue) {
        return $LocalAdminAccount
    }
    else {
        $LocalAdminAccount = New-LocalUser -Name $LocalAdminName -Disabled -NoPassword
        return $LocalAdminAccount
    }
}

function Set-LocalAccount ($Password, $Account) {
    # will change the password to the random one provided for the account provided
    # will then enable the account (no consequence if already enabled), necessary if the account was just created
    # and add the user to the administrator group while ignoring the "already a member" error

    $Account | Set-LocalUser  -Password (ConvertTo-SecureString "$Password" -AsPlainText -Force)
    $Account | Enable-LocalUser
    Add-LocalGroupMember -Name "Administrators" -Member $Account -ErrorAction SilentlyContinue
}

function Handle-LegacyLocalAdminAccount {
    # legacy code for non windows 10 computer, will check if the account exists and create it if not

    if (! (& net user $LocalAdminName)) {
        & net user /add /active:no $LocalAdminName
    }
}

function Set-LegacyLocalAccount {
    # legacy code for non windows 10 computer, will enable the localadmin account and set the generated password
    # and add the user to the group
    # AN ERROR RETURNED IS NORMAL IF THE ACCOUNT IS ALREADY A MEMBER OF THE GROUP

    & net user /active:yes $LocalAdminName "$RandomPassword"
    & net localgroup /add Administrators $LocalAdminName
}

# determine if legacy mode should be on
$Legacy = Get-Context

# This will generate a password with the given length and number of special characters
$RandomPassword = [System.Web.Security.Membership]::GeneratePassword($PasswordLength,$PasswordAmountOfSpecialCharacters)

# run legacy if mode is set to true
if ($Legacy -eq $True) {
    Handle-LegacyLocalAdminAccount
    Set-LegacyLocalAccount
}
# else run normal powershell mode
else {
    $LocalAdminAccount = Handle-LocalAdminAccount
    Set-LocalAccount $RandomPassword $LocalAdminAccount
}

# create the registry key for Datto to export the password on a custom field
New-ItemProperty -Path $DattoRegistryPath -Name $DattoCustomField -Value "$RandomPassword" -Force | Out-Null


