<#

.COPYRIGHT
Licensed under the MIT license.
See LICENSE in the project root for license information.

Version History
0.1    Scott Breen    3/12/2019     Initial version
0.2    Scott Breen    10/12/2019    Fixed some bugs and changed get-groupmembers function to return members of all subgbroups and to only return the IDs of those objects (using transitiveMembers instead of getGroupMembers).
0.3    Scott Breen    10/12/2019    Changes code to be more efficient in only getting group membership when required and filtering the devices enrolled in the last 24 hours by default.
0.4    Scott Breen    13/01/2020    Changed to use app only authentication
0.5    Scott Breen    13/01/2020    Changed output to work with Azure Automation Runbooks
0.6    Scott Breen    17/02/2020    Added ability to just target personal devices
#>

####################################################


#change this attribute if you want to get devices enrolled within the last ‘n’ minutes. 
#Change this to 0 to get all devices. The time is in minutes.
#1440 is 24 hours
$filterByEnrolledWithinMinutes=0

#set the following attribute to true if instead of using “enrolled within last n minutes” 
#you’d like to control the schedule by getting all devices since the last execution of the 
#Azure Run book that this script is being run in. 
$useAzureAutomationLastJobTimeAsFilter=$true

#Azure AD  App Details for Auth
$tenant = "breenacademy.onmicrosoft.com"
$clientId = "851cd1f9-469d-47ba-bfde-eab80639f08f"
$clientSecret = "o6UQ3_uA?5VV_sh:7zBwMppixQiFG8V0"

#Runbook details if running in Azure Automation to detect last job run time and to ensure not conflicting with running jobs. 
#If the script is being run from an onpremises server or manually, just leave these attributes as the default, the script will 
#ignore them if it isn’t being run in the context of Azure Automation.
$runbookName = "DeviceScopeTag"
$rgName = "BreenLab"
$aaName = "BreenAuto"

#Record the list of user group to scope tag group mapping here
$UserGroupRoleGroupMapping=@()
$hash = @{                         
        UserGroupID            = "66cc746f-1219-4afb-83e1-2fcf96ea4df2" #10001 - Breen Academy North
        ScopeTagGroupID    = "af5fa98e-2b94-4cd8-9d3f-ec364882fba5"
        }                                              
$UserGroupRoleGroupMapping+=(New-Object PSObject -Property $hash)
$hash = @{                       
        UserGroupID             = "0b59cddd-d56c-4857-98d8-f1bb066a947e" #10002 - Breen Academy South
        ScopeTagGroupID    = "23cf75a8-1ba8-4602-bc4a-cdd2d4e39085"
        }                                              
$UserGroupRoleGroupMapping+=(New-Object PSObject -Property $hash)

#create the property to keep a cached copy of user group membership while the script runs
$cachedUserGroupMemberships=@()

#set to true to filter the devices retrieved to personal devices
$personalOnly=$true

#If the script is being run from Azure Automation (this variable is populated in Auzre Automation)
if ($PSPrivateMetadata.JobId) {

    $saveVerbosePreference=$VerbosePreference
    $global:VerbosePreference = 'SilentlyContinue'
    import-module AzureRM.Automation -verbose:$false
    import-module AzureRM.Profile -verbose:$false
    $global:VerbosePreference = $saveVerbosePreference

    #get the Azure Automation Account Connection
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    $ConnectionResult=Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
        -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $AzureContext = Select-AzureRmSubscription -SubscriptionId $connection.SubscriptionID

    # Check for already running or new runbooks
    $jobs = Get-AzureRmAutomationJob -ResourceGroupName $rgName -AutomationAccountName $aaName -RunbookName $runbookName -AzureRmContext $AzureContext

    # If then check to see if it is already running
    $runningCount = ($jobs | ? {$_.Status -eq "Running"}).count

    If (($jobs.status -contains "Running" -And $runningCount -gt 1 ) -Or ($jobs.Status -eq "New")) {
        # Exit code
        Write-Output "Runbook is already running"
        Exit 1
    } else {
        Write-Verbose "Runbook is not already running"
    }

    If ($useAzureAutomationLastJobTimeAsFilter) {
        write-output "Getting last job start time"
        $mostRecentJob = $jobs | ? {$_.Status -eq "Completed"} | sort-object startTime -descending | select-Object -first 1
        $LastRunTime=$mostRecentJob.startTime.dateTime
        write-verbose "Last run time was $LastRunTime"
    }
    
}



