$JSONArchiveTasksPath = ".\Save-WindowsServerArchiveData.json"
# get object from JSON file
$ArchiveTasks = Get-Content -Path $JSONArchiveTasksPath | ConvertFrom-Json

# informations concerning target repository for archived files and log repository for robocopy
$ArchiveTargetName = "server-name"
$ArchiveTargetDriveLetter = "F"
$ArchiveTargetParentFolder = "Archive\Data"
$UNCRobocopyLogPath = "\\" + $ArchiveTargetName + "\" + $ArchiveTargetDriveLetter + "$\" + $ArchiveTargetParentFolder + "\Logs"
$LogFileFullPath = $UNCRobocopyLogPath + "\Save-WindowsServerArchiveData.log"



##############################################################################################################
#                                 General function for script wide use                                       # 
##############################################################################################################


function Write-Log { 
    # This will handles writing to a log file with different level and the possibility to write to the user prompt
    # at the same time

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory = $true, 
            ValueFromPipelineByPropertyName = $true)] 
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
            $NewLogFile = New-Item $Path -Force -ItemType File 
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


function Get-RunningContext ($Argument) {
    # from the argument, if it equals live, returns live, otherwise return test
    # this will by default run the script in test mode (list only) and only start live if the user requests it
    # running context is logged

    if ($Argument -eq "LIVE") {
        Write-Log  -LogContent "Running context is LIVE" -Level "Info"
        return $true
    }
    else {
        Write-Log  -LogContent "Running context is TEST" -Level "Info"
        return $false
    }
}


##############################################################################################################
#                                 Functions realizing script actions                                         # 
##############################################################################################################

function Copy-ArchiveTaskData ($Source, $Destination, $LogUNCPath) {
    # this will call robocopy to perform the copy from $Source to $Destination with specific options, 
    # handling test mode. Beware as test mode can take a lot of time, as it will list everything
    
    if ($LIVEMode -eq $true) { robocopy /FFT /XO /E /Z /R:2 /W:3 /MT:32 /TEE /LOG+:$LogUNCPath $Source $Destination }
    else { robocopy /FFT /XO /E /Z /R:2 /W:3 /MT:32 /L /TEE /LOG+:$LogUNCPath $Source $Destination }
    
    # for documentation on robocopy options, see https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
}


##############################################################################################################
#                          Checks and informations gathering functions                                       # 
##############################################################################################################

function Get-Server ($ServerName) {
    # this will test that the server is a member of Active Directory and if it is reachable via the network, and if so, return it with error handling

    # checks membership in AD and catches an error if not present
    try {
        $Server = Get-ADComputer -Identity $ServerName
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Log -LogContent "The computer $ServerName does not exist in Active Directory." -Level "Error" 
        return $false
    }

    # verifies the connection to the server
    if (! (Test-Connection -ComputerName $Server.name -Count 2 -Quiet)) {
        Write-Log -LogContent "$Server cannot be reached via the network." -Level "Error"
        return $false
    }
    # if in AD and reachable, return $Server object
    else {
        return $Server
    }
}

function Test-ServerDrive ($Drive, $Server) {
    # this will check that a server has a share that corresponds to a specific drive

    # create the UNC path for the given drive (all drive have a hidden share unless deleted)
    $DriveHiddenPath = "\\" + $Server.Name + "\" + $Drive + "$"
    $DriveExists = Test-Path -Path $DriveHiddenPath

    return $DriveExists
}


function Get-UNCPath ($FolderPath, $Drive, $Server) {
    # this will check a given folder exists and the current user has read permission on it, and if so, returns the UNC path

    $UNCPath = "\\" + $Server.Name + "\" + $Drive + "$\" + $FolderPath
    $FolderExists = Test-Path -Path $UNCPath

    # check if parent folder to archive is readable by catching access unauthorized errors
    # beware this will not check all children folders ; if a children is not readable, this will be logged
    # by robocopy but will not be caught here
    try {
        # Without erroraction to stop, the try/catch will not catch System.UnauthorizedAccessException as
        # they're not by default terminating errors
        # out-null so that the user is not prompted with the result of Get-ChildItem
        Get-ChildItem $UNCPath -ErrorAction Stop | Out-Null
        # will only be set to true if there is no error
        $FolderIsReadable = $true
    } # try
    catch [System.UnauthorizedAccessException] {
        Write-Log -LogContent $_.Exception.Message -Level "Error"
        $FolderIsReadable = $false
    }
    
    return $UNCPath, $FolderExists, $FolderIsReadable
}
##############################################################################################################
#                                           Main script                                                      # 
##############################################################################################################

