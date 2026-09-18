# ============================================================
# Test-NetworkPath.ps1
# Windows Network Diagnostic & Troubleshooting Tool
# ============================================================

$Target = Read-Host "Enter hostname or IP address"

$PortInput = Read-Host "Enter TCP ports separated by commas (Example: 80,443,3389)"

$Ports = $PortInput -split "," |
    ForEach-Object {
        $_.Trim()
    } |
    Where-Object {
        $_ -match '^\d+$'
    } |
    ForEach-Object {
        [int]$_
    }

$ComputerName = $env:COMPUTERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFolder = "C:\Temp\NetworkReports"

$SafeTarget = $Target -replace '[\\/:*?"<>|]', '_'

$ReportPath =
    "$ReportFolder\$ComputerName`_$SafeTarget`_$Timestamp.html"


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
Write-Host "========================================"
Write-Host "       NETWORK DIAGNOSTIC TOOL"
Write-Host "========================================"
Write-Host ""

Write-Host "Source: $ComputerName"
Write-Host "Target: $Target"
Write-Host ""


# ============================================================
# LOCAL NETWORK CONFIGURATION
# ============================================================

$LocalNetwork = Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4Address
    } |
    ForEach-Object {

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
            Interface =
                $_.InterfaceAlias

            IPv4Address =
                $_.IPv4Address.IPAddress -join ", "

            PrefixLength =
                $_.IPv4Address.PrefixLength -join ", "

            Gateway =
                $Gateway

            DNSServers =
                $DNS
        }
    }


# ============================================================
# DEFAULT GATEWAY TEST
# ============================================================

$DefaultGateway =
    Get-NetRoute `
        -DestinationPrefix "0.0.0.0/0" `
        -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric |
        Select-Object -First 1


if ($DefaultGateway) {

    $GatewayAddress =
        $DefaultGateway.NextHop

    $GatewayReachable =
        Test-Connection `
            -ComputerName $GatewayAddress `
            -Count 2 `
            -Quiet `
            -ErrorAction SilentlyContinue

    $GatewayResult = [PSCustomObject]@{
        Gateway   = $GatewayAddress
        Reachable = $GatewayReachable
        Interface = $DefaultGateway.InterfaceAlias
    }
}
else {

    $GatewayResult = [PSCustomObject]@{
        Gateway   = "Not Found"
        Reachable = $false
        Interface = "N/A"
    }
}


# ============================================================
# DNS RESOLUTION
# ============================================================

try {

    $DNSRecords =
        Resolve-DnsName `
            -Name $Target `
            -ErrorAction Stop |
            Where-Object {
                $_.IPAddress
            }

    $DNSResult =
        $DNSRecords |
        ForEach-Object {

            [PSCustomObject]@{
                Name      = $_.Name
                IPAddress = $_.IPAddress
                Status    = "Resolved"
            }
        }

    $DNSResolved = $true
}
catch {

    $DNSResolved = $false

    $DNSResult = [PSCustomObject]@{
        Name      = $Target
        IPAddress = "N/A"
        Status    = "Resolution Failed"
    }
}


# ============================================================
# PING TEST
# ============================================================

$PingSucceeded =
    Test-Connection `
        -ComputerName $Target `
        -Count 3 `
        -Quiet `
        -ErrorAction SilentlyContinue


$PingResult = [PSCustomObject]@{
    Target        = $Target
    PingSucceeded = $PingSucceeded
}


# ============================================================
# TCP PORT TESTS
# ============================================================

$PortResults = @()


