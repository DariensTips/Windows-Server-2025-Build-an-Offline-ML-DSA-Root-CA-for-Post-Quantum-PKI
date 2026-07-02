# KeyLength is specified in bits. For ML-DSA-87: 2592 bytes x 8 = 20736 bits

# For Standalone Root CA (recommended for production)  
Install-WindowsFeature -Name AD-Certificate -IncludeManagementTools


#-------------------

$ADCSparams = @{
    CAType                    = "StandaloneRootCA"
    CACommonName              = "Dariens Tips PQC ML-DSA Root Certification Authority"
    CADistinguishedNameSuffix = "OU=darienstips9409,O=Darien Hawkins,ST=Virgina,C=US"
    CryptoProviderName        = "ML-DSA:87#Microsoft Software Key Storage Provider"
    KeyLength                 = 20736
    HashAlgorithmName         = "NoHash"
    ValidityPeriod            = "Years"
    ValidityPeriodUnits       = 20
    DatabaseDirectory         = "C:\WINDOWS\system32\CertLog"
    LogDirectory              = "C:\WINDOWS\system32\CertLog"
}
Install-AdcsCertificationAuthority @ADCSparams


# C:\WINDOWS\system32\CertLog


Function setRootCACRLandCDP {
  certutil.exe -setreg CA\CRLPeriod Weeks
  certutil.exe -setreg CA\CRLPeriodUnits 52
  certutil.exe -setreg CA\CRLDeltaPeriodUnits 0
  certutil.exe -setreg CA\CRLPublicationURLs `
    "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%3%8%9.crl\n2:http://pki.dariens.tips/CertEnroll/%3%8%9.crl"
  certutil.exe -setreg CA\CACertPublicationURLs `
    "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:http://pki.dariens.tips/CertEnroll/%1_%3%4.crt"
}
setRootCACRLandCDP


Restart-Service -Name certsvc
start-sleep -Seconds 5
certutil.exe -crl


# Check
certutil.exe -getreg CA\CRLPeriod
certutil.exe -getreg CA\CRLPeriodUnits
certutil.exe -getreg CA\CRLDeltaPeriodUnits
certutil.exe -getreg CA\CRLPublicationURLs
certutil.exe -getreg CA\CACertPublicationURLs


# Backup the CA database and private key
$rightNow = Get-Date -Format yyyyMMddHHmmss
$RootCARootPath = 'C:\RootCA'
$CABackupPath = "$RootCARootPath\CA-Backup-$rightNow"
New-Item -ItemType Directory -Path $CABackupPath -Force

reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' "$CABackupPath\CertSvc-Configuration.reg" /y

Backup-CARoleService -Path $CABackupPath -Password (Read-Host -Prompt 'Enter CA backup password' -AsSecureString)

# Ensure CRL is published and there is only one CRL in the folder
Get-ChildItem -Path C:\Windows\System32\CertSrv\CertEnroll\*.crl

#Export
$CAExportPath = "$RootCARootPath\PKI-Export-$rightNow"
New-Item -ItemType Directory -Path $CAExportPath -Force

certutil.exe '-ca.cert' "$CAExportPath\DariensTips-ML-DSA-RootCA.cer"
Copy-Item -Path 'C:\WINDOWS\system32\CertSrv\CertEnroll\*.crt' -Destination $CAExportPath\ -Force
Copy-Item -Path 'C:\Windows\System32\CertSrv\CertEnroll\*.crl' -Destination $CAExportPath\ -Force

Get-ChildItem -Path "$CAExportPath\*" -Include '*.crt' -File |
  ForEach-Object {certutil.exe '-dump' $_.FullName}

Get-ChildItem -Path "$CAExportPath\*" -Include '*.cer' -File |
  ForEach-Object {certutil.exe '-dump' $_.FullName}
  
Get-ChildItem -Path "$CAExportPath\*" -Include '*.crt','*.cer' -File |
  ForEach-Object {Get-FileHash $_.FullName | Format-List}

certutil.exe '-dump' "$CAExportPath\DariensTips-ML-DSA-RootCA.cer" |
Select-String -Pattern 'ML-DSA|ObjectId|Public Key Algorithm|Signature Algorithm'



#----------------------------

Install-WindowsFeature -Name BitLocker -IncludeManagementTools


# Enable local BitLocker policy to allow TPM + PIN at startup
$FveKey = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
New-Item -Path $FveKey -Force
function Enable-BitLockerTPMPINPolicy {
  New-ItemProperty -Path $FveKey -Name UseAdvancedStartup -PropertyType DWord -Value 1 -Force
  New-ItemProperty -Path $FveKey -Name EnableBDEWithNoTPM -PropertyType DWord -Value 0 -Force
  New-ItemProperty -Path $FveKey -Name UseTPMPIN -PropertyType DWord -Value 1 -Force
}
Enable-BitLockerTPMPINPolicy


gpupdate /force

function Enable-BitLockerTPMPIN {
  $piTwentyDigits = "31415926535897932384"
  $SecurePINString = ConvertTo-SecureString $piTwentyDigits -AsPlainText -Force
  Enable-BitLocker -MountPoint c: -EncryptionMethod XtsAes256 -TpmAndPinProtector $SecurePINString
  Add-BitLockerKeyProtector -MountPoint c: -RecoveryPasswordProtector
}
Enable-BitLockerTPMPIN


Clear-History
$HistoryPath = (Get-PSReadLineOption).HistorySavePath
Remove-Item -LiteralPath $HistoryPath -Force
Restart-Computer


(Get-BitLockerVolume -MountPoint c:).keyprotector





