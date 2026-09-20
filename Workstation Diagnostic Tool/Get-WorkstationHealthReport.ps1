# ============================================================
# Get-WorkstationHealthReport.ps1
#
# Service Desk Workstation Health Diagnostic Tool
#
# Checks:
#   - Connectivity / WinRM
#   - Logged-on user
#   - OS / hardware information
#   - Current CPU utilization
#   - Live per-process CPU utilization
#   - Memory utilization
#   - Page file utilization
#   - Disk capacity
#   - System uptime
#   - Process count
#   - Explorer responsiveness
#   - Windows Update activity
#   - Pending reboot
#   - Critical Windows services
#   - Recent System errors
#   - Recent Application errors
#   - Unexpected shutdowns
#   - Hyper-V / virtualization errors
#   - True application crash events
#
# Output:
#   - Overall workstation health assessment
#   - Console findings
#   - CSV evidence
#   - HTML report
#
# This script is READ-ONLY.
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$ReportFolder = "C:\Temp\WorkstationDiagnostics"
$Technician   = $env:USERNAME
$Timestamp    = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$EventLookbackHours = 24
$CPUSampleSeconds   = 3


if (!(Test-Path $ReportFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $ReportFolder `
        -Force |
        Out-Null
}


# ============================================================
# HEADER
# ============================================================

Clear-Host

Write-Host ""
Write-Host "=================================================="
Write-Host "        WORKSTATION HEALTH DIAGNOSTIC TOOL"
Write-Host "=================================================="
Write-Host ""

Write-Host "This tool is READ-ONLY."
Write-Host ""


# ============================================================
# GET COMPUTER
# ============================================================

$ComputerName =
    Read-Host "Enter workstation name"


if ([string]::IsNullOrWhiteSpace($ComputerName)) {

    Write-Host ""
    Write-Host "No workstation name was entered."

    return
}


# ============================================================
# CONNECTIVITY TEST
# ============================================================

Write-Host ""
Write-Host "Testing connectivity..."
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

    Write-Host "Unable to continue remote diagnostics."
    Write-Host "PowerShell Remoting is unavailable on $ComputerName."

    return
}


# ============================================================
# COLLECT SYSTEM INFORMATION
# ============================================================

Write-Host "Collecting workstation information..."


try {

    $SystemData =
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


                $Processor =
                    Get-CimInstance `
                        -ClassName Win32_Processor |
                    Select-Object -First 1


                $Processors =
                    @(
                        Get-CimInstance `
                            -ClassName Win32_Processor
                    )


                $CurrentCPU =
                    (
                        $Processors |
                        Measure-Object `
                            -Property LoadPercentage `
                            -Average
                    ).Average


                $LastBoot =
                    $OS.LastBootUpTime


                $Uptime =
                    (Get-Date) - $LastBoot


                $TotalMemoryGB =
                    [math]::Round(
                        $Computer.TotalPhysicalMemory / 1GB,
                        2
                    )


                $FreeMemoryGB =
                    [math]::Round(
                        $OS.FreePhysicalMemory / 1MB,
                        2
                    )


                $UsedMemoryGB =
                    [math]::Round(
                        $TotalMemoryGB - $FreeMemoryGB,
                        2
                    )


                $MemoryPercent =
                    if ($TotalMemoryGB -gt 0) {

                        [math]::Round(
                            ($UsedMemoryGB / $TotalMemoryGB) * 100,
                            1
                        )
                    }

                    else {

                        0
                    }


                # =============================================
                # PAGE FILE
                # =============================================

                $PageFiles =
                    @(
                        Get-CimInstance `
                            -ClassName Win32_PageFileUsage `
                            -ErrorAction SilentlyContinue
                    )


                $PageFileAllocatedMB =
                    (
                        $PageFiles |
                        Measure-Object `
                            -Property AllocatedBaseSize `
                            -Sum
                    ).Sum


                $PageFileUsedMB =
                    (
                        $PageFiles |
                        Measure-Object `
                            -Property CurrentUsage `
                            -Sum
                    ).Sum


                if ($null -eq $PageFileAllocatedMB) {

                    $PageFileAllocatedMB = 0
                }


                if ($null -eq $PageFileUsedMB) {

                    $PageFileUsedMB = 0
                }


                $PageFilePercent =
                    if ($PageFileAllocatedMB -gt 0) {

                        [math]::Round(
                            (
                                $PageFileUsedMB /
                                $PageFileAllocatedMB
                            ) * 100,
                            1
                        )
                    }

                    else {

                        0
                    }


                # =============================================
                # EXPLORER
                # =============================================

                $Explorer =
                    Get-Process `
                        -Name explorer `
                        -ErrorAction SilentlyContinue |
                    Select-Object -First 1


                if ($Explorer) {

                    try {

                        $ExplorerResponding =
                            $Explorer.Responding
                    }

                    catch {

                        $ExplorerResponding =
                            "Unknown"
                    }
                }

                else {

                    $ExplorerResponding =
                        "Not Running"
                }


                # =============================================
                # WINDOWS UPDATE ACTIVITY
                # =============================================

                $TiWorker =
                    Get-Process `
                        -Name TiWorker `
                        -ErrorAction SilentlyContinue


                $TrustedInstaller =
                    Get-Process `
                        -Name TrustedInstaller `
                        -ErrorAction SilentlyContinue


                $UpdateActivity =
                    (
                        $null -ne $TiWorker -or
                        $null -ne $TrustedInstaller
                    )


                # =============================================
                # PROCESS COUNT
                # =============================================

                $ProcessCount =
                    @(
                        Get-Process
                    ).Count


                [PSCustomObject]@{

                    ComputerName =
                        $env:COMPUTERNAME

                    Domain =
                        $Computer.Domain

                    LoggedOnUser =
                        $Computer.UserName

                    Manufacturer =
                        $Computer.Manufacturer

                    Model =
                        $Computer.Model

                    OperatingSystem =
                        $OS.Caption

                    OSVersion =
                        $OS.Version

                    Architecture =
                        $OS.OSArchitecture

                    CPU =
                        $Processor.Name

                    LogicalProcessors =
                        $Computer.NumberOfLogicalProcessors

                    CPUUsagePercent =
                        [math]::Round(
                            $CurrentCPU,
                            1
                        )

                    TotalMemoryGB =
                        $TotalMemoryGB

                    UsedMemoryGB =
                        $UsedMemoryGB

                    FreeMemoryGB =
                        $FreeMemoryGB

                    MemoryUsagePercent =
                        $MemoryPercent

                    PageFileAllocatedMB =
                        $PageFileAllocatedMB

                    PageFileUsedMB =
                        $PageFileUsedMB

                    PageFileUsagePercent =
                        $PageFilePercent

                    ProcessCount =
                        $ProcessCount

                    ExplorerResponding =
                        $ExplorerResponding

                    WindowsUpdateActivity =
                        $UpdateActivity

                    LastBoot =
                        $LastBoot

                    UptimeDays =
                        [math]::Round(
                            $Uptime.TotalDays,
                            1
                        )
                }
            } |
        Select-Object `
            ComputerName,
            Domain,
            LoggedOnUser,
            Manufacturer,
            Model,
            OperatingSystem,
            OSVersion,
            Architecture,
            CPU,
            LogicalProcessors,
            CPUUsagePercent,
            TotalMemoryGB,
            UsedMemoryGB,
            FreeMemoryGB,
            MemoryUsagePercent,
            PageFileAllocatedMB,
            PageFileUsedMB,
            PageFileUsagePercent,
            ProcessCount,
            ExplorerResponding,
            WindowsUpdateActivity,
            LastBoot,
            UptimeDays
}

catch {

    Write-Host ""
    Write-Host "Unable to retrieve workstation information."
    Write-Host $_.Exception.Message

    return
}


# ============================================================
# DISK INFORMATION
# ============================================================

Write-Host "Checking disk capacity..."


try {

    $DiskData =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ErrorAction Stop `
                -ScriptBlock {

                    Get-CimInstance `
                        -ClassName Win32_LogicalDisk `
                        -Filter "DriveType=3" |
                    ForEach-Object {

                        $SizeGB =
                            [math]::Round(
                                $_.Size / 1GB,
                                2
                            )


                        $FreeGB =
                            [math]::Round(
                                $_.FreeSpace / 1GB,
                                2
                            )


                        $FreePercent =
                            if ($_.Size -gt 0) {

                                [math]::Round(
                                    (
                                        $_.FreeSpace /
                                        $_.Size
                                    ) * 100,
                                    1
                                )
                            }

                            else {

                                0
                            }


                        [PSCustomObject]@{

                            Drive =
                                $_.DeviceID

                            SizeGB =
                                $SizeGB

                            FreeGB =
                                $FreeGB

                            FreePercent =
                                $FreePercent
                        }
                    }
                } |
            Select-Object `
                Drive,
                SizeGB,
                FreeGB,
                FreePercent
        )
}

catch {

    $DiskData = @()
}


# ============================================================
# LIVE PROCESS CPU SAMPLE
# ============================================================

Write-Host "Sampling live process CPU utilization..."


try {

    $LiveCPU =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $CPUSampleSeconds `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $SampleSeconds
                    )


                    $LogicalProcessors =
                        (
                            Get-CimInstance `
                                -ClassName Win32_ComputerSystem
                        ).NumberOfLogicalProcessors


                    if (!$LogicalProcessors) {

                        $LogicalProcessors = 1
                    }


                    $Snapshot1 = @{}


                    Get-Process `
                        -ErrorAction SilentlyContinue |
                    Where-Object {

                        $_.CPU -ne $null
                    } |
                    ForEach-Object {

                        $Snapshot1[$_.Id] =
                            [PSCustomObject]@{

                                Name =
                                    $_.ProcessName

                                CPU =
                                    $_.CPU
                            }
                    }


                    Start-Sleep `
                        -Seconds $SampleSeconds


                    $Results =
                        @()


                    Get-Process `
                        -ErrorAction SilentlyContinue |
                    Where-Object {

                        $_.CPU -ne $null
                    } |
                    ForEach-Object {

                        if (
                            $Snapshot1.ContainsKey(
                                $_.Id
                            )
                        ) {

                            $OldCPU =
                                $Snapshot1[$_.Id].CPU


                            $CPUChange =
                                $_.CPU - $OldCPU


                            if ($CPUChange -ge 0) {

                                $CPUPercent =
                                    (
                                        $CPUChange /
                                        $SampleSeconds /
                                        $LogicalProcessors
                                    ) * 100


                                $Results +=
                                    [PSCustomObject]@{

                                        Process =
                                            $_.ProcessName

                                        PID =
                                            $_.Id

                                        CurrentCPUPercent =
                                            [math]::Round(
                                                $CPUPercent,
                                                1
                                            )

                                        MemoryMB =
                                            [math]::Round(
                                                $_.WorkingSet64 / 1MB,
                                                2
                                            )
                                    }
                            }
                        }
                    }


                    $Results |
                        Sort-Object `
                            CurrentCPUPercent `
                            -Descending |
                        Select-Object -First 10
                } |
            Select-Object `
                Process,
                PID,
                CurrentCPUPercent,
                MemoryMB
        )
}

