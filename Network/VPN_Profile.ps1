# internal documentation is available at https://docs.google.com/document/d/1KWl379Rvqb6IDjac5SsFdY0JbP5HMG4JMTcgkPL-GMY/

$ConnectionName = "VPN name"
$OldConnectionName = "domain VPN"
$ServerAddress = "server ip"
$CertLocation = "./cert" # certificate should be moved with the script for correct execution


# Windows settings for VPN cmdlet
$TunnelType = "IKEv2"

# IKEv2 cryptography settings (details, see watchguard ikev2 vpn configuration documentation)
$Phase1Hash = "SHA256128"
$Phase2Hash = "SHA256"
$Phase1Cipher = "AES256"
$Phase2Cipher = "AES256"
$DiffieHellmanGroup = "ECP384"
$DiffieHellmanPFSGroup = "ECP384"

# Authentication type (RADIUS server, see documentation)
$AuthType = "EAP"

# VPN boolean settings
$BoolRememberCredential = $true # cache credentials so users don't have to type their password again when on a user session if they're disconnected
$BoolAllUserConnection = $true # adds the VPN to the global VPN catalogue on the computer, do not change unless you want to limit VPN use to after connection witha specific user
$BoolSplitTunnelling = $true # set to true to only redirect part of the traffic (see $Routes for list) if false, will redirect all traffic

# Event log settings for writing output and errors of the deployment script to the event log for easier debugging
$LogName = "Application"
$LogSource = "VPN deployment script"
$EventID = "4242" # event ID could be diversified, currently only using 4242 for convenience

# List of subnet for which a route should be added to the domain VPN
$Routes = @(
 # ip to route
)

function RemoveOldConnection () {
    # fix for pc having the initially incorrect name for the VPN

    # using a try/catch to return error to event log if it happens
    try {
        Remove-VpnConnection -AllUserConnection -Name $OldConnectionName -Force
    }   
    catch {
        PrintError "Error in removing old connection $OldConnectionName ! $_.Exception.Message" # transferring the exception message in event log
    }
}
function PrintError ($Message) {
    # that function will write the message in parameter as an error to the event log with the logging parameters given
    Write-EventLog -LogName $LogName -Source $LogSource -EventID $EventID -EntryType Error -Message $Message
}
function PrintInformation ($Message) {
    # that function will write the message in parameter as an information to the event log with the logging parameters given
    Write-EventLog -LogName $LogName -Source $LogSource -EventID $EventID -EntryType Information -Message $Message
}
function SetIPSecConfiguration () {
    # will configure the different ciphers for the IPSec VPN session with IKEv2, see internal documentation and microsoft : 
    # https://docs.microsoft.com/en-us/powershell/module/vpnclient/set-vpnconnectionipsecconfiguration?view=win10-ps

    # using a try/catch to return error to event log if it happens
    try {
        $params = @{
            ConnectionName                   = $ConnectionName; 
            AuthenticationTransformConstants = $Phase1Hash;
            CipherTransformConstants         = $Phase1Cipher;
            EncryptionMethod                 = $Phase2Cipher;
            IntegrityCheckMethod             = $Phase2Hash;
            PfsGroup                         = $DiffieHellmanPFSGroup;
            DHGroup                          = $DiffieHellmanGroup;
            Force                            = $true;
        }
        Set-VpnConnectionIPsecConfiguration @params
    }   
    catch {
        PrintError "Error in setting up the IPSec $ConnectionName configuration ! $_.Exception.Message" # transferring the exception message in event log
    }
}

function AddVPNConnection () {
    # will add the vpn connection and call for IPsec and route configuration, see microsoft and internal documentation :
    # https://docs.microsoft.com/en-us/powershell/module/vpnclient/add-vpnconnection?view=win10-ps

    # using a try/catch to return error to event log if it happens
    try {
        $params = @{
            ConnectionName       = $ConnectionName; 
            ServerAddress        = $ServerAddress;
            TunnelType           = $TunnelType;
            EncryptionLevel      = "Required";
            AuthenticationMethod = $AuthType;
            SplitTunneling       = $BoolSplitTunnelling;
            AllUserConnection    = $BoolAllUserConnection;
            RememberCredential   = $BoolRememberCredential
        }
        Add-VpnConnection @params
        SetIPSecConfiguration # calling for the IPsec configuration function
        AddVPNRoutes # calling for route configuration function
        PrintInformation "Created the $ConnectionName VPN connection"
    }   
    catch {
        PrintError "Error in creating the $ConnectionName VPN connection! $_.Exception.Message" # transferring the exception message in event log
    }
}
  
function UpdateVPNConnection () {
    # will update the vpn connection and call for IPsec and route configuration, see microsoft and internal documentation :
    # https://docs.microsoft.com/en-us/powershell/module/vpnclient/set-vpnconnection?view=win10-ps

    # using a try/catch to return error to event log if it happens
    try {
        $params = @{
            Name                 = $ConnectionName; 
            ServerAddress        = $ServerAddress;
            TunnelType           = $TunnelType;
            EncryptionLevel      = "Required";
            AuthenticationMethod = $AuthType;
            WarningAction        = "SilentlyContinue";
            SplitTunneling       = $BoolSplitTunnelling;
            AllUserConnection    = $BoolAllUserConnection;
            RememberCredential   = $BoolRememberCredential
        }
        Set-VpnConnection @params
        SetIPSecConfiguration # calling for the IPsec configuration function
        AddVPNRoutes # calling for route configuration function
        PrintInformation "Updated the $ConnectionName VPN connection"
    }  
    catch {
        PrintError "Error in updating the $ConnectionName VPN connection! $_.Exception.Message" # transferring the exception message in event log
    }
}

function AddVPNRoutes () {
    # will update the vpn connection and call for IPsec and route configuration, see microsoft and internal documentation :
    # https://docs.microsoft.com/en-us/powershell/module/vpnclient/set-vpnconnection?view=win10-ps

    # using a try/catch to return error to event log if it happens
    try {
        if ($BoolSplitTunnelling) {
            foreach ($Route in $Routes) {
                $params = @{
                    ConnectionName    = $ConnectionName; 
                    AllUserConnection = $BoolAllUserConnection;
                    DestinationPrefix = $Route
                }
                Add-VpnConnectionRoute @params
    }
    
        }
    }
    catch {
        PrintError "Error in adding routes for the $ConnectionName VPN connection! $_.Exception.Message" # transferring the exception message in event log
    }
}

# importing VPN server certificate for initial connection trust
Import-Certificate -CertStoreLocation cert:\LocalMachine\root $CertLocation

# Creation of an even log source for log purposes (necessary if not present, see microsoft documentation)
New-EventLog -LogName $LogName -Source $LogSource -ErrorAction SilentlyContinue # silentlycontinue if source is already created


# getting VPN connection objects if they exists, ignoring errors
$VPN = Get-VpnConnection -AllUserConnection -Name $ConnectionName -ErrorAction SilentlyContinue
$OldVPN = Get-VpnConnection -AllUserConnection -Name $OldConnectionName -ErrorAction SilentlyContinue

# check if old connection is present REMOVE AFTER JUNE 2020 WITH REMOVEOLDCONNECTION FUNCTION AND $OLDVPN VARIABLE
if ($OldVPN) {
    RemoveOldConnection
} 

# checking if the vpn connection is already there to decide between adding or updating connection
if ($VPN -and ($VPN.Name -eq $ConnectionName)) {
    UpdateVPNConnection
} 
else {
   AddVPNConnection
}


exit