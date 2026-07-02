# Windows Server 2025 ML-DSA Two-Tier PKI Lab

This repository supports a two-part Windows Server 2025 Active Directory Certificate Services (AD CS) lab for building a **post-quantum-ready two-tier PKI hierarchy** using the Microsoft **ML-DSA** cryptographic provider.

The same GitHub page can be referenced by both videos:

1. **Part 1:** Build and secure a standalone offline ML-DSA Root CA.
2. **Part 2:** Build a domain-joined Enterprise ML-DSA Subordinate CA.

> Replace the example names, domain values, DNS names, paths, and organization values before using these commands in your own lab.

---

## Videos in this series

### Part 1

**Windows Server 2025: Build an Offline ML-DSA Root CA for Post-Quantum PKI**

This part builds the offline Root CA, configures CDP and AIA publication paths, publishes a base CRL, backs up the CA, and exports the Root CA certificate and CRL files.

### Part 2

**Windows Server 2025: Build an Enterprise ML-DSA Subordinate CA for Post-Quantum PKI**

This part builds the Enterprise Subordinate CA, generates the SubCA request, submits and issues the request from the offline Root CA, completes the SubCA installation, and publishes the Root CA certificate and CRL through HTTP.

---

## Files

| File | Purpose |
|---|---|
| `MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1` | Combined PowerShell script with functions for the offline Root CA, Enterprise Subordinate CA, request processing, certificate installation, verification, and HTTP publishing. |
| `README.md` | This documentation file. |

---

## What the combined script does

The PowerShell script contains phases for:

- Installing a standalone offline Root CA.
- Configuring the Root CA with the `ML-DSA:87` provider.
- Configuring Root CA CDP and AIA HTTP locations.
- Setting a Root CA base CRL lifetime.
- Disabling Delta CRLs for the offline Root CA.
- Publishing a fresh Root CA base CRL.
- Backing up the Root CA database, private key material, and CertSvc registry configuration.
- Exporting the Root CA certificate and copying `.crt` and `.crl` files for publication.
- Creating an Enterprise Subordinate CA request.
- Submitting the SubCA request to the offline Root CA.
- Manually issuing the pending SubCA request.
- Retrieving the issued SubCA certificate.
- Importing the Root CA certificate into the SubCA Trusted Root store.
- Importing the Root CA CRL into the SubCA CA/CRL store.
- Installing the issued SubCA certificate.
- Starting and verifying Certificate Services on the SubCA.
- Installing IIS and publishing static CDP/AIA files through an HTTP `CertEnroll` virtual directory.

---

## Requirements

### Offline Root CA

- Windows Server 2025 Server Core or Windows Server 2025 with Desktop Experience.
- Local administrator rights.
- AD CS Certification Authority role service.
- A newly built server intended to become the offline Root CA.
- A reachable HTTP publication location, such as:

```text
http://pki.example.com/CertEnroll/
```

### Enterprise Subordinate CA

- Windows Server 2025 Server Core or Windows Server 2025 with Desktop Experience.
- Domain-joined server.
- A domain account with the required AD CS installation rights.
- AD CS Certification Authority role service.
- Access to the Root CA certificate and Root CA CRL exported from the offline Root CA.
- Access to the SubCA certificate issued by the offline Root CA.

### ML-DSA support

Review the current Microsoft documentation before using ML-DSA in a production environment. ML-DSA support in AD CS depends on operating system build level, cumulative updates, client support, and certificate scenario compatibility.

---

## Important customization values

Before running the script, review and modify the **Configuration** section at the top of the PowerShell file.

Common values to change:

```powershell
$RootCACommonName
$RootCADistinguishedNameSuffix
$SubCACommonName
$SubCADistinguishedNameSuffix
$PkiHttpBase
$RootCARootPath
$SubCARequestRoot
$HttpCertEnrollPhysicalPath
```

Example placeholder values:

```powershell
$RootCACommonName              = 'ORG PQC ML-DSA Root Certification Authority'
$RootCADistinguishedNameSuffix = 'O=ORG,ST=STATE,C=US'
$SubCACommonName               = 'ORG-MLDSA-Enterprise-Subordinate-CA'
$SubCADistinguishedNameSuffix  = 'DC=example,DC=com'
$PkiHttpBase                   = 'http://pki.example.com/CertEnroll'
```

---

## Recommended workflow

### 1. Build the offline Root CA