catch {

    $LiveCPU = @()
}


# ============================================================
# TOP MEMORY PROCESSES
# ============================================================

Write-Host "Checking top memory consumers..."


try {

    $TopMemory =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ErrorAction Stop `
                -ScriptBlock {

                    Get-Process `
                        -ErrorAction SilentlyContinue |
                    Sort-Object `
                        WorkingSet64 `
                        -Descending |
                    Select-Object -First 10 |
                    ForEach-Object {

                        [PSCustomObject]@{

                            Process =
                                $_.ProcessName

                            PID =
                                $_.Id

                            MemoryMB =
                                [math]::Round(
                                    $_.WorkingSet64 / 1MB,
                                    2
                                )

                            CPUTimeSeconds =
                                if ($_.CPU) {

                                    [math]::Round(
                                        $_.CPU,
                                        2
                                    )
                                }

                                else {

                                    0
                                }
                        }
                    }
                } |
            Select-Object `
                Process,
                PID,
                MemoryMB,
                CPUTimeSeconds
        )
}

catch {

    $TopMemory = @()
}


# ============================================================
# PENDING REBOOT
# ============================================================

Write-Host "Checking pending reboot state..."


try {

    $PendingReboot =
        Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ScriptBlock {

                $CBS =
                    Test-Path `
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"


                $WU =
                    Test-Path `
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"


                $PendingFileRename =
                    Get-ItemProperty `
                        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                        -Name PendingFileRenameOperations `
                        -ErrorAction SilentlyContinue


                $RenamePending =
                    $null -ne
                    $PendingFileRename.PendingFileRenameOperations


                [PSCustomObject]@{

                    ComponentBasedServicing =
                        $CBS

                    WindowsUpdate =
                        $WU

                    PendingFileRename =
                        $RenamePending

                    RebootRequired =
                        (
                            $CBS -or
                            $WU -or
                            $RenamePending
                        )
                }
            } |
        Select-Object `
            ComponentBasedServicing,
            WindowsUpdate,
            PendingFileRename,
            RebootRequired
}

