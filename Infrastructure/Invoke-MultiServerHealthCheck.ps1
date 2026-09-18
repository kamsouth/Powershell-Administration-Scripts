# ============================================================
# Invoke-MultiServerHealthCheck.ps1
# Multi-Server Windows Infrastructure Health Monitoring Tool
# ============================================================

$InventoryPath = "C:\Scripts\Servers.csv"
$ReportFolder = "C:\Temp\InfrastructureReports"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportPath = "$ReportFolder\InfrastructureHealth_$Timestamp.html"


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


# ============================================================
# VALIDATE SERVER INVENTORY
# ============================================================

if (!(Test-Path $InventoryPath)) {

    Write-Host ""
    Write-Host "ERROR: Server inventory was not found."
    Write-Host ""
    Write-Host "Expected location:"
    Write-Host $InventoryPath
    Write-Host ""

    Write-Host "Create Servers.csv using this format:"
    Write-Host ""

    Write-Host "ComputerName,Role"
    Write-Host "DC01,DomainController"
    Write-Host "CLIENT01,Workstation"

    return
}


# ============================================================
# IMPORT SERVER INVENTORY
# ============================================================

$Servers = Import-Csv $InventoryPath

$Results = @()


Write-Host ""
Write-Host "========================================"
Write-Host "     MULTI-SERVER HEALTH MONITOR"
Write-Host "========================================"
Write-Host ""

Write-Host "Inventory:"
Write-Host $InventoryPath
Write-Host ""


# ============================================================
# PROCESS EACH SYSTEM
# ============================================================

