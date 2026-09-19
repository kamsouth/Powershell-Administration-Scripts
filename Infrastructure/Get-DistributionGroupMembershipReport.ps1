# ============================================================
# Get-DistributionGroupMembershipReport.ps1
#
# Exchange Online Distribution Group Membership Audit Tool
#
# Reports:
#   - Distribution group details
#   - Group owners
#   - Group members
#   - Member email addresses
#   - Recipient types
#   - Total membership count
#
# Features:
#   - Read-only
#   - Validates distribution group
#   - CSV export
#   - HTML report
#   - Ticket-ready notes
#   - Automatically opens HTML report
#   - Leaves Exchange Online session connected
#
# Supports:
#   - Distribution Groups
#   - Mail-Enabled Security Groups
#
# Does NOT modify group membership.
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$ReportFolder = "C:\Temp\ExchangeAutomation\DistributionGroupReports"
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
# VERIFY EXCHANGE ONLINE MODULE
# ============================================================

if (!(Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {

    Write-Host ""
    Write-Host "ExchangeOnlineManagement module is not installed."
    Write-Host ""
    Write-Host "Install it with:"
    Write-Host "Install-Module ExchangeOnlineManagement -Scope CurrentUser"
    Write-Host ""

    return
}


Import-Module ExchangeOnlineManagement


# ============================================================
# CONNECT TO EXCHANGE ONLINE
# ============================================================

Write-Host ""
Write-Host "=========================================="
Write-Host "   DISTRIBUTION GROUP MEMBERSHIP REPORT"
Write-Host "=========================================="
Write-Host ""

Write-Host "Connecting to Exchange Online..."
Write-Host ""


try {

    Connect-ExchangeOnline `
        -ShowBanner:$false `
        -ErrorAction Stop
}

catch {

    Write-Host ""
    Write-Host "Exchange Online connection failed."
    Write-Host ""

    Write-Host $_.Exception.Message

    return
}


try {

    # ========================================================
    # GET DISTRIBUTION GROUP
    # ========================================================

    $GroupInput =
        Read-Host "Enter distribution group name or email address"


    try {

        $Group =
            Get-DistributionGroup `
                -Identity $GroupInput `
                -ErrorAction Stop
    }

    catch {

        Write-Host ""
        Write-Host "=========================================="
        Write-Host "             GROUP NOT FOUND"
        Write-Host "=========================================="
        Write-Host ""

        Write-Host "The object could not be found as a traditional"
        Write-Host "Exchange distribution group."
        Write-Host ""

        Write-Host "This script supports:"
        Write-Host " - Distribution Groups"
        Write-Host " - Mail-Enabled Security Groups"
        Write-Host ""

        Write-Host "Microsoft 365 Groups use Get-UnifiedGroup instead."
        Write-Host ""

        throw $_.Exception.Message
    }


    # ========================================================
    # GROUP INFORMATION
    # ========================================================

    $GroupAddress =
        $Group.PrimarySmtpAddress.ToString()


    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              GROUP FOUND"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Display Name:   $($Group.DisplayName)"
    Write-Host "Email Address:  $GroupAddress"
    Write-Host "Alias:          $($Group.Alias)"
    Write-Host "Type:           $($Group.RecipientTypeDetails)"
    Write-Host ""


    # ========================================================
    # GET GROUP OWNERS
    # ========================================================

    Write-Host "Retrieving group owners..."


    $OwnerResults = @()


    foreach ($OwnerIdentity in $Group.ManagedBy) {

        try {

            $Owner =
                Get-Recipient `
                    -Identity $OwnerIdentity `
                    -ErrorAction Stop


            $OwnerEmail =
                if ($Owner.PrimarySmtpAddress) {

                    $Owner.PrimarySmtpAddress.ToString()
                }

                else {

                    "N/A"
                }


            $OwnerResults +=
                [PSCustomObject]@{

                    DisplayName =
                        $Owner.DisplayName

                    Email =
                        $OwnerEmail

                    RecipientType =
                        $Owner.RecipientTypeDetails
                }
        }

        catch {

            $OwnerResults +=
                [PSCustomObject]@{

                    DisplayName =
                        $OwnerIdentity.ToString()

                    Email =
                        "Unable to Resolve"

                    RecipientType =
                        "Unknown"
                }
        }
    }


    # ========================================================
    # GET GROUP MEMBERS
    # ========================================================

    Write-Host "Retrieving group members..."
    Write-Host ""


    $Members =
        @(
            Get-DistributionGroupMember `
                -Identity $Group.Identity `
                -ResultSize Unlimited `
                -ErrorAction Stop
        )


    # ========================================================
    # BUILD MEMBER REPORT
    # ========================================================

    $MemberResults = @()


    foreach ($Member in $Members) {

        $MemberEmail =
            if ($Member.PrimarySmtpAddress) {

                $Member.PrimarySmtpAddress.ToString()
            }

            else {

                "N/A"
            }


        $MemberResults +=
            [PSCustomObject]@{

                DisplayName =
                    $Member.DisplayName

                Email =
                    $MemberEmail

                RecipientType =
                    $Member.RecipientTypeDetails
            }
    }


    # ========================================================
    # SORT RESULTS
    # ========================================================

    $MemberResults =
        @(
            $MemberResults |
            Sort-Object DisplayName
        )


    $OwnerResults =
        @(
            $OwnerResults |
            Sort-Object DisplayName
        )


    # ========================================================
    # DISPLAY MEMBERS
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "               MEMBERS"
    Write-Host "=========================================="
    Write-Host ""


    if ($MemberResults.Count -gt 0) {

        $MemberResults |
            Format-Table `
                DisplayName,
                Email,
                RecipientType `
                -AutoSize
    }

    else {

        Write-Host "No members were found in this group."
    }


    # ========================================================
    # DISPLAY OWNERS
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "                OWNERS"
    Write-Host "=========================================="
    Write-Host ""


    if ($OwnerResults.Count -gt 0) {

        $OwnerResults |
            Format-Table `
                DisplayName,
                Email,
                RecipientType `
                -AutoSize
    }

    else {

        Write-Host "No group owners were returned."
    }


    # ========================================================
    # RECIPIENT TYPE SUMMARY
    # ========================================================

    $RecipientTypeSummary =
        @(
            $MemberResults |
            Group-Object RecipientType |
            Sort-Object Name |
            ForEach-Object {

                [PSCustomObject]@{

                    RecipientType =
                        $_.Name

                    Count =
                        $_.Count
                }
            }
        )


    # ========================================================
    # SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "               SUMMARY"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Group:          $($Group.DisplayName)"
    Write-Host "Address:        $GroupAddress"
    Write-Host "Group Type:     $($Group.RecipientTypeDetails)"
    Write-Host "Total Members:  $($MemberResults.Count)"
    Write-Host "Total Owners:   $($OwnerResults.Count)"
    Write-Host ""


    if ($RecipientTypeSummary.Count -gt 0) {

        Write-Host "Member Types:"
        Write-Host ""

        $RecipientTypeSummary |
            Format-Table `
                RecipientType,
                Count `
                -AutoSize
    }


    # ========================================================
    # CREATE SAFE FILE NAME
    # ========================================================

    $SafeGroupName =
        $Group.Alias -replace '[\\/:*?"<>|]', '_'


    # ========================================================
    # OUTPUT FILE PATHS
    # ========================================================

    $CSVPath =
        "$ReportFolder\$SafeGroupName`_Members_$Timestamp.csv"


    $OwnerCSVPath =
        "$ReportFolder\$SafeGroupName`_Owners_$Timestamp.csv"


    $HTMLPath =
        "$ReportFolder\$SafeGroupName`_MembershipReport_$Timestamp.html"


    $TicketNotePath =
        "$ReportFolder\$SafeGroupName`_TicketNote_$Timestamp.txt"


    # ========================================================
    # EXPORT MEMBER CSV
    # ========================================================

    $MemberResults |
        Export-Csv `
            -Path $CSVPath `
            -NoTypeInformation `
            -Encoding UTF8


    # ========================================================
    # EXPORT OWNER CSV
    # ========================================================

    $OwnerResults |
        Export-Csv `
            -Path $OwnerCSVPath `
            -NoTypeInformation `
            -Encoding UTF8


    # ========================================================
    # BUILD GROUP SUMMARY OBJECT
    # ========================================================

    $GroupSummary =
        [PSCustomObject]@{

            DisplayName =
                $Group.DisplayName

            EmailAddress =
                $GroupAddress

            Alias =
                $Group.Alias

            GroupType =
                $Group.RecipientTypeDetails

            MemberCount =
                $MemberResults.Count

            OwnerCount =
                $OwnerResults.Count

            GeneratedBy =
                $Technician

            Generated =
                Get-Date
        }


    # ========================================================
    # HTML GROUP SUMMARY
    # ========================================================

    $GroupSummaryHTML =
        $GroupSummary |
        ConvertTo-Html `
            -Fragment


    # ========================================================
    # HTML MEMBERS TABLE
    # ========================================================

    if ($MemberResults.Count -gt 0) {

        $MembersHTML =
            $MemberResults |
            ConvertTo-Html `
                -Fragment
    }

    else {

        $MembersHTML =
            "<p>No members were found in this group.</p>"
    }


    # ========================================================
    # HTML OWNERS TABLE
    # ========================================================

    if ($OwnerResults.Count -gt 0) {

        $OwnersHTML =
            $OwnerResults |
            ConvertTo-Html `
                -Fragment
    }

    else {

        $OwnersHTML =
            "<p>No group owners were returned.</p>"
    }


    # ========================================================
    # HTML RECIPIENT TYPE SUMMARY
    # ========================================================

    if ($RecipientTypeSummary.Count -gt 0) {

        $RecipientTypeHTML =
            $RecipientTypeSummary |
            ConvertTo-Html `
                -Fragment
    }

    else {

        $RecipientTypeHTML =
            "<p>No recipient type information available.</p>"
    }


    # ========================================================
    # BUILD HTML REPORT
    # ========================================================

    $HTML = @"

<html>

<head>

<title>
Distribution Group Membership Report - $($Group.DisplayName)
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
}

th {
    background-color: #eeeeee;
}

</style>

</head>


<body>


<h1>
Exchange Online Distribution Group Membership Report
</h1>


<p>

<strong>Group:</strong>
$($Group.DisplayName)

<br>

<strong>Email Address:</strong>
$GroupAddress

<br>

<strong>Generated:</strong>
$(Get-Date)

<br>

<strong>Generated By:</strong>
$Technician

</p>


<h2>
Group Summary
</h2>

$GroupSummaryHTML


<h2>
Group Owners
</h2>

$OwnersHTML


<h2>
Member Type Summary
</h2>

$RecipientTypeHTML


<h2>
Group Members
</h2>

$MembersHTML


</body>

</html>

"@


    # ========================================================
    # SAVE HTML REPORT
    # ========================================================

    $HTML |
        Out-File `
            -FilePath $HTMLPath `
            -Encoding UTF8


    # ========================================================
    # CREATE TICKET NOTE
    # ========================================================

    $TicketNote = @"

Distribution Group Membership Review

Group:
$($Group.DisplayName)

Group Address:
$GroupAddress

Group Type:
$($Group.RecipientTypeDetails)

Total Members:
$($MemberResults.Count)

Total Owners:
$($OwnerResults.Count)

Reviewed By:
$Technician

Completed:
$(Get-Date)

Distribution group membership and ownership were reviewed using Exchange Online PowerShell.

Member CSV:
$CSVPath

Owner CSV:
$OwnerCSVPath

HTML Report:
$HTMLPath

"@


    $TicketNote |
        Out-File `
            -FilePath $TicketNotePath `
            -Encoding UTF8


    # ========================================================
    # COMPLETION
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "           REPORT COMPLETE"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Members:"
    Write-Host $($MemberResults.Count)

    Write-Host ""
    Write-Host "Owners:"
    Write-Host $($OwnerResults.Count)

    Write-Host ""
    Write-Host "Member CSV:"
    Write-Host $CSVPath

    Write-Host ""
    Write-Host "Owner CSV:"
    Write-Host $OwnerCSVPath

    Write-Host ""
    Write-Host "HTML Report:"
    Write-Host $HTMLPath

    Write-Host ""
    Write-Host "Ticket Note:"
    Write-Host $TicketNotePath


    # ========================================================
    # DISPLAY TICKET NOTE
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "           GENERATED TICKET NOTE"
    Write-Host "=========================================="
    Write-Host ""

    Get-Content $TicketNotePath


    # ========================================================
    # OPEN HTML REPORT
    # ========================================================

    Write-Host ""
    Write-Host "Opening distribution group report..."

    Start-Process `
        -FilePath $HTMLPath
}


catch {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "             REPORT FAILED"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host $_.Exception.Message
}


finally {

    # ========================================================
    # KEEP EXCHANGE SESSION CONNECTED
    # ========================================================

    Write-Host ""
    Write-Host "Exchange Online session remains connected."
    Write-Host ""

    Write-Host "Disconnect when finished with:"
    Write-Host "Disconnect-ExchangeOnline -Confirm:`$false"
}
