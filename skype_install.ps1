<#
.Description
       Skype For Business Server 2015. I'm pretty sure thescript also works for later SfB.
       Automated Installation
       Enterprise topology with 1 FE, Office Web Apps
       Backend is SQL Server 2012 with Always-On (some manual operations are required after deployment)
       All roles except of roles for Enterprise Voice (mediation and etc) are on FE
       + update get installed at the end of script. you can upload newest SkypeFB updates installer to prereqs folder.
.NOTES
       Name: SFB
       Author : Roman Levchenko
       WebSite: www.rlevchenko.com
       Prerequisites: skype share on DFS, SQL Instance (AlwaysON must be configured later), Office Web Apps
       Post-installation steps: check simple URLs (shoulde be configured during script execution), 
                                add additional FE/Edge, change SQL AlwaysOn Listener if it is necessary
#>

#Import Module

Import-Module "C:\Program Files\Common Files\Skype For Business Server 2015\modules\SkypeForBusiness\SkypeForBusiness.psd1"
Import-Module ActiveDirectory


## Variables ##

$Domain = Get-ADDomain
$Computer = $env:computername + '.' + $Domain.DNSRoot
$DC = (Get-ADForest).SchemaMaster
$Sbase = "CN=Configuration," + $Domain.DistinguishedName
$sqlfqdn = 'sqlag' + '.' + $domain.DNSRoot
$sqlprim = 'srv-sql-01' + '.' + $domain.DNSRoot
$poolfqdns = 'poolfe' + '.' + $domain.DNSRoot
$dialin = 'https://dialin' + '.' + $domain.dnsroot
$meet = 'https://meet' + '.' + $domain.dnsroot
$admin = 'https://admin' + '.' + $domain.dnsroot
$sip = 'sip' + '.' + $domain.DNSRoot
$owa = 'srv-owa-01' + '.' + $domain.DNSRoot
$owaurl = 'https://' + $owa + '/hosting/discover/'

#Prepare disk
$disk = get-disk | ? { $_.Size -eq "107374182400" -and $_.ProvisioningType -eq "Thin" }
Initialize-Disk $disk.Number
New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter S
Get-Partition -DiskNumber $disk.Number | Format-Volume -FileSystem NTFS -Force -Confirm:$false -ErrorAction SilentlyContinue

#install required KB
& C:\SkypeSource\prereqs\KB.MSU /quiet

<# Install the additional preprequisites 
cmd /c "SkypeFiles\Setup\amd64\setup\ocscore.msi" /q
cmd /c "SkypeFiles\Setup\amd64\vcredist_x64.exe" /q
cmd /c "SkypeFiles\Setup\amd64\setup\admintools.msi" /q
cmd /c "SkypeFiles\Setup\amd64\SQLSysClrTypes.msi" /q
#>

#Prepare AD to Skype
Install-CSAdServerSchema -Confirm:$false -Verbose -Report "C:\SkypeSource\logs\Install-CSAdServerSchema.html" | Out-Null
#cannot update forest with lync extensions "directory object not found". additional parameters and force wait are needed
do { $csforest = get-csadforest; Enable-CSAdForest -GlobalSettingsDomainController $DC -Verbose -Force -Confirm:$false -Report "C:\SkypeSource\logs\Enable-CSAdForest.html" | Out-Null }
until ($csforest -contains "LC_FORESTSETTINGS_STATE_READY")
do { $csdomain = get-csaddomain ; Enable-CSAdDomain -GlobalSettingsDomainController $DC -Force -Verbose -Confirm:$false -Report "C:\SkypeSource\logs\Enable-CSAdDomain.html" | Out-Null }
until ($csdomain -contains "LC_DOMAINSETTINGS_STATE_READY")
Start-Sleep -Seconds 120
#Create required DNS records (pool,fe,simple URLs) , add domain admins to Skype Adm Groups
$lyncIP = Get-NetAdapter | Get-NetIPAddress -AddressFamily IPv4
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name sip -ZoneName $Domain.DNSRoot -ComputerName $DC
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name meet -ZoneName $Domain.DNSRoot -ComputerName $DC
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name admin -ZoneName $Domain.DNSRoot -ComputerName $DC
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name dialin -ZoneName $Domain.DNSRoot -ComputerName $DC
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name poolfe -ZoneName $Domain.DNSRoot -ComputerName $DC

#Record for web scheduler
Add-DnsServerResourceRecordA -IPv4Address $lyncIP.IPv4Address -Name scheduler -ZoneName $Domain.DNSRoot -ComputerName $DC

