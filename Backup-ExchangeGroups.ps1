
<#PSScriptInfo

.VERSION 1.0

.GUID 7f9c662f-bc10-4bd8-aeea-023a1d42b6e4

.AUTHOR june

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 PowerShell script to backup Exchange Distribution Groups (Static/Dyamic) to XML files.

#> 
Param(
        #Exchange OnPrem Server FQDN
        [Parameter(Mandatory=$true,Position=0)]
        [string]$exchangeServer,

        #path to the backup directory (eg. c:\scripts\backup)
        [Parameter(Mandatory=$true,Position=1)]
        [string]$backupDirectory,

        #organization name
        [Parameter(Mandatory=$true,Position=2)]
        [string]$orgName,

        #path to the log directory (eg. c:\scripts\logs)
        [Parameter()]
        [string]$logDirectory,
        
        #Sender Email Address
        [Parameter()]
        [string]$sender,

        #Recipient Email Addresses - separate with comma
        [Parameter()]
        [string[]]$recipients,

        #Switch to enable email report
        [Parameter()]
        [switch]$sendEmail,

        #smtpServer
        [Parameter()]
        [string]$smtpServer,

        #smtpPort
        [Parameter()]
        [string]$smtpPort,

        #credential for SMTP server (if applicable)
        [Parameter()]
        [pscredential]$smtpCredential,

        #switch to indicate if SSL will be used for SMTP relay
        [Parameter()]
        [switch]$smtpSSL,

        #Delete older backups (days)
        [Parameter()]
        [int]$cleanBackupsOlderThanXDays,

        #switch to backup distribution groups
        [Parameter()]
        [switch]$backupDistributionGroups,

        #switch to backup dynamic distribution groups
        [Parameter()]
        [switch]$backupDynamicDistributionGroups,

        #switch to enable compression of the report files (ZIP)
        [Parameter()]
        [switch]$compressFiles,

        #limit the result - for testing purposes only.
        [Parameter(Mandatory=$false)]
        [int]$limit
)
#Functions------------------------------------------------------------------------------------------
#Function to connect to Exchange OnPrem Shell
Function New-ExchangeOnPremSession()
{
    [CmdletBinding()]
    param(
        [parameter(mandatory=$true,position=0)]
        [string] $exchangeServer
    )
    Remove-PSSession -Name "ExchangeOnPrem" -Confirm:$false -ErrorAction SilentlyContinue
	$EXSession = New-PSSession -Name "ExchangeOnPrem" -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$($exchangeServer)/PowerShell/" -Authentication Kerberos
	Import-PSSession $EXSession -AllowClobber -DisableNameChecking | out-null
}

