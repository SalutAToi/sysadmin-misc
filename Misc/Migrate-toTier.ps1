# Migrate the Company infrastructure to the new Tier OU structure
# Requires the Powershell module for AD


# module import for the script, using AD and datto
Import-Module ActiveDirectory
Import-Module DattoRMM

$APISecretKey = Read-Host -Prompt "Please input the secret API key "

# configuration for datto API
$params = @{
    Url       = 'datto api url'
    Key       = 'datto key'
    SecretKey = $APISecretKey
}

# giving api params to datto
Set-DrmmApiParameters @params

# location where to find users and computers to migrate
$SearchBases = @(
    "OU=Offices,DC=domain,dc=com",
    "OU=XXX domain(To Be),DC=domain,dc=com"
)


# object contaning all non treated objects
$RemainingObjects = @()

$LogFileFullPath = ".\Migrate-ToTier.log"

$RemainingInfoFilePath = ".\RemainingObjectsComplete.csv"

# offices, validating regex and related OU
$OUsMap = @{
    Sydney        = @{
        regex = 'Sydney'
        OU    = 'OU=Sydney,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    Perth         = @{
        regex = 'Perth'
        OU    = 'OU=Perth,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    Adelaide      = @{
        regex = 'Adelaide'
        OU    = 'OU=Adelaide,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    Melbourne     = @{
        regex = 'Melbourne'
        OU    = 'OU=Melbourne,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    Brisbane      = @{
        regex = 'Brisbane'
        OU    = 'OU=Brisbane,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    google       = @{
        regex = '^CC.*|^Brisbane.*|^Cancer.*|^Gold.*|^South Pacific.*|^Warrigal.*|^West.*|^Grinders.*|^Mackay.*|^Newcastle.*|^Sunshine.*|^Kintyre.*|^Sushi.*|^Sydney.*'
        OU    = 'OU=G Sync,OU=Users,OU=Corp,DC=domain,dc=com'
    }
    laptop        = @{
        regex = 'Laptop'
        OU    = 'OU=Laptops,OU=Tier 2,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    desktop       = @{
        regex = 'Desktop'
        OU    = 'OU=Desktops,OU=Tier 2,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    contractors   = @{
        regex = 'contractors'
        OU    = 'OU=Contractors,OU=Users,OU=Corp,DC=domain,dc=com'
    };
    shared        = @{
        regex = 'shared'
        OU    = 'OU=Shared,OU=Tier 2,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    app_server    = @{
        regex = 'app_server'
        OU    = 'OU=Application,OU=Tier 1,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    net_server    = @{
        regex = 'net_server'
        OU    = 'OU=Network,OU=Tier 1,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    file_server   = @{
        regex = 'file_server'
        OU    = 'OU=File,OU=Tier 1,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    update_server = @{
        regex = 'update_server'
        OU    = 'OU=Update,OU=Tier 1,OU=Computers,OU=Corp,DC=domain,dc=com'
    };
    t0_paw        = @{
        regex = 't0_paw'
        OU    = 'OU=Privileged Access Workstations,OU=Tier 0,OU=Corp,DC=domain,dc=com'
    };
    t1_paw        = @{
        regex = 't1_paw'
        OU    = 'OU=Privileged Access Workstations,OU=Tier 1,OU=Corp,DC=domain,dc=com'
    };
    t0_service    = @{
        regex = 't0_service'
        OU    = 'OU=Users,OU=Tier 0,OU=Service,OU=Corp,DC=domain,dc=com'
    };
    t1_service    = @{
        regex = 't1_service'
        OU    = 'OU=Users,OU=Tier 1,OU=Service,OU=Corp,DC=domain,dc=com'
    }
    
}


function Write-Log { 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory = $true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message,
 
        [Parameter(Mandatory = $false)] 
        [Alias('LogPath')] 
        [string]$Path = $LogFileFullPath,
         
        [Parameter(Mandatory = $true)]
        [Alias('LogLevel')] 
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level
    ) 
 
    Begin { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process { 
         
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        if (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File 
        } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
            } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
            } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
            } 
        } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End { 
    }
}
function Add-Remaining {
    #adds a user to the $remaining variable in a specific format

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory = $true)] 
        [ValidateNotNullOrEmpty()] 
        [ValidateSet("User", "Computer", "Group")]
        [string]$ObjectType,     
    
        [Parameter(Mandatory = $true)] 
        [ValidateNotNullOrEmpty()] 
        [string]$SAMAccountName, 
    
        [Parameter(Mandatory = $true)] 
        [string]$Reason, 
            
        [Parameter(Mandatory = $false)]
        [string]$Migrateto = $null,

        [Parameter(Mandatory = $false)]
        [string]$ComputerType = "N/A"
    ) 
    
    Begin { 
    } 
    Process {
        
        $RemainingEntry = [ordered] @{
            'type'           = $ObjectType;
            'samaccountname' = $SAMAccountName;
            'computertype'   = $ComputerType;
            'reason'         = $Reason;
            'migrateto'      = $MigrateTo;
            'comment'        = ''
        }
        
        $script:RemainingObjects += New-Object PSObject -Property $RemainingEntry
    
    } 
    End { 
    }
}

