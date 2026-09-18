# ============================================================
# Test-ADInfrastructureHealth.ps1
# Active Directory Infrastructure Health Diagnostic Tool
# ============================================================

Import-Module ActiveDirectory

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFolder = "C:\Temp\ADInfrastructureReports"

$ReportPath =
    "$ReportFolder\ADInfrastructureHealth_$Timestamp.html"


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
Write-Host "=========================================="
Write-Host "   ACTIVE DIRECTORY INFRASTRUCTURE CHECK"
Write-Host "=========================================="
Write-Host ""


try {

    # ========================================================
    # DOMAIN INFORMATION
    # ========================================================

    $Domain = Get-ADDomain `
        -ErrorAction Stop

    $Forest = Get-ADForest `
        -ErrorAction Stop


    $DomainInfo = [PSCustomObject]@{

        DomainName =
            $Domain.DNSRoot

        NetBIOSName =
            $Domain.NetBIOSName

        Forest =
            $Forest.Name

        DomainMode =
            $Domain.DomainMode

        ForestMode =
            $Forest.ForestMode

        PDCEmulator =
            $Domain.PDCEmulator

        RIDMaster =
            $Domain.RIDMaster

        InfrastructureMaster =
            $Domain.InfrastructureMaster

        SchemaMaster =
            $Forest.SchemaMaster

        DomainNamingMaster =
            $Forest.DomainNamingMaster
    }


    Write-Host "Domain: $($Domain.DNSRoot)"
    Write-Host "Forest: $($Forest.Name)"
    Write-Host ""


    # ========================================================
    # DISCOVER DOMAIN CONTROLLERS
    # ========================================================

    $DomainControllers =
        Get-ADDomainController `
            -Filter * |
        Sort-Object HostName


    Write-Host "Domain Controllers Found:"
    Write-Host ""

    foreach ($DC in $DomainControllers) {

        Write-Host "  $($DC.HostName)"
    }


    # ========================================================
    # RESULT ARRAYS
    # ========================================================

    $DCResults = @()

    $PortResults = @()

    $ServiceResults = @()

    $ShareResults = @()

    $DCDiagResults = @()

    $TimeResults = @()


    # ========================================================
    # REQUIRED AD PORTS
    # ========================================================

    $ADPorts = @{

        53   = "DNS"

        88   = "Kerberos"

        135  = "RPC Endpoint Mapper"

        389  = "LDAP"

        445  = "SMB"

        464  = "Kerberos Password Change"

        636  = "LDAPS"

        3268 = "Global Catalog"

        3269 = "Global Catalog SSL"
    }


    # ========================================================
    # CHECK EACH DOMAIN CONTROLLER
    # ========================================================

    foreach ($DC in $DomainControllers) {

        $DCName = $DC.HostName


        Write-Host ""
        Write-Host "------------------------------------------"
        Write-Host "Checking $DCName"
        Write-Host "------------------------------------------"


        # ====================================================
        # BASIC REACHABILITY
        # ====================================================

        $PingResult =
            Test-Connection `
                -ComputerName $DCName `
                -Count 2 `
                -Quiet `
                -ErrorAction SilentlyContinue


        # ====================================================
        # DNS RESOLUTION
        # ====================================================

        try {

            $DNSLookup =
                Resolve-DnsName `
                    -Name $DCName `
                    -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress
                } |
                Select-Object -First 1


            $DNSStatus = "Success"

            $ResolvedAddress =
                $DNSLookup.IPAddress
        }
        catch {

            $DNSStatus = "Failed"

            $ResolvedAddress = "N/A"
        }


        $DCResults += [PSCustomObject]@{

            DomainController =
                $DCName

            Site =
                $DC.Site

            IPv4Address =
                $DC.IPv4Address

            GlobalCatalog =
                $DC.IsGlobalCatalog

            ReadOnly =
                $DC.IsReadOnly

            Ping =
                $PingResult

            DNSResolution =
                $DNSStatus

            ResolvedAddress =
                $ResolvedAddress
        }


        # ====================================================
        # TCP PORT CHECKS
        # ====================================================

        foreach ($Port in $ADPorts.Keys) {

            Write-Host `
                "Testing $DCName TCP $Port ($($ADPorts[$Port]))..."

            $Connection =
                Test-NetConnection `
                    -ComputerName $DCName `
                    -Port $Port `
                    -WarningAction SilentlyContinue


            $PortResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Port =
                    $Port

                Service =
                    $ADPorts[$Port]

                Reachable =
                    $Connection.TcpTestSucceeded
            }
        }


        # ====================================================
        # WINDOWS SERVICE CHECKS
        # ====================================================

        $ServicesToCheck = @(

            "NTDS"

            "DNS"

            "Netlogon"

            "KDC"

            "W32Time"

            "DFSR"
        )


        try {

            $RemoteServices =
                Invoke-Command `
                    -ComputerName $DCName `
                    -ArgumentList @(,$ServicesToCheck) `
                    -ErrorAction Stop `
                    -ScriptBlock {

                        param($Services)

                        foreach ($ServiceName in $Services) {

                            $Service =
                                Get-Service `
                                    -Name $ServiceName `
                                    -ErrorAction SilentlyContinue


                            if ($Service) {

                                [PSCustomObject]@{

                                    Service =
                                        $Service.Name

                                    DisplayName =
                                        $Service.DisplayName

                                    Status =
                                        $Service.Status.ToString()
                                }
                            }
                            else {

                                [PSCustomObject]@{

                                    Service =
                                        $ServiceName

                                    DisplayName =
                                        "Not Installed"

                                    Status =
                                        "N/A"
                                }
                            }
                        }
                    }


            foreach ($Service in $RemoteServices) {

                $ServiceResults += [PSCustomObject]@{

                    DomainController =
                        $DCName

                    Service =
                        $Service.Service

                    DisplayName =
                        $Service.DisplayName

                    Status =
                        $Service.Status
                }
            }
        }
        catch {

            $ServiceResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Service =
                    "Remote Service Check"

                DisplayName =
                    "PowerShell Remoting"

                Status =
                    "ERROR: $($_.Exception.Message)"
            }
        }


        # ====================================================
        # SYSVOL / NETLOGON SHARES
        # ====================================================

        try {

            $Shares =
                Invoke-Command `
                    -ComputerName $DCName `
                    -ErrorAction Stop `
                    -ScriptBlock {

                        Get-SmbShare `
                            -Name "SYSVOL","NETLOGON" `
                            -ErrorAction SilentlyContinue |
                        Select-Object Name,Path
                    }


            foreach ($Share in $Shares) {

                $ShareResults += [PSCustomObject]@{

                    DomainController =
                        $DCName

                    Share =
                        $Share.Name

                    Path =
                        $Share.Path

                    Status =
                        "Present"
                }
            }


            foreach ($ExpectedShare in @(
                "SYSVOL",
                "NETLOGON"
            )) {

                if (
                    $ExpectedShare -notin
                    $Shares.Name
                ) {

                    $ShareResults += [PSCustomObject]@{

                        DomainController =
                            $DCName

                        Share =
                            $ExpectedShare

                        Path =
                            "N/A"

                        Status =
                            "MISSING"
                    }
                }
            }
        }
        catch {

            $ShareResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Share =
                    "SYSVOL / NETLOGON"

                Path =
                    "N/A"

                Status =
                    "ERROR: $($_.Exception.Message)"
            }
        }


        # ====================================================
        # WINDOWS TIME CHECK
        # ====================================================

        try {

            $TimeOutput =
                w32tm `
                    /query `
                    /computer:$DCName `
                    /status 2>&1


            $TimeResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Status =
                    "Query Successful"

                Details =
                    ($TimeOutput -join " ")
            }
        }
        catch {

            $TimeResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Status =
                    "Failed"

                Details =
                    $_.Exception.Message
            }
        }


        # ====================================================
        # DCDIAG
        # ====================================================

        Write-Host ""
        Write-Host "Running DCDIAG against $DCName..."


        if (
            Get-Command dcdiag `
                -ErrorAction SilentlyContinue
        ) {

            $DCDiagOutput =
                dcdiag `
                    /s:$DCName `
                    /test:Advertising `
                    /test:Services `
                    /test:SysVolCheck `
                    /test:NetLogons `
                    /test:DNS 2>&1


            $FailedTests =
                $DCDiagOutput |
                Select-String `
                    -Pattern "failed test"


            if ($FailedTests) {

                $DiagStatus =
                    "WARNING"
            }
            else {

                $DiagStatus =
                    "PASS"
            }


            $DCDiagResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Status =
                    $DiagStatus

                FailedTests =
                    if ($FailedTests) {

                        (
                            $FailedTests.Line `
                            -join " | "
                        )
                    }
                    else {

                        "None detected"
                    }
            }
        }
        else {

            $DCDiagResults += [PSCustomObject]@{

                DomainController =
                    $DCName

                Status =
                    "NOT AVAILABLE"

                FailedTests =
                    "dcdiag.exe was not found."
            }
        }
    }


    # ========================================================
    # REPADMIN REPLICATION SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host "Running replication diagnostics..."
    Write-Host ""


    if (
        Get-Command repadmin `
            -ErrorAction SilentlyContinue
    ) {

        $ReplicationSummary =
            repadmin /replsummary 2>&1


        $ReplicationDetails =
            repadmin /showrepl * /csv 2>$null


        if ($ReplicationDetails) {

            try {

                $ReplicationData =
                    $ReplicationDetails |
                    ConvertFrom-Csv
            }
            catch {

                $ReplicationData = $null
            }
        }
        else {

            $ReplicationData = $null
        }
    }
    else {

        $ReplicationSummary =
            "repadmin.exe was not found."

        $ReplicationData = $null
    }


    # ========================================================
    # OVERALL FINDINGS
    # ========================================================

    $Findings = @()


    $FailedPorts =
        $PortResults |
        Where-Object {
            $_.Reachable -eq $false
        }


    foreach ($Failure in $FailedPorts) {

        $Findings +=
            "$($Failure.DomainController): TCP $($Failure.Port) ($($Failure.Service)) failed."
    }


    $StoppedServices =
        $ServiceResults |
        Where-Object {

            $_.Status -ne "Running" -and
            $_.Status -ne "N/A"
        }


    foreach ($Failure in $StoppedServices) {

        $Findings +=
            "$($Failure.DomainController): $($Failure.Service) status is $($Failure.Status)."
    }


    $MissingShares =
        $ShareResults |
        Where-Object {
            $_.Status -ne "Present"
        }


    foreach ($Failure in $MissingShares) {

        $Findings +=
            "$($Failure.DomainController): $($Failure.Share) status is $($Failure.Status)."
    }


    $FailedDiag =
        $DCDiagResults |
        Where-Object {
            $_.Status -eq "WARNING"
        }


    foreach ($Failure in $FailedDiag) {

        $Findings +=
            "$($Failure.DomainController): DCDIAG reported a failed test."
    }


    if ($Findings.Count -eq 0) {

        $OverallHealth =
            "No major Active Directory infrastructure issues detected."

        $FindingObjects =
            [PSCustomObject]@{

                Finding =
                    $OverallHealth
            }
    }
    else {

        $OverallHealth =
            "$($Findings.Count) potential issue(s) detected."

        $FindingObjects =
            foreach ($Finding in $Findings) {

                [PSCustomObject]@{

                    Finding =
                        $Finding
                }
            }
    }


    # ========================================================
    # CONSOLE SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "           AD HEALTH SUMMARY"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host $OverallHealth

    Write-Host ""

    $DCResults |
        Format-Table `
            DomainController,
            Site,
            IPv4Address,
            Ping,
            DNSResolution `
            -AutoSize


    Write-Host ""

    Write-Host "DCDIAG Results:"

    $DCDiagResults |
        Format-Table `
            DomainController,
            Status `
            -AutoSize


    # ========================================================
    # REPADMIN OUTPUT FOR HTML
    # ========================================================

    $ReplicationSummaryHTML =
        "<pre>" +
        (
            (
                $ReplicationSummary |
                Out-String
            ) `
            -replace "&","&amp;" `
            -replace "<","&lt;" `
            -replace ">","&gt;"
        ) +
        "</pre>"


    # ========================================================
    # HTML REPORT
    # ========================================================

    $HTML = @"

