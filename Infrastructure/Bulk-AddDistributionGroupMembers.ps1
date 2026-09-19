# ============================================================
# Bulk-AddDistributionGroupMembers.ps1
#
# Exchange Online Distribution Group Membership Automation
#
# Features:
#   - Validates distribution group
#   - Validates recipients
#   - Detects existing members
#   - Prevents duplicate additions
#   - Displays change preview
#   - Requires explicit APPLY confirmation
#   - Adds pending members
#   - Verifies membership after change
#   - Writes audit log
#   - Generates ticket-ready notes
#   - Leaves Exchange Online session connected
#
# Supports:
#   - Distribution Groups
#   - Mail-Enabled Security Groups
#
# Does NOT support Microsoft 365 Groups.
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$AuditFolder = "C:\Temp\ExchangeAutomation"
$Technician  = $env:USERNAME
$Timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

if (!(Test-Path $AuditFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $AuditFolder `
        -Force |
        Out-Null
}

$AuditLog =
    "$AuditFolder\DistributionGroup-Audit.log"

$TicketNotePath =
    "$AuditFolder\DistributionGroup-Add-TicketNote_$Timestamp.txt"


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
Write-Host " DISTRIBUTION GROUP MEMBER AUTOMATION"
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

        Write-Host "Microsoft 365 Groups require different commands."
        Write-Host ""

        throw $_.Exception.Message
    }


    $GroupAddress =
        $Group.PrimarySmtpAddress.ToString()


    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              GROUP FOUND"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Display Name:  $($Group.DisplayName)"
    Write-Host "Email Address: $GroupAddress"
    Write-Host "Alias:         $($Group.Alias)"
    Write-Host "Type:          $($Group.RecipientTypeDetails)"
    Write-Host ""


    # ========================================================
    # GET CURRENT MEMBERS
    # ========================================================

    Write-Host "Retrieving current membership..."
    Write-Host ""

    $CurrentMembers =
        @(
            Get-DistributionGroupMember `
                -Identity $Group.Identity `
                -ResultSize Unlimited `
                -ErrorAction Stop
        )

    Write-Host "Current Members: $($CurrentMembers.Count)"
    Write-Host ""


    # ========================================================
    # GET USERS
    # ========================================================

    Write-Host "Enter recipient email addresses separated by commas."
    Write-Host ""

    $UserInput =
        Read-Host "Users"

    $Users =
        $UserInput `
            -split "," |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            $_
        } |
        Select-Object -Unique


    if (!$Users) {

        throw "No recipients were entered."
    }


    # ========================================================
    # VALIDATE RECIPIENTS
    # ========================================================

    Write-Host ""
    Write-Host "Validating recipients and checking membership..."
    Write-Host ""

    $ChangePlan = @()


    foreach ($UserAddress in $Users) {

        try {

            $Recipient =
                Get-Recipient `
                    -Identity $UserAddress `
                    -ErrorAction Stop


            $RecipientAddress =
                $Recipient.PrimarySmtpAddress.ToString()


            # =================================================
            # CHECK IF ALREADY MEMBER
            # =================================================

            $ExistingMember =
                $CurrentMembers |
                Where-Object {

                    $_.PrimarySmtpAddress -and
                    $_.PrimarySmtpAddress.ToString() -eq
                    $RecipientAddress
                }


            if ($ExistingMember) {

                $Status =
                    "Already Member"
            }

            else {

                $Status =
                    "Pending Addition"
            }


            # =================================================
            # ADD TO CHANGE PLAN
            # =================================================

            $ChangePlan +=
                [PSCustomObject]@{

                    DisplayName =
                        $Recipient.DisplayName

                    Email =
                        $RecipientAddress

                    RecipientType =
                        $Recipient.RecipientTypeDetails

                    Status =
                        $Status
                }
        }

        catch {

            $ChangePlan +=
                [PSCustomObject]@{

                    DisplayName =
                        "N/A"

                    Email =
                        $UserAddress

                    RecipientType =
                        "N/A"

                    Status =
                        "INVALID RECIPIENT"
                }
        }
    }


    # ========================================================
    # DISPLAY CHANGE PREVIEW
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              CHANGE PREVIEW"
    Write-Host "=========================================="
    Write-Host ""


    $ChangePlan |
        Format-Table `
            DisplayName,
            Email,
            RecipientType,
            Status `
            -AutoSize


    $PendingUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -eq "Pending Addition"
            }
        )


    $ExistingUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -eq "Already Member"
            }
        )


    $InvalidUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -eq "INVALID RECIPIENT"
            }
        )


    Write-Host ""
    Write-Host "Requested Users: $($ChangePlan.Count)"
    Write-Host "Pending Adds:    $($PendingUsers.Count)"
    Write-Host "Already Members: $($ExistingUsers.Count)"
    Write-Host "Invalid Users:   $($InvalidUsers.Count)"
    Write-Host ""


    # ========================================================
    # STOP IF NOTHING TO DO
    # ========================================================

    if ($PendingUsers.Count -eq 0) {

        Write-Host "No membership changes are required."

        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - No membership changes required"

        return
    }


    # ========================================================
    # CONFIRM CHANGE
    # ========================================================

    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    $Confirmation =
        Read-Host "Type APPLY to add the pending members"


    if ($Confirmation -ne "APPLY") {

        Write-Host ""
        Write-Host "Operation cancelled. No changes were made."


        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - Operation cancelled"

        return
    }


    # ========================================================
    # APPLY CHANGES
    # ========================================================

    $Completed = @()
    $Failed    = @()


    foreach ($User in $PendingUsers) {

        try {

            Add-DistributionGroupMember `
                -Identity $Group.Identity `
                -Member $User.Email `
                -ErrorAction Stop


            Write-Host ""
            Write-Host "Added:"
            Write-Host $User.Email


            # =================================================
            # VERIFY MEMBERSHIP
            # =================================================

            $UpdatedMembers =
                @(
                    Get-DistributionGroupMember `
                        -Identity $Group.Identity `
                        -ResultSize Unlimited `
                        -ErrorAction Stop
                )


            $VerifiedMember =
                $UpdatedMembers |
                Where-Object {

                    $_.PrimarySmtpAddress -and
                    $_.PrimarySmtpAddress.ToString() -eq
                    $User.Email
                }


            if (!$VerifiedMember) {

                throw "Post-change membership verification failed."
            }


            # =================================================
            # STORE SUCCESS RESULT
            # =================================================

            $Completed +=
                [PSCustomObject]@{

                    DisplayName =
                        $User.DisplayName

                    Email =
                        $User.Email

                    Verified =
                        $true
                }


            # =================================================
            # WRITE AUDIT LOG
            # =================================================

            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - Added: $($User.Email) - Verified: True"
        }

        catch {

            Write-Host ""
            Write-Host "FAILED:"
            Write-Host $User.Email
            Write-Host $_.Exception.Message


            $Failed +=
                [PSCustomObject]@{

                    DisplayName =
                        $User.DisplayName

                    Email =
                        $User.Email

                    Error =
                        $_.Exception.Message
                }


            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - FAILED - Group: $GroupAddress - User: $($User.Email) - Error: $($_.Exception.Message)"
        }
    }


    # ========================================================
    # FINAL MEMBERSHIP
    # ========================================================

    $FinalMembers =
        @(
            Get-DistributionGroupMember `
                -Identity $Group.Identity `
                -ResultSize Unlimited `
                -ErrorAction Stop
        )


    # ========================================================
    # BUILD TICKET NOTE
    # ========================================================

    $CompletedUserList =
        if ($Completed.Count -gt 0) {

            ($Completed.Email -join ", ")
        }

        else {

            "None"
        }


    $ExistingUserList =
        if ($ExistingUsers.Count -gt 0) {

            ($ExistingUsers.Email -join ", ")
        }

        else {

            "None"
        }


    $InvalidUserList =
        if ($InvalidUsers.Count -gt 0) {

            ($InvalidUsers.Email -join ", ")
        }

        else {

            "None"
        }


    $FailedUserList =
        if ($Failed.Count -gt 0) {

            ($Failed.Email -join ", ")
        }

        else {

            "None"
        }


    $TicketNote = @"

Distribution Group Membership Update

Group:
$($Group.DisplayName)

Group Address:
$GroupAddress

Users Requested:
$($ChangePlan.Count)

Users Added:
$($Completed.Count)

Successfully Added:
$CompletedUserList

Already Members:
$($ExistingUsers.Count)

Existing Members Requested:
$ExistingUserList

Invalid Recipients:
$($InvalidUsers.Count)

Invalid Users:
$InvalidUserList

Failed Changes:
$($Failed.Count)

Failed Users:
$FailedUserList

Final Group Member Count:
$($FinalMembers.Count)

Technician:
$Technician

Completed:
$(Get-Date)

Recipients were validated before the change and membership was verified after completion.

"@


    # ========================================================
    # SAVE TICKET NOTE
    # ========================================================

    $TicketNote |
        Out-File `
            -FilePath $TicketNotePath `
            -Encoding UTF8


    # ========================================================
    # FINAL SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "               COMPLETE"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Added:           $($Completed.Count)"
    Write-Host "Already Members: $($ExistingUsers.Count)"
    Write-Host "Invalid:         $($InvalidUsers.Count)"
    Write-Host "Failed:          $($Failed.Count)"
    Write-Host "Final Members:   $($FinalMembers.Count)"

    Write-Host ""
    Write-Host "Audit Log:"
    Write-Host $AuditLog

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
}


catch {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              SCRIPT FAILED"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host $_.Exception.Message


    Add-Content `
        -Path $AuditLog `
        -Value "$(Get-Date) - Technician: $Technician - SCRIPT FAILURE - $($_.Exception.Message)"
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
