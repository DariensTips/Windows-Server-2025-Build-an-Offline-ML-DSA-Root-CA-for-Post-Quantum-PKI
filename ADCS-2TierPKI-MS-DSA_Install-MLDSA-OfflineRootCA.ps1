#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install, configure, verify, back up, and export files for a standalone offline ML-DSA Root CA.

.DESCRIPTION
    This script is intended for a Windows Server 2025 Core lab or demonstration.
    It installs the AD CS Certification Authority role service, configures a standalone
    Root CA using ML-DSA:87, configures CDP and AIA for offline Root CA use,
    publishes a new base CRL, backs up the CA, and exports the Root CA files.

.NOTES
    Review and customize all variables before running.
    Run from an elevated PowerShell session.
    Do not store passwords, BitLocker PINs, or recovery material in reusable scripts.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Customize these values before running.
# -----------------------------------------------------------------------------
$CACommonName   = 'Dariens Tips PQC ML-DSA Root Certification Authority'
$DNSSuffix      = 'OU=darienstips9409,O=Darien Hawkins,ST=Virginia,C=US'
$PkiHttpBase    = 'http://pki.dariens.tips/CertEnroll'
$RootCARootPath = 'C:\RootCA'

# ML-DSA:87 values shown in the AD CS GUI for the Microsoft Software KSP.
$CryptoProviderName  = 'ML-DSA:87#Microsoft Software Key Storage Provider'
$KeyLength           = 20736
$HashAlgorithmName   = 'NoHash'
$CAValidityPeriod    = 'Years'
$CAValidityUnits     = 20
$RootCrlPeriod       = 'Weeks'
$RootCrlPeriodUnits  = 52

$CertEnrollPath = Join-Path $env:SystemRoot 'System32\CertSrv\CertEnroll'
$rightNow       = Get-Date -Format yyyyMMddHHmmss
$CABackupPath   = Join-Path $RootCARootPath "CA-Backup-$rightNow"
$CAExportPath   = Join-Path $RootCARootPath 'PKI-Export'
$FriendlyCer    = Join-Path $CAExportPath 'DariensTips-ML-DSA-RootCA.cer'

# -----------------------------------------------------------------------------
# Helper output function.
# -----------------------------------------------------------------------------
function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ''
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# 1. Install AD CS Certification Authority role service.
# -----------------------------------------------------------------------------
Write-Section 'Install AD CS Certification Authority role service'

Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools

# -----------------------------------------------------------------------------
# 2. Configure the standalone Root CA using parameter splatting.
# -----------------------------------------------------------------------------
Write-Section 'Configure standalone ML-DSA Root CA'

$ADCSparams = @{
    CAType                    = 'StandaloneRootCA'
    CACommonName              = $CACommonName
    CADistinguishedNameSuffix = $DNSSuffix
    CryptoProviderName        = $CryptoProviderName
    KeyLength                 = $KeyLength
    HashAlgorithmName         = $HashAlgorithmName
    ValidityPeriod            = $CAValidityPeriod
    ValidityPeriodUnits       = $CAValidityUnits
    DatabaseDirectory         = 'C:\WINDOWS\system32\CertLog'
    LogDirectory              = 'C:\WINDOWS\system32\CertLog'
}

Install-AdcsCertificationAuthority @ADCSparams

# -----------------------------------------------------------------------------
# 3. Verify basic CA installation details.
# -----------------------------------------------------------------------------
Write-Section 'Verify CA installation'

certutil.exe -getconfig
certutil.exe -CAInfo
certutil.exe -getreg CA\CSP

# -----------------------------------------------------------------------------
# 4. Configure Root CA CRL, CDP, and AIA settings.
# -----------------------------------------------------------------------------
Write-Section 'Configure Root CA CRL, CDP, and AIA settings'

# Set the Root CA base CRL lifetime to 52 weeks.
certutil.exe -setreg CA\CRLPeriod $RootCrlPeriod
certutil.exe -setreg CA\CRLPeriodUnits $RootCrlPeriodUnits

# Disable Delta CRLs for this offline Root CA.
certutil.exe -setreg CA\CRLDeltaPeriodUnits 0

# CDP: publish base CRL locally, include reachable HTTP CRL location in issued certificates.
$CRLPublicationURLs = "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%3%8%9.crl\n2:$PkiHttpBase/%3%8%9.crl"
certutil.exe -setreg CA\CRLPublicationURLs $CRLPublicationURLs

# AIA: publish CA certificate locally, include reachable HTTP CA certificate location in issued certificates.
$CACertPublicationURLs = "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:$PkiHttpBase/%1_%3%4.crt"
certutil.exe -setreg CA\CACertPublicationURLs $CACertPublicationURLs

# -----------------------------------------------------------------------------
# 5. Restart Certificate Services and publish a fresh base CRL.
# -----------------------------------------------------------------------------
Write-Section 'Restart Certificate Services and publish a new base CRL'

Restart-Service -Name CertSvc
certutil.exe -crl

# -----------------------------------------------------------------------------
# 6. Verify CRL, CDP, and AIA settings.
# -----------------------------------------------------------------------------
Write-Section 'Verify Root CA CRL, CDP, and AIA settings'

