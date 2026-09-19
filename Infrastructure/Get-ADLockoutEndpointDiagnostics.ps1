# ============================================================
# Get-ADLockoutEndpointDiagnostics.ps1
#
# AD Account Lockout Endpoint Diagnostic Tool
#
# Purpose:
#   Investigates a computer identified as a possible source
#   of recurring Active Directory account lockouts.
#
# Checks:
#   - Computer / domain information
#   - Current AD account status (when AD module is available)
#   - Services running as affected user
#   - Scheduled tasks running as affected user
#   - Task Scheduler credential failures
#   - Task Scheduler error-code decoding
#   - Last successful task execution
#   - Password-change correlation
#   - Last bad-password correlation
#   - Interactive / RDP sessions
#   - Failed logons (4625)
#   - Explicit credential usage (4648)
#
# Important:
#   Findings identify evidence and likely stale-credential
#   sources. They do NOT automatically prove which source
#   caused a specific AD lockout. Correlate with DC events
#   such as 4740, 4771 and 4776.
#
# This script is READ-ONLY.
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
# FUNCTIONS
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


function Convert-TaskSchedulerResult {

    param (
        [string]$ResultCode
    )


    if ([string]::IsNullOrWhiteSpace($ResultCode)) {

        return [PSCustomObject]@{

            Decimal =
                ""

            Hex =
                ""

            Meaning =
                ""
        }
    }


    try {

        $NumericCode =
            [Int64]$ResultCode


        $HexCode =
            "0x{0:X8}" -f $NumericCode
    }

    catch {

        return [PSCustomObject]@{

            Decimal =
                $ResultCode

            Hex =
                "Unknown"

            Meaning =
                "Unable to decode result code"
        }
    }


    $Meaning =
        switch ($NumericCode) {

            0 {
                "Success"
            }

            2147943726 {
                "Incorrect username or password"
            }

            2147943785 {
                "Requested logon type has not been granted"
            }

            default {
                "See Windows error documentation"
            }
        }


    return [PSCustomObject]@{

        Decimal =
            $NumericCode

        Hex =
            $HexCode

        Meaning =
            $Meaning
    }
}


# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "      AD LOCKOUT ENDPOINT DIAGNOSTIC TOOL"
Write-Host "=================================================="
Write-Host ""

Write-Host "This tool is READ-ONLY."
Write-Host ""


# ============================================================
# TARGET COMPUTER
# ============================================================

$ComputerName =
    Read-Host "Enter suspected source computer"


if ([string]::IsNullOrWhiteSpace($ComputerName)) {

    Write-Host ""
    Write-Host "No computer name was entered."

    return
}


# ============================================================
# AFFECTED USER
# ============================================================

$Username =
    Read-Host "Enter affected AD username"


if ([string]::IsNullOrWhiteSpace($Username)) {

    Write-Host ""
    Write-Host "No username was entered."

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

    $HoursBack =
        [int]$HoursInput
}

else {

    Write-Host ""
    Write-Host "Invalid value. Using 24 hours."

    $HoursBack = 24
}


$StartTime =
    (Get-Date).AddHours(-$HoursBack)


# ============================================================
# CONNECTIVITY
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "               CONNECTIVITY TEST"
Write-Host "=================================================="
Write-Host ""


try {

    $PingSuccess =
        Test-Connection `
            -ComputerName $ComputerName `
            -Count 2 `
            -Quiet `
            -ErrorAction Stop
}

catch {

    $PingSuccess = $false
}


Write-Host "Ping: $PingSuccess"


try {

    Test-WSMan `
        -ComputerName $ComputerName `
        -ErrorAction Stop |
        Out-Null

    $WinRMSuccess = $true
}

catch {

    $WinRMSuccess = $false
}


Write-Host "PowerShell Remoting: $WinRMSuccess"
Write-Host ""


if (!$WinRMSuccess) {

    Write-Host "PowerShell Remoting is unavailable on:"
    Write-Host $ComputerName
    Write-Host ""

    return
}


# ============================================================
# OPTIONAL ACTIVE DIRECTORY CONTEXT
# ============================================================

$ADUserInfo = $null


if (Get-Module -ListAvailable -Name ActiveDirectory) {

    try {

        Import-Module ActiveDirectory `
            -ErrorAction Stop


        $ADUserInfo =
            Get-ADUser `
                -Identity $Username `
                -Properties `
                    LockedOut,
                    BadPwdCount,
                    LastBadPasswordAttempt,
                    PasswordLastSet `
                -ErrorAction Stop |
            Select-Object `
                SamAccountName,
                LockedOut,
                BadPwdCount,
                LastBadPasswordAttempt,
                PasswordLastSet
    }

    catch {

        $ADUserInfo = $null
    }
}


