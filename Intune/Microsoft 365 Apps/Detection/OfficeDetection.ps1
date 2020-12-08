###########################
#Script Variables
###########################
#Excluded Apps
#array of strings. eg. @("groove","teams")
#list: https://docs.microsoft.com/en-us/deployoffice/office-deployment-tool-configuration-options#id-attribute-part-of-excludeapp-element
## NOTE This is only checked with the product ID is O365ProPlusRetail
$ExcludedApps=@("groove","lync","OneDrive","Bing")

#ProductReleaseID of the product you want to check for
#list: https://docs.microsoft.com/en-us/office365/troubleshoot/installation/product-ids-supported-office-deployment-click-to-run#:~:text=Table%202%20%20%20%20Product%20%20,%20%20SkypeforBusinessEntryRetail%20%203%20more%20rows%20
$ProductID="O365ProPlusRetail"

#Platform
#The platform you want to be installed. x64 or x86.
$Platform="x64"
###########################

#Office key
$NotDetected=$false
$RegOffice="HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
$RegKeys = get-itemproperty -Path $RegOffice

#check platform
$CurrentPlatform=$RegKeys.Platform
IF ($Platform -ne $CurrentPlatform) {
    write-host "Platform: '$Platform' does not match '$CurrentPlatform'"
    $NotDetected=$true
}

#check installed products
$CurrentProductReleaseIDs=$RegKeys.ProductReleaseIDs
If ($CurrentProductReleaseIDs -notlike "*$ProductID*") {
    write-host "ProductReleaseIDs: '$ProductID' not found in '$CurrentProductReleaseIDs'"
    $NotDetected=$true
}

#Check Excluded Apps
IF ($ProductID -eq "O365ProPlusRetail") {
    $CurrentExcludedApps=$RegKeys."O365ProPlusRetail.ExcludedApps"
    IF ($CurrentExcludedApps) {
        $CurrentExcludedApps=$CurrentExcludedApps.Split(",")

        #check if extra apps are excluded
        Foreach ($ExcludedApp in $CurrentExcludedApps) {
            If ($ExcludedApps -notcontains $ExcludedApp) {
                write-host "Excluded Apps - Extra: $excludedapp"
                $NotDetected=$true
            }
        }
    }

    If ($ExcludedApps) {
        #check that all the required excluded apps ARE excluded
        Foreach ($ExcludedApp in $ExcludedApps) {
            If ($CurrentExcludedApps -contains $ExcludedApp) {
                #write-host "contains $excludedapp"
            } else {
                write-host "Excluded Apps - Missing: $excludedapp"
                $NotDetected=$true
            }
        }
    }
}

#check detection
If ($NotDetected) {
    exit 1
} else {
    Write-host "Detected successfully"
    exit 0
}