#Autodiscovery for Skype For Business
Add-DnsServerResourceRecordCName -Name lyncdiscoverinternal -HostNameAlias $poolfqdns -ZoneName $Domain.DNSRoot -ComputerName $DC

#Add Legacy SRV record
Add-DnsServerResourceRecord -Srv -Name _sipinternaltls._tcp -Port 5061 -Priority 0 -Weight 0 -DomainName $poolfqdns -ZoneName $Domain.DNSRoot -ComputerName $DC

#Add domains admins to RTC Admins
Add-ADGroupMember -Identity CSAdministrator -Members "Domain Admins"
Add-ADGroupMember -Identity RTCUniversalServerAdmins -Members "Domain Admins"

#Install CMS and Set Store Location
Install-CsDatabase -CentralManagementDatabase -SqlServerFqdn $sqlprim -DatabasePaths S:\SQLLogs, S:\Databases | Out-Null
do { $cmsloc = Get-CsConfigurationStoreLocation; Set-CsConfigurationStoreLocation -SqlServerFqdn $sqlfqdn -GlobalSettingsDomainController $DC -Confirm:$false }
until ($cmsloc.BackEndServer -eq $sqlfqdn)

#Build and Publish Lync Topology
#Some XML parts must be changed with right FQDNs

$xml = New-Object XML
$xml.Load("c:\SkypeSource\DefaultTopology.xml")
$xml.Topology.InternalDomains.DefaultDomain = $domain.DNSRoot
$xml.Topology.InternalDomains.InternalDomain.Name = $domain.DNSRoot
#($xml.Topology.SimpleUrlConfiguration.SimpleUrl|? {$_.Component -eq "Dialin"}).ActiveURL=$dialin
#($xml.Topology.SimpleUrlConfiguration.SimpleUrl.SimpleUrlEntry|? {$_.URL -eq "https://dialin.tenant.rlevchenko.com"}).URL=$dialin
#($xml.Topology.SimpleUrlConfiguration.SimpleUrl.SimpleUrlEntry|? {$_.URL -eq "https://meet.tenant.rlevchenko.com"}).URL=$meet
#($xml.Topology.SimpleUrlConfiguration.SimpleUrl|? {$_.Component -eq "Meet"}).ActiveURL=$meet
($xml.Topology.Clusters.Cluster | ? { $_.FQDN -eq "poolfe.tenant.rlevchenko.com" }).Fqdn = $poolfqdns
($xml.Topology.Clusters.Cluster | ? { $_.FQDN -eq "srv-sql-01.tenant.rlevchenko.com" }).Fqdn = $sqlfqdn
($xml.Topology.Clusters.Cluster | ? { $_.FQDN -eq "tenant.rlevchenko.com" }).Fqdn = $domain.DNSRoot
($xml.Topology.Clusters.Cluster | ? { $_.FQDN -eq "srv-owa-01.tenant.rlevchenko.com" }).Fqdn = $owa
($xml.Topology.Clusters.Cluster.Machine | ? { $_.FQDN -eq "tenant.rlevchenko.com" }).Fqdn = $domain.DNSRoot
($xml.Topology.Clusters.Cluster.Machine | ? { $_.FQDN -eq "skype-fe-01.tenant.rlevchenko.com" }).Fqdn = $Computer
($xml.Topology.Clusters.Cluster.Machine | ? { $_.FQDN -eq "srv-sql-01.tenant.rlevchenko.com" }).Fqdn = $sqlfqdn
($xml.Topology.Clusters.Cluster.Machine | ? { $_.FaultDomain -eq "srv-sql-01.tenant.rlevchenko.com" }).FaultDomain = $sqlfqdn
($xml.Topology.Clusters.Cluster.Machine | ? { $_.UpgradeDomain -eq "srv-sql-01.tenant.rlevchenko.com" }).UpgradeDomain = $sqlfqdn
($xml.Topology.Clusters.Cluster.Machine | ? { $_.FQDN -eq "srv-owa-01.tenant.rlevchenko.com" }).Fqdn = $owa
($xml.Topology.SqlInstances.SqlInstance | ? { $_.AlwaysOnPrimaryNodeFqdn -eq "srv-sql-01.tenant.rlevchenko.com" }).AlwaysOnPrimaryNodeFqdn = $sqlprim
($xml.Topology.Services.Service.wacservice | ? { $_.DiscoveryURL -eq "https://srv-owa-01.tenant.rlevchenko.com/hosting/discover/" }).DiscoveryUrl = $owaurl
$xml.Topology.Services.Service.Webservice.externalsettings.Host = $poolfqdns
$xml.Save("c:\SkypeSource\DefaultTopology.xml")