if ($ADUserInfo) {

    Write-Host "Active Directory context retrieved."
    Write-Host ""

    Write-Host "Locked Out:                $($ADUserInfo.LockedOut)"
    Write-Host "Bad Password Count:        $($ADUserInfo.BadPwdCount)"
    Write-Host "Last Bad Password Attempt: $($ADUserInfo.LastBadPasswordAttempt)"
    Write-Host "Password Last Set:         $($ADUserInfo.PasswordLastSet)"
    Write-Host ""
}

else {

    Write-Host "Active Directory context unavailable."
    Write-Host "Endpoint diagnostics will continue."
    Write-Host ""
}


# ============================================================
# SYSTEM INFORMATION
# ============================================================

Write-Host "Collecting system information..."


try {

    $SystemInfo =
        Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ScriptBlock {

                $OS =
                    Get-CimInstance `
                        -ClassName Win32_OperatingSystem


                $Computer =
                    Get-CimInstance `
                        -ClassName Win32_ComputerSystem


                [PSCustomObject]@{

                    ComputerName =
                        $env:COMPUTERNAME

                    Domain =
                        $Computer.Domain

                    Manufacturer =
                        $Computer.Manufacturer

                    Model =
                        $Computer.Model

                    OS =
                        $OS.Caption

                    OSVersion =
                        $OS.Version

                    LastBoot =
                        $OS.LastBootUpTime

                    CurrentUser =
                        $Computer.UserName
                }
            } |
        Select-Object `
            ComputerName,
            Domain,
            Manufacturer,
            Model,
            OS,
            OSVersion,
            LastBoot,
            CurrentUser
}

catch {

    Write-Host ""
    Write-Host "Unable to retrieve system information."
    Write-Host $_.Exception.Message

    return
}


# ============================================================
# SERVICES USING ACCOUNT
# ============================================================

Write-Host "Checking Windows services..."


try {

    $Services =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $Username `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $TargetUser
                    )


                    Get-CimInstance `
                        -ClassName Win32_Service |
                    Where-Object {

                        $_.StartName -and
                        (
                            $_.StartName -like "*\$TargetUser" -or
                            $_.StartName -like "$TargetUser@*" -or
                            $_.StartName -ieq $TargetUser
                        )
                    } |
                    ForEach-Object {

                        [PSCustomObject]@{

                            Name =
                                $_.Name

                            DisplayName =
                                $_.DisplayName

                            State =
                                $_.State

                            StartMode =
                                $_.StartMode

                            StartName =
                                $_.StartName
                        }
                    }
                } |
            Select-Object `
                Name,
                DisplayName,
                State,
                StartMode,
                StartName
        )
}

catch {

    $Services = @()
}


# ============================================================
# SCHEDULED TASKS USING ACCOUNT
# ============================================================

Write-Host "Checking scheduled tasks..."