<html>

<head>

<title>
Active Directory Infrastructure Health Report
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
    margin-top: 30px;
}

pre {
    padding: 15px;
    border: 1px solid #cccccc;
    overflow-x: auto;
}

</style>

</head>

<body>

<h1>
Active Directory Infrastructure Health Report
</h1>

<p>
<strong>Domain:</strong>
$($Domain.DNSRoot)
<br>

<strong>Forest:</strong>
$($Forest.Name)
<br>

<strong>Generated:</strong>
$(Get-Date)
</p>


<h2>
Overall Findings
</h2>

$(
    $FindingObjects |
    ConvertTo-Html -Fragment
)


<h2>
Domain Information
</h2>

$(
    $DomainInfo |
    ConvertTo-Html -Fragment
)


<h2>
Domain Controllers
</h2>

$(
    $DCResults |
    ConvertTo-Html -Fragment
)


<h2>
Active Directory TCP Port Tests
</h2>

$(
    $PortResults |
    Sort-Object DomainController,Port |
    ConvertTo-Html -Fragment
)


<h2>
Critical AD Services
</h2>

$(
    $ServiceResults |
    ConvertTo-Html -Fragment
)


<h2>
SYSVOL and NETLOGON Shares
</h2>

$(
    $ShareResults |
    ConvertTo-Html -Fragment
)


<h2>
Domain Controller Diagnostics
</h2>

$(
    $DCDiagResults |
    ConvertTo-Html -Fragment
)


<h2>
Windows Time Status
</h2>

$(
    $TimeResults |
    ConvertTo-Html -Fragment
)


<h2>
Replication Summary
</h2>

$ReplicationSummaryHTML


<h2>
Replication Details
</h2>

$(
    if ($ReplicationData) {

        $ReplicationData |
        ConvertTo-Html -Fragment
    }
    else {

        "<p>No replication detail records were returned.</p>"
    }
)

</body>

</html>

"@


    # ========================================================
    # SAVE REPORT
    # ========================================================

    $HTML |
        Out-File `
            -FilePath $ReportPath `
            -Encoding UTF8


    Write-Host ""
    Write-Host "=========================================="
    Write-Host "       AD HEALTH CHECK COMPLETE"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Report saved to:"
    Write-Host $ReportPath


    # ========================================================
    # OPEN REPORT
    # ========================================================

    Write-Host ""
    Write-Host "Opening Active Directory health report..."

    Start-Process `
        -FilePath $ReportPath
}
catch {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "         AD HEALTH CHECK FAILED"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host $_.Exception.Message
}