# sets the variable defining if running in live mode
$LIVEMode = Get-RunningContext $args[0]

# create the log repository if it doesn't exist, silently continue to handle cases where it already exists without disturbing the user
# out-null to avoid displaying the result
New-Item -ItemType Directory $UNCRobocopyLogPath -ErrorAction SilentlyContinue | Out-Null

# assigning $ArchiveTarget while handling errors from it and exiting if there is
if (! ($ArchiveTarget = Get-Server $ArchiveTargetName)) {
    Write-Log -LogContent "The Archive target $ArchiveTargetName test has returned an error." -Level "Error"
    Write-Log -LogContent "Exiting the script as the first condition is not met" -Level "Info"
    exit
}

# loop through every server listed in the configuration
foreach ($ServerArchiveTask in $ArchiveTasks) {
    
    # gets the server object while handling non existence and skipping that loop if it returns an error
    if (! ($Server = Get-Server $ServerArchiveTask.server)) {
        Write-Log -LogContent "The Archive source server $($ServerArchiveTask.server) test has returned an error." -Level "Error"
        Write-Log -LogContent "Skipping $($ServerArchiveTask.server)." -Level "Info"
        continue
    }

    # loop through every drive listed for archive in a server
    foreach ($DriveArchiveTask in $ServerArchiveTask.tasks) {

        # skips the loop (and therefore the drive) if the drive does not exist
        if (Test-ServerDrive - eq $false) {
            Write-Log -LogContent "The drive $($DriveArchiveTask.drive) on $($ServerArchiveTask.server) does not exist or is not shared" -Level "Error"
            Write-Log -LogContent "Skipping drive $($DriveArchiveTask.drive) on $($ServerArchiveTask.server)." -Level "Info"
            continue
        }

        # loop through every folder listed for archive on that drive
        foreach ($FolderArchivePartialPath in $DriveArchiveTask.path) {

            # get all verifications for the folders
            $FolderUNCPath, $FolderExists, $FolderIsReadable = Get-UNCPath $FolderArchivePartialPath $DriveArchiveTask.drive $Server
            # create the path for the archive target (server) where the archive will be stored
            $ArchiveTargetUNCPath = "\\" + $ArchiveTarget.name + "\" + $ArchiveTargetDriveLetter + "$\" + $ArchiveTargetParentFolder +
                "\" + $Server.name + "\" + $DriveArchiveTask.drive + "\" + $FolderArchivePartialPath

                # set logging options for robocopy logs (different from the script logs) with one log file per robocopy operations
                # stored in a tree similar to that of the file
                $RobocopyLogName = "ROBOCOPY_" + $Server.name + "_" + $DriveArchiveTask.drive + ".log"
                $ArchiveTargetRobocopyLogUNCPath = $UNCRobocopyLogPath + "\" + $RobocopyLogName

            # handles cases where the check variables from Get-UNCPath are not both $true, skips if they aren't and perform the copy if $true
            if ($FolderExists -eq $true -AND $FolderIsReadable -eq $true) {
                Write-Log -LogContent "Initiating robocopy, LIVEMode = $LIVEMode, Source = $FolderUNCPath, Destination = $ArchiveTargetUNCPath" -Level "Info"
                Copy-ArchiveTaskData $FolderUNCPath $ArchiveTargetUNCPath $ArchiveTargetRobocopyLogUNCPath
            }
            else {
                Write-Log -LogContent "Skipping copy for $FolderUNCPath because the folder does not exist or is not readable by the user running the script" -Level "Info"
            }
        } # foreach ($FolderArchivePartialPath in $DriveArchiveTask.path)
    } # foreach ($DriveArchiveTask in $ServerArchiveTask.tasks)
} # foreach ($ServerArchiveTask in $ArchiveTasks)