catch {

    $PendingReboot =
        [PSCustomObject]@{

            ComponentBasedServicing = "Unknown"
            WindowsUpdate           = "Unknown"
            PendingFileRename       = "Unknown"
            RebootRequired          = "Unknown"
        }
}


# ============================================================
# CRITICAL SERVICES
# ============================================================

Write-Host "Checking important Windows services..."


$ServiceNames = @(

    "AudioSrv",
    "AudioEndpointBuilder",
    "Dnscache",
    "Dhcp",
    "LanmanWorkstation",
    "Winmgmt",
    "wuauserv"
)


try {

    $ServiceData =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList (,$ServiceNames) `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $Services
                    )


                    foreach ($ServiceName in $Services) {

                        $Service =
                            Get-Service `
                                -Name $ServiceName `
                                -ErrorAction SilentlyContinue


                        if ($Service) {

                            [PSCustomObject]@{

                                Name =
                                    $Service.Name

                                DisplayName =
                                    $Service.DisplayName

                                Status =
                                    $Service.Status

                                StartType =
                                    $Service.StartType
                            }
                        }
                    }
                } |
            Select-Object `
                Name,
                DisplayName,
                Status,
                StartType
        )
}

catch {

    $ServiceData = @()
}


# ============================================================
# EVENT LOG COLLECTION
# ============================================================

