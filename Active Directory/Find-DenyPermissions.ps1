# finds all users having deny permissions on their acl


$SearchBase = ''

$UsersList = Get-ADUser -Filter * -SearchBase $SearchBase

$UsersList | ForEach-Object {
   
    $DN = $_.distinguishedname
    $ACL = Get-ACL -Path "Microsoft.ActiveDirectory.Management.dll\ActiveDirectory:://RootDSE/$DN" 
    
    $DenyACEs = $ACL.Access | Where-Object { $_.AccessControlType -eq "Deny" }
    
    foreach ($DenyACE in $DenyACEs) {
        echo $_.samaccountname
    }
}
