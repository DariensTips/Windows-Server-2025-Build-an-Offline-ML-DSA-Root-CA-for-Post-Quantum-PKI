<#
.SYNOPSIS
    Windows Server 2025 ML-DSA two-tier PKI lab script.

.DESCRIPTION
    Combined PowerShell helper script for two videos/labs:

    Part 1:
      Build a standalone offline ML-DSA Root CA.

    Part 2:
      Build a domain-joined Enterprise ML-DSA Subordinate CA,
      submit the SubCA request to the offline Root CA, install the
      issued SubCA certificate, and publish Root CA files over HTTP.

.NOTES
    Public distribution sample.

    Replace example names, DNS names, distinguished names, paths, and
    organization values for your environment.

    Run only the phase that applies to the current server.

    Do not store production secrets in this script.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet(
        'ShowHelp',
        'RootCAInstall',
        'RootCAConfigureCdpAia',
        'RootCAPublishCrl',
        'RootCABackupExport',
        'RootCAAll',
        'SubCACreateRequest',
        'RootCASubmitIssueSubCA',
        'SubCAComplete',
        'SubCAVerify',
        'WebPublishFiles'
    )]
    [string]$Phase = 'ShowHelp',

    [int]$RequestId = 0,

    [switch]$EnableDirectoryBrowsing
)

# ============================================================
# Configuration
# ============================================================
# Replace these values before using this in your own lab.

$CryptoProviderName = 'ML-DSA:87#Microsoft Software Key Storage Provider'
$MLDSA87KeyLength   = 20736
$MLDSAHashAlgorithm = 'NoHash'

# Offline Root CA values
$RootCACommonName              = 'ORG PQC ML-DSA Root Certification Authority'
$RootCADistinguishedNameSuffix = 'O=ORG,ST=STATE,C=US'
$RootCAValidityPeriod          = 'Years'
$RootCAValidityPeriodUnits     = 20
$RootCARootPath                = 'C:\RootCA'
$PkiHttpBase                   = 'http://pki.example.com/CertEnroll'

# Enterprise Subordinate CA values
$SubCACommonName               = 'ORG-MLDSA-Enterprise-Subordinate-CA'
$SubCADistinguishedNameSuffix  = 'DC=example,DC=com'
$SubCARequestRoot              = 'C:\SubCA-Request'
$SubCARequestPath              = Join-Path $SubCARequestRoot "$SubCACommonName.req"
$SubCAIssuedCertName           = "$SubCACommonName.cer"

# SubCA staging folders
$SubCARootCAFilesFolder        = Join-Path $SubCARequestRoot 'RootCA-Files'
$SubCAIssuedCertFolder         = Join-Path $SubCARequestRoot 'Issued'
$SubCAIssuedCertPath           = Join-Path $SubCAIssuedCertFolder $SubCAIssuedCertName

# HTTP publishing values
$HttpSiteName                  = 'Default Web Site'
$HttpVirtualDirectoryAlias     = 'CertEnroll'
$HttpCertEnrollPhysicalPath    = 'C:\PKI\CertEnroll'

# AD CS default database and log paths
$CertLogPath                   = 'C:\WINDOWS\system32\CertLog'

# ============================================================
# Helper functions
# ============================================================

function Write-Section {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host ''
    Write-Host '============================================================'
    Write-Host $Message
    Write-Host '============================================================'
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Get-SingleFileOrThrow {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Description
    )

    $files = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue

    if (-not $files) {
        throw "No $Description found in path: $Path"
    }

    if ($files.Count -gt 1) {
        Write-Warning "Multiple $Description files found. Using the first one: $($files[0].FullName)"
    }

    return $files[0].FullName
}