Write-Host "Analyzing recent event logs..."


$EventStartTime =
    (Get-Date).AddHours(
        -$EventLookbackHours
    )


# ============================================================
# SYSTEM ERRORS
# ============================================================

try {

    $SystemErrors =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $EventStartTime `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $StartTime
                    )


                    Get-WinEvent `
                        -FilterHashtable @{
                            LogName   = "System"
                            Level     = 2
                            StartTime = $StartTime
                        } `
                        -ErrorAction SilentlyContinue |
                    Select-Object -First 50 |
                    ForEach-Object {

                        [PSCustomObject]@{

                            TimeCreated =
                                $_.TimeCreated

                            EventID =
                                $_.Id

                            Provider =
                                $_.ProviderName

                            Message =
                                (
                                    $_.Message `
                                        -replace "`r", " " `
                                        -replace "`n", " "
                                )
                        }
                    }
                } |
            Select-Object `
                TimeCreated,
                EventID,
                Provider,
                Message
        )
}

catch {

    $SystemErrors = @()
}


# ============================================================
# APPLICATION ERRORS
# ============================================================

try {

    $ApplicationErrors =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $EventStartTime `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $StartTime
                    )


                    Get-WinEvent `
                        -FilterHashtable @{
                            LogName   = "Application"
                            Level     = 2
                            StartTime = $StartTime
                        } `
                        -ErrorAction SilentlyContinue |
                    Select-Object -First 50 |
                    ForEach-Object {

                        [PSCustomObject]@{

                            TimeCreated =
                                $_.TimeCreated

                            EventID =
                                $_.Id

                            Provider =
                                $_.ProviderName

                            Message =
                                (
                                    $_.Message `
                                        -replace "`r", " " `
                                        -replace "`n", " "
                                )
                        }
                    }
                } |
            Select-Object `
                TimeCreated,
                EventID,
                Provider,
                Message
        )
}

catch {

    $ApplicationErrors = @()
}


# ============================================================
# TRUE APPLICATION CRASH EVENTS
#
# IMPORTANT:
# Event IDs 1000 and 1001 are used by multiple providers.
#
# We only consider:
#
#   Event 1000 + Provider "Application Error"
#   Event 1001 + Provider "Windows Error Reporting"
#
# This prevents events such as Microsoft-Windows-LoadPerf
# 1000/1001 from being falsely classified as app crashes.
# ============================================================

try {

    $ApplicationCrashes =
        @(
            Invoke-Command `
                -ComputerName $ComputerName `
                -ArgumentList $EventStartTime `
                -ErrorAction Stop `
                -ScriptBlock {

                    param (
                        $StartTime
                    )


                    Get-WinEvent `
                        -FilterHashtable @{
                            LogName   = "Application"
                            StartTime = $StartTime
                        } `
                        -ErrorAction SilentlyContinue |
                    Where-Object {

                        (
                            $_.Id -eq 1000 -and
                            $_.ProviderName -eq "Application Error"
                        ) -or

                        (
                            $_.Id -eq 1001 -and
                            $_.ProviderName -eq "Windows Error Reporting"
                        )
                    } |
                    Select-Object -First 30 |
                    ForEach-Object {

                        [PSCustomObject]@{

                            TimeCreated =
                                $_.TimeCreated

                            EventID =
                                $_.Id

                            Provider =
                                $_.ProviderName

                            Message =
                                (
                                    $_.Message `
                                        -replace "`r", " " `
                                        -replace "`n", " "
                                )
                        }
                    }
                } |
            Select-Object `
                TimeCreated,
                EventID,
                Provider,
                Message
        )
}

catch {

    $ApplicationCrashes = @()
}


# ============================================================
# EVENT PATTERN ANALYSIS
# ============================================================

$UnexpectedShutdowns =
    @(
        $SystemErrors |
        Where-Object {
            $_.EventID -eq 6008
        }
    )


$HyperVFailures =
    @(
        $SystemErrors |
        Where-Object {

            $_.Provider -eq
            "Microsoft-Windows-Hyper-V-Hypervisor" -and
            $_.EventID -eq 41
        }
    )


$VBSErrors =
    @(
        $SystemErrors |
        Where-Object {

            $_.Provider -eq
            "Microsoft-Windows-Kernel-Boot" -and
            $_.EventID -eq 124
        }
    )


# ============================================================
# DETECT VIRTUAL MACHINE
# ============================================================

$IsVirtualMachine = $false


if (
    $SystemData.Manufacturer -match
    "innotek|VMware|QEMU|Xen|Microsoft Corporation"
) {

    $IsVirtualMachine = $true
}


if (
    $SystemData.Model -match
    "VirtualBox|Virtual Machine|VMware|KVM"
) {

    $IsVirtualMachine = $true
}


# ============================================================
# BUILD FINDINGS
# ============================================================

$Findings = @()


# ============================================================
# CPU
# ============================================================

if ($SystemData.CPUUsagePercent -ge 97) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "CRITICAL"

            Category =
                "CPU"

            Finding =
                "Current CPU utilization is $($SystemData.CPUUsagePercent)%."

            Recommendation =
                "Review live high-CPU processes immediately."
        }
}

elseif ($SystemData.CPUUsagePercent -ge 85) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "CPU"

            Finding =
                "Current CPU utilization is elevated at $($SystemData.CPUUsagePercent)%."

            Recommendation =
                "Review the Live CPU Processes section."
        }
}


# ============================================================
# MEMORY
# ============================================================

if ($SystemData.MemoryUsagePercent -ge 95) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "CRITICAL"

            Category =
                "Memory"

            Finding =
                "Physical memory usage is $($SystemData.MemoryUsagePercent)%."

            Recommendation =
                "Review high-memory processes and available RAM."
        }
}

elseif ($SystemData.MemoryUsagePercent -ge 85) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "Memory"

            Finding =
                "Physical memory usage is elevated at $($SystemData.MemoryUsagePercent)%."

            Recommendation =
                "Review the Top Memory Processes section."
        }
}


# ============================================================
# PAGE FILE
# ============================================================

if ($SystemData.PageFileUsagePercent -ge 80) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "Page File"

            Finding =
                "Page file usage is $($SystemData.PageFileUsagePercent)%."

            Recommendation =
                "Review memory pressure and high-memory applications."
        }
}


# ============================================================
# DISK SPACE
# ============================================================

foreach ($Disk in $DiskData) {

    if (
        $Disk.FreePercent -lt 5 -or
        $Disk.FreeGB -lt 5
    ) {

        $Findings +=
            [PSCustomObject]@{

                Severity =
                    "CRITICAL"

                Category =
                    "Disk Space"

                Finding =
                    "$($Disk.Drive) has only $($Disk.FreeGB) GB free ($($Disk.FreePercent)%)."

                Recommendation =
                    "Free disk space before continuing troubleshooting."
            }
    }

    elseif (
        $Disk.FreePercent -lt 10 -or
        $Disk.FreeGB -lt 10
    ) {

        $Findings +=
            [PSCustomObject]@{

                Severity =
                    "WARNING"

                Category =
                    "Disk Space"

                Finding =
                    "$($Disk.Drive) has $($Disk.FreeGB) GB free ($($Disk.FreePercent)%)."

                Recommendation =
                    "Low disk space may contribute to poor workstation performance."
            }
    }
}


# ============================================================
# UPTIME
# ============================================================

if ($SystemData.UptimeDays -ge 14) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "INFO"

            Category =
                "Uptime"

            Finding =
                "The workstation has been running for $($SystemData.UptimeDays) days."

            Recommendation =
                "Consider restarting the workstation during troubleshooting."
        }
}


# ============================================================
# PENDING REBOOT
# ============================================================

if ($PendingReboot.RebootRequired -eq $true) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "INFO"

            Category =
                "Pending Reboot"

            Finding =
                "Windows reports that a reboot is pending."

            Recommendation =
                "Restart the workstation when appropriate."
        }
}


# ============================================================
# EXPLORER RESPONSIVENESS
# ============================================================

if ($SystemData.ExplorerResponding -eq $false) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "Windows Explorer"

            Finding =
                "Windows Explorer is currently not responding."

            Recommendation =
                "Investigate Explorer and shell-related resource usage."
        }
}


# ============================================================
# WINDOWS UPDATE ACTIVITY
# ============================================================

if ($SystemData.WindowsUpdateActivity -eq $true) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "INFO"

            Category =
                "Windows Servicing"

            Finding =
                "Windows servicing activity is currently detected."

            Recommendation =
                "TiWorker or TrustedInstaller activity may temporarily increase CPU or disk usage."
        }
}


# ============================================================
# SERVICES
# ============================================================

foreach ($Service in $ServiceData) {

    if (
        $Service.Status -ne "Running" -and
        $Service.StartType -eq "Automatic"
    ) {

        $Findings +=
            [PSCustomObject]@{

                Severity =
                    "WARNING"

                Category =
                    "Windows Service"

                Finding =
                    "$($Service.DisplayName) is $($Service.Status)."

                Recommendation =
                    "Review the service before attempting remediation."
            }
    }
}


# ============================================================
# UNEXPECTED SHUTDOWNS
# ============================================================

if ($UnexpectedShutdowns.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "Unexpected Shutdown"

            Finding =
                "$($UnexpectedShutdowns.Count) unexpected shutdown event(s) were detected during the last $EventLookbackHours hours."

            Recommendation =
                "Review shutdown timing and determine whether the device lost power, crashed, or was forcibly restarted."
        }
}


# ============================================================
# HYPER-V FAILURES
# ============================================================

if ($HyperVFailures.Count -gt 0) {

    if ($IsVirtualMachine) {

        $Severity =
            "INFO"

        $Recommendation =
            "The system appears to be virtualized. Hyper-V launch failures may occur when nested virtualization is unavailable."
    }

    else {

        $Severity =
            "WARNING"

        $Recommendation =
            "Review virtualization configuration, firmware virtualization support, and Hyper-V settings."
    }


    $Findings +=
        [PSCustomObject]@{

            Severity =
                $Severity

            Category =
                "Virtualization"

            Finding =
                "$($HyperVFailures.Count) Hyper-V hypervisor launch failure(s) were detected."

            Recommendation =
                $Recommendation
        }
}


# ============================================================
# VBS ERRORS
# ============================================================

if ($VBSErrors.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "INFO"

            Category =
                "Virtualization-Based Security"

            Finding =
                "$($VBSErrors.Count) VBS policy/virtualization startup error(s) were detected."

            Recommendation =
                "Review only if virtualization or security-isolation features are expected on this system."
        }
}


# ============================================================
# TRUE APPLICATION CRASHES
# ============================================================

if ($ApplicationCrashes.Count -gt 0) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "WARNING"

            Category =
                "Application Crash"

            Finding =
                "$($ApplicationCrashes.Count) application crash or Windows Error Reporting event(s) were detected."

            Recommendation =
                "Review the Application Crash Events section for recurring applications, installers, servicing failures, or faulting modules."
        }
}


# ============================================================
# GENERIC SYSTEM EVENT INFORMATION
# ============================================================

if (
    $SystemErrors.Count -gt 0 -and
    $UnexpectedShutdowns.Count -eq 0 -and
    $HyperVFailures.Count -eq 0 -and
    $VBSErrors.Count -eq 0
) {

    $Findings +=
        [PSCustomObject]@{

            Severity =
                "INFO"

            Category =
                "System Event Log"

            Finding =
                "$($SystemErrors.Count) System error event(s) were detected."

            Recommendation =
                "Review recurring providers and event IDs."
        }
}


# ============================================================
# OVERALL STATUS
# ============================================================

$CriticalCount =
    @(
        $Findings |
        Where-Object {
            $_.Severity -eq "CRITICAL"
        }
    ).Count


$WarningCount =
    @(
        $Findings |
        Where-Object {
            $_.Severity -eq "WARNING"
        }
    ).Count


$InfoCount =
    @(
        $Findings |
        Where-Object {
            $_.Severity -eq "INFO"
        }
    ).Count


if ($CriticalCount -gt 0) {

    $OverallStatus =
        "CRITICAL"
}

elseif ($WarningCount -gt 0) {

    $OverallStatus =
        "ATTENTION NEEDED"
}

else {

    $OverallStatus =
        "HEALTHY"
}


# ============================================================
# RESOURCE ASSESSMENT
# ============================================================

$ResourceAssessment = @()


if ($SystemData.CPUUsagePercent -lt 85) {

    $ResourceAssessment +=
        "No current CPU pressure detected."
}


if ($SystemData.MemoryUsagePercent -lt 85) {

    $ResourceAssessment +=
        "No current physical memory pressure detected."
}


$LowDiskDetected =
    @(
        $DiskData |
        Where-Object {

            $_.FreePercent -lt 10 -or
            $_.FreeGB -lt 10
        }
    ).Count -gt 0


if (!$LowDiskDetected) {

    $ResourceAssessment +=
        "No low disk-space condition detected."
}


$ResourceAssessmentText =
    $ResourceAssessment -join " "


# ============================================================
# CONSOLE SUMMARY
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "        WORKSTATION HEALTH ASSESSMENT"
Write-Host "=================================================="
Write-Host ""

Write-Host "Overall Status: $OverallStatus"
Write-Host ""

Write-Host "Computer:       $($SystemData.ComputerName)"
Write-Host "User:           $($SystemData.LoggedOnUser)"
Write-Host "CPU:            $($SystemData.CPUUsagePercent)%"
Write-Host "Memory:         $($SystemData.MemoryUsagePercent)%"
Write-Host "Page File:      $($SystemData.PageFileUsagePercent)%"
Write-Host "Uptime:         $($SystemData.UptimeDays) days"
Write-Host "Processes:      $($SystemData.ProcessCount)"
Write-Host "Explorer:       $($SystemData.ExplorerResponding)"
Write-Host "Pending Reboot: $($PendingReboot.RebootRequired)"
Write-Host ""

Write-Host $ResourceAssessmentText
Write-Host ""


if ($Findings.Count -gt 0) {

    $Findings |
        Format-Table `
            Severity,
            Category,
            Finding `
            -Wrap
}

else {

    Write-Host "No significant workstation issues detected."
}


# ============================================================
# OUTPUT PATHS
# ============================================================

$SafeComputer =
    $ComputerName -replace '[\\/:*?"<>|]', '_'


$DiskCSV =
    "$ReportFolder\$SafeComputer`_Disk_$Timestamp.csv"


