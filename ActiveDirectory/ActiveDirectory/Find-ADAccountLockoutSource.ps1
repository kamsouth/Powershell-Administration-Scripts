# ============================================================
# Find-ADAccountLockoutSource.ps1
#
# Active Directory Account Lockout Investigation Tool
#
# Purpose:
#   Investigates recurring AD account lockouts by correlating
#   domain controller Security logs.
#
# Events:
#   4740 - Account locked out
#   4771 - Kerberos pre-authentication failure
#   4776 - NTLM credential validation
#   4625 - Failed logon
#
# Features:
#   - Read-only
#   - Searches all Domain Controllers
#   - Identifies caller computer
#   - Identifies source workstation/IP
#   - Shows authentication method
#   - Shows logon type
#   - Highlights bad-password evidence
#   - Generates CSV + HTML report
#   - Automatically opens report
#
# Requirements:
#   - ActiveDirectory PowerShell module
#   - Permission to remotely read DC Security logs
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$ReportFolder = "C:\Temp\ADLockoutReports"
$Technician   = $env:USERNAME
$Timestamp    = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

if (!(Test-Path $ReportFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $ReportFolder `
        -Force |
        Out-Null
}


# ============================================================
# VERIFY ACTIVE DIRECTORY MODULE
# ============================================================

if (!(Get-Module -ListAvailable -Name ActiveDirectory)) {

    Write-Host ""
    Write-Host "ActiveDirectory PowerShell module is not installed."
    Write-Host ""
    Write-Host "Install RSAT Active Directory PowerShell tools first."
    Write-Host ""

    return
}

Import-Module ActiveDirectory


# ============================================================
# EVENT DATA FUNCTION
# ============================================================

function Get-EventData {

    param (
        $Event
    )

    $EventData = @{}

    try {

        [xml]$XML = $Event.ToXml()

        foreach ($DataItem in $XML.Event.EventData.Data) {

            if ($DataItem.Name) {

                $EventData[$DataItem.Name] =
                    [string]$DataItem.'#text'
            }
        }
    }

    catch {

        # Leave EventData empty if XML parsing fails
    }

    return $EventData
}


# ============================================================
# LOGON TYPE FUNCTION
# ============================================================

function Get-LogonTypeDescription {

    param (
        [string]$LogonType
    )

    switch ($LogonType) {

        "2"  { return "Interactive" }
        "3"  { return "Network" }
        "4"  { return "Batch" }
        "5"  { return "Service" }
        "7"  { return "Unlock" }
        "8"  { return "Network Cleartext" }
        "9"  { return "New Credentials" }
        "10" { return "Remote Interactive / RDP" }
        "11" { return "Cached Interactive" }

        default {

            if ($LogonType) {

                return "Type $LogonType"
            }

            return "N/A"
        }
    }
}


# ============================================================
# FAILURE DESCRIPTION FUNCTION
# ============================================================

function Get-FailureDescription {

    param (
        [int]$EventID,
        [string]$Status,
        [string]$SubStatus,
        [string]$FailureCode
    )


    if ($EventID -eq 4771) {

        if ($FailureCode -eq "0x18") {

            return "Kerberos pre-authentication failed - likely incorrect or stale password"
        }

        return "Kerberos authentication failure"
    }


    if ($EventID -eq 4776) {

        if ($Status -eq "0xC000006A") {

            return "NTLM authentication failed - bad password"
        }

        if ($Status -eq "0xC0000234") {

            return "NTLM authentication attempted against an already locked account"
        }

        return "NTLM credential validation failure"
    }


    if ($EventID -eq 4625) {

        if (
            $Status -eq "0xC000006A" -or
            $SubStatus -eq "0xC000006A"
        ) {

            return "Failed logon - incorrect password"
        }

        if (
            $Status -eq "0xC0000234" -or
            $SubStatus -eq "0xC0000234"
        ) {

            return "Failed logon - account already locked"
        }

        return "Failed Windows logon"
    }


    return "Authentication event"
}


# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "      AD ACCOUNT LOCKOUT INVESTIGATOR"
Write-Host "=============================================="
Write-Host ""

Write-Host "This tool is READ-ONLY."
Write-Host ""


# ============================================================
# GET USER
# ============================================================

$Username =
    Read-Host "Enter AD username (SamAccountName)"


try {

    $ADUser =
        Get-ADUser `
            -Identity $Username `
            -Properties `
                LockedOut,
                Enabled,
                LastBadPasswordAttempt,
                BadPwdCount `
            -ErrorAction Stop
}

catch {

    Write-Host ""
    Write-Host "AD user could not be found."
    Write-Host ""
    Write-Host $_.Exception.Message

    return
}


# ============================================================
# LOOKBACK WINDOW
# ============================================================

$HoursInput =
    Read-Host "How many hours should be searched? Press Enter for 24"


if ([string]::IsNullOrWhiteSpace($HoursInput)) {

    $HoursBack = 24
}

elseif ($HoursInput -as [int]) {

    $HoursBack = [int]$HoursInput
}

else {

    Write-Host ""
    Write-Host "Invalid value. Using 24 hours."

    $HoursBack = 24
}


$StartTime =
    (Get-Date).AddHours(-$HoursBack)


# ============================================================
# USER SUMMARY
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "                USER STATUS"
Write-Host "=============================================="
Write-Host ""

Write-Host "User:                  $($ADUser.SamAccountName)"
Write-Host "Enabled:               $($ADUser.Enabled)"
Write-Host "Currently Locked Out:  $($ADUser.LockedOut)"
Write-Host "Bad Password Count:    $($ADUser.BadPwdCount)"
Write-Host "Last Bad Password:     $($ADUser.LastBadPasswordAttempt)"
Write-Host ""


# ============================================================
# GET DOMAIN CONTROLLERS
# ============================================================

Write-Host "Discovering Domain Controllers..."
Write-Host ""


try {

    $DomainControllers =
        @(
            Get-ADDomainController `
                -Filter * `
                -ErrorAction Stop
        )
}

catch {

    Write-Host "Unable to discover Domain Controllers."
    Write-Host $_.Exception.Message

    return
}


Write-Host "Domain Controllers Found: $($DomainControllers.Count)"
Write-Host ""


# ============================================================
# FIND EVENT 4740 LOCKOUTS
# ============================================================

$LockoutEvents = @()
$DCFailures    = @()


foreach ($DC in $DomainControllers) {

    Write-Host "Checking lockouts on $($DC.HostName)..."

    try {

        $Events =
            Get-WinEvent `
                -ComputerName $DC.HostName `
                -FilterHashtable @{
                    LogName   = "Security"
                    Id        = 4740
                    StartTime = $StartTime
                } `
                -ErrorAction Stop


        foreach ($Event in $Events) {

            $Data =
                Get-EventData `
                    -Event $Event


            if (
                $Data["TargetUserName"] -ieq
                $ADUser.SamAccountName
            ) {

                $CallerComputer =
                    $Data["CallerComputerName"]


                if ([string]::IsNullOrWhiteSpace($CallerComputer)) {

                    $CallerComputer = "Unknown"
                }


                $LockoutEvents +=
                    [PSCustomObject]@{

                        TimeCreated =
                            $Event.TimeCreated

                        DomainController =
                            $DC.HostName

                        Username =
                            $Data["TargetUserName"]

                        CallerComputer =
                            $CallerComputer

                        RecordID =
                            $Event.RecordId
                    }
            }
        }
    }

    catch {

        Write-Host "Could not read Security log on $($DC.HostName)"

        $DCFailures +=
            [PSCustomObject]@{

                DomainController =
                    $DC.HostName

                Error =
                    $_.Exception.Message
            }
    }
}


$LockoutEvents =
    @(
        $LockoutEvents |
        Sort-Object TimeCreated
    )


# ============================================================
# DISPLAY LOCKOUTS
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "             ACCOUNT LOCKOUT EVENTS"
Write-Host "=============================================="
Write-Host ""


if ($LockoutEvents.Count -gt 0) {

    $LockoutEvents |
        Format-Table `
            TimeCreated,
            DomainController,
            CallerComputer `
            -AutoSize
}

else {

    Write-Host "No Event ID 4740 lockouts were found."
    Write-Host ""
    Write-Host "Possible reasons:"
    Write-Host " - No lockout occurred during the selected period"
    Write-Host " - Security log rolled over"
    Write-Host " - Auditing is not enabled"
    Write-Host " - You do not have permission to read the DC Security log"
}


# ============================================================
# SEARCH RELATED AUTH FAILURES
#
# Search a small window around each 4740 event.
# This avoids pulling enormous Security logs.
# ============================================================

$RelatedEvents = @()


foreach ($Lockout in $LockoutEvents) {

    $WindowStart =
        $Lockout.TimeCreated.AddMinutes(-5)

    $WindowEnd =
        $Lockout.TimeCreated.AddMinutes(1)


    foreach ($DC in $DomainControllers) {

        Write-Host ""
        Write-Host "Correlating authentication failures on $($DC.HostName)..."

        try {

            $AuthEvents =
                Get-WinEvent `
                    -ComputerName $DC.HostName `
                    -FilterHashtable @{
                        LogName   = "Security"
                        Id        = 4625,4771,4776
                        StartTime = $WindowStart
                        EndTime   = $WindowEnd
                    } `
                    -ErrorAction Stop


            foreach ($Event in $AuthEvents) {

                $Data =
                    Get-EventData `
                        -Event $Event


                $EventUsername =
                    $Data["TargetUserName"]


                if (
                    $EventUsername -ine
                    $ADUser.SamAccountName
                ) {

                    continue
                }


                # =============================================
                # DETERMINE SOURCE
                # =============================================

                $SourceComputer = $null
                $SourceIP       = $null


                if ($Event.Id -eq 4771) {

                    $SourceIP =
                        $Data["IpAddress"]

                    $SourceComputer =
                        $SourceIP
                }


                elseif ($Event.Id -eq 4776) {

                    $SourceComputer =
                        $Data["Workstation"]
                }


                elseif ($Event.Id -eq 4625) {

                    $SourceComputer =
                        $Data["WorkstationName"]

                    $SourceIP =
                        $Data["IpAddress"]
                }


                if (
                    [string]::IsNullOrWhiteSpace($SourceComputer) -or
                    $SourceComputer -eq "-"
                ) {

                    $SourceComputer = "Unknown"
                }


                if (
                    [string]::IsNullOrWhiteSpace($SourceIP) -or
                    $SourceIP -eq "-"
                ) {

                    $SourceIP = "N/A"
                }


                # =============================================
                # EVENT TYPE
                # =============================================

                switch ($Event.Id) {

                    4625 {
                        $EventType = "Failed Logon"
                    }

                    4771 {
                        $EventType = "Kerberos Failure"
                    }

                    4776 {
                        $EventType = "NTLM Validation"
                    }
                }


                # =============================================
                # LOGON TYPE
                # =============================================

                $LogonType =
                    Get-LogonTypeDescription `
                        -LogonType $Data["LogonType"]


                # =============================================
                # FAILURE DESCRIPTION
                # =============================================

                $Reason =
                    Get-FailureDescription `
                        -EventID $Event.Id `
                        -Status $Data["Status"] `
                        -SubStatus $Data["SubStatus"] `
                        -FailureCode $Data["FailureCode"]


                # =============================================
                # ADD RESULT
                # =============================================

                $RelatedEvents +=
                    [PSCustomObject]@{

                        TimeCreated =
                            $Event.TimeCreated

                        DomainController =
                            $DC.HostName

                        EventID =
                            $Event.Id

                        EventType =
                            $EventType

                        Username =
                            $EventUsername

                        Source =
                            $SourceComputer

                        IPAddress =
                            $SourceIP

                        LogonType =
                            $LogonType

                        AuthenticationPackage =
                            $Data["AuthenticationPackageName"]

                        Process =
                            $Data["ProcessName"]

                        Status =
                            $Data["Status"]

                        SubStatus =
                            $Data["SubStatus"]

                        FailureCode =
                            $Data["FailureCode"]

                        Reason =
                            $Reason

                        RecordID =
                            $Event.RecordId
                    }
            }
        }

        catch {

            # Security log may not be available from every DC.
        }
    }
}


