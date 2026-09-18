# ============================================================
# Get-ServerHealthReport.ps1
# Windows Server Infrastructure Health Check
# ============================================================

$ComputerName = $env:COMPUTERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFolder = "C:\Temp\ServerHealthReports"
$ReportPath = "$ReportFolder\$ComputerName`_HealthReport_$Timestamp.html"

# ============================================================
# CREATE REPORT DIRECTORY
# ============================================================

if (!(Test-Path $ReportFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $ReportFolder `
        -Force |
        Out-Null
}

Write-Host ""
Write-Host "======================================"
Write-Host "        SERVER HEALTH CHECK"
Write-Host "======================================"
Write-Host ""

Write-Host "Scanning $ComputerName..."
Write-Host ""

try {

    # ========================================================
    # OPERATING SYSTEM
    # ========================================================

    $OS = Get-CimInstance `
        -ClassName Win32_OperatingSystem `
        -ErrorAction Stop

    $Uptime = (Get-Date) - $OS.LastBootUpTime

    $OSInfo = [PSCustomObject]@{
        ComputerName    = $ComputerName
        OperatingSystem = $OS.Caption
        Version         = $OS.Version
        LastBoot        = $OS.LastBootUpTime
        UptimeDays      = [math]::Round(
            $Uptime.TotalDays,
            2
        )
    }

    # ========================================================
    # CPU
    # ========================================================

    $CPU = Get-CimInstance `
        -ClassName Win32_Processor `
        -ErrorAction Stop |
        Select-Object -First 1

    $CPUInfo = [PSCustomObject]@{
        Processor          = $CPU.Name
        Cores              = $CPU.NumberOfCores
        LogicalProcessors  = $CPU.NumberOfLogicalProcessors
        CurrentLoadPercent = $CPU.LoadPercentage
    }

    # ========================================================
    # MEMORY
    # ========================================================

    $TotalMemoryGB = [math]::Round(
        $OS.TotalVisibleMemorySize / 1MB,
        2
    )

    $FreeMemoryGB = [math]::Round(
        $OS.FreePhysicalMemory / 1MB,
        2
    )

    $UsedMemoryGB = [math]::Round(
        $TotalMemoryGB - $FreeMemoryGB,
        2
    )

    $MemoryPercent = [math]::Round(
        ($UsedMemoryGB / $TotalMemoryGB) * 100,
        2
    )

    $MemoryInfo = [PSCustomObject]@{
        TotalMemoryGB     = $TotalMemoryGB
        UsedMemoryGB      = $UsedMemoryGB
        FreeMemoryGB      = $FreeMemoryGB
        MemoryUsedPercent = $MemoryPercent
    }

    # ========================================================
    # DISK INFORMATION
    # ========================================================

    $DiskInfo = Get-CimInstance `
        -ClassName Win32_LogicalDisk `
        -Filter "DriveType=3" |
        ForEach-Object {

            $SizeGB = [math]::Round(
                $_.Size / 1GB,
                2
            )

            $FreeGB = [math]::Round(
                $_.FreeSpace / 1GB,
                2
            )

            if ($_.Size -gt 0) {

                $FreePercent = [math]::Round(
                    ($_.FreeSpace / $_.Size) * 100,
                    2
                )
            }
            else {

                $FreePercent = 0
            }

            [PSCustomObject]@{
                Drive       = $_.DeviceID
                SizeGB      = $SizeGB
                FreeGB      = $FreeGB
                FreePercent = $FreePercent
            }
        }

    # ========================================================
    # NETWORK CONFIGURATION
    # ========================================================

    $NetworkInfo = Get-NetIPConfiguration |
        Where-Object {
            $_.IPv4Address
        } |
        ForEach-Object {

            $IPv4 = $_.IPv4Address.IPAddress -join ", "

            $Gateway = if ($_.IPv4DefaultGateway) {
                $_.IPv4DefaultGateway.NextHop -join ", "
            }
            else {
                "None"
            }

            $DNS = if ($_.DNSServer.ServerAddresses) {
                $_.DNSServer.ServerAddresses -join ", "
            }
            else {
                "None"
            }

            [PSCustomObject]@{
                Interface   = $_.InterfaceAlias
                IPv4Address = $IPv4
                Gateway     = $Gateway
                DNSServers  = $DNS
            }
        }

    # ========================================================
    # CRITICAL SERVICES
    # ========================================================

    $ServicesToCheck = @(
        "NTDS"
        "DNS"
        "Netlogon"
        "W32Time"
    )

    $ServiceInfo = foreach ($Service in $ServicesToCheck) {

        $Result = Get-Service `
            -Name $Service `
            -ErrorAction SilentlyContinue

        if ($Result) {

            [PSCustomObject]@{
                Service     = $Result.Name
                DisplayName = $Result.DisplayName
                Status      = $Result.Status
            }
        }
        else {

            [PSCustomObject]@{
                Service     = $Service
                DisplayName = "Service not installed"
                Status      = "N/A"
            }
        }
    }

    # ========================================================
    # RECENT SYSTEM ERRORS
    # Last 24 Hours
    # ========================================================

    $RecentErrors = Get-WinEvent `
        -FilterHashtable @{
            LogName   = "System"
            Level     = 1,2
            StartTime = (Get-Date).AddHours(-24)
        } `
        -ErrorAction SilentlyContinue |
        Select-Object `
            -First 20 `
            TimeCreated,
            Id,
            ProviderName,
            LevelDisplayName,
            Message

    # ========================================================
    # NETWORK CONNECTIVITY TESTS
    # ========================================================

    $NetworkTests = @()

    $Targets = @(
        "127.0.0.1"
        "8.8.8.8"
    )

    foreach ($Target in $Targets) {

        $Result = Test-NetConnection `
            -ComputerName $Target `
            -WarningAction SilentlyContinue

        $NetworkTests += [PSCustomObject]@{
            Target        = $Target
            PingSucceeded = $Result.PingSucceeded
            RemoteAddress = $Result.RemoteAddress
        }
    }

    # ========================================================
    # DNS RESOLUTION TEST
    # ========================================================

    try {

        $DNSResult = Resolve-DnsName `
            -Name "microsoft.com" `
            -ErrorAction Stop |
            Where-Object {
                $_.IPAddress
            } |
            Select-Object -First 1

        $DNSStatus = [PSCustomObject]@{
            Test   = "microsoft.com"
            Status = "Success"
            Result = $DNSResult.IPAddress
        }
    }
    catch {

        $DNSStatus = [PSCustomObject]@{
            Test   = "microsoft.com"
            Status = "Failed"
            Result = $_.Exception.Message
        }
    }

    # ========================================================
    # CONSOLE SUMMARY
    # ========================================================

    Write-Host "Computer:    $ComputerName"
    Write-Host "Uptime:      $($OSInfo.UptimeDays) days"
    Write-Host "CPU Load:    $($CPUInfo.CurrentLoadPercent)%"
    Write-Host "Memory Used: $MemoryPercent%"

    Write-Host ""
    Write-Host "Disk Status:"

    $DiskInfo |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Critical Services:"

    $ServiceInfo |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Network Tests:"

    $NetworkTests |
        Format-Table -AutoSize

    # ========================================================
    # HTML REPORT
    # ========================================================

    $HTML = @"

<html>

<head>

<title>Server Health Report - $ComputerName</title>

<style>

body {
    font-family: Arial, Helvetica, sans-serif;
    margin: 30px;
}

h1 {
    margin-bottom: 5px;
}

h2 {
    margin-top: 30px;
}

table {
    border-collapse: collapse;
    width: 100%;
    margin-bottom: 25px;
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

</style>

</head>

<body>

<h1>Server Health Report</h1>

<p>
<strong>Server:</strong> $ComputerName
<br>
<strong>Generated:</strong> $(Get-Date)
</p>

<h2>Operating System</h2>

$(
    $OSInfo |
    ConvertTo-Html -Fragment
)

<h2>CPU</h2>

$(
    $CPUInfo |
    ConvertTo-Html -Fragment
)

<h2>Memory</h2>

$(
    $MemoryInfo |
    ConvertTo-Html -Fragment
)

<h2>Disk Usage</h2>

$(
    $DiskInfo |
    ConvertTo-Html -Fragment
)

<h2>Network Configuration</h2>

$(
    $NetworkInfo |
    ConvertTo-Html -Fragment
)

<h2>Critical Services</h2>

$(
    $ServiceInfo |
    ConvertTo-Html -Fragment
)

<h2>Network Connectivity</h2>

$(
    $NetworkTests |
    ConvertTo-Html -Fragment
)

<h2>DNS Resolution</h2>

$(
    $DNSStatus |
    ConvertTo-Html -Fragment
)

<h2>Recent Critical / Error Events</h2>

$(
    $RecentErrors |
    ConvertTo-Html -Fragment
)

</body>

</html>

"@

    # ========================================================
    # WRITE HTML REPORT
    # ========================================================

    $HTML |
        Out-File `
            -FilePath $ReportPath `
            -Encoding UTF8

    # ========================================================
    # COMPLETION
    # ========================================================

    Write-Host ""
    Write-Host "======================================"
    Write-Host "      HEALTH CHECK COMPLETE"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "Report saved to:"
    Write-Host $ReportPath

    # ========================================================
    # AUTOMATICALLY OPEN REPORT
    # ========================================================

    Write-Host ""
    Write-Host "Opening health report..."

    Start-Process `
        -FilePath $ReportPath `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "======================================"
    Write-Host "      SERVER HEALTH CHECK FAILED"
    Write-Host "======================================"
    Write-Host ""

    Write-Host $_.Exception.Message
}