$LiveCPUCSV =
    "$ReportFolder\$SafeComputer`_LiveCPU_$Timestamp.csv"


$MemoryCSV =
    "$ReportFolder\$SafeComputer`_TopMemory_$Timestamp.csv"


$SystemEventCSV =
    "$ReportFolder\$SafeComputer`_SystemErrors_$Timestamp.csv"


$ApplicationEventCSV =
    "$ReportFolder\$SafeComputer`_ApplicationErrors_$Timestamp.csv"


$CrashCSV =
    "$ReportFolder\$SafeComputer`_ApplicationCrashes_$Timestamp.csv"


$HTMLPath =
    "$ReportFolder\$SafeComputer`_WorkstationHealth_$Timestamp.html"


# ============================================================
# EXPORT CSV
# ============================================================

$DiskData |
    Export-Csv `
        -Path $DiskCSV `
        -NoTypeInformation `
        -Encoding UTF8


$LiveCPU |
    Export-Csv `
        -Path $LiveCPUCSV `
        -NoTypeInformation `
        -Encoding UTF8


$TopMemory |
    Export-Csv `
        -Path $MemoryCSV `
        -NoTypeInformation `
        -Encoding UTF8


$SystemErrors |
    Export-Csv `
        -Path $SystemEventCSV `
        -NoTypeInformation `
        -Encoding UTF8