try {

    $ScheduledTasks =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $Username `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $TargetUser
                    )


                    Get-ScheduledTask |
                    Where-Object {

                        $_.Principal.UserId -and
                        (
                            $_.Principal.UserId -like "*\$TargetUser" -or
                            $_.Principal.UserId -like "$TargetUser@*" -or
                            $_.Principal.UserId -ieq $TargetUser
                        )
                    } |
                    ForEach-Object {

                        $TaskInfo =
                            Get-ScheduledTaskInfo `
                                -TaskName $_.TaskName `
                                -TaskPath $_.TaskPath `
                                -ErrorAction SilentlyContinue


                        [PSCustomObject]@{

                            TaskName =
                                $_.TaskName

                            TaskPath =
                                $_.TaskPath

                            User =
                                $_.Principal.UserId

                            State =
                                $_.State

                            LogonType =
                                $_.Principal.LogonType

                            LastRunTime =
                                $TaskInfo.LastRunTime

                            NextRunTime =
                                $TaskInfo.NextRunTime

                            LastTaskResult =
                                $TaskInfo.LastTaskResult
                        }
                    }
                } |
            Select-Object `
                TaskName,
                TaskPath,
                User,
                State,
                LogonType,
                LastRunTime,
                NextRunTime,
                LastTaskResult
        )
}

catch {

    $ScheduledTasks = @()
}


# ============================================================
# TASK SCHEDULER OPERATIONAL LOG
# ============================================================

Write-Host "Analyzing Task Scheduler credential events..."


$TaskSchedulerEvents = @()


if ($ScheduledTasks.Count -gt 0) {

    $TaskNames =
        @(
            $ScheduledTasks.TaskName |
            Select-Object -Unique
        )


    try {

        $RawTaskEvents =
            @(
                Invoke-Command `
                    -ComputerName $ComputerName `
                    -ArgumentList $StartTime,$TaskNames `
                    -ErrorAction Stop `
                    -ScriptBlock {

                        param (
                            $WindowStart,
                            $TaskNames
                        )


                        $Events =
                            @(
                                Get-WinEvent `
                                    -FilterHashtable @{
                                        LogName   = "Microsoft-Windows-TaskScheduler/Operational"
                                        Id        = 100,101,102,104,110,200,201
                                        StartTime = $WindowStart
                                    } `
                                    -ErrorAction SilentlyContinue
                            )


                        foreach ($Event in $Events) {

                            $MatchedTask =
                                $TaskNames |
                                Where-Object {

                                    $Event.Message -match
                                    [regex]::Escape($_)
                                } |
                                Select-Object -First 1


                            if (!$MatchedTask) {

                                continue
                            }


                            $EventData = @{}


                            try {

                                [xml]$XML =
                                    $Event.ToXml()


                                foreach (
                                    $DataItem in
                                    $XML.Event.EventData.Data
                                ) {

                                    if ($DataItem.Name) {

                                        $EventData[$DataItem.Name] =
                                            [string]$DataItem.'#text'
                                    }
                                }
                            }

                            catch {

                            }


                            $ResultCode = $null


                            foreach (
                                $PossibleName in
                                @(
                                    "ResultCode",
                                    "ErrorCode",
                                    "ErrorValue"
                                )
                            ) {

                                if (
                                    $EventData.ContainsKey(
                                        $PossibleName
                                    )
                                ) {

                                    $ResultCode =
                                        $EventData[$PossibleName]

                                    break
                                }
                            }


                            if (
                                !$ResultCode -and
                                $Event.Message -match
                                "Error Value:\s*(\d+)"
                            ) {

                                $ResultCode =
                                    $Matches[1]
                            }


                            if (
                                !$ResultCode -and
                                $Event.Message -match
                                "return code\s+(\d+)"
                            ) {

                                $ResultCode =
                                    $Matches[1]
                            }


                            [PSCustomObject]@{

                                TimeCreated =
                                    $Event.TimeCreated

                                EventID =
                                    $Event.Id

                                Level =
                                    $Event.LevelDisplayName

                                TaskName =
                                    $MatchedTask

                                ResultCode =
                                    $ResultCode

                                Message =
                                    $Event.Message
                            }
                        }
                    }
            )


        foreach ($Event in $RawTaskEvents) {

            $Decoded =
                Convert-TaskSchedulerResult `
                    -ResultCode $Event.ResultCode


            $TaskSchedulerEvents +=
                [PSCustomObject]@{

                    TimeCreated =
                        $Event.TimeCreated

                    EventID =
                        $Event.EventID

                    Level =
                        $Event.Level

                    TaskName =
                        $Event.TaskName

                    ResultCode =
                        $Decoded.Decimal

                    ResultHex =
                        $Decoded.Hex

                    Meaning =
                        $Decoded.Meaning
                }
        }


        $TaskSchedulerEvents =
            @(
                $TaskSchedulerEvents |
                Sort-Object TimeCreated
            )
    }

    catch {

        $TaskSchedulerEvents = @()
    }
}


# ============================================================
# BUILD TASK CREDENTIAL SUMMARY
# ============================================================

$TaskCredentialSummary = @()


