CA07-MLDSA

new-netipaddress -InterfaceAlias "Ethernet" -IPAddress 10.22.25.7 -prefixlength 24 -DefaultGateway 10.22.25.1
new-netipaddress -InterfaceAlias "Ethernet" -IPAddress fd00:10:22:25::7 -prefixlength 64 -DefaultGateway fd00:10:22:25::1
set-dnsclientserveraddress -interfacealias "Ethernet" -serveraddresses 10.22.25.25,10.22.25.26,10.22.25.29,fd00:10:22:25::25,fd00:10:22:25::26,fd00:10:22:25::29


# Create request folder
$RequestFolder = 'C:\SubCA-Request'
$RequestPath   = "$RequestFolder\CA07-MLDSA-Enterprise-Subordinate2.req"
New-Item -ItemType Directory -Path $RequestFolder -Force


# Install AD CS Certification Authority role
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools


# Create Enterprise ML-DSA Subordinate CA request
$ADCSparams = @{
    CAType                    = 'EnterpriseSubordinateCA'
    CACommonName              = 'CA07-MLDSA-Enterprise-Subordinate2-CA'
    CADistinguishedNameSuffix = 'DC=dariens,DC=tips'
    CryptoProviderName        = 'ML-DSA:87#Microsoft Software Key Storage Provider'
    KeyLength                 = 20736
    HashAlgorithmName         = 'NoHash'
    OutputCertRequestFile     = $RequestPath
    DatabaseDirectory         = 'C:\WINDOWS\system32\CertLog'
    LogDirectory              = 'C:\WINDOWS\system32\CertLog'
}
Install-AdcsCertificationAuthority @ADCSparams

certutil.exe '-dump' $RequestPath

#----------------------

#Perform the request to the Root CA and retrieve the issued certificate
$rootCARoot = "C:\RootCA"
New-Item -Type Directory -Path "$rootCARoot\Requests" -Force
New-Item -Type Directory -Path "$rootCARoot\Issued" -Force

certreq.exe -submit "$rootCARoot\Requests\CA07-MLDSA-Enterprise-Subordinate2.req"

$reqID = <RequestId>
certutil.exe -resubmit $reqID
certreq.exe -retrieve $reqID "$rootCARoot\Issued\CA07-MLDSA-Enterprise-Subordinate2.cer"

#----------------------

# Complete AD CS Configuration, PowerShell
$RequestRootFolder = 'C:\SubCA-Request'
$RequestFolder     = "$RequestRootFolder\PKI-Export-20260627153016"
$IssuedCertFolder  = "$RequestRootFolder\Issued"
$RootCACert        = "$RequestFolder\DariensTips-ML-DSA-RootCA.cer"
$RootCACrl         = "$RequestFolder\Dariens Tips PQC ML-DSA Root Certification Authority.crl"

certutil.exe '-dump' $RootCACert
certutil.exe '-dump' $RootCACrl

# Install Root CA certificate into Local Computer Trusted Root store
Import-Certificate `
    -FilePath $RootCACert `
    -CertStoreLocation 'Cert:\LocalMachine\Root'

# Install Root CA CRL into the local CA/CRL store
certutil.exe -f -addstore CA $RootCACrl

# Install the issued subordinate CA certificate into the local CA store
certutil.exe '-installcert' "$IssuedCertFolder\CA07-MLDSA-Enterprise-Subordinate2.cer"
Start-Service -Name certsvc

# Check the CA configuration
certutil.exe -ping
certutil.exe -getconfig
certutil.exe -CAInfo