$ApplicationErrors |
    Export-Csv `
        -Path $ApplicationEventCSV `
        -NoTypeInformation `
        -Encoding UTF8


$ApplicationCrashes |
    Export-Csv `
        -Path $CrashCSV `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# HTML FRAGMENTS
# ============================================================

$Assessment =
    [PSCustomObject]@{

        OverallStatus =
            $OverallStatus

        CPU =
            "$($SystemData.CPUUsagePercent)%"

        Memory =
            "$($SystemData.MemoryUsagePercent)%"

        PageFile =
            "$($SystemData.PageFileUsagePercent)%"

        UptimeDays =
            $SystemData.UptimeDays

        ProcessCount =
            $SystemData.ProcessCount

        ExplorerResponding =
            $SystemData.ExplorerResponding

        PendingReboot =
            $PendingReboot.RebootRequired

        CriticalFindings =
            $CriticalCount

        WarningFindings =
            $WarningCount

        InformationFindings =
            $InfoCount
    }


$AssessmentHTML =
    $Assessment |
    ConvertTo-Html -Fragment


$FindingsHTML =
    if ($Findings.Count -gt 0) {

        $Findings |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No significant workstation issues detected.</p>"
    }


$SystemHTML =
    $SystemData |
    ConvertTo-Html -Fragment


$DiskHTML =
    if ($DiskData.Count -gt 0) {

        $DiskData |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No disk information returned.</p>"
    }


$LiveCPUHTML =
    if ($LiveCPU.Count -gt 0) {

        $LiveCPU |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No live CPU process information returned.</p>"
    }


$MemoryHTML =
    if ($TopMemory.Count -gt 0) {

        $TopMemory |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No memory process information returned.</p>"
    }


$ServiceHTML =
    if ($ServiceData.Count -gt 0) {

        $ServiceData |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No service information returned.</p>"
    }


$SystemErrorHTML =
    if ($SystemErrors.Count -gt 0) {

        $SystemErrors |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No System errors were found.</p>"
    }


$ApplicationErrorHTML =
    if ($ApplicationErrors.Count -gt 0) {

        $ApplicationErrors |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No Application errors were found.</p>"
    }


$ApplicationCrashHTML =
    if ($ApplicationCrashes.Count -gt 0) {

        $ApplicationCrashes |
            ConvertTo-Html -Fragment
    }

    else {

        "<p>No true application crash or Windows Error Reporting events were found.</p>"
    }


# ============================================================
# HTML REPORT
# ============================================================

$HTML = @"

<html>

<head>

<title>
Workstation Health Report - $ComputerName
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

.summary {
    border: 1px solid #cccccc;
    padding: 15px;
    margin-bottom: 25px;
}

</style>

</head>


<body>


<h1>
Workstation Health Diagnostic Report
</h1>


<p>

<strong>Computer:</strong>
$ComputerName

<br>

<strong>Generated:</strong>
$(Get-Date)

<br>

<strong>Technician:</strong>
$Technician

</p>


<div class="summary">

<strong>Overall Status:</strong>
$OverallStatus

<br><br>

$ResourceAssessmentText

</div>


<h2>
Workstation Health Assessment
</h2>

$AssessmentHTML


<h2>
Diagnostic Findings
</h2>

$FindingsHTML


<h2>
System Information
</h2>

$SystemHTML


<h2>
Disk Capacity
</h2>

$DiskHTML


<h2>
Live CPU Processes
</h2>

<p>
CPU values below are sampled current utilization rather than lifetime process CPU time.
</p>

$LiveCPUHTML


<h2>
Top Memory Processes
</h2>

$MemoryHTML


<h2>
Pending Reboot
</h2>

$(
    $PendingReboot |
    ConvertTo-Html -Fragment
)


<h2>
Critical Windows Services
</h2>

$ServiceHTML


<h2>
Application Crash / Windows Error Reporting Events
</h2>

<p>
This section filters Event IDs 1000 and 1001 by provider to avoid
incorrectly classifying unrelated events such as LoadPerf events as
application crashes.
</p>

$ApplicationCrashHTML


<h2>
Recent System Errors
</h2>

$SystemErrorHTML


<h2>
Recent Application Errors
</h2>

$ApplicationErrorHTML


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
Write-Host "=================================================="
Write-Host "             DIAGNOSTIC COMPLETE"
Write-Host "=================================================="
Write-Host ""

Write-Host "Overall Status: $OverallStatus"
Write-Host "Critical:       $CriticalCount"
Write-Host "Warnings:       $WarningCount"
Write-Host "Information:    $InfoCount"

Write-Host ""
Write-Host "HTML Report:"
Write-Host $HTMLPath

Write-Host ""
Write-Host "Opening report..."


Start-Process `
    -FilePath $HTMLPath