foreach ($Task in $ScheduledTasks) {

    $EventsForTask =
        @(
            $TaskSchedulerEvents |
            Where-Object {
                $_.TaskName -eq $Task.TaskName
            }
        )


    $SuccessfulEvents =
        @(
            $EventsForTask |
            Where-Object {

                $_.EventID -eq 102 -or
                (
                    $_.EventID -eq 201 -and
                    $_.ResultCode -eq 0
                )
            } |
            Sort-Object TimeCreated
        )


    $CredentialFailures =
        @(
            $EventsForTask |
            Where-Object {

                $_.ResultCode -eq 2147943726 -or
                $_.ResultHex -eq "0x8007052E"
            } |
            Sort-Object TimeCreated
        )


    $LastSuccessfulRun =
        if ($SuccessfulEvents.Count -gt 0) {

            $SuccessfulEvents[-1].TimeCreated
        }

        else {

            $Task.LastRunTime
        }


    $FirstCredentialFailure =
        if ($CredentialFailures.Count -gt 0) {

            $CredentialFailures[0].TimeCreated
        }

        else {

            $null
        }


    $LastCredentialFailure =
        if ($CredentialFailures.Count -gt 0) {

            $CredentialFailures[-1].TimeCreated
        }

        else {

            $null
        }


    $FailuresAfterPasswordChange = 0
    $NearLastBadPasswordAttempt  = $false


    if (
        $ADUserInfo -and
        $ADUserInfo.PasswordLastSet
    ) {

        $FailuresAfterPasswordChange =
            @(
                $CredentialFailures |
                Where-Object {

                    $_.TimeCreated -ge
                    $ADUserInfo.PasswordLastSet
                }
            ).Count
    }


    if (
        $ADUserInfo -and
        $ADUserInfo.LastBadPasswordAttempt
    ) {

        foreach ($Failure in $CredentialFailures) {

            $Difference =
                [math]::Abs(
                    (
                        $Failure.TimeCreated -
                        $ADUserInfo.LastBadPasswordAttempt
                    ).TotalMinutes
                )


            if ($Difference -le 5) {

                $NearLastBadPasswordAttempt = $true

                break
            }
        }
    }


    # ========================================================
    # ASSESSMENT
    # ========================================================

    if (
        $CredentialFailures.Count -gt 0 -and
        $FailuresAfterPasswordChange -gt 0 -and
        $NearLastBadPasswordAttempt
    ) {

        $Assessment =
            "Strong correlation: this scheduled task recorded invalid-credential failures after the user's password change and near the AD bad-password timestamp. Review the stored task credentials. Confirm lockout causality with DC logs."
    }

    elseif (
        $CredentialFailures.Count -gt 0 -and
        $FailuresAfterPasswordChange -gt 0
    ) {

        $Assessment =
            "Stale credential evidence: this task recorded invalid-password failures after the user's password changed. The timestamps do not closely align with AD's last bad-password timestamp, so treat this as a stale-credential risk unless DC logs corroborate it."
    }

    elseif ($CredentialFailures.Count -gt 0) {

        $Assessment =
            "Invalid-credential Task Scheduler failures were detected. Review stored credentials and correlate the timestamps with DC authentication events."
    }

    else {

        $Assessment =
            "No incorrect-password Task Scheduler failures were found during the selected search window."
    }


    $TaskCredentialSummary +=
        [PSCustomObject]@{

            TaskName =
                $Task.TaskName

            User =
                $Task.User

            LogonType =
                $Task.LogonType

            LastSuccessfulRun =
                $LastSuccessfulRun

            CredentialFailures =
                $CredentialFailures.Count

            FirstCredentialFailure =
                $FirstCredentialFailure

            LastCredentialFailure =
                $LastCredentialFailure

            FailuresAfterPasswordChange =
                $FailuresAfterPasswordChange

            NearLastBadPasswordAttempt =
                $NearLastBadPasswordAttempt

            Assessment =
                $Assessment
        }
}


# ============================================================
# INTERACTIVE / RDP SESSIONS
# ============================================================

Write-Host "Checking interactive and RDP sessions..."


