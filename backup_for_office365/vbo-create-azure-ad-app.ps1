<# 
.SYNOPSIS
    Create an Azure AD application for authentication, backup and recovyer from Veeam's Backup for Microsoft Office 365
.DESCRIPTION
    This script is meant to be used by a security or Azure AD administrator to provide the necessary Azure AD application to be used in Veeam Backup for Microsoft Office 365.

    Use this script only if you can't use the product's built-in functionality to create the application (which will require Global Admin permissions).

    The script will do the following and does not require any Veeam component to run:

    1. Connect to Azure AD with given admin credentials
    2. Create a public/private key-pair for app authentication and export the key to a file
    3. Create a new application registration within Azure AD
    4. Add the key for authentication to the app
    5. Assign the required permisisons for VBO to the application

    For a detailed list of permissions used in this script, please check
    https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html?ver=50
    
    The "Exchange/full_access_as_user" permission will not be created automatically - it is only required when the Office 365 region is "Germany" and would require special care in automation.

    Based on limitations in the AzureAD powershell module the application can't be tagged as a public client when not limiting it to interactive restores. This step has to be done manually, but the script will inform at the end about it.

    Created for Veeam Backup for Microsoft Office 365 v5
.NOTES
    Written by Stefan Zimmermann <stefan.zimmermann@veeam.com>

    v1.0.0, 14.01.2021

    Released under the MIT license.
.LINK
    https://github.com/StefanZi
    https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html?ver=50
#>
#Requires -Modules AzureAd
[CmdletBinding(PositionalBinding=$False)]
Param(
    # Azure Tenant ID - can be found on the Azure AD overview page
    [Parameter(Mandatory=$true)] 
    [string] $azureTenantId,

    # DisplayName for the app registration    
    [String] $appName = "Veeam Backup for Microsoft Office 365",

    # Limit permissions to usage for only backup or restore, omitting this creates permissions for both
    [String][ValidateSet("Backup", "InteractiveRestore", "ProgrammaticRestore")] $limitUsageTo,

    # Limit permissions to the following service(s). Omitting this creates permissions for all supported.
    [String[]][ValidateSet("Exchange", "SharePoint", "OneDrive", "Teams")] $limitServiceTo,

    # Path to the file where the public key will be stored (CRT)
    [string] $certificateFilePath = "$($PSScriptRoot)\veeam_backup_office365_app_public.crt",

    # Path to the file where the private key will be exported (PFX)
    [string] $keyFilePath = "$($PSScriptRoot)\veeam_backup_office365_app_private.pfx",

    # Lifetime of the key-pair in days
    [int] $keyLifeTimeDays = 3*365,

    # Password for exported key file
    [securestring] $keyPassword,

    # Overwrite/regenerate authentication key if exists
    [switch] $overwriteKey,

    # Overwrite/regenerate app registration if exists with same name
    [switch] $overwriteApp,

    # Use the following credentials to connect to the Azure AD instead of asking. Can't be used for MFA
    [PSCredential] $azureAdCredential,

    # Keylength for generated RSA key pair
    [int] $keyLength = 4096
);

# For debug purposes - prevents the requirement to manually log in to Azure AD all the time
# Save credentials with 
#   Get-Credential | Export-CliXMl -Path .\azureadcredentials.xml
#$azureAdCredential = Import-CliXml -Path "$($PSScriptRoot)\azureadcredentials.xml"

$apiAppIds = @{
    Graph = "00000003-0000-0000-c000-000000000000"; # Microsoft Graph
    Exchange = "00000002-0000-0ff1-ce00-000000000000"; # Office 365 Exchange Online
    SharePoint = "00000003-0000-0ff1-ce00-000000000000"; # Office 365 SharePoint Online
}

$permissionTypes = @{
    Application = "Role";
    Delegated = "Scope";
}

$usages = @{
    Backup = "Backup";
    InteractiveRestore = "InteractiveRestore";
    ProgrammaticRestore = "ProgrammaticRestore";
}

$services = @{
    Exchange = "Exchange";
    SharePoint = "SharePoint";
    OneDrive = "OneDrive";
    Teams = "Teams";
}