foreach ($Port in $Ports) {

    Write-Host "Testing TCP $Port..."

    try {

        $Connection =
            Test-NetConnection `
                -ComputerName $Target `
                -Port $Port `
                -WarningAction SilentlyContinue

        $PortResults += [PSCustomObject]@{
            Target       = $Target
            Port         = $Port
            TcpSucceeded = $Connection.TcpTestSucceeded
            RemoteIP     = $Connection.RemoteAddress
        }
    }
    catch {

        $PortResults += [PSCustomObject]@{
            Target       = $Target
            Port         = $Port
            TcpSucceeded = $false
            RemoteIP     = "N/A"
        }
    }
}


# ============================================================
# ROUTE INFORMATION
# ============================================================

try {

    $RouteTest =
        Test-NetConnection `
            -ComputerName $Target `
            -DiagnoseRouting `
            -WarningAction SilentlyContinue

    $RouteResult = [PSCustomObject]@{
        RemoteAddress =
            $RouteTest.RemoteAddress

        SelectedSourceAddress =
            $RouteTest.SelectedSourceAddress

        OutgoingInterface =
            $RouteTest.OutgoingInterfaceIndex

        SelectedNetRoute =
            $RouteTest.SelectedNetRoute
    }
}
catch {

    $RouteResult = [PSCustomObject]@{
        RemoteAddress         = "N/A"
        SelectedSourceAddress = "N/A"
        OutgoingInterface     = "N/A"
        SelectedNetRoute      = "Route check failed"
    }
}


# ============================================================
# TRACEROUTE
# ============================================================

try {

    $Trace =
        Test-NetConnection `
            -ComputerName $Target `
            -TraceRoute `
            -WarningAction SilentlyContinue

    $TraceResults = @()

    $Hop = 1

    foreach ($Address in $Trace.TraceRoute) {

        $TraceResults += [PSCustomObject]@{
            Hop       = $Hop
            IPAddress = $Address
        }

        $Hop++
    }
}
catch {

    $TraceResults = [PSCustomObject]@{
        Hop       = "N/A"
        IPAddress = "Traceroute failed"
    }
}


# ============================================================
# BASIC DIAGNOSTIC SUMMARY
# ============================================================

$Issues = @()


if (!$DNSResolved) {

    $Issues += "DNS resolution failed."
}


if (!$GatewayResult.Reachable) {

    $Issues += "Default gateway is not responding."
}


if (!$PingSucceeded) {

    $Issues += "Target did not respond to ICMP ping."
}


$FailedPorts =
    $PortResults |
    Where-Object {
        !$_.TcpSucceeded
    }


foreach ($FailedPort in $FailedPorts) {

    $Issues +=
        "TCP port $($FailedPort.Port) did not respond."
}


if ($Issues.Count -eq 0) {

    $OverallStatus = "No major connectivity issues detected."
}
else {

    $OverallStatus =
        "$($Issues.Count) potential issue(s) detected."
}


# ============================================================
# CONSOLE OUTPUT
# ============================================================

Write-Host ""
Write-Host "========================================"
Write-Host "         DIAGNOSTIC SUMMARY"
Write-Host "========================================"
Write-Host ""

Write-Host "DNS Resolved:       $DNSResolved"
Write-Host "Gateway Reachable:  $($GatewayResult.Reachable)"
Write-Host "Ping Successful:    $PingSucceeded"
Write-Host ""

Write-Host $OverallStatus


if ($Issues) {

    Write-Host ""

    foreach ($Issue in $Issues) {

        Write-Host "- $Issue"
    }
}


# ============================================================
# HTML REPORT
# ============================================================

$IssueObjects = foreach ($Issue in $Issues) {

    [PSCustomObject]@{
        Finding = $Issue
    }
}


if (!$IssueObjects) {

    $IssueObjects = [PSCustomObject]@{
        Finding = "No major connectivity issues detected."
    }
}


$HTML = @"

<html>

<head>

<title>
Network Diagnostic Report - $Target
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

h1 {
    margin-bottom: 5px;
}

h2 {
    margin-top: 30px;
}

</style>

</head>

<body>

<h1>
Network Diagnostic Report
</h1>

<p>
<strong>Source:</strong>
$ComputerName
<br>

<strong>Target:</strong>
$Target
<br>

<strong>Generated:</strong>
$(Get-Date)
</p>


<h2>
Diagnostic Findings
</h2>

$(
    $IssueObjects |
    ConvertTo-Html -Fragment
)


<h2>
Local Network Configuration
</h2>

$(
    $LocalNetwork |
    ConvertTo-Html -Fragment
)


<h2>
Default Gateway
</h2>

$(
    $GatewayResult |
    ConvertTo-Html -Fragment
)


<h2>
DNS Resolution
</h2>

$(
    $DNSResult |
    ConvertTo-Html -Fragment
)


<h2>
Ping Test
</h2>

$(
    $PingResult |
    ConvertTo-Html -Fragment
)


<h2>
TCP Port Tests
</h2>

$(
    $PortResults |
    ConvertTo-Html -Fragment
)


<h2>
Route Information
</h2>

$(
    $RouteResult |
    ConvertTo-Html -Fragment
)


<h2>
Traceroute
</h2>

$(
    $TraceResults |
    ConvertTo-Html -Fragment
)


</body>

</html>

"@


# ============================================================
# SAVE REPORT
# ============================================================

$HTML |
    Out-File `
        -FilePath $ReportPath `
        -Encoding UTF8


Write-Host ""
Write-Host "========================================"
Write-Host "       NETWORK TEST COMPLETE"
Write-Host "========================================"
Write-Host ""

Write-Host "Report saved to:"
Write-Host $ReportPath


# ============================================================
# AUTO OPEN REPORT
# ============================================================

Write-Host ""
Write-Host "Opening network diagnostic report..."

Start-Process `
    -FilePath $ReportPath