try {

    $UserSessions =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $Username `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $TargetUser
                    )


                    quser 2>$null |
                    Where-Object {

                        $_ -match
                        [regex]::Escape($TargetUser)
                    } |
                    ForEach-Object {

                        [PSCustomObject]@{

                            Session =
                                $_.ToString().Trim()
                        }
                    }
                } |
            Select-Object Session
        )
}

catch {

    $UserSessions = @()
}


# ============================================================
# ENDPOINT FAILED LOGON EVENTS - 4625
# ============================================================

Write-Host "Searching endpoint failed authentication events..."


try {

    $FailedLogons =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $Username,$StartTime `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $TargetUser,
                        $WindowStart
                    )


                    $Events =
                        @(
                            Get-WinEvent `
                                -FilterHashtable @{
                                    LogName   = "Security"
                                    Id        = 4625
                                    StartTime = $WindowStart
                                } `
                                -ErrorAction SilentlyContinue
                        )


                    foreach ($Event in $Events) {

                        $Data = @{}


                        try {

                            [xml]$XML =
                                $Event.ToXml()


                            foreach (
                                $DataItem in
                                $XML.Event.EventData.Data
                            ) {

                                if ($DataItem.Name) {

                                    $Data[$DataItem.Name] =
                                        [string]$DataItem.'#text'
                                }
                            }
                        }

                        catch {

                        }


                        if (
                            $Data["TargetUserName"] -ine
                            $TargetUser
                        ) {

                            continue
                        }


                        [PSCustomObject]@{

                            TimeCreated =
                                $Event.TimeCreated

                            Username =
                                $Data["TargetUserName"]

                            LogonType =
                                $Data["LogonType"]

                            Workstation =
                                $Data["WorkstationName"]

                            IPAddress =
                                $Data["IpAddress"]

                            Process =
                                $Data["ProcessName"]

                            AuthenticationPackage =
                                $Data["AuthenticationPackageName"]

                            Status =
                                $Data["Status"]

                            SubStatus =
                                $Data["SubStatus"]

                            RecordID =
                                $Event.RecordId
                        }
                    }
                }
        )


    $FailedLogons =
        @(
            $FailedLogons |
            ForEach-Object {

                [PSCustomObject]@{

                    TimeCreated =
                        $_.TimeCreated

                    Username =
                        $_.Username

                    LogonType =
                        Get-LogonTypeDescription `
                            -LogonType $_.LogonType

                    Workstation =
                        if ($_.Workstation) {
                            $_.Workstation
                        }
                        else {
                            "N/A"
                        }

                    IPAddress =
                        if ($_.IPAddress) {
                            $_.IPAddress
                        }
                        else {
                            "N/A"
                        }

                    Process =
                        $_.Process

                    AuthenticationPackage =
                        $_.AuthenticationPackage

                    Status =
                        $_.Status

                    SubStatus =
                        $_.SubStatus

                    RecordID =
                        $_.RecordID
                }
            } |
            Sort-Object TimeCreated
        )
}

catch {

    $FailedLogons = @()
}


# ============================================================
# EXPLICIT CREDENTIAL USAGE - 4648
# ============================================================

Write-Host "Searching explicit credential events..."


try {

    $ExplicitCredentialEvents =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $Username,$StartTime `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $TargetUser,
                        $WindowStart
                    )


                    $Events =
                        @(
                            Get-WinEvent `
                                -FilterHashtable @{
                                    LogName   = "Security"
                                    Id        = 4648
                                    StartTime = $WindowStart
                                } `
                                -ErrorAction SilentlyContinue
                        )


                    foreach ($Event in $Events) {

                        $Data = @{}


                        try {

                            [xml]$XML =
                                $Event.ToXml()


                            foreach (
                                $DataItem in
                                $XML.Event.EventData.Data
                            ) {

                                if ($DataItem.Name) {

                                    $Data[$DataItem.Name] =
                                        [string]$DataItem.'#text'
                                }
                            }
                        }

                        catch {

                        }


                        if (
                            $Data["TargetUserName"] -ine
                            $TargetUser
                        ) {

                            continue
                        }


                        [PSCustomObject]@{

                            TimeCreated =
                                $Event.TimeCreated

                            Username =
                                $Data["TargetUserName"]

                            SubjectUser =
                                $Data["SubjectUserName"]

                            Process =
                                $Data["ProcessName"]

                            TargetServer =
                                $Data["TargetServerName"]

                            IPAddress =
                                $Data["IpAddress"]

                            RecordID =
                                $Event.RecordId
                        }
                    }
                } |
            Select-Object `
                TimeCreated,
                Username,
                SubjectUser,
                Process,
                TargetServer,
                IPAddress,
                RecordID |
            Sort-Object TimeCreated
        )
}

catch {

    $ExplicitCredentialEvents = @()
}


# ============================================================
# BUILD FINDINGS
# ============================================================

$Findings = @()


# ============================================================
# STRONG TASK CREDENTIAL FINDINGS
# ============================================================

foreach ($TaskFinding in $TaskCredentialSummary) {

    if ($TaskFinding.CredentialFailures -gt 0) {

        if ($TaskFinding.NearLastBadPasswordAttempt) {

            $Category =
                "Scheduled Task Credential - Correlated"
        }

        else {

            $Category =
                "Scheduled Task Credential"
        }


        $Findings +=
            [PSCustomObject]@{

                Category =
                    $Category

                EvidenceCount =
                    $TaskFinding.CredentialFailures

                Finding =
                    "Scheduled task '$($TaskFinding.TaskName)' is configured to run as '$($TaskFinding.User)' and recorded incorrect-password authentication failures."

                RecommendedCheck =
                    "Review stored credentials for the task and correlate failure timestamps with DC Event IDs 4740, 4771 and 4776."
            }
    }
}


# ============================================================
# GENERIC TASK FINDING
# ============================================================

if (
    $ScheduledTasks.Count -gt 0 -and
    $TaskCredentialSummary.CredentialFailures -notcontains 1
) {

    $Findings +=
        [PSCustomObject]@{

            Category =
                "Scheduled Task"

            EvidenceCount =
                $ScheduledTasks.Count

            Finding =
                "One or more scheduled tasks are configured using the affected user's account."

            RecommendedCheck =
                "Review task credentials, run history and password age."
        }
}


# ============================================================
# SERVICE FINDING
# ============================================================

if ($Services.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Category =
                "Windows Service"

            EvidenceCount =
                $Services.Count

            Finding =
                "One or more Windows services are configured to run using the affected user's account."

            RecommendedCheck =
                "Determine whether the service contains an old stored password."
        }
}


# ============================================================
# SESSION FINDING
# ============================================================

if ($UserSessions.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Category =
                "Interactive Session"

            EvidenceCount =
                $UserSessions.Count

            Finding =
                "The affected user has an active or disconnected session on the endpoint."

            RecommendedCheck =
                "Review interactive and disconnected RDP sessions."
        }
}


# ============================================================
# FAILED LOGON FINDING
# ============================================================

if ($FailedLogons.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Category =
                "Failed Authentication"

            EvidenceCount =
                $FailedLogons.Count

            Finding =
                "The endpoint recorded failed authentication attempts for the affected account."

            RecommendedCheck =
                "Compare timestamps and logon types with the domain controller lockout events."
        }
}


# ============================================================
# EXPLICIT CREDENTIAL FINDING
# ============================================================

if ($ExplicitCredentialEvents.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Category =
                "Explicit Credentials"

            EvidenceCount =
                $ExplicitCredentialEvents.Count

            Finding =
                "The affected account appears in explicit credential usage events."

            RecommendedCheck =
                "Review the process and target server associated with Event ID 4648."
        }
}


# ============================================================
# DISPLAY RESULTS
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "             DIAGNOSTIC FINDINGS"
Write-Host "=================================================="
Write-Host ""


if ($Findings.Count -gt 0) {

    $Findings |
        Format-Table `
            Category,
            EvidenceCount,
            Finding `
            -Wrap
}

else {

    Write-Host "No obvious credential source was identified."
}


# ============================================================
# TASK CREDENTIAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "        TASK SCHEDULER CREDENTIAL EVIDENCE"
Write-Host "=================================================="
Write-Host ""


if ($TaskCredentialSummary.Count -gt 0) {

    $TaskCredentialSummary |
        Format-Table `
            TaskName,
            User,
            LastSuccessfulRun,
            CredentialFailures,
            FirstCredentialFailure,
            LastCredentialFailure,
            NearLastBadPasswordAttempt `
            -AutoSize
}

else {

    Write-Host "No scheduled task credential evidence found."
}


# ============================================================
# TASK SCHEDULER EVENT DETAILS
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "          TASK SCHEDULER EVENT DETAILS"
Write-Host "=================================================="
Write-Host ""


if ($TaskSchedulerEvents.Count -gt 0) {

    $TaskSchedulerEvents |
        Format-Table `
            TimeCreated,
            EventID,
            TaskName,
            ResultHex,
            Meaning `
            -AutoSize
}

else {

    Write-Host "No matching Task Scheduler events found."
}


# ============================================================
# SERVICES
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "       SERVICES USING AFFECTED ACCOUNT"
Write-Host "=================================================="
Write-Host ""


if ($Services.Count -gt 0) {

    $Services |
        Format-Table `
            Name,
            State,
            StartMode,
            StartName `
            -AutoSize
}

else {

    Write-Host "No matching Windows services were found."
}


# ============================================================
# SCHEDULED TASKS
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "       SCHEDULED TASKS USING ACCOUNT"
Write-Host "=================================================="
Write-Host ""


if ($ScheduledTasks.Count -gt 0) {

    $ScheduledTasks |
        Format-Table `
            TaskName,
            User,
            State,
            LogonType,
            LastRunTime,
            LastTaskResult `
            -AutoSize
}

else {

    Write-Host "No matching scheduled tasks were found."
}


# ============================================================
# SAFE FILE NAMES
# ============================================================

$SafeComputer =
    $ComputerName -replace '[\\/:*?"<>|]', '_'

$SafeUsername =
    $Username -replace '[\\/:*?"<>|]', '_'


# ============================================================
# OUTPUT PATHS
# ============================================================

$ServiceCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_Services_$Timestamp.csv"


$TaskCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_Tasks_$Timestamp.csv"


$TaskEventCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_TaskSchedulerEvents_$Timestamp.csv"


$TaskSummaryCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_TaskCredentialSummary_$Timestamp.csv"


$FailedLogonCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_FailedLogons_$Timestamp.csv"


$CredentialCSV =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_ExplicitCredentials_$Timestamp.csv"


$HTMLPath =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_EndpointDiagnostics_$Timestamp.html"


$TicketNotePath =
    "$ReportFolder\$SafeUsername`_$SafeComputer`_TicketNote_$Timestamp.txt"


# ============================================================
# EXPORT CSV FILES
# ============================================================

$Services |
    Export-Csv `
        -Path $ServiceCSV `
        -NoTypeInformation `
        -Encoding UTF8


$ScheduledTasks |
    Export-Csv `
        -Path $TaskCSV `
        -NoTypeInformation `
        -Encoding UTF8


$TaskSchedulerEvents |
    Export-Csv `
        -Path $TaskEventCSV `
        -NoTypeInformation `
        -Encoding UTF8


$TaskCredentialSummary |
    Export-Csv `
        -Path $TaskSummaryCSV `
        -NoTypeInformation `
        -Encoding UTF8


$FailedLogons |
    Export-Csv `
        -Path $FailedLogonCSV `
        -NoTypeInformation `
        -Encoding UTF8


$ExplicitCredentialEvents |
    Export-Csv `
        -Path $CredentialCSV `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# HTML FRAGMENTS
# ============================================================

$SystemHTML =
    $SystemInfo |
    ConvertTo-Html -Fragment


if ($ADUserInfo) {

    $ADHTML =
        $ADUserInfo |
        ConvertTo-Html -Fragment
}

else {

    $ADHTML =
        "<p>Active Directory context was unavailable from the system running the diagnostic script.</p>"
}


if ($Findings.Count -gt 0) {

    $FindingsHTML =
        $Findings |
        ConvertTo-Html -Fragment
}

else {

    $FindingsHTML =
        "<p>No obvious credential source was identified.</p>"
}


if ($TaskCredentialSummary.Count -gt 0) {

    $TaskSummaryHTML =
        $TaskCredentialSummary |
        ConvertTo-Html -Fragment
}

else {

    $TaskSummaryHTML =
        "<p>No scheduled task credential evidence found.</p>"
}


if ($TaskSchedulerEvents.Count -gt 0) {

    $TaskEventHTML =
        $TaskSchedulerEvents |
        ConvertTo-Html -Fragment
}

else {

    $TaskEventHTML =
        "<p>No matching Task Scheduler events found.</p>"
}


if ($Services.Count -gt 0) {

    $ServicesHTML =
        $Services |
        ConvertTo-Html -Fragment
}

else {

    $ServicesHTML =
        "<p>No matching Windows services were found.</p>"
}


if ($ScheduledTasks.Count -gt 0) {

    $TasksHTML =
        $ScheduledTasks |
        ConvertTo-Html -Fragment
}

else {

    $TasksHTML =
        "<p>No matching scheduled tasks were found.</p>"
}


if ($UserSessions.Count -gt 0) {

    $SessionsHTML =
        $UserSessions |
        ConvertTo-Html -Fragment
}

else {

    $SessionsHTML =
        "<p>No matching logged-on sessions were returned.</p>"
}


if ($FailedLogons.Count -gt 0) {

    $FailedLogonsHTML =
        $FailedLogons |
        ConvertTo-Html -Fragment
}

else {

    $FailedLogonsHTML =
        "<p>No matching failed authentication events were found.</p>"
}


if ($ExplicitCredentialEvents.Count -gt 0) {

    $ExplicitCredentialsHTML =
        $ExplicitCredentialEvents |
        ConvertTo-Html -Fragment
}

else {

    $ExplicitCredentialsHTML =
        "<p>No matching explicit credential events were found.</p>"
}


# ============================================================
# HTML REPORT
# ============================================================

$HTML = @"

<html>

<head>

<title>
AD Lockout Endpoint Diagnostics - $Username
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
    vertical-align: top;
}