Run on the offline Root CA from an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCAAll
```

This installs AD CS, configures the offline Root CA, configures CDP/AIA, publishes the CRL, backs up the CA, and exports publication files.

---

### 2. Copy Root CA files to the SubCA staging folder

Copy the Root CA export folder from the offline Root CA to the SubCA.

The SubCA later needs:

```text
OfflineRootCA.cer or the AD CS-published .crt file
Root CA base .crl file
```

---

### 3. Create the Enterprise Subordinate CA request

Run on the future Enterprise Subordinate CA from an elevated PowerShell session using a domain account with the required AD CS rights:

```powershell
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase SubCACreateRequest
```

This installs the AD CS role service and creates a SubCA request file.

---

### 4. Move the SubCA request to the offline Root CA

Copy the generated request file from the SubCA to the offline Root CA request folder.

Example:

```text
C:\RootCA\Requests\ORG-MLDSA-Enterprise-Subordinate-CA.req
```

---

### 5. Submit, issue, and retrieve the SubCA certificate

Run on the offline Root CA:

```powershell
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCASubmitIssueSubCA
```

The script submits the request. Because this is a standalone Root CA workflow, the request is normally pending until manually issued. Enter the returned Request ID when prompted, or provide it directly:

```powershell
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase RootCASubmitIssueSubCA -RequestId 5
```

Copy the issued SubCA certificate back to the SubCA.

---

### 6. Complete the Enterprise Subordinate CA configuration

Run on the Enterprise Subordinate CA:

```powershell
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase SubCAComplete
```

This imports the Root CA certificate, imports the Root CA CRL, installs the issued SubCA certificate, starts Certificate Services, and verifies the CA.

---

### 7. Publish Root CA certificate and CRL over HTTP

Run on the SubCA or a dedicated web server:

```powershell
.\MLDSAADCS_ADCS-2TierPKI-MLDSA.ps1 -Phase WebPublishFiles
```

This installs IIS, creates a `CertEnroll` virtual directory, grants read access to IIS, copies `.cer`, `.crt`, and `.crl` files to the publishing folder, and enables static HTTP access.

---

## CDP and AIA design

The offline Root CA uses HTTP CDP and AIA URLs similar to:

```text
http://pki.example.com/CertEnroll/<CRL file>
http://pki.example.com/CertEnroll/<CA certificate file>
```

The Root CA publishes files locally, then the files are manually copied to the online HTTP publication point.

For the offline Root CA, the script configures:

```powershell
certutil.exe -setreg CA\CRLPublicationURLs "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%3%8%9.crl\n2:http://pki.example.com/CertEnroll/%3%8%9.crl"

certutil.exe -setreg CA\CACertPublicationURLs "1:C:\WINDOWS\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:http://pki.example.com/CertEnroll/%1_%3%4.crt"
```

Meaning:

| Value | Meaning |
|---:|---|
| `1` | Publish the CRL or CA certificate locally. |
| `2` | Include the HTTP location in issued certificates. |

---

## Why HTTP instead of HTTPS for CDP and AIA?

CRL and AIA locations are commonly published over HTTP because CRLs and CA certificates are already signed objects. Using HTTPS for bootstrap certificate and revocation retrieval can create certificate validation circular dependencies.

Use anonymous read-only HTTP access for `.crl`, `.crt`, and `.cer` files. Do not require authentication.

---

## Root CA CRL lifetime

The script configures the offline Root CA base CRL lifetime as 52 weeks:

```powershell
certutil.exe -setreg CA\CRLPeriod Weeks
certutil.exe -setreg CA\CRLPeriodUnits 52
```

Even though the Root CA is offline, its CRL still expires. Clients use the Root CA CRL to determine whether the Subordinate CA certificate has been revoked.

---

## Delta CRLs

The script disables Delta CRLs on the offline Root CA:

```powershell
certutil.exe -setreg CA\CRLDeltaPeriodUnits 0
```

For an offline Root CA, Delta CRLs are normally unnecessary because the Root CA should issue and revoke certificates very rarely.

---

## Exported Root CA files

The Root CA export folder should contain files similar to:

```text
OfflineRootCA.cer
<ServerName>_<CAName>.crt
<CAName>.crl
```

Recommended use:

| File | Purpose |
|---|---|
| `.cer` | Human-friendly exported copy of the Root CA public certificate. |
| `.crt` | AD CS-published CA certificate file that should match the AIA URL. |
| `.crl` | Root CA base CRL file that should match the CDP URL. |

---

## SubCA validation commands

Useful commands after completing the Enterprise Subordinate CA:

```powershell
certutil.exe -ping
certutil.exe -getconfig
certutil.exe -CAInfo
certutil.exe '-ca.cert' C:\Temp\SubCA.cer
certutil.exe '-dump' C:\Temp\SubCA.cer
certutil.exe -crl
certutil.exe -urlfetch -verify C:\Temp\SubCA.cer
```

---

## Security notes

- Protect the offline Root CA private key.
- Protect CA backups, backup passwords, and exported registry configuration.
- Power off and secure the Root CA when it is not being used.
- Bring the Root CA online before the Root CA CRL expires.
- Verify CDP and AIA reachability before issuing certificates broadly.
- Verify Active Directory replication health and DNS resolution.
- Do not hard-code BitLocker PINs, recovery passwords, CA backup passwords, or other secrets into reusable scripts.
- In production, use your organization’s PKI design, naming standards, security controls, backup process, and change-control process.

---

## References

- Microsoft: Post-Quantum Cryptography in AD CS overview  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/post-quantum-cryptography-overview

- Microsoft: Configure a certification authority to use ML-DSA  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/configure-ml-dsa-certification-authority

- Microsoft: Configure ML-DSA certificate templates  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/configure-ml-dsa-certificate-templates

- Microsoft: Install-AdcsCertificationAuthority  
  https://learn.microsoft.com/en-us/powershell/module/adcsdeployment/install-adcscertificationauthority

- Microsoft: Backup-CARoleService  
  https://learn.microsoft.com/en-us/powershell/module/adcsadministration/backup-caroleservice

- Microsoft: certreq  
  https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certreq_1

- Microsoft: certutil  
  https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil

---

## Disclaimer

This script and README are provided for lab, demonstration, and educational use. Review and adapt them for your security policy, naming standards, backup procedures, CRL publication process, client compatibility requirements, and production PKI requirements before using them outside a lab.