#Function to compress the CSV file (ps 4.0)
Function New-ZipFile
{
	[CmdletBinding()] 
    param ( 
        [Parameter(Mandatory)] 
        [string]$fileToZip,    
				[Parameter(Mandatory)]
				[string]$destinationZip
	)
	Add-Type -assembly System.IO.Compression
	Add-Type -assembly System.IO.Compression.FileSystem
	[System.IO.Compression.ZipArchive]$outZipFile = [System.IO.Compression.ZipFile]::Open($destinationZip, ([System.IO.Compression.ZipArchiveMode]::Create))
	[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($outZipFile, $fileToZip, (Split-Path $fileToZip -Leaf)) | out-null
	$outZipFile.Dispose()
}

#Function to delete old files based on age
Function Invoke-Housekeeping
{
    [CmdletBinding()] 
    param ( 
        [Parameter(Mandatory)] 
        [string]$folderPath,
    
		[Parameter(Mandatory)]
		[int]$daysToKeep
    )
    
    $datetoDelete = (Get-Date).AddDays(-$daysToKeep)
    $filesToDelete = Get-ChildItem $FolderPath | Where-Object { $_.LastWriteTime -lt $datetoDelete }

    if (($filesToDelete.Count) -gt 0) {	
		foreach ($file in $filesToDelete) {
            Remove-Item -Path ($file.FullName) -Force -ErrorAction SilentlyContinue
		}
	}	
}

#Function to Stop Transaction Logging
Function Stop-TxnLogging
{
	$txnLog=""
	Do {
		try {
			Stop-Transcript | Out-Null
		} 
		catch [System.InvalidOperationException]{
			$txnLog="stopped"
		}
    } While ($txnLog -ne "stopped")
}

#Function to Start Transaction Logging
Function Start-TxnLogging 
{
    param 
    (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$logDirectory
    )
	Stop-TxnLogging
    Start-Transcript $logDirectory -Append
}
#----------------------------------------------------------------------------------------------------
Stop-TxnLogging
Clear-Host
$scriptInfo = Test-ScriptFileInfo -Path $MyInvocation.MyCommand.Definition

#parameter check ----------------------------------------------------------------------------------------------------
$isAllGood = $true
if (!$backupDistributionGroups -and !$backupDynamicDistributionGroups)
{
    Write-Host "ERROR: No backup type is specified. Please use one or both switches (-backupDistributionGroups, -backupDynamicDistributionGroups)" -ForegroundColor Yellow
    $isAllGood = $false
}

#parameter check ----------------------------------------------------------------------------------------------------
$isAllGood = $true

if ($sendEmail)
{
    if (!$sender)
    {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: A valid sender email address is not specified." -ForegroundColor Yellow
        $isAllGood = $false
    }

    if (!$recipients)
    {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: No recipients specified." -ForegroundColor Yellow
        $isAllGood = $false
    }

    if (!$smtpServer )
    {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: No SMTP Server specified." -ForegroundColor Yellow
        $isAllGood = $false
    }

    if (!$smtpPort )
    {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: No SMTP Port specified." -ForegroundColor Yellow
        $isAllGood = $false
    }
}

if ($isAllGood -eq $false)
{
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: Exiting Script." -ForegroundColor Yellow
    EXIT
}
#----------------------------------------------------------------------------------------------------

if ($isAllGood -eq $false)
{
    EXIT
}
#----------------------------------------------------------------------------------------------------

#365 Mail-------------------------------------------------------------------------------------
#[string]$smtpServer = "smtp.office365.com"
#[int]$smtpPort = "587"
[string]$mailSubject = "Exchange Groups Backup"
#----------------------------------------------------------------------------------------------------

#Set Paths-------------------------------------------------------------------------------------------
$Today=Get-Date
[string]$fileSuffix = '{0:dd-MMM-yyyy_hh-mm_tt}' -f $Today
$logFile = "$($logDirectory)\DebugLog_$($fileSuffix).txt"
$backupPath = "$($backupDirectory)\$($fileSuffix)"
$DG_backupFile = "$($backupPath)\DistributionGroups.xml"
$DDG_backupFile = "$($backupPath)\DynamicDistributionGroups.xml"
$zipFile = "$($backupDirectory)\Backup_$($fileSuffix).zip"
#----------------------------------------------------------------------------------------------------

#Create folders if not found
if ($logDirectory) 
{
    if (!(Test-Path $logDirectory)) 
    {
        New-Item -ItemType Directory -Path $logDirectory | Out-Null
        #start transcribing----------------------------------------------------------------------------------
        Start-TxnLogging $logFile
        #----------------------------------------------------------------------------------------------------
    }
	else
	{
		Start-TxnLogging $logFile
	}
}

if (!(Test-Path $backupPath)) {New-Item -ItemType Directory -Path $backupPath | Out-Null}



#BEGIN------------------------------------------------------------------------------------------
Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Begin" -ForegroundColor Green
Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Connecting to Exchange Server [$($exchangeServer)]" -ForegroundColor Green

#Connect to O365 Shell
try 
{
     New-ExchangeOnPremSession -exchangeServer $exchangeServer
}
catch 
{
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": There was an error connecting to Exchange. Terminating Script" -ForegroundColor YELLOW
    Stop-TxnLogging
    EXIT
}

$tenantName = $orgName

#Start Export Process---------------------------------------------------------------------------
if ($backupDistributionGroups)
{
    $members = @()
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Retrieving Distribution Groups" -ForegroundColor Yellow
    if ($limit)
    {
        $dgrouplist = Get-DistributionGroup -ResultSize $limit -WarningAction SilentlyContinue | Sort-Object Name
    }
    else
    {
        $dgrouplist = Get-DistributionGroup -ResultSize Unlimited -WarningAction SilentlyContinue | Sort-Object Name
    }
    
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": There are a total of $($dgrouplist.count) Distribution Groups" -ForegroundColor Yellow
    $dgrouplist | Export-Clixml -Path $DG_backupFile -Depth 5

    $i=1
    foreach ($dgroup in $dgrouplist)
    {
        $dgroup_members = Get-Group $dgroup.DistinguishedName | Select-Object Members,WindowsEmailAddress,DisplayName
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ($($i) of $($dgrouplist.count)) | [$($dgroup_members.members.count) members] | $($dgroup.DisplayName)" -ForegroundColor Yellow
        $i=$i+1
        $members += $dgroup_members
    }
    $members | Export-Clixml -Path "$backupPath\DistributionGroupMembers.xml"
}

if ($backupDynamicDistributionGroups)
{
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Retrieving Dynamic Distribution Groups" -ForegroundColor Yellow
    if ($limit)
    {
        $ddgrouplist = Get-DynamicDistributionGroup -ResultSize $Limit -WarningAction SilentlyContinue | Sort-Object Name
    }
    else
    {
        $ddgrouplist = Get-DynamicDistributionGroup -ResultSize Unlimited -WarningAction SilentlyContinue | Sort-Object Name
    }
    
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": There are a total of $($ddgrouplist.count) Dynamic Distribution Groups" -ForegroundColor Yellow
    $ddgrouplist | Export-Clixml -Path $DDG_backupFile -Depth 5
}
#----------------------------------------------------------------------------------------------------

#Zip the file to save space--------------------------------------------------------------------------
if ($compressFiles)
{
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Compressing files..." -ForegroundColor Yellow
    Compress-Archive -Path "$backupPath\*.*" -DestinationPath $zipFile -CompressionLevel Optimal
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Backup Saved to $zipFile" -ForegroundColor Yellow
    $zipSize = (Get-ChildItem $zipFile | Measure-Object -Property Length -Sum)
    #Allow some time (in seconds) for the file access to close, increase especially if the resulting files are huge, or server I/O is busy.
    $sleepTime=5
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Pending next operation for $($sleepTime) seconds" -ForegroundColor Yellow
    Start-Sleep -Seconds $sleepTime
    Remove-Item -Path $backupPath -Recurse -Force
}
else 
{
    Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Backup Saved to $backupPath" -ForegroundColor Yellow
    $zipSize = (Get-ChildItem "$backupPath\*.*" | Measure-Object -Property Length -Sum)
}
#----------------------------------------------------------------------------------------------------

#Invoke Housekeeping---------------------------------------------------------------------------------
#if ($enableHousekeeping)
if ($cleanBackupsOlderThanXDays)
{
	Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Deleting backup files older than $($cleanBackupsOlderThanXDays) days" -ForegroundColor Yellow
	Invoke-Housekeeping -folderPath $backupDirectory -daysToKeep $cleanBackupsOlderThanXDays
}
#-----------------------------------------------------------------------------------------------
#Count the number of backups existing and the total size----------------------------------------
$topLevelBackupFiles = (Get-ChildItem $backupDirectory)
$deepLevelBackupFiles = (Get-ChildItem $backupDirectory -Recurse | Measure-Object -Property Length -Sum)
#-----------------------------------------------------------------------------------------------
$timeTaken = New-TimeSpan -Start $Today -End (Get-Date)
#Send email if option is enabled ---------------------------------------------------------------
if ($sendEmail)
{
Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Sending report to" ($recipients -join ";") -ForegroundColor Yellow
$xSubject="[$($tenantName)] $($mailSubject): " + ('{0:dd-MMM-yyyy hh:mm:ss tt}' -f $Today)
$htmlBody=@'
<!DOCTYPE html>
<html>
<head>
<style>
table {
  font-family: "Century Gothic", sans-serif;
  border-collapse: collapse;
  width: 100%;
}
td, th {
  border: 1px solid #dddddd;
  text-align: left;
  padding: 8px;
}

</style>
</head>
<body>
<table>
'@
$htmlBody+="<tr><th>----SUMMARY----</th></tr>"
$htmlBody+="<tr><th>Tenant Name</th><td>$($tenantName)</td></tr>"
if ($backupDistributionGroups)
{
    $htmlBody+="<tr><th>Number of Distribution Groups</th><td>$($dgrouplist.count)</td></tr>"
}

if ($backupDynamicDistributionGroups)
{
    $htmlBody+="<tr><th>Number of Dynamic Distribution Groups</th><td>$($ddgrouplist.count)</td></tr>"
}

$htmlBody+="<tr><th>Backup Server</th><td>"+(Get-Content env:computername)+"</td></tr>"

if ($compressFiles)
{
    $htmlBody+="<tr><th>Backup File</th><td>$($zipFile)</td></tr>"
}
else
{
    $htmlBody+="<tr><th>Backup Folder</th><td>$($backupPath)</td></tr>"
}
if ($logDirectory) 
{
    $htmlBody+="<tr><th>Log File</th><td>$($logFile)</td></tr>"
}

$htmlBody+="<tr><th>Backup Size</th><td>"+ ("{0:N0}" -f ($zipSize.Sum / 1KB)) + " KB</td></tr>"
$htmlBody+="<tr><th>Time to Complete</th><td>"+ ("{0:N0}" -f $($timeTaken.TotalMinutes)) + " Minutes</td></tr>"
$htmlBody+="<tr><th>Total Number of Backups</th><td>$($topLevelBackupFiles.Count)</td></tr>"
$htmlBody+="<tr><th>Total Backup Folder Size</th><td>"+ ("{0:N0}" -f ($deepLevelBackupFiles.Sum / 1KB)) + " KB</td></tr>"
$htmlBody+="<tr><th>----SETTINGS----</th></tr>"
$htmlBody+="<tr><th>Compress Backup</th><td>$($compressFiles)</td></tr>"

if ($cleanBackupsOlderThanXDays -and $cleanBackupsOlderThanXDays -gt 1)
{
    $htmlBody+="<tr><th>Delete Backups Older Than </th><td>$($cleanBackupsOlderThanXDays) days</td></tr>"
}
elseif ($cleanBackupsOlderThanXDays -and $cleanBackupsOlderThanXDays -eq 1)
{
    $htmlBody+="<tr><th>Delete Backups Older Than </th><td>$($cleanBackupsOlderThanXDays) day</td></tr>"
}

#if ($sendEmail)
#{
#    $htmlBody+="<tr><th>SMTP Server</th><td>$($smtpServer)</td></tr>"
#}

$htmlBody+="<tr><th>Script Path</th><td>$($MyInvocation.MyCommand.Definition)</td></tr>"
$htmlBody+="<tr><th>Script Info</th><td><a href=""$($scriptInfo.ProjectURI)"">$($scriptInfo.Name)</a> version $($scriptInfo.version)</td></tr>"
$htmlBody+="</table></body></html>"
#Send-MailMessage -from $sender -to $recipients -subject $xSubject -body $htmlBody -dno onSuccess, onFailure -smtpServer $SMTPServer -Port $smtpPort -Credential $credential -UseSsl -BodyAsHtml
if ($sendEmail -eq $true)
    {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": Sending email to" ($recipients -join ",") -ForegroundColor Green
        $mailParams = @{
            From = $sender
            To = $recipients
            Subject = $xSubject
            Body = $htmlBody
            smtpServer = $smtpServer
            Port = $smtpPort
            useSSL = $smtpSSL
            BodyAsHtml = $true
        }

        if ($smtpCredential) 
        {
            $mailParams += @{
                credential = $smtpCredential
            }
        }
        Send-MailMessage @mailParams
    }
}
#-----------------------------------------------------------------------------------------------
Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": End" -ForegroundColor Green
#-----------------------------------------------------------------------------------------------
Stop-TxnLogging