th {
    background-color: #eeeeee;
}

h1 {
    margin-bottom: 5px;
}

h2 {
    margin-top: 35px;
}

.notice {
    padding: 12px;
    border: 1px solid #cccccc;
    margin-top: 20px;
}

</style>

</head>


<body>


<h1>
AD Lockout Endpoint Diagnostic Report
</h1>


<p>

<strong>Affected User:</strong>
$Username

<br>

<strong>Computer:</strong>
$ComputerName

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
System Information
</h2>

$SystemHTML


<h2>
Active Directory Account Context
</h2>

$ADHTML


<h2>
Diagnostic Findings
</h2>

$FindingsHTML


<h2>
Task Scheduler Credential Analysis
</h2>

$TaskSummaryHTML


<h2>
Task Scheduler Event Evidence
</h2>

$TaskEventHTML


<h2>
Windows Services Using Account
</h2>

$ServicesHTML


<h2>
Scheduled Tasks Using Account
</h2>

$TasksHTML


<h2>
Interactive / RDP Sessions
</h2>

$SessionsHTML


<h2>
Failed Authentication Events
</h2>

$FailedLogonsHTML


<h2>
Explicit Credential Events
</h2>

$ExplicitCredentialsHTML


<h2>
Additional Follow-Up Checks
</h2>