#Publish and enable saved topology
Publish-CSTopology -Filename c:\SkypeSource\DefaultTopology.xml -Force | Out-Null
Enable-CSTopology | Out-Null
Start-Sleep -Seconds 60

#Install other databases to backend
Install-CsDatabase -ConfiguredDatabases -SqlServerFqdn $sqlfqdn -DatabasePaths S:\SQLLogs, S:\Databases | Out-Null


#Local Databases
#& 'C:\Program Files\Skype For Business Server 2015\Deployment\bootstrapper.exe' /BootstrapSqlExpress /SourceDirectory:"C:\SkypeSource\SkypeFiles\Setup\amd64"|Out-Null
#Local Management Store
& 'C:\Program Files\Skype For Business Server 2015\Deployment\bootstrapper.exe' /Bootstraplocalmgmt /SourceDirectory:"C:\SkypeSource\SkypeFiles\Setup\amd64" | Out-Null
Enable-CsReplica | Out-Null
Start-CSWindowsService replica | Out-Null
$CSConfigExp = Export-csconfiguration -asbytes
Import-CsConfiguration -Byteinput $CSConfigExp -LocalStore | Out-Null


#Install Skype Services
& 'C:\Program Files\Skype For Business Server 2015\Deployment\Bootstrapper.exe' /SourceDirectory:"C:\SkypeSource\SkypeFiles\Setup\amd64" | Out-Null

#Request and assign certificates

$CDP = Get-ADObject -LDAPFilter "(&(cn=CDP))" -SearchBase $Sbase
$CA = Get-Adobject -LDAPFilter "(&(objectClass=pKIEnrollmentService)(cn=*))" -SearchBase $Sbase
$CAhostname = (Get-ADObject -SearchBase $CDP -Filter * | ? { $_.Name -like "srv-*" -and $_.ObjectClass -eq "Container" }).Name
$CAName = $CAhostname + "." + $domain.DNSroot + "\" + $CA.Name

$certServer = Request-CsCertificate -New -Type Default, WebServicesInternal, WebServicesExternal -CA $CAName -Country "RU" -State "VRN" -City "Voronezh" -FriendlyName "Skype WS Internal Certficate" -PrivateKeyExportable $True -KeySize 2048 -DomainName $sip -AllSipDomain
$certOAuth = Request-CsCertificate -New -Type OAuthTokenIssuer -CA $CAName -Country "RU" -State "VRN" -City "Voronezh" -FriendlyName "Skype OathCert" -PrivateKeyExportable $True -KeySize 2048 -AllSipDomain
Set-CsCertificate -Reference $certServer -Type Default, WebservicesInternal, WebServicesExternal
Set-CsCertificate -Reference $certOAuth -Type OAuthTokenIssuer
$CSConfigExp = Export-csconfiguration -asbytes
Import-CsConfiguration -Byteinput $CSConfigExp -LocalStore | Out-Null
#Start Skype Services
Start-CsPool -PoolFQDN $poolfqdns -Force -Confirm:$false | Out-Null

#Simple URLs
#Meet and Dialin Simple URLs
$urlEntry = New-CsSimpleUrlEntry -Url $dialin
$simpleUrl = New-CsSimpleUrl -Component "dialin" -Domain "*" -SimpleUrl $urlEntry -ActiveUrl $dialin
 
$urlEntry2 = New-CsSimpleUrlEntry -Url $meet
$simpleUrl2 = New-CsSimpleUrl -Component "meet" -Domain $domain.DNSRoot -SimpleUrl $urlEntry2 -ActiveUrl $meet
 
Set-CsSimpleUrlConfiguration -SimpleUrl @{Add = $simpleUrl, $simpleUrl2 }

#Admin Simple URL
$urlEntry3 = New-CsSimpleUrlEntry -Url $admin
$simpleUrl3 = New-CsSimpleUrl -Component "admin" -Domain "*" -SimpleUrl $urlEntry3 -ActiveUrl $admin
 
Set-CsSimpleUrlConfiguration -SimpleUrl @{Add = $simpleUrl3 }
Enable-CsComputer -Force

#Update Skype with cumulative update
Stop-CsWindowsService -ComputerName $computer | Out-Null
cmd /c """C:\SkypeSource\prereqs\SkypeServerUpdateInstaller.exe""" /silentmode"" | Out-Null
Reset-CsPoolRegistrarState -ResetType FullReset -PoolFqdn $poolfqdns -Force | Out-Null
Start-CsPool -PoolFqdn $poolfqdns -Force | Out-Null
