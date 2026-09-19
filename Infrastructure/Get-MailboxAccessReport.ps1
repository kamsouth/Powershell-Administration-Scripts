# ============================================================
# Get-MailboxAccessReport.ps1
#
# Exchange Online Shared Mailbox Access Audit Tool
#
# Reports:
#   - Full Access
#   - Send As
#   - Send on Behalf
#
# Features:
#   - Read-only
#   - Validates mailbox
#   - Collects explicit mailbox permissions
#   - Generates CSV report
#   - Generates HTML report
#   - Generates ticket/audit notes
#   - Leaves Exchange session connected
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$ReportFolder = "C:\Temp\ExchangeAutomation\MailboxReports"
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
Write-Host "       MAILBOX ACCESS AUDIT TOOL"
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

    Write-Host "Exchange Online connection failed."
    Write-Host ""
    Write-Host $_.Exception.Message

    return
}


try {

    # ========================================================
    # GET MAILBOX
    # ========================================================

    $MailboxInput =
        Read-Host "Enter shared mailbox name or email address"


    $Mailbox =
        Get-Mailbox `
            -Identity $MailboxInput `
            -ErrorAction Stop


    $MailboxAddress =
        $Mailbox.PrimarySmtpAddress.ToString()


    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              MAILBOX FOUND"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Display Name: $($Mailbox.DisplayName)"
    Write-Host "Address:      $MailboxAddress"
    Write-Host "Type:         $($Mailbox.RecipientTypeDetails)"
    Write-Host ""


    # ========================================================
    # RESULTS ARRAY
    # ========================================================

    $AccessResults = @()


    # ========================================================
    # FULL ACCESS
    # ========================================================

    Write-Host "Collecting Full Access permissions..."


    $FullAccessPermissions =
        Get-MailboxPermission `
            -Identity $Mailbox.Identity `
            -ErrorAction Stop |
        Where-Object {

            $_.AccessRights -contains "FullAccess" -and
            $_.Deny -eq $false -and
            $_.User.ToString() -notlike "*SELF*"
        }


    foreach ($Permission in $FullAccessPermissions) {

        $AccessResults +=
            [PSCustomObject]@{

                Mailbox =
                    $MailboxAddress

                User =
                    $Permission.User.ToString()

                PermissionType =
                    "Full Access"

                Inherited =
                    $Permission.IsInherited
            }
    }


    # ========================================================
    # SEND AS
    # ========================================================

    Write-Host "Collecting Send As permissions..."


    $SendAsPermissions =
        Get-RecipientPermission `
            -Identity $Mailbox.Identity `
            -ErrorAction Stop |
        Where-Object {

            $_.AccessRights -contains "SendAs" -and
            $_.Trustee.ToString() -notlike "*SELF*"
        }


    foreach ($Permission in $SendAsPermissions) {

        $AccessResults +=
            [PSCustomObject]@{

                Mailbox =
                    $MailboxAddress

                User =
                    $Permission.Trustee.ToString()

                PermissionType =
                    "Send As"

                Inherited =
                    $false
            }
    }


    # ========================================================
    # SEND ON BEHALF
    # ========================================================

    Write-Host "Collecting Send on Behalf permissions..."


    $SendOnBehalfUsers =
        $Mailbox.GrantSendOnBehalfTo


    foreach ($Delegate in $SendOnBehalfUsers) {

        try {

            $Recipient =
                Get-Recipient `
                    -Identity $Delegate `
                    -ErrorAction Stop


            $DelegateName =
                if ($Recipient.PrimarySmtpAddress) {

                    $Recipient.PrimarySmtpAddress.ToString()
                }
                else {

                    $Recipient.DisplayName
                }
        }

        catch {

            $DelegateName =
                $Delegate.ToString()
        }


        $AccessResults +=
            [PSCustomObject]@{

                Mailbox =
                    $MailboxAddress

                User =
                    $DelegateName

                PermissionType =
                    "Send on Behalf"

                Inherited =
                    $false
            }
    }


    # ========================================================
    # DISPLAY RESULTS
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "           MAILBOX ACCESS REPORT"
    Write-Host "=========================================="
    Write-Host ""


    if ($AccessResults.Count -gt 0) {

        $AccessResults |
            Sort-Object `
                PermissionType,
                User |
            Format-Table `
                User,
                PermissionType,
                Inherited `
                -AutoSize
    }

    else {

        Write-Host "No delegated mailbox permissions were found."
    }


    # ========================================================
    # COUNTS
    # ========================================================

    $FullAccessCount =
        @(
            $AccessResults |
            Where-Object {
                $_.PermissionType -eq "Full Access"
            }
        ).Count


    $SendAsCount =
        @(
            $AccessResults |
            Where-Object {
                $_.PermissionType -eq "Send As"
            }
        ).Count


    $SendOnBehalfCount =
        @(
            $AccessResults |
            Where-Object {
                $_.PermissionType -eq "Send on Behalf"
            }
        ).Count


    Write-Host ""
    Write-Host "Full Access:      $FullAccessCount"
    Write-Host "Send As:          $SendAsCount"
    Write-Host "Send on Behalf:   $SendOnBehalfCount"
    Write-Host ""


    # ========================================================
    # FILE PATHS
    # ========================================================

    $SafeMailboxName =
        $Mailbox.Alias -replace '[\\/:*?"<>|]', '_'


    $CSVPath =
        "$ReportFolder\$SafeMailboxName`_Access_$Timestamp.csv"


    $HTMLPath =
        "$ReportFolder\$SafeMailboxName`_Access_$Timestamp.html"


    $TicketNotePath =
        "$ReportFolder\$SafeMailboxName`_TicketNote_$Timestamp.txt"


    # ========================================================
    # EXPORT CSV
    # ========================================================

    $AccessResults |
        Export-Csv `
            -Path $CSVPath `
            -NoTypeInformation `
            -Encoding UTF8


    # ========================================================
    # SUMMARY OBJECT
    # ========================================================

    $Summary =
        [PSCustomObject]@{

            Mailbox =
                $Mailbox.DisplayName

            Address =
                $MailboxAddress

            MailboxType =
                $Mailbox.RecipientTypeDetails

            FullAccess =
                $FullAccessCount

            SendAs =
                $SendAsCount

            SendOnBehalf =
                $SendOnBehalfCount

            GeneratedBy =
                $Technician

            Generated =
                Get-Date
        }


    # ========================================================
    # HTML REPORT
    # ========================================================

    $HTML = @"

<html>

<head>

<title>
Mailbox Access Report - $($Mailbox.DisplayName)
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
Exchange Online Mailbox Access Report
</h1>

<p>

<strong>Mailbox:</strong>
$($Mailbox.DisplayName)

<br>

<strong>Address:</strong>
$MailboxAddress

<br>

<strong>Generated:</strong>
$(Get-Date)

</p>


<h2>
Summary
</h2>

$(
    $Summary |
    ConvertTo-Html -Fragment
)


<h2>
Delegated Permissions
</h2>

$(
    if ($AccessResults.Count -gt 0) {

        $AccessResults |
            Sort-Object PermissionType,User |
            ConvertTo-Html -Fragment
    }
    else {

        "<p>No delegated mailbox permissions were found.</p>"
    }
)


</body>

</html>

"@


    $HTML |
        Out-File `
            -FilePath $HTMLPath `
            -Encoding UTF8


    # ========================================================
    # GENERATE TICKET NOTE
    # ========================================================

    $TicketNote = @"

Shared Mailbox Access Review

Mailbox:
$($Mailbox.DisplayName)

Mailbox Address:
$MailboxAddress

Full Access Delegates:
$FullAccessCount

Send As Delegates:
$SendAsCount

Send on Behalf Delegates:
$SendOnBehalfCount

Reviewed By:
$Technician

Completed:
$(Get-Date)

Mailbox delegation permissions were reviewed using Exchange Online PowerShell.

CSV Report:
$CSVPath

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
    Write-Host "            AUDIT COMPLETE"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "CSV Report:"
    Write-Host $CSVPath

    Write-Host ""
    Write-Host "HTML Report:"
    Write-Host $HTMLPath

    Write-Host ""
    Write-Host "Ticket Note:"
    Write-Host $TicketNotePath


    # ========================================================
    # OPEN HTML REPORT
    # ========================================================

    Write-Host ""
    Write-Host "Opening mailbox access report..."

    Start-Process `
        -FilePath $HTMLPath
}

catch {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              AUDIT FAILED"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host $_.Exception.Message
}

finally {

    Write-Host ""
    Write-Host "Exchange Online session remains connected."
    Write-Host ""
    Write-Host "Disconnect when finished with:"
    Write-Host "Disconnect-ExchangeOnline -Confirm:`$false"
}