<ul>

<li>Windows Credential Manager</li>

<li>Persistent mapped network drives</li>

<li>Scheduled tasks with stored passwords</li>

<li>Windows services running under the user account</li>

<li>VPN clients</li>

<li>Disconnected RDP sessions</li>

<li>Legacy applications storing domain credentials</li>

<li>Office applications using stale credentials</li>

<li>Mobile devices</li>

<li>Other endpoints where the user is signed in</li>

</ul>


<div class="notice">

<strong>Correlation Warning:</strong>

A task, service, session, or authentication event does not by itself
prove that it caused the Active Directory lockout.

Confirm the source by comparing timestamps with domain controller
Event IDs 4740, 4771 and 4776.

</div>


</body>

</html>

"@


$HTML |
    Out-File `
        -FilePath $HTMLPath `
        -Encoding UTF8


# ============================================================
# GENERATE TICKET NOTE
# ============================================================

$FindingSummary =
    if ($Findings.Count -gt 0) {

        (
            $Findings |
            ForEach-Object {

                "$($_.Category): $($_.Finding)"
            }
        ) -join "`r`n"
    }

    else {

        "No obvious credential source was identified."
    }


$TicketNote = @"

AD Account Lockout Endpoint Investigation

Affected User:
$Username

Investigated Endpoint:
$ComputerName

