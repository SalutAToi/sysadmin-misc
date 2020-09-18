$OldSuffix = "domain.com"
$NewSuffix = "domain.com"
$OU = "OU=Users,OU=Corp,DC=domain,dc=com"


Get-ADUser -SearchBase $OU -Filter * | ForEach-Object {
    $NewUPN = $_.UserPrincipalName.Replace($OldSuffix,$NewSuffix)

    $_ | Set-ADUser -UserPrincipalName $NewUPN -Verbose *>> .\log.txt
}