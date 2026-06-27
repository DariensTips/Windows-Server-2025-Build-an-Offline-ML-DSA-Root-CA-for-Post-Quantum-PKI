# Build an Offline ML-DSA Root CA on Windows Server 2025 Core

This repository contains a PowerShell script used in the video/lab for building a standalone offline Root Certification Authority using Active Directory Certificate Services (AD CS) and the Microsoft ML-DSA cryptographic provider.

This is **Part 1** of a two-tier PKI build:

1. Build and secure the standalone offline ML-DSA Root CA.
2. Build the domain-joined Enterprise ML-DSA Subordinate CA.

## What the script does

The script performs the following major tasks:

- Installs the AD CS Certification Authority role service.
- Configures a standalone Root CA using the ML-DSA:87 provider.
- Configures the Root CA base CRL lifetime.
- Disables Delta CRLs for the offline Root CA.
- Configures CDP so the Root CA publishes the CRL locally and issued certificates point to a reachable HTTP CDP location.
- Configures AIA so the Root CA publishes the CA certificate locally and issued certificates point to a reachable HTTP AIA location.
- Restarts Certificate Services and publishes a new base CRL.
- Verifies important CA settings with `certutil.exe`.
- Backs up the CA database, private key material, and CertSvc registry configuration.
- Exports the Root CA certificate and copies the AIA `.crt` file and base `.crl` file for publication.

## Requirements

- Windows Server 2025 Core or Windows Server 2025 with Desktop Experience.
- Administrative PowerShell session.
- AD CS management tools available on the Root CA.
- A newly built Root CA system.
- A reachable HTTP publication location, such as:

```text
http://pki.dariens.tips/CertEnroll/
```

Microsoft documents ML-DSA support in AD CS for Windows Server 2025 with the 2026-05 security update, KB5087539, or later. Review the official Microsoft documentation before using this in a production environment.

## Files

| File | Purpose |
|---|---|
| `Install-MLDSA-OfflineRootCA.ps1` | Main PowerShell script for installing, configuring, verifying, backing up, and exporting the offline Root CA files. |
| `README.md` | This documentation file. |

## Important customization values

Before running the script, review and modify these variables:

```powershell
$CACommonName  = 'Dariens Tips PQC ML-DSA Root Certification Authority'
$DNSSuffix     = 'OU=darienstips9409,O=Darien Hawkins,ST=Virginia,C=US'
$PkiHttpBase   = 'http://pki.dariens.tips/CertEnroll'
$RootCARootPath = 'C:\RootCA'
```

The `CACommonName` and distinguished name suffix combine to form the CA certificate subject. As a best practice, the Root CA identity should identify the PKI hierarchy or organization rather than matching the internal Active Directory domain name.

## Example usage

Run from an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
.\Install-MLDSA-OfflineRootCA.ps1
```

## CDP and AIA design

For this offline Root CA, the script configures CDP and AIA as follows:

```powershell
certutil.exe -setreg CA\CRLPublicationURLs "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%3%8%9.crl\n2:http://pki.dariens.tips/CertEnroll/%3%8%9.crl"
certutil.exe -setreg CA\CACertPublicationURLs "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:http://pki.dariens.tips/CertEnroll/%1_%3%4.crt"
```

Meaning:

| Value | Meaning |
|---:|---|
| `1` | Publish the CRL or CA certificate locally. |
| `2` | Include the HTTP location in issued certificates. |

The Root CA publishes files locally. You then manually copy the exported `.crt` and `.crl` files to the online HTTP publication location.

## CRL lifetime

The script configures the Root CA base CRL lifetime as 52 weeks:

```powershell
certutil.exe -setreg CA\CRLPeriod Weeks
certutil.exe -setreg CA\CRLPeriodUnits 52
```

Even though the Root CA is offline, its CRL still expires. Clients use the Root CA CRL to determine whether the Subordinate CA certificate has been revoked.

## Delta CRLs

The script disables Delta CRLs:

```powershell
certutil.exe -setreg CA\CRLDeltaPeriodUnits 0
```

For an offline Root CA, Delta CRLs are normally unnecessary because the Root CA should issue and revoke certificates very rarely.

## Exported files

After running the backup and export section, the export folder should contain files similar to:

```text
DariensTips-ML-DSA-RootCA.cer
<ServerName>_<CAName>.crt
<CAName>.crl
```

Recommended use:

| File | Purpose |
|---|---|
| `.cer` | Human-friendly exported copy of the Root CA public certificate. |
| `.crt` | AD CS-published CA certificate file that should match the AIA URL. |
| `.crl` | Root CA base CRL file that should match the CDP URL. |

## Backup warning

The CA backup contains sensitive material. Protect the backup password, private key material, exported registry configuration, and any external storage used to move the offline Root CA files.

## Optional BitLocker note

For an offline Root CA, consider protecting the system drive with BitLocker and storing recovery material securely offline. Do not place BitLocker startup PINs or recovery passwords directly in reusable scripts.

## References

- Microsoft: Post-Quantum Cryptography in AD CS overview  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/post-quantum-cryptography-overview

- Microsoft: Configure a certification authority to use ML-DSA  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/configure-ml-dsa-certification-authority

- Microsoft: Backup-CARoleService  
  https://learn.microsoft.com/en-us/powershell/module/adcsadministration/backup-caroleservice

- Microsoft: certutil  
  https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil

## Disclaimer

This script is provided for lab, demonstration, and educational use. Review and adapt it for your security policy, naming standards, backup procedures, CRL publication process, and production PKI requirements before using it outside a lab.
