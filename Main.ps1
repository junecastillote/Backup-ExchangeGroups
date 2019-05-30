#EDIT THESE VALUES
#Where is your script located?
$scriptFile = "C:\Scripts\Backup-ExchangeGroups\Backup-ExchangeGroups.ps1"

#Where do we save the backup?
$backupDirectory = "C:\Scripts\Backup-ExchangeGroups\Backup"

#Where do we put the transcript log?
$logDirectory = "C:\Scripts\Backup-ExchangeGroups\Log"

#Which XML file contains your Office 365 Login?
#   If you don't have this yet, run this: Get-Credential | Export-CliXML <file.xml>
$smtpCredentialFile = "C:\Scripts\Backup-ExchangeGroups\credential.xml"

#If we will send the email summary, what is the sender email address we should use?
#   This must be a valid, existing mailbox and address in Office 365
#   The account you use for the Credential File must have "Send As" permission on this mailbox
$sender = "sender@domain.com"

#Who are the recipients?
#   Multiple recipients can be added (eg. "recipient1@domain.com","recipient2@domain.com")
$recipients = "recipient1@domain.com","recipient2@domain.com"

$smtpSSL = $false
$smtpServer = "Server"
$smtpPort = 25
$exchangeServer = "ExchangeServer"

#If you want to delete older backups, define the age in days.
$cleanBackupsOlderThanXDays = 60

#Should we compress the backup in a Zip file? $true or $false
$compressFiles = $true

#Do you want to send the email summary? $true or $false
$sendEmail = $true

#Do you want to backup the Distribution Groups and Members? $true or $false
$backupDistributionGroups = $true

#Do you want to backup the Dynamic Distribution Groups? $true or $false
$backupDynamicDistributionGroups = $true

#If you want to test only or set specific result count, change this to any value other than zero.
# 0 = Unlimited
$limit = 0
#------------------------------------------

#DO NOT TOUCH THE BELOW CODES
$params = @{
    backupDirectory = $backupDirectory
    sendEmail = $sendEmail
    backupDistributionGroups = $backupDistributionGroups
    backupDynamicDistributionGroups = $backupDynamicDistributionGroups
}

if ($exchangeServer){$params += @{exchangeServer = $exchangeServer}}
if ($logDirectory){$params += @{logDirectory = $logDirectory}}
if ($compressFiles){$params += @{compressFiles = $compressFiles}}
if ($cleanBackupsOlderThanXDays){$params += @{cleanBackupsOlderThanXDays = $cleanBackupsOlderThanXDays}}
if ($sender){$params += @{sender = $sender}}
if ($recipients){$params += @{recipients = $recipients}}
if ($smtpServer){$params += @{smtpServer = $smtpServer}}
if ($smtpPort){$params += @{smtpPort = $smtpPort}}
if ($smtpSSL){$params += @{smtpSSL = $smtpSSL}}
if ($smtpCredentialFile) {$smtpCredential = (Import-Clixml $credentialFile);$params += @{smtpCredential = $smtpCredential}}
if ($limit -gt 0){$params += @{Limit = $limit}}


& "$scriptFile" @params