# Permissions from Veeam Helpcenter (https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html?ver=50)
# Exchange full_access_as_user permission omitted, add manually if using Germany region
$permissions = @(
    @{ 
        ApiAppId = $apiAppIds.Graph;
        Value = "Directory.Read.All";
        Usage = $usages.Backup;
        Service = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{ 
        ApiAppId = $apiAppIds.Graph;
        Value = "Directory.Read.All";
        Usage = $usages.ProgrammaticRestore;
        Service = $services.Exchange, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{ 
        ApiAppId = $apiAppIds.Graph;
        Value = "Directory.Read.All";
        Usage = $usages.InteractiveRestore;
        Service = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "Group.Read.All";
        Usage = $usages.Backup;
        Service = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "Group.ReadWrite.All";
        Usage = $usages.ProgrammaticRestore;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "Group.ReadWrite.All";
        Usage = $usages.InteractiveRestore;
        Service = $services.Teams;
        Type = $permissionTypes.Delegated;
    }
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "offline_access";
        Usage = $usages.InteractiveRestore;
        Service = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "Sites.ReadWrite.All";
        Usage = $usages.Backup;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value = "TeamSettings.ReadWrite.All";
        Usage = $usages.Backup;
        Service = $services.Teams;
        Type = $permissionTypes.Application;
    },    
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value = "full_access_as_app";
        Usage = $usages.Backup;
        Service = $services.Exchange, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value = "full_access_as_app";
        Usage = $usages.ProgrammaticRestore;
        Service = $services.Exchange;
        Type = $permissionTypes.Application;
    },    
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value = "EWS.AccessAsUser.All";
        Usage = $usages.InteractiveRestore;
        Service = $services.Exchange;
        Type = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value = "Sites.FullControl.All";
        Usage = $usages.Backup, $usages.ProgrammaticRestore;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value = "User.Read.All";
        Usage = $usages.Backup, $usages.ProgrammaticRestore;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value = "AllSites.FullControl";
        Usage = $usages.InteractiveRestore;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value = "User.ReadWrite.All";
        Usage = $usages.InteractiveRestore;
        Service = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type = $permissionTypes.Delegated;     
    }
)

Import-Module AzureAd

try {
    if ($azureAdCredential) {
        $adConnection = Connect-AzureAD -TenantId $azureTenantId -Credential $azureAdCredential -ErrorAction SilentlyContinue
    } else {
        Write-Host -ForegroundColor Cyan "Please check for an opened window and log in to Azure AD"
        $adConnection = Connect-AzureAD -TenantId $azureTenantId -ErrorAction SilentlyContinue
    }
    Write-Host "Connected to Azure AD tenant $($azureTenantId) as $($adConnection.Account)"
} catch {
    Write-Host -ForegroundColor Red "Connection to Azure AD tenant ID $($azureTenantId) failed: $_"
    Write-Debug $_.Exception
    exit 1
}

$today = Get-Date

# Create new self-signed certificate or use existing one for key authentication with the app
if (!(Test-Path $certificateFilePath) -or ($overwriteKey -eq $true)) {
    try {        
        $cert = New-SelfSignedCertificate -KeyAlgorithm RSA -KeyDescription "$appName" -KeyExportPolicy Exportable -KeyLength $keyLength -Subject "$appName"  -FriendlyName "$appName" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter $today.AddDays($keyLifeTimeDays)
        Export-Certificate -Cert $cert -FilePath $certificateFilePath > $null

        Write-Host "Created new certificate in $($certificateFilePath) with a lifetime of $($keyLifeTimeDays) days."

        if (!$keyPassword) {
            Write-Host -ForegroundColor Cyan "Please specify a password to encrypt the exported key: "
            $keyPassword = Read-Host -AsSecureString
        }

        Export-PfxCertificate -Cert $cert -FilePath $keyFilePath -Password $keyPassword > $null
        Write-Host "Exported your key file to $($keyFilePath)."
    } catch {
        Write-Host -ForegroundColor Red "There was an error during the creation or export of the authentication certificate: $_"
        Write-Debug $_.Exception
        exit 2
    }
} else {
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($certificateFilePath)
        Write-Host "Using already present certificate from $($certificateFilePath)"
    } catch {
        Write-Host -ForegroundColor Red "Could not load already present certificate $($certificateFilePath): $_"
        Write-Debug $_.Exception
        exit 3
    }
}


# Check if app already exists

if ($vboApp = Get-AzureADApplication -SearchString "$($appName)" -ErrorAction SilentlyContinue) {
    if ($overwriteApp -eq $true) {
        try {
            $oldServicePrincipal = Get-AzureADServicePrincipal -Filter "AppId eq '$($vboApp.AppId)'"
            if ($oldServicePrincipal) {
                Remove-AzureADServicePrincipal -ObjectId $oldServicePrincipal.ObjectId
            }
            Remove-AzureADApplication -ObjectId $vboApp.ObjectId
            
            Write-Host "Found existing application with name $($appName) and removed it as configured"
        } catch {
            Write-Host -ForegroundColor Red "Could not remove Azure AD application $($appName): $_"
            Write-Debug $_.Exception
            exit 4
        }
    } else {
        Write-Host -ForegroundColor Red "Application '$($vboApp.Displayname)' (Application-ID: $($vboApp.AppId)) already exists - please specify '-overwriteApp' or give another name with '-appName'"
        exit 4
    }
}