certutil.exe -getreg CA\CRLPeriod
certutil.exe -getreg CA\CRLPeriodUnits
certutil.exe -getreg CA\CRLDeltaPeriodUnits
certutil.exe -getreg CA\CRLPublicationURLs
certutil.exe -getreg CA\CACertPublicationURLs

Write-Host ''
Write-Host 'Current CertEnroll files:' -ForegroundColor Cyan
Get-ChildItem -Path $CertEnrollPath -File | Select-Object Name, Length, LastWriteTime

# -----------------------------------------------------------------------------
# 7. Back up CA database, private key material, and registry configuration.
# -----------------------------------------------------------------------------
Write-Section 'Back up CA database, private key material, and registry configuration'

New-Item -ItemType Directory -Path $CABackupPath -Force | Out-Null

reg.exe export `
    'HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' `
    "$CABackupPath\CertSvc-Configuration-$rightNow.reg" /y

Backup-CARoleService -Path $CABackupPath -Password (Read-Host -Prompt 'Enter CA backup password' -AsSecureString)

# Record important CA registry settings as text for quick review.
certutil.exe -getreg CA     | Out-File -FilePath (Join-Path $CABackupPath 'CA-getreg.txt')
certutil.exe -getreg Policy | Out-File -FilePath (Join-Path $CABackupPath 'Policy-getreg.txt')
certutil.exe -getreg Exit   | Out-File -FilePath (Join-Path $CABackupPath 'Exit-getreg.txt')

# Preserve CAPolicy.inf if present.
$CAPolicyPath = Join-Path $env:SystemRoot 'CAPolicy.inf'
if (Test-Path -LiteralPath $CAPolicyPath) {
    Copy-Item -LiteralPath $CAPolicyPath -Destination $CABackupPath -Force
}

# -----------------------------------------------------------------------------
# 8. Export Root CA certificate and copy AIA/CDP publication files.
# -----------------------------------------------------------------------------
Write-Section 'Export Root CA certificate and publication files'

New-Item -ItemType Directory -Path $CAExportPath -Force | Out-Null

# Export a friendly copy of the Root CA public certificate.
certutil.exe '-ca.cert' $FriendlyCer

# Copy the AD CS-published CA certificate file used by AIA.
Copy-Item -Path (Join-Path $CertEnrollPath '*.crt') -Destination $CAExportPath -Force

# Copy the base CRL used by CDP. Avoid stale Delta CRLs, which normally contain + in the filename.
Get-ChildItem -Path $CertEnrollPath -Filter '*.crl' -File |
    Where-Object { $_.Name -notlike '*+*.crl' } |
    Copy-Item -Destination $CAExportPath -Force

# -----------------------------------------------------------------------------
# 9. Verify exported certificate and CRL files.
# -----------------------------------------------------------------------------
Write-Section 'Verify exported Root CA files'

Get-ChildItem -Path $CAExportPath -File | Select-Object Name, Length, LastWriteTime

Write-Host ''
Write-Host 'Dump exported .cer and .crt files:' -ForegroundColor Cyan
Get-ChildItem -Path "$CAExportPath\*" -Include '*.crt','*.cer' -File |
    ForEach-Object {
        certutil.exe '-dump' $_.FullName
    }

Write-Host ''
Write-Host 'Check exported CRL files:' -ForegroundColor Cyan
Get-ChildItem -Path $CAExportPath -Filter '*.crl' -File |
    ForEach-Object {
        certutil.exe '-dump' $_.FullName
    }

Write-Host ''
Write-Host 'SHA256 hashes for exported files:' -ForegroundColor Cyan
Get-FileHash -Path (Join-Path $CAExportPath '*') -Algorithm SHA256 |
    Format-Table -AutoSize

Write-Host ''
Write-Host 'ML-DSA verification strings:' -ForegroundColor Cyan
certutil.exe '-dump' $FriendlyCer |
    Select-String -Pattern 'ML-DSA|ObjectId|Public Key Algorithm|Signature Algorithm|NoHash'

# -----------------------------------------------------------------------------
# 10. Optional BitLocker guidance placeholder.
# -----------------------------------------------------------------------------
<#[
Optional BitLocker steps, not run automatically:

Install-WindowsFeature -Name BitLocker -IncludeManagementTools
Restart-Computer

After restart, use a prompt instead of hardcoding a PIN:

$SecurePINString = Read-Host -Prompt 'Enter BitLocker startup PIN' -AsSecureString
Enable-BitLocker -MountPoint 'C:' -EncryptionMethod XtsAes256 -Pin $SecurePINString -TpmAndPinProtector
Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector
(Get-BitLockerVolume -MountPoint 'C:').KeyProtector
Restart-Computer
Get-BitLockerVolume -MountPoint 'C:'

If TPM plus PIN is blocked by local policy, enable the appropriate BitLocker
startup authentication policy first. Do not place PINs or recovery passwords
inside reusable scripts.
]#>

Write-Host ''
Write-Host 'Root CA configuration, backup, and export workflow complete.' -ForegroundColor Green
Write-Host "CA backup path:  $CABackupPath"
Write-Host "CA export path:  $CAExportPath"
Write-Host 'Copy the exported .crt and .crl files to the online HTTP publication location before issuing the SubCA certificate.'