# ============================================================
# REMOVE DUPLICATES
# ============================================================

$RelatedEvents =
    @(
        $RelatedEvents |
        Sort-Object `
            DomainController,
            RecordID `
            -Unique |
        Sort-Object TimeCreated
    )


# ============================================================
# DISPLAY AUTH FAILURES
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "        RELATED AUTHENTICATION FAILURES"
Write-Host "=============================================="
Write-Host ""


if ($RelatedEvents.Count -gt 0) {

    $RelatedEvents |
        Format-Table `
            TimeCreated,
            EventID,
            EventType,
            Source,
            IPAddress,
            LogonType,
            Reason `
            -AutoSize
}

else {

    Write-Host "No related authentication failures were found."
}


# ============================================================
# BUILD SOURCE EVIDENCE
# ============================================================

$SourceEvidence = @()


foreach ($Lockout in $LockoutEvents) {

    if (
        $Lockout.CallerComputer -and
        $Lockout.CallerComputer -ne "Unknown"
    ) {

        $SourceEvidence +=
            [PSCustomObject]@{

                Source =
                    $Lockout.CallerComputer

                Evidence =
                    "4740 Caller Computer"
            }
    }
}


foreach ($Failure in $RelatedEvents) {

    if (
        $Failure.Source -and
        $Failure.Source -ne "Unknown" -and
        $Failure.Source -ne "N/A"
    ) {

        $SourceEvidence +=
            [PSCustomObject]@{

                Source =
                    $Failure.Source

                Evidence =
                    "$($Failure.EventID) $($Failure.EventType)"
            }
    }
}