Search Window:
Last $HoursBack hours

Findings:
$FindingSummary

Matching Scheduled Tasks:
$($ScheduledTasks.Count)

Task Scheduler Credential Failures:
$(
    @(
        $TaskSchedulerEvents |
        Where-Object {
            $_.ResultHex -eq "0x8007052E"
        }
    ).Count
)

Matching Services:
$($Services.Count)

Matching Failed Logons:
$($FailedLogons.Count)

Explicit Credential Events:
$($ExplicitCredentialEvents.Count)

Technician:
$Technician

Completed:
$(Get-Date)

Important:
Endpoint evidence should be correlated with domain controller Event IDs
4740, 4771 and 4776 before identifying a definitive lockout source.

HTML Report:
$HTMLPath

"@


$TicketNote |
    Out-File `
        -FilePath $TicketNotePath `
        -Encoding UTF8


# ============================================================
# COMPLETE
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "            DIAGNOSTIC COMPLETE"
Write-Host "=================================================="
Write-Host ""

Write-Host "Findings:                   $($Findings.Count)"
Write-Host "Matching Services:          $($Services.Count)"
Write-Host "Matching Scheduled Tasks:   $($ScheduledTasks.Count)"
Write-Host "Task Scheduler Events:      $($TaskSchedulerEvents.Count)"
Write-Host "Failed Endpoint Logons:     $($FailedLogons.Count)"
Write-Host "Explicit Credential Events: $($ExplicitCredentialEvents.Count)"

Write-Host ""
Write-Host "HTML Report:"
Write-Host $HTMLPath

Write-Host ""
Write-Host "Ticket Note:"
Write-Host $TicketNotePath

Write-Host ""
Write-Host "Opening diagnostic report..."


Start-Process `
    -FilePath $HTMLPath