function Show-Help {
    Write-Section 'Windows Server 2025 ML-DSA Two-Tier PKI Script'

    Write-Host 'Use one phase at a time on the appropriate server.'
    Write-Host ''
    Write-Host 'Offline Root CA phases:'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCAAll'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCAInstall'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCAConfigureCdpAia'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCAPublishCrl'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCABackupExport'
    Write-Host ''
    Write-Host 'Enterprise Subordinate CA phases:'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase SubCACreateRequest'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase SubCAComplete'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase SubCAVerify'
    Write-Host ''
    Write-Host 'Run on the offline Root CA after copying the SubCA request file:'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCASubmitIssueSubCA'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCASubmitIssueSubCA -RequestId 5'
    Write-Host ''
    Write-Host 'Run on the SubCA or a dedicated web server to publish CDP/AIA files:'
    Write-Host '  .\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase WebPublishFiles'
}

# ============================================================
# Part 1: Offline Root CA
# ============================================================

function Install-OfflineMLDSARootCA {
    Write-Section 'Installing standalone offline ML-DSA Root CA'

    Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools

    $ADCSparams = @{
        CAType                    = 'StandaloneRootCA'
        CACommonName              = $RootCACommonName
        CADistinguishedNameSuffix = $RootCADistinguishedNameSuffix
        CryptoProviderName        = $CryptoProviderName
        KeyLength                 = $MLDSA87KeyLength
        HashAlgorithmName         = $MLDSAHashAlgorithm
        ValidityPeriod            = $RootCAValidityPeriod
        ValidityPeriodUnits       = $RootCAValidityPeriodUnits
        DatabaseDirectory         = $CertLogPath
        LogDirectory              = $CertLogPath
    }

    Install-AdcsCertificationAuthority @ADCSparams

    Write-Host ''
    Write-Host 'Root CA installation verification:'
    certutil.exe -getconfig
    certutil.exe -CAInfo
}

function Set-OfflineRootCACdpAndAia {
    Write-Section 'Configuring offline Root CA CRL, CDP, and AIA settings'

    $crlPublicationUrls = "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%3%8%9.crl\n2:$PkiHttpBase/%3%8%9.crl"
    $caCertPublicationUrls = "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:$PkiHttpBase/%1_%3%4.crt"

    certutil.exe -setreg CA\CRLPeriod Weeks
    certutil.exe -setreg CA\CRLPeriodUnits 52
    certutil.exe -setreg CA\CRLDeltaPeriodUnits 0
    certutil.exe -setreg CA\CRLPublicationURLs $crlPublicationUrls
    certutil.exe -setreg CA\CACertPublicationURLs $caCertPublicationUrls

    Restart-Service -Name CertSvc
    Start-Sleep -Seconds 5

    Write-Host ''
    Write-Host 'Configured Root CA CRL/CDP/AIA settings:'
    certutil.exe -getreg CA\CRLPeriod
    certutil.exe -getreg CA\CRLPeriodUnits
    certutil.exe -getreg CA\CRLDeltaPeriodUnits
    certutil.exe -getreg CA\CRLPublicationURLs
    certutil.exe -getreg CA\CACertPublicationURLs
}

function Publish-OfflineRootCACrl {
    Write-Section 'Publishing offline Root CA base CRL'

    certutil.exe -crl

    Write-Host ''
    Write-Host 'Current CertEnroll CRL files:'
    Get-ChildItem -Path 'C:\Windows\System32\CertSrv\CertEnroll' -Filter '*.crl' -ErrorAction SilentlyContinue
}