$SourceSummary =
    @(
        $SourceEvidence |
        Group-Object Source |
        Sort-Object Count -Descending |
        ForEach-Object {

            [PSCustomObject]@{

                Source =
                    $_.Name

                EvidenceCount =
                    $_.Count

                Evidence =
                    (
                        $_.Group.Evidence |
                        Sort-Object -Unique
                    ) -join ", "
            }
        }
    )


# ============================================================
# DISPLAY LIKELY SOURCES
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "          LIKELY LOCKOUT SOURCES"
Write-Host "=============================================="
Write-Host ""


if ($SourceSummary.Count -gt 0) {

    $SourceSummary |
        Format-Table `
            Source,
            EvidenceCount,
            Evidence `
            -AutoSize


    $TopSource =
        $SourceSummary |
        Select-Object -First 1


    Write-Host ""
    Write-Host "Most frequent source evidence:"
    Write-Host $TopSource.Source
}

else {

    Write-Host "No source system could be identified from available logs."
}


# ============================================================
# INVESTIGATION GUIDANCE
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "          NEXT INVESTIGATION STEPS"
Write-Host "=============================================="
Write-Host ""

Write-Host "Once a likely source computer is identified, check:"
Write-Host ""
Write-Host " - Windows Credential Manager"
Write-Host " - Persistent mapped drives"
Write-Host " - Scheduled Tasks"
Write-Host " - Windows Services running as the user"
Write-Host " - Saved RDP credentials"
Write-Host " - Disconnected RDP sessions"
Write-Host " - VPN clients"
Write-Host " - Applications/services with cached credentials"
Write-Host " - Mobile or legacy authentication clients"
Write-Host ""