function Get-AuthTokenClientSecret {

    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>

    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$Tenant"

    #Load Azure AD Module for Authentication
    $saveVerbosePreference=$VerbosePreference
    $global:VerbosePreference = 'SilentlyContinue'
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    $global:VerbosePreference = $saveVerbosePreference
    if ($AadModule -eq $null) {
        write-error "AzureAD Powershell module not installed..."
        exit
    }

    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    if($AadModule.count -gt 1){
        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]
        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
        # Checking if there are multiple versions of the same module found
        if($AadModule.count -gt 1){
            $aadModule = $AadModule | select -Unique
        }
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    } else {
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    }

    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    

	try {

        #https://docs.microsoft.com/en-us/dotnet/api/microsoft.identitymodel.clients.activedirectory.authenticationcontext.acquiretokenasync?view=azure-dotnet#Microsoft_IdentityModel_Clients_ActiveDirectory_AuthenticationContext_AcquireTokenAsync_System_String_Microsoft_IdentityModel_Clients_ActiveDirectory_ClientCredential_
	    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
        $clientCredential = New-Object -TypeName "Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential"($clientID, $clientSecret)
        $authResult=$authContext.AcquireTokenAsync($resourceAppIdURI, $clientCredential).result

		# If the accesstoken is valid then create the authentication header
		if($authResult.AccessToken){
            # Creating header for Authorization token
		    $authHeader = @{
			    'Content-Type'='application/json'
			    'Authorization'="Bearer " + $authResult.AccessToken
			    'ExpiresOn'=$authResult.ExpiresOn
			    }

		    return $authHeader

		}

		else {
		    write-error "Authorization Access Token is null, please re-run authentication..."
		    break

		}

	}

	catch {

	    write-output $_.Exception.Message 
	    write-output $_.Exception.ItemName 
	    break

	}

}


####################################################

	
####################################################
Function Get-UserGroups {
	
[cmdletbinding()]
    param (
        $id
    )

	
	$graphApiVersion = "Beta"
	$Resource = "users/$id/getMemberGroups"
    $body='{"securityEnabledOnly": true}'
	
	try
	{

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $body).value

	}
	
	catch
	{
		
		$ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break
		
	}
	
}


####################################################
Function Get-GroupMembers {
	
[cmdletbinding()]
    param (
        $id
    )

	
	$graphApiVersion = "Beta"
	$Resource = "groups/$id/transitiveMembers"
    $body='{"securityEnabledOnly": true}'
	
	try
	{

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).value.id

	}
	
	catch
	{
		
		$ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break
		
	}
	
}
Function Get-User {
	
[cmdletbinding()]
    param (
        $id
    )

	
	$graphApiVersion = "Beta"
	$Resource = "users/$id"
	
	try
	{

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get

	}
	
	catch
	{
		
		$ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break
		
	}
	
}



Function Get-Devices {
	
[cmdletbinding()]

param
(
    $filterByEnrolledWithinMinutes,
    $enrolledSinceDate
)

#https://docs.microsoft.com/en-us/graph/query-parameters

	
	$graphApiVersion = "beta"
	$Resource = "deviceManagement/managedDevices"

    If ($filterByEnrolledWithinMinutes) {
        $minutesago = "{0:s}" -f (get-date).addminutes(0-$filterByEnrolledWithinMinutes) + "Z"
        $filter = "?`$filter=enrolledDateTime ge $minutesAgo"

        If ($personalOnly) {
            $filter ="$filter and managedDeviceOwnerType eq 'Personal'"
        }
    } else {
        If ($personalOnly) {
            $filter ="?`$filter=managedDeviceOwnerType eq 'Personal'"
        } else {
            $filter = ""
        }
    }

    if ($enrolledSinceDate) {
        $formattedDateTime ="{0:s}" -f (get-date $enrolledSinceDate) + "Z"
        $filter = "?`$filter=enrolledDateTime ge $formattedDateTime"

        If ($personalOnly) {
            $filter ="$filter and managedDeviceOwnerType eq 'Personal'"
        }
    }
	
	try
	{
        
		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)$filter"
		Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get

	}
	
	catch
	{
		
		$ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break
		
	}
	
}

####################################################

####################################################




Function Get-AADDevice(){

<#
.SYNOPSIS
This function is used to get an AAD Device from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets an AAD Device registered with AAD
.EXAMPLE
Get-AADDevice -DeviceID $DeviceID
Returns an AAD Device from Azure AD
.NOTES
NAME: Get-AADDevice
#>

[cmdletbinding()]

param
(
    $DeviceID
)

# Defining Variables
$graphApiVersion = "v1.0"
$Resource = "devices"
    
    try {

    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$filter=deviceId eq '$DeviceID'"

    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).value 

    }

    catch {

        $ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break

    }

}