function Backup-AndExportOfflineRootCA {
    Write-Section 'Backing up and exporting offline Root CA files'

    $rightNow = Get-Date -Format yyyyMMddHHmmss
    $caBackupPath = Join-Path $RootCARootPath "CA-Backup-$rightNow"
    $caExportPath = Join-Path $RootCARootPath "PKI-Export-$rightNow"

    New-DirectoryIfMissing -Path $RootCARootPath
    New-DirectoryIfMissing -Path $caBackupPath
    New-DirectoryIfMissing -Path $caExportPath

    reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' "$caBackupPath\CertSvc-Configuration.reg" /y

    Backup-CARoleService `
        -Path $caBackupPath `
        -Password (Read-Host -Prompt 'Enter CA backup password' -AsSecureString)

    certutil.exe '-ca.cert' "$caExportPath\OfflineRootCA.cer"

    Copy-Item `
        -Path 'C:\WINDOWS\system32\CertSrv\CertEnroll\*.crt' `
        -Destination $caExportPath `
        -Force `
        -ErrorAction SilentlyContinue

    Get-ChildItem -Path 'C:\Windows\System32\CertSrv\CertEnroll' -Filter '*.crl' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*+*.crl' } |
        Copy-Item -Destination $caExportPath -Force

    Write-Host ''
    Write-Host "Root CA backup path: $caBackupPath"
    Write-Host "Root CA export path: $caExportPath"
    Write-Host ''
    Write-Host 'Exported files:'
    Get-ChildItem -Path $caExportPath

    Write-Host ''
    Write-Host 'Certificate hashes:'
    Get-ChildItem -Path $caExportPath -Include '*.crt','*.cer' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            Get-FileHash $_.FullName -Algorithm SHA256 | Format-List
        }

    Write-Host ''
    Write-Host 'ML-DSA details from exported Root CA certificate:'
    certutil.exe '-dump' "$caExportPath\OfflineRootCA.cer" |
        Select-String -Pattern 'ML-DSA|ObjectId|Public Key Algorithm|Signature Algorithm'
}

function Invoke-RootCAAll {
    Install-OfflineMLDSARootCA
    Set-OfflineRootCACdpAndAia
    Publish-OfflineRootCACrl
    Backup-AndExportOfflineRootCA
}

# Optional BitLocker helpers.
# These are intentionally not part of RootCAAll because BitLocker policy and
# protector choices should be validated for each environment.

function Enable-BitLockerTPMPINPolicy {
    Write-Section 'Configuring local BitLocker policy for TPM + PIN startup protector'

    $fveKey = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    New-Item -Path $fveKey -Force | Out-Null

    New-ItemProperty -Path $fveKey -Name UseAdvancedStartup -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $fveKey -Name EnableBDEWithNoTPM -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $fveKey -Name UseTPMPIN -PropertyType DWord -Value 1 -Force | Out-Null

    gpupdate /force
}

function Enable-SystemDriveBitLockerTPMPIN {
    Write-Section 'Enabling BitLocker with TPM + PIN'

    Install-WindowsFeature -Name BitLocker -IncludeManagementTools

    $securePin = Read-Host -Prompt 'Enter BitLocker startup PIN' -AsSecureString

    Enable-BitLocker `
        -MountPoint 'C:' `
        -EncryptionMethod XtsAes256 `
        -Pin $securePin `
        -TpmAndPinProtector

    Add-BitLockerKeyProtector `
        -MountPoint 'C:' `
        -RecoveryPasswordProtector

    Write-Warning 'Record and secure the recovery password and PIN according to your security policy.'
}

# ============================================================
# Part 2: Enterprise Subordinate CA
# ============================================================

function New-EnterpriseMLDSASubCARequest {
    Write-Section 'Creating Enterprise ML-DSA Subordinate CA request'

    New-DirectoryIfMissing -Path $SubCARequestRoot

    Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools

    $ADCSparams = @{
        CAType                    = 'EnterpriseSubordinateCA'
        CACommonName              = $SubCACommonName
        CADistinguishedNameSuffix = $SubCADistinguishedNameSuffix
        CryptoProviderName        = $CryptoProviderName
        KeyLength                 = $MLDSA87KeyLength
        HashAlgorithmName         = $MLDSAHashAlgorithm
        OutputCertRequestFile     = $SubCARequestPath
        DatabaseDirectory         = $CertLogPath
        LogDirectory              = $CertLogPath
    }

    Install-AdcsCertificationAuthority @ADCSparams

    Write-Host ''
    Write-Host "SubCA request path: $SubCARequestPath"
    Write-Host ''
    Write-Host 'Request inspection:'
    certutil.exe '-dump' $SubCARequestPath
}

