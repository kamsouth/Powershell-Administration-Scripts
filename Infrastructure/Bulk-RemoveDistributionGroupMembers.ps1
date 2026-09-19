# ============================================================
# Bulk-RemoveDistributionGroupMembers.ps1
#
# Exchange Online Distribution Group Membership Removal Tool
#
# Features:
#   - Validates distribution group
#   - Validates recipients
#   - Checks current membership
#   - Skips users who are not members
#   - Displays removal preview
#   - Requires explicit REMOVE confirmation
#   - Removes pending members
#   - Verifies removal after change
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
    "$AuditFolder\DistributionGroup-Remove-TicketNote_$Timestamp.txt"


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
Write-Host " DISTRIBUTION GROUP MEMBER REMOVAL TOOL"
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
    # VALIDATE RECIPIENTS AND MEMBERSHIP
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
            # CHECK IF CURRENT MEMBER
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
                    "Pending Removal"
            }

            else {

                $Status =
                    "Not A Member"
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
                $_.Status -eq "Pending Removal"
            }
        )


    $NotMembers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -eq "Not A Member"
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
    Write-Host "Pending Removes: $($PendingUsers.Count)"
    Write-Host "Not Members:     $($NotMembers.Count)"
    Write-Host "Invalid Users:   $($InvalidUsers.Count)"
    Write-Host ""


    # ========================================================
    # STOP IF NOTHING TO REMOVE
    # ========================================================

    if ($PendingUsers.Count -eq 0) {

        Write-Host "No membership removals are required."

        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - No membership removals required"

        return
    }


    # ========================================================
    # CONFIRM REMOVAL
    # ========================================================

    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""
    Write-Host "WARNING:"
    Write-Host "The members shown as Pending Removal will be removed."
    Write-Host ""

    $Confirmation =
        Read-Host "Type REMOVE to continue"


    if ($Confirmation -ne "REMOVE") {

        Write-Host ""
        Write-Host "Operation cancelled. No changes were made."


        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - Removal cancelled"

        return
    }


    # ========================================================
    # APPLY REMOVALS
    # ========================================================

    $Completed = @()
    $Failed    = @()


    foreach ($User in $PendingUsers) {

        try {

            Remove-DistributionGroupMember `
                -Identity $Group.Identity `
                -Member $User.Email `
                -Confirm:$false `
                -ErrorAction Stop


            Write-Host ""
            Write-Host "Removed:"
            Write-Host $User.Email


            # =================================================
            # VERIFY REMOVAL
            # =================================================

            $UpdatedMembers =
                @(
                    Get-DistributionGroupMember `
                        -Identity $Group.Identity `
                        -ResultSize Unlimited `
                        -ErrorAction Stop
                )


            $StillMember =
                $UpdatedMembers |
                Where-Object {

                    $_.PrimarySmtpAddress -and
                    $_.PrimarySmtpAddress.ToString() -eq
                    $User.Email
                }


            if ($StillMember) {

                throw "Post-removal membership verification failed."
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

                    VerifiedRemoved =
                        $true
                }


            # =================================================
            # WRITE AUDIT LOG
            # =================================================

            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - Group: $GroupAddress - Removed: $($User.Email) - Verified: True"
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
                -Value "$(Get-Date) - Technician: $Technician - FAILED REMOVAL - Group: $GroupAddress - User: $($User.Email) - Error: $($_.Exception.Message)"
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


    $NotMemberList =
        if ($NotMembers.Count -gt 0) {

            ($NotMembers.Email -join ", ")
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

Distribution Group Membership Removal

Group:
$($Group.DisplayName)

Group Address:
$GroupAddress

Users Requested:
$($ChangePlan.Count)

Users Removed:
$($Completed.Count)

Successfully Removed:
$CompletedUserList

Users Not Currently Members:
$($NotMembers.Count)

Not Members:
$NotMemberList

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

Recipients were validated before the change and membership removal was verified after completion.

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

    Write-Host "Removed:     $($Completed.Count)"
    Write-Host "Not Members: $($NotMembers.Count)"
    Write-Host "Invalid:     $($InvalidUsers.Count)"
    Write-Host "Failed:      $($Failed.Count)"
    Write-Host "Final Count: $($FinalMembers.Count)"

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