function Get-DattoInformation () {
    # will get a list of all computers and their corresponding category (laptop, server or desktop)

    $DevicesType = @{}
    Get-DrmmAccountDevices | ForEach-Object {
        $DevicesType[$_.hostname] = $_.deviceType.category
    }

    return $DevicesType
}

function Move-UsertoTier ($User) {
    #From the attribute and name of the user account, will decide where the users needs to be moved and move it
    # or adds it to a list of remaining users

    $Username = $User.name

    switch -regex ($User.physicalDeliveryOfficeName) {
        $OUsMap['Sydney']['regex'] {
            Move-ADObject -Identity $User -TargetPath $OUsMap['Sydney']['OU']
            Write-Log -LogContent "Moving $Username to Sydney OU" -Level Info
        }
        $OUsMap['Adelaide']['regex'] {
            Move-ADObject -Identity $User -TargetPath $OUsMap['Adelaide']['OU']
            Write-Log -LogContent "Moving $Username to Adelaide OU" -Level Info
        }
        $OUsMap['Melbourne']['regex'] {
            Move-ADObject -Identity $User -TargetPath $OUsMap['Melbourne']['OU']
            Write-Log -LogContent "Moving $Username to Melbourne OU" -Level Info
        }
        $OUsMap['Brisbane']['regex'] {
            Move-ADObject -Identity $User -TargetPath $OUsMap['Brisbane']['OU']
            Write-Log -LogContent "Moving $Username to Brisbane OU" -Level Info
        }
        $OUsMap['Perth']['regex'] {
            Move-ADObject -Identity $User -TargetPath $OUsMap['Perth']['OU']
            Write-Log -LogContent "Moving $Username to Perth OU" -Level Info
        }
        $null {
            if ($User.Name -match $OUsMap['google']['regex'] ) {
                Move-ADObject -Identity $User -TargetPath $OUsMap['google']['OU']
                Write-Log -LogContent "Moving $Username to google OU" -Level Info
            }
            elseif ($User.Name -cmatch '^[A-Z][a-z]* [A-Z][a-z]*$') {
                # regex validating a regular user name, cmatch for case sensitivity, will return false positives
                Add-Remaining -ObjectType 'User' -SAMAccountName $User.SAMAccountName -Reason "Potential office user w/o office"
            }
            else {
                Add-Remaining -ObjectType 'User' -SAMAccountName $User.SAMAccountName -Reason "Unknow user"
            }
        } # $null 
        Default {
            Add-Remaining -ObjectType 'User' -SAMAccountName $User.SAMAccountName -Reason "Invalid Office name"
        }
    } #  switch -regex ($User.physicalDeliveryOfficeName)
} #function Move-UsertoTier


function Move-ComputerToTier ($Computer) {
    # From a query to Datto to determine the type, decides where the computer needs to be moved

    $Computername = $Computer.Name

    switch ($DevicesType[$Computer.Name]) {
        $OUsMap['laptop']['regex'] { 
            Move-ADObject -Identity $Computer -TargetPath $OUsMap['laptop']['OU']
            Write-Log -LogContent "Moving $Computername to laptop OU" -Level Info
            
        }
        $OUsMap['desktop']['regex'] { 
            Move-ADObject -Identity $Computer -TargetPath $OUsMap['desktop']['OU']
            Write-Log -LogContent "Moving $Computername to desktop OU" -Level Info
        }
        'Server' { 
            Add-Remaining -ObjectType 'Computer' -SAMAccountName $Computer.SAMAccountName -ComputerType $DevicesType[$Computer.Name] -Reason "Server"
        }
        Default {
            Add-Remaining -ObjectType 'Computer' -SAMAccountName $Computer.SAMAccountName -ComputerType $DevicesType[$Computer.Name] -Reason "Unknow type"
        }
    }
}

$DevicesType = Get-DattoInformation

if (Test-Path $RemainingInfoFilePath) {
    Import-CSV $RemainingInfoFilePath | ForEach-Object {
        if ($_.migrateto -notlike $null) {
            if ($_.type -like 'User') {
                Get-ADUser -Identity $_.samaccountname | Move-ADObject -TargetPath $OUsMap[$_.migrateto]['OU']
                $Username = $_.samaccountname
                $OU = $OUsMap[$_.migrateto]['OU']
                Write-Log -LogContent "Moving $Username to $OU OU" -Level Info
            }
            elseif ($_.type -like 'Computer') {
                Get-ADComputer -Identity $_.samaccountname | Move-ADObject -TargetPath $OUsMap[$_.migrateto]['OU']
                $Computername = $_.samaccountname
                $OU = $OUsMap[$_.migrateto]['OU']
                Write-Log -LogContent "Moving $Computername to $OU OU" -Level Info
            }
            
        }
    }
    Write-Log -LogContent "========================================================================================" -Level Info
}

# foreach ($SearchBase in $SearchBases) {
#     $UsersToMigrate += Get-ADUser -Properties physicalDeliveryOfficeName -SearchBase $SearchBase -Filter *
#     $ComputersToMigrate += Get-ADComputer -SearchBase $SearchBase -Filter *
# }

# foreach ($User in $UsersToMigrate) {
#     Move-UsertoTier $User
# }

# foreach ($Computer in $ComputersToMigrate) {
#     Move-ComputerToTier $Computer
# }


$RemainingObjects | Export-CSV -NoTypeInformation -Path .\RemainingObjects.csv