function Submit-Issue-AndRetrieveSubCARequest {
    Write-Section 'Submitting, issuing, and retrieving SubCA certificate on the offline Root CA'

    $rootRequestsFolder = Join-Path $RootCARootPath 'Requests'
    $rootIssuedFolder   = Join-Path $RootCARootPath 'Issued'

    New-DirectoryIfMissing -Path $rootRequestsFolder
    New-DirectoryIfMissing -Path $rootIssuedFolder

    $rootRequestPath = Join-Path $rootRequestsFolder "$SubCACommonName.req"
    $rootIssuedPath  = Join-Path $rootIssuedFolder $SubCAIssuedCertName

    if (-not (Test-Path -LiteralPath $rootRequestPath)) {
        Write-Warning "Expected SubCA request not found: $rootRequestPath"
        Write-Warning 'Copy the SubCA request file to this path, or update $SubCACommonName / paths in the configuration section.'
        throw 'SubCA request file missing.'
    }

    Write-Host ''
    Write-Host 'Submitting SubCA request to the Root CA.'
    Write-Host 'A CA selection dialog may appear.'
    certreq.exe -submit $rootRequestPath

    if ($RequestId -le 0) {
        $RequestId = [int](Read-Host -Prompt 'Enter the Request ID returned by certreq')
    }

    Write-Host ''
    Write-Host "Issuing pending request ID: $RequestId"
    certutil.exe -resubmit $RequestId

    Write-Host ''
    Write-Host "Retrieving issued certificate to: $rootIssuedPath"
    certreq.exe -retrieve $RequestId $rootIssuedPath

    Write-Host ''
    Write-Host 'Issued certificate inspection:'
    certutil.exe '-dump' $rootIssuedPath
}

function Complete-EnterpriseSubCAConfiguration {
    Write-Section 'Completing Enterprise Subordinate CA configuration'

    New-DirectoryIfMissing -Path $SubCARootCAFilesFolder
    New-DirectoryIfMissing -Path $SubCAIssuedCertFolder

    if (-not (Test-Path -LiteralPath $SubCAIssuedCertPath)) {
        Write-Warning "Issued SubCA certificate not found: $SubCAIssuedCertPath"
        Write-Warning 'Copy the issued SubCA certificate into the Issued folder or update the configuration section.'
        throw 'Issued SubCA certificate missing.'
    }

    $rootCACert = Get-SingleFileOrThrow -Path $SubCARootCAFilesFolder -Filter '*.cer' -Description 'Root CA certificate'
    $rootCACrl  = Get-SingleFileOrThrow -Path $SubCARootCAFilesFolder -Filter '*.crl' -Description 'Root CA CRL'

    Write-Host ''
    Write-Host "Using Root CA certificate: $rootCACert"
    Write-Host "Using Root CA CRL:         $rootCACrl"
    Write-Host "Using SubCA certificate:   $SubCAIssuedCertPath"

    Write-Host ''
    Write-Host 'Inspecting Root CA certificate and CRL:'
    certutil.exe '-dump' $rootCACert
    certutil.exe '-dump' $rootCACrl

    Write-Host ''
    Write-Host 'Importing Root CA certificate into Local Machine Trusted Root store.'
    Import-Certificate `
        -FilePath $rootCACert `
        -CertStoreLocation 'Cert:\LocalMachine\Root'

    Write-Host ''
    Write-Host 'Importing Root CA CRL into local CA/CRL store.'
    certutil.exe -f -addstore CA $rootCACrl

    Write-Host ''
    Write-Host 'Installing issued SubCA certificate.'
    certutil.exe '-installcert' $SubCAIssuedCertPath

    Write-Host ''
    Write-Host 'Starting Certificate Services.'
    Start-Service -Name CertSvc

    Invoke-SubCAVerification
}

function Invoke-SubCAVerification {
    Write-Section 'Verifying Enterprise Subordinate CA'

    New-DirectoryIfMissing -Path 'C:\Temp'

    certutil.exe -ping
    certutil.exe -getconfig
    certutil.exe -CAInfo

    certutil.exe '-ca.cert' 'C:\Temp\SubCA.cer'
    certutil.exe '-dump' 'C:\Temp\SubCA.cer'

    certutil.exe -crl

    Write-Host ''
    Write-Host 'Current CertEnroll files:'
    Get-ChildItem -Path 'C:\Windows\System32\CertSrv\CertEnroll' -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'Chain and revocation verification:'
    certutil.exe -urlfetch -verify 'C:\Temp\SubCA.cer'
}