foreach ($Server in $Servers) {

    $ComputerName = $Server.ComputerName
    $Role = $Server.Role

    Write-Host "Scanning $ComputerName..."

    # ========================================================
    # TEST BASIC CONNECTIVITY
    # ========================================================

    $Online = Test-Connection `
        -ComputerName $ComputerName `
        -Count 1 `
        -Quiet `
        -ErrorAction SilentlyContinue


    if (!$Online) {

        Write-Host "  Status: OFFLINE"

        $Results += [PSCustomObject]@{
            ComputerName    = $ComputerName
            Role            = $Role
            Status          = "OFFLINE"
            UptimeDays      = "N/A"
            CPUPercent      = "N/A"
            MemoryPercent   = "N/A"
            DiskFreePercent = "N/A"
            ServiceStatus   = "N/A"
        }

        continue
    }


    try {

        # ====================================================
        # REMOTE SYSTEM HEALTH COLLECTION
        # ====================================================

        $HealthData = Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ScriptBlock {

                # ------------------------------------------------
                # Operating System
                # ------------------------------------------------

                $OS = Get-CimInstance `
                    -ClassName Win32_OperatingSystem


                $Uptime =
                    (Get-Date) - $OS.LastBootUpTime


                # ------------------------------------------------
                # CPU
                # ------------------------------------------------

                $CPUData =
                    Get-CimInstance `
                        -ClassName Win32_Processor


                $CPUAverage =
                    ($CPUData |
                        Measure-Object `
                            -Property LoadPercentage `
                            -Average).Average


                if ($null -eq $CPUAverage) {

                    $CPUPercent = "N/A"
                }
                else {

                    $CPUPercent =
                        [math]::Round(
                            $CPUAverage,
                            2
                        )
                }


                # ------------------------------------------------
                # Memory
                # ------------------------------------------------

                $TotalMemoryGB = [math]::Round(
                    $OS.TotalVisibleMemorySize / 1MB,
                    2
                )


                $FreeMemoryGB = [math]::Round(
                    $OS.FreePhysicalMemory / 1MB,
                    2
                )


                $UsedMemoryGB =
                    $TotalMemoryGB - $FreeMemoryGB


                if ($TotalMemoryGB -gt 0) {

                    $MemoryPercent = [math]::Round(
                        ($UsedMemoryGB / $TotalMemoryGB) * 100,
                        2
                    )
                }
                else {

                    $MemoryPercent = 0
                }


                # ------------------------------------------------
                # SYSTEM DRIVE
                # ------------------------------------------------

                $Disk = Get-CimInstance `
                    -ClassName Win32_LogicalDisk `
                    -Filter "DeviceID='C:'"


                if ($Disk.Size -gt 0) {

                    $DiskFreePercent = [math]::Round(
                        ($Disk.FreeSpace / $Disk.Size) * 100,
                        2
                    )
                }
                else {

                    $DiskFreePercent = 0
                }


                # ------------------------------------------------
                # RETURN DATA
                # ------------------------------------------------

                [PSCustomObject]@{
                    UptimeDays = [math]::Round(
                        $Uptime.TotalDays,
                        2
                    )

                    CPUPercent =
                        $CPUPercent

                    MemoryPercent =
                        $MemoryPercent

                    DiskFreePercent =
                        $DiskFreePercent
                }
            }


        # ====================================================
        # ROLE-BASED SERVICE SELECTION
        # ====================================================

        switch ($Role) {

            "DomainController" {

                $ServicesToCheck = @(
                    "NTDS"
                    "DNS"
                    "Netlogon"
                    "W32Time"
                )
            }


            "Workstation" {

                $ServicesToCheck = @(
                    "W32Time"
                    "Dnscache"
                    "LanmanWorkstation"
                )
            }


            "Server" {

                $ServicesToCheck = @(
                    "W32Time"
                    "LanmanServer"
                )
            }


            default {

                $ServicesToCheck = @(
                    "W32Time"
                    "LanmanServer"
                )
            }
        }


        # ====================================================
        # REMOTE SERVICE CHECK
        # ====================================================

        $ServiceData = Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ArgumentList @(,$ServicesToCheck) `
            -ScriptBlock {

                param($Services)

                foreach ($ServiceName in $Services) {

                    $Service = Get-Service `
                        -Name $ServiceName `
                        -ErrorAction SilentlyContinue


                    if ($Service) {

                        [PSCustomObject]@{
                            Name   = $Service.Name
                            Status = $Service.Status.ToString()
                        }
                    }
                    else {

                        [PSCustomObject]@{
                            Name   = $ServiceName
                            Status = "Not Installed"
                        }
                    }
                }
            }


        # ====================================================
        # EVALUATE SERVICE HEALTH
        # ====================================================

        $ProblemServices =
            $ServiceData |
            Where-Object {
                $_.Status -ne "Running"
            }


        if ($ProblemServices) {

            $ServiceStatus =
                "WARNING: " +
                (($ProblemServices |
                    ForEach-Object {
                        "$($_.Name) [$($_.Status)]"
                    }) -join ", ")
        }
        else {

            $ServiceStatus = "Healthy"
        }


        # ====================================================
        # DETERMINE OVERALL SYSTEM HEALTH
        # ====================================================

        $OverallStatus = "HEALTHY"


        if (
            $HealthData.CPUPercent -ne "N/A" -and
            [double]$HealthData.CPUPercent -ge 90
        ) {

            $OverallStatus = "WARNING"
        }


        if (
            [double]$HealthData.MemoryPercent -ge 90
        ) {

            $OverallStatus = "WARNING"
        }


        if (
            [double]$HealthData.DiskFreePercent -le 15
        ) {

            $OverallStatus = "WARNING"
        }


        if (
            $ServiceStatus -ne "Healthy"
        ) {

            $OverallStatus = "WARNING"
        }


        # ====================================================
        # STORE RESULT
        # ====================================================

        $Results += [PSCustomObject]@{
            ComputerName    = $ComputerName
            Role            = $Role
            Status          = $OverallStatus
            UptimeDays      = $HealthData.UptimeDays
            CPUPercent      = $HealthData.CPUPercent
            MemoryPercent   = $HealthData.MemoryPercent
            DiskFreePercent = $HealthData.DiskFreePercent
            ServiceStatus   = $ServiceStatus
        }


        Write-Host "  Status: $OverallStatus"
    }


    catch {

        Write-Host "  Status: ERROR"

        $Results += [PSCustomObject]@{
            ComputerName    = $ComputerName
            Role            = $Role
            Status          = "ERROR"
            UptimeDays      = "N/A"
            CPUPercent      = "N/A"
            MemoryPercent   = "N/A"
            DiskFreePercent = "N/A"
            ServiceStatus   = $_.Exception.Message
        }
    }
}


# ============================================================
# CONSOLE SUMMARY
# ============================================================

Write-Host ""
Write-Host "========================================"
Write-Host "         INFRASTRUCTURE SUMMARY"
Write-Host "========================================"
Write-Host ""


$Results |
    Format-Table `
        ComputerName,
        Role,
        Status,
        UptimeDays,
        CPUPercent,
        MemoryPercent,
        DiskFreePercent `
        -AutoSize


# ============================================================
# SUMMARY COUNTS
# ============================================================

$TotalSystems =
    @($Results).Count


$HealthySystems =
    @(
        $Results |
        Where-Object {
            $_.Status -eq "HEALTHY"
        }
    ).Count


$WarningSystems =
    @(
        $Results |
        Where-Object {
            $_.Status -eq "WARNING"
        }
    ).Count


$OfflineSystems =
    @(
        $Results |
        Where-Object {
            $_.Status -eq "OFFLINE"
        }
    ).Count


$ErrorSystems =
    @(
        $Results |
        Where-Object {
            $_.Status -eq "ERROR"
        }
    ).Count


$Summary = [PSCustomObject]@{
    TotalSystems = $TotalSystems
    Healthy      = $HealthySystems
    Warning      = $WarningSystems
    Offline      = $OfflineSystems
    Errors       = $ErrorSystems
}


# ============================================================
# HTML REPORT
# ============================================================

$HTML = @"

<html>

<head>

<title>
Infrastructure Health Report
</title>

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

</style>

</head>

<body>

<h1>
Infrastructure Health Report
</h1>

<p>
<strong>Generated:</strong>
$(Get-Date)
</p>


<h2>
Environment Summary
</h2>

$(
    $Summary |
    ConvertTo-Html -Fragment
)


<h2>
System Health
</h2>

$(
    $Results |
    ConvertTo-Html -Fragment
)


</body>

</html>

"@


# ============================================================
# SAVE HTML REPORT
# ============================================================

$HTML |
    Out-File `
        -FilePath $ReportPath `
        -Encoding UTF8


# ============================================================
# COMPLETION
# ============================================================

Write-Host ""

Write-Host "========================================"
Write-Host "       HEALTH CHECK COMPLETE"
Write-Host "========================================"

Write-Host ""

Write-Host "Total Systems: $TotalSystems"
Write-Host "Healthy:       $HealthySystems"
Write-Host "Warnings:      $WarningSystems"
Write-Host "Offline:       $OfflineSystems"
Write-Host "Errors:        $ErrorSystems"

Write-Host ""

Write-Host "Report saved to:"
Write-Host $ReportPath


# ============================================================
# AUTOMATICALLY OPEN REPORT
# ============================================================

Write-Host ""
Write-Host "Opening infrastructure report..."

Start-Process `
    -FilePath $ReportPath