Function Add-DeviceMember {
	
[cmdletbinding()]

param
(
	[Parameter(Mandatory=$true)]
	[string]$GroupId,
    [Parameter(Mandatory=$true)]
	[string]$DeviceID
)
	
	$graphApiVersion = "Beta"
	$Resource = "groups/$groupid/members/`$ref"
	
	try
	{

    $JSON=@"
{
"`@odata.id": "https://graph.microsoft.com/$graphApiVersion/directoryObjects/$deviceid"
}
"@

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $JSON -ContentType "application/json"

	}
	
	catch
	{
		
		$ex = $_.Exception
        If ($ex.Response) {
		    $errorResponse = $ex.Response.GetResponseStream()
		    $reader = New-Object System.IO.StreamReader($errorResponse)
		    $reader.BaseStream.Position = 0
		    $reader.DiscardBufferedData()
		    $responseBody = $reader.ReadToEnd();
		    write-verbose "Response content:`n$responseBody" 
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            write-error $ex.message
        }
		break
		
	}
	
}

####################################################



# Checking if authToken exists before running authentication
if($global:authToken){

	# Setting DateTime to Universal time to work in all timezones
	$DateTime = (Get-Date).ToUniversalTime()

	# If the authToken exists checking when it expires
	$TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

		if($TokenExpires -le 0){
		    write-verbose "Authentication Token expired $TokenExpires minutes ago"
		    $global:authToken = Get-AuthTokenClientSecret
		}
}

# Authentication doesn't exist, calling Get-AuthToken function

else {
    # Getting the authorization token
    write-output "Authenticating..."
    $global:authToken = Get-AuthTokenClientSecret
}

#endregion

####################################################



IF ($filterByEnrolledWithinMinutes -ne 0) {
    write-output "getting devices recorded as enrolled within the last $filterByEnrolledWithinMinutes minutes"
    $devices=(Get-Devices -filterbyenrolledwithinminutes $filterByEnrolledWithinMinutes).value
} else {
    If ($LastRunTime) {
        write-output "getting devices recorded as enrolled since the last runbook execution - $LastRunTime"
        $devices=(Get-Devices -enrolledSinceDate $LastRunTime).value

    } else {

        write-output "getting all devices"
        $devices=(Get-Devices).value

    }
}


write-output "$($devices.count) returned."
foreach ($device in $devices) {
    If ($device.userid) {
        write-output "Processing device: $($device.devicename). Serial: $($device.serialnumber). AADDeviceID= $($device.azureADDeviceId). User: $($device.userPrincipalName)"

        #check if we have the user group membership in our user group cache
        If ($cachedUserGroupMemberships.UserID -contains $device.userid) {
            foreach ($cachedGroup in $cachedUserGroupMemberships) {
                IF ($cachedGroup.userid -eq $device.userId) {
                    write-verbose "`tusing user group membership cache for user $($device.userId)"
                    $userGroupMemerships=$cachedGroup.Groups
                }
            }
        } else {

            #keep a cache of the user group membership to reduce graph queries
            $userGroupMemership=Get-UserGroups -id $device.userId
            $hash = @{            
                UserID          = $device.userid                
                Groups            = $userGroupMemership
                }                                              
            $cachedUserGroupMemberships+=(New-Object PSObject -Property $hash)
        }

        #iterate through the users groups and see if they match any of our groups we're using for scope tag mapping
        foreach ($userGroup in $userGroupMemership) {
            If ($UserGroupRoleGroupMapping.UserGroupID -contains $userGroup) {
                
                #assign scope tag group
                foreach ($deviceGroup in $UserGroupRoleGroupMapping) {
                    If ($deviceGroup.UserGroupID -eq $userGroup) {

                        write-verbose "`tuser $($device.userid) is in a group that matches a scope tag assignment. Group ID is $userGroup."

                        #get group members if needed and cache
                        if (-not $deviceGroup.ScopeTagGroupMembers) {
                            write-verbose "`tgetting groupmembers for $($devicegroup.ScopeTagGroupID)"
                            $deviceGroup | add-member -MemberType NoteProperty -Name ScopeTagGroupMembers -Value (get-groupmembers $deviceGroup.ScopeTagGroupID) -Force
                        }
                        
                        #get the id of the device from Azure AD - we need this to add it to the group
                        write-verbose "`tgetting device from Azure AD with device ID $($device.azureADDeviceId)"
                        $deviceID=(get-aaddevice $device.azureADDeviceId).id

                        #if the device isnt already a member of the group, add it now.
                        IF ($deviceID) {
                            If ($deviceGroup.ScopeTagGroupMembers -notcontains $deviceID) {
                                write-output "`tadding device $deviceID to device scope tag group $($deviceGroup.ScopeTagGroupID)"
                                $result=Add-DeviceMember -GroupId $deviceGroup.ScopeTagGroupID -DeviceID $deviceID
                            } else {
                                write-verbose "`tdevice $deviceID already a member of $($deviceGroup.ScopeTagGroupID)"
                            }
                        } else {
                            write-verbose "`t$deviceID not found"
                        }
                    }
                }
                
            }
        }

    }
}