# ============================================================
# HTTP CDP/AIA publishing
# ============================================================

function Publish-PkiFilesOverHttp {
    Write-Section 'Publishing Root CA files over HTTP with IIS'

    Install-WindowsFeature `
        -Name Web-Server,Web-Static-Content,Web-Default-Doc,Web-Dir-Browsing,Web-Filtering,Web-Mgmt-Console `
        -IncludeManagementTools

    New-DirectoryIfMissing -Path $HttpCertEnrollPhysicalPath

    # Copy common CA publication files from the SubCA staging folder if present.
    if (Test-Path -LiteralPath $SubCARootCAFilesFolder) {
        Copy-Item -Path (Join-Path $SubCARootCAFilesFolder '*.cer') -Destination $HttpCertEnrollPhysicalPath -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $SubCARootCAFilesFolder '*.crt') -Destination $HttpCertEnrollPhysicalPath -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $SubCARootCAFilesFolder '*.crl') -Destination $HttpCertEnrollPhysicalPath -Force -ErrorAction SilentlyContinue
    }

    # Grant read access to IIS worker processes.
    icacls.exe $HttpCertEnrollPhysicalPath /grant 'IIS_IUSRS:(OI)(CI)RX' /T

    Import-Module WebAdministration

    $existingVdir = Get-WebVirtualDirectory -Site $HttpSiteName -Name $HttpVirtualDirectoryAlias -ErrorAction SilentlyContinue

    if (-not $existingVdir) {
        New-WebVirtualDirectory `
            -Site $HttpSiteName `
            -Name $HttpVirtualDirectoryAlias `
            -PhysicalPath $HttpCertEnrollPhysicalPath
    }
    else {
        Set-ItemProperty `
            -Path "IIS:\Sites\$HttpSiteName\$HttpVirtualDirectoryAlias" `
            -Name physicalPath `
            -Value $HttpCertEnrollPhysicalPath
    }

    # Allow double escaping so CA file names containing plus signs or escaped characters are served correctly.
    Set-WebConfigurationProperty `
        -PSPath 'MACHINE/WEBROOT/APPHOST' `
        -Filter "system.webServer/security/requestFiltering" `
        -Name allowDoubleEscaping `
        -Value True

    if ($EnableDirectoryBrowsing) {
        Set-WebConfigurationProperty `
            -Filter /system.webServer/directoryBrowse `
            -Name enabled `
            -Value true `
            -PSPath "IIS:\Sites\$HttpSiteName\$HttpVirtualDirectoryAlias"
    }

    Restart-WebItem "IIS:\Sites\$HttpSiteName"

    Write-Host ''
    Write-Host "HTTP physical path: $HttpCertEnrollPhysicalPath"
    Write-Host "HTTP virtual path:  /$HttpVirtualDirectoryAlias/"
    Write-Host ''
    Write-Host 'Published files:'
    Get-ChildItem -Path $HttpCertEnrollPhysicalPath -ErrorAction SilentlyContinue
}

# ============================================================
# Main execution
# ============================================================

switch ($Phase) {
    'ShowHelp' {
        Show-Help
    }
    'RootCAInstall' {
        Install-OfflineMLDSARootCA
    }
    'RootCAConfigureCdpAia' {
        Set-OfflineRootCACdpAndAia
    }
    'RootCAPublishCrl' {
        Publish-OfflineRootCACrl
    }
    'RootCABackupExport' {
        Backup-AndExportOfflineRootCA
    }
    'RootCAAll' {
        Invoke-RootCAAll
    }
    'SubCACreateRequest' {
        New-EnterpriseMLDSASubCARequest
    }
    'RootCASubmitIssueSubCA' {
        Submit-Issue-AndRetrieveSubCARequest
    }
    'SubCAComplete' {
        Complete-EnterpriseSubCAConfiguration
    }
    'SubCAVerify' {
        Invoke-SubCAVerification
    }
    'WebPublishFiles' {
        Publish-PkiFilesOverHttp
    }
}