# ============================================================
# REPORT PATHS
# ============================================================

$SafeUsername =
    $ADUser.SamAccountName -replace '[\\/:*?"<>|]', '_'


$LockoutCSV =
    "$ReportFolder\$SafeUsername`_Lockouts_$Timestamp.csv"


$AuthCSV =
    "$ReportFolder\$SafeUsername`_AuthenticationFailures_$Timestamp.csv"


$HTMLPath =
    "$ReportFolder\$SafeUsername`_LockoutInvestigation_$Timestamp.html"


# ============================================================
# EXPORT CSV
# ============================================================

$LockoutEvents |
    Export-Csv `
        -Path $LockoutCSV `
        -NoTypeInformation `
        -Encoding UTF8


$RelatedEvents |
    Export-Csv `
        -Path $AuthCSV `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# HTML TABLES
# ============================================================

if ($LockoutEvents.Count -gt 0) {

    $LockoutHTML =
        $LockoutEvents |
        ConvertTo-Html -Fragment
}

else {

    $LockoutHTML =
        "<p>No account lockout events were found.</p>"
}


if ($RelatedEvents.Count -gt 0) {

    $RelatedHTML =
        $RelatedEvents |
        ConvertTo-Html -Fragment
}

else {

    $RelatedHTML =
        "<p>No related authentication failures were found.</p>"
}


if ($SourceSummary.Count -gt 0) {

    $SourceHTML =
        $SourceSummary |
        ConvertTo-Html -Fragment
}

else {

    $SourceHTML =
        "<p>No likely source systems could be identified.</p>"
}


# ============================================================
# HTML REPORT
# ============================================================

$HTML = @"

<html>

<head>

<title>
AD Account Lockout Investigation - $($ADUser.SamAccountName)
</title>

<style>

body {
    font-family: Arial, Helvetica, sans-serif;
    margin: 30px;
}

table {
    border-collapse: collapse;
    width: 100%;
    margin-bottom: 30px;
}

th,
td {
    border: 1px solid #cccccc;
    padding: 8px;
    text-align: left;
}

th {
    background-color: #eeeeee;
}

h2 {
    margin-top: 30px;
}

</style>

</head>

<body>

<h1>
Active Directory Account Lockout Investigation
</h1>

<p>

<strong>User:</strong>
$($ADUser.SamAccountName)

<br>

<strong>Search Window:</strong>
Last $HoursBack hours

<br>

<strong>Generated:</strong>
$(Get-Date)

<br>

<strong>Generated By:</strong>
$Technician

</p>


<h2>
Current Account Status
</h2>

<table>

<tr>
<th>Enabled</th>
<th>Locked Out</th>
<th>Bad Password Count</th>
<th>Last Bad Password Attempt</th>
</tr>

<tr>
<td>$($ADUser.Enabled)</td>
<td>$($ADUser.LockedOut)</td>
<td>$($ADUser.BadPwdCount)</td>
<td>$($ADUser.LastBadPasswordAttempt)</td>
</tr>

</table>


<h2>
Likely Lockout Sources
</h2>

$SourceHTML


<h2>
Account Lockout Events - 4740
</h2>

$LockoutHTML


<h2>
Related Authentication Failures
</h2>

$RelatedHTML


<h2>
Common Follow-Up Checks
</h2>

<ul>

<li>Windows Credential Manager</li>

<li>Persistent mapped network drives</li>

<li>Scheduled Tasks</li>

<li>Windows Services running under the user's account</li>

<li>Saved Remote Desktop credentials</li>

<li>Disconnected RDP sessions</li>

<li>VPN applications</li>

<li>Applications using cached domain credentials</li>

<li>Mobile or legacy authentication clients</li>

</ul>


</body>

</html>

"@


$HTML |
    Out-File `
        -FilePath $HTMLPath `
        -Encoding UTF8


# ============================================================
# COMPLETE
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host "          INVESTIGATION COMPLETE"
Write-Host "=============================================="
Write-Host ""

Write-Host "Lockout Events:"
Write-Host $($LockoutEvents.Count)

Write-Host ""
Write-Host "Related Authentication Failures:"
Write-Host $($RelatedEvents.Count)

Write-Host ""
Write-Host "Lockout CSV:"
Write-Host $LockoutCSV

Write-Host ""
Write-Host "Authentication Failure CSV:"
Write-Host $AuthCSV

Write-Host ""
Write-Host "HTML Report:"
Write-Host $HTMLPath

Write-Host ""
Write-Host "Opening report..."

Start-Process `
    -FilePath $HTMLPath