$redirectUrls = @("http://localhost/")

try {    
    $vboApp = New-AzureADApplication -DisplayName $appName -ReplyUrls $redirectUrls -ErrorAction SilentlyContinue

    $owner = Get-AzureADUser -SearchString $adConnection.Account.Id
    Add-AzureADApplicationOwner -ObjectId $vboApp.ObjectId -RefObjectId $owner.ObjectId

    if ($limitUsageTo -eq "InteractiveRestore") {
        Set-AzureADApplication -ObjectId $vboApp.ObjectId -PublicClient $true
    }

    New-AzureADServicePrincipal -AppId $vboApp.AppId > $null

    Write-Host "Created new Azure AD application registration '$($appName)'"
} catch {
    Write-Host -ForegroundColor Red "Failed to create new app registration: $_"
    Write-Debug $_.Exception
    exit 5
}



# Certificate handling as per https://docs.microsoft.com/en-us/powershell/module/azuread/new-azureadapplicationkeycredential?view=azureadps-2.0
Write-Host "Add certificate authentication to Azure AD application"
$bin = $cert.GetRawCertData()

$base64Value = [System.Convert]::ToBase64String($bin)
$bin = $cert.GetCertHash()
New-AzureADApplicationKeyCredential -ObjectId $vboApp.ObjectId -Type AsymmetricX509Cert -Usage Verify -Value $base64Value -EndDate $(Get-Date -UFormat "%Y/%m/%d" -Date $cert.NotAfter) -OutVariable $keyCredential

# Filter permissions based on limitations

Write-Host "Building effective permissions list based on usage ($($limitUsageTo)) and service ($($limitServiceTo)) limitations (if any)"
$filteredPermissions = [System.Collections.ArrayList]@()
foreach ($permission in $permissions) {
    if (!$limitUsageTo -or ($limitUsageTo -in $permission.Usage)) {
        if (!$limitServiceTo -or ($limitServiceTo | Where-Object { $permission.Service -contains $_ })) {
            Write-Debug "Adding permission $(($apiAppIds.GetEnumerator() | Where-Object Value -eq $permission.apiAppId).Name)/$($permission.Value)"
            $filteredPermissions.Add($permission) > $null
        }
    }
} 


$requiredResourceAccessList = New-Object -Type 'System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]'

foreach ($serviceAppId in ($filteredPermissions.ApiAppId | Select-Object -Unique)) {
    $servicePrincipal = Get-AzureADServicePrincipal -Filter "AppId eq '$($serviceAppId)'"   
    $requiredResourceAccess = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
    $requiredResourceAccess.ResourceAppId = $servicePrincipal.AppId

    foreach ($filteredPermission in ($filteredPermissions | Where-Object { $_.ApiAppId -eq $serviceAppId})) {
        if ($filteredPermission.Type -eq $permissionTypes.Application) {
            $permissionDetails = $servicePrincipal.AppRoles | Where-Object { $_.Value -eq $filteredPermission.Value }
        } else {
            $permissionDetails = $servicePrincipal.Oauth2Permissions | Where-Object { $_.Value -eq $filteredPermission.Value }
        }
        $permissionObject = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess"
        $permissionObject.Id = $permissionDetails.Id
        $permissionObject.Type = $filteredPermission.Type
        $requiredResourceAccess.ResourceAccess += $permissionObject
    }
    
    $requiredResourceAccessList += $requiredResourceAccess
}    

try {
    Set-AzureADApplication -ObjectId $vboApp.ObjectId -RequiredResourceAccess $requiredResourceAccessList
    Write-Host "Added permissions to Azure AD application"
} catch {
    Write-Host -ForegroundColor Red "Was not able to add permissions to Azure AD app - $_"
    Write-Debug $_.Exception
    exit 6
}

Write-Host "Logging off Azure AD"
Disconnect-AzureAD > $null

Write-Host "The following Azure AD application has been created for the use with VBO:"
Write-Host -ForegroundColor Green "
App-ID:     $($vboApp.AppId)
App-Name:   $($vboApp.DisplayName)
Key-File:   $($keyFilePath)
"
Write-Host "The following manual steps are required from here:"

Write-Host -ForegroundColor Cyan "* Check the API permissions of the app in the Azure AD portal and grant admin consent."
if (!$limitUsageTo) {
    Write-Host -ForegroundColor Cyan "* Manually enable the 'Allow public client flows' on the 'Authentication' page of the app details for interactive restores"
}
Write-Host -ForegroundColor Cyan "* Give the App-ID, the created private key file and it's password to the Veeam Backup for Microsoft Office 365 admin."