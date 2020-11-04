$users = Get-ADUser -Filter * -Properties "admincount" | Where-Object {$_.admincount -ne $null -and $_.samaccountname -notmatch ''}


#HashTable to be used for the reset


$isProtected = $false ## allows inheritance
$preserveInheritance = $true ## preserve inheritance rules


ForEach($user in $users)
{
    # Binding the users to DS
    $ou = [ADSI]("LDAP://" + $user)
    $sec = $ou.psbase.objectSecurity

    if ($sec.get_AreAccessRulesProtected())
    {
		#Changes AdminCount back to not set
        Get-ADuser $user.DistinguishedName -Properties "admincount" | Set-ADUser -Clear AdminCount
        #Change security and commit
		$sec.SetAccessRuleProtection($isProtected, $preserveInheritance)
        $ou.psbase.commitchanges()
    }
}