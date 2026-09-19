# ============================================================
# Grant-MailboxPermissions.ps1
#
# Exchange Online Shared Mailbox Permission Automation
#
# Supports:
#   - Full Access
#   - Send As
#   - Full Access + Send As
#
# Features:
#   - Exchange Online connection
#   - Mailbox validation
#   - Recipient validation
#   - Existing permission detection
#   - Change preview
#   - Explicit APPLY confirmation
#   - Permission assignment
#   - Post-change verification
#   - Audit logging
#   - Ticket note generation
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
    "$AuditFolder\MailboxPermission-Audit.log"

$TicketNotePath =
    "$AuditFolder\MailboxPermission-TicketNote_$Timestamp.txt"


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
Write-Host "      MAILBOX PERMISSION AUTOMATION"
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
    # GET SHARED MAILBOX
    # ========================================================

    $MailboxInput =
        Read-Host "Enter shared mailbox name or email address"

    $Mailbox =
        Get-Mailbox `
            -Identity $MailboxInput `
            -ErrorAction Stop


    Write-Host ""
    Write-Host "=========================================="
    Write-Host "              MAILBOX FOUND"
    Write-Host "=========================================="
    Write-Host ""

    Write-Host "Display Name: $($Mailbox.DisplayName)"
    Write-Host "Address:      $($Mailbox.PrimarySmtpAddress)"
    Write-Host "Type:         $($Mailbox.RecipientTypeDetails)"
    Write-Host ""


    # ========================================================
    # GET USERS
    # ========================================================

    Write-Host "Enter user email addresses separated by commas."
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

        throw "No users were entered."
    }


    # ========================================================
    # SELECT PERMISSION TYPE
    # ========================================================

    Write-Host ""
    Write-Host "Select Permission Type"
    Write-Host ""
    Write-Host "1 - Full Access"
    Write-Host "2 - Send As"
    Write-Host "3 - Full Access + Send As"
    Write-Host ""

    $PermissionChoice =
        Read-Host "Selection"


    switch ($PermissionChoice) {

        "1" {
            $PermissionType = "FullAccess"
        }

        "2" {
            $PermissionType = "SendAs"
        }

        "3" {
            $PermissionType = "FullAccessAndSendAs"
        }

        default {
            throw "Invalid permission selection."
        }
    }


    # ========================================================
    # VALIDATE USERS AND CHECK EXISTING PERMISSIONS
    # ========================================================

    $ChangePlan = @()

    Write-Host ""
    Write-Host "Validating users and checking permissions..."
    Write-Host ""


    foreach ($UserAddress in $Users) {

        try {

            $Recipient =
                Get-Recipient `
                    -Identity $UserAddress `
                    -ErrorAction Stop


            $RecipientAddress =
                $Recipient.PrimarySmtpAddress.ToString()


            $FullAccessExists = $false
            $SendAsExists     = $false


            # =================================================
            # CHECK FULL ACCESS
            # =================================================

            $MailboxPermissions =
                Get-MailboxPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction SilentlyContinue


            $ExistingFullAccess =
                $MailboxPermissions |
                Where-Object {

                    $_.User.ToString() -eq $RecipientAddress -and
                    $_.AccessRights -contains "FullAccess" -and
                    $_.Deny -eq $false
                }


            if ($ExistingFullAccess) {

                $FullAccessExists = $true
            }


            # =================================================
            # CHECK SEND AS
            # =================================================

            $RecipientPermissions =
                Get-RecipientPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction SilentlyContinue


            $ExistingSendAs =
                $RecipientPermissions |
                Where-Object {

                    $_.Trustee.ToString() -eq $RecipientAddress -and
                    $_.AccessRights -contains "SendAs"
                }


            if ($ExistingSendAs) {

                $SendAsExists = $true
            }


            # =================================================
            # DETERMINE ACTION REQUIRED
            # =================================================

            switch ($PermissionType) {

                "FullAccess" {

                    if ($FullAccessExists) {

                        $Status =
                            "Already Has Full Access"
                    }
                    else {

                        $Status =
                            "Pending Full Access"
                    }
                }


                "SendAs" {

                    if ($SendAsExists) {

                        $Status =
                            "Already Has Send As"
                    }
                    else {

                        $Status =
                            "Pending Send As"
                    }
                }


                "FullAccessAndSendAs" {

                    if (
                        $FullAccessExists -and
                        $SendAsExists
                    ) {

                        $Status =
                            "Already Has Both Permissions"
                    }

                    elseif (
                        !$FullAccessExists -and
                        !$SendAsExists
                    ) {

                        $Status =
                            "Pending Full Access + Send As"
                    }

                    elseif (!$FullAccessExists) {

                        $Status =
                            "Pending Full Access"
                    }

                    else {

                        $Status =
                            "Pending Send As"
                    }
                }
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

                    FullAccess =
                        $FullAccessExists

                    SendAs =
                        $SendAsExists

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

                    FullAccess =
                        $false

                    SendAs =
                        $false

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
            FullAccess,
            SendAs,
            Status `
            -AutoSize


    $PendingUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -like "Pending*"
            }
        )


    $InvalidUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -eq "INVALID RECIPIENT"
            }
        )


    $AlreadyConfigured =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -like "Already*"
            }
        )


    Write-Host ""
    Write-Host "Requested Users:    $($ChangePlan.Count)"
    Write-Host "Pending Changes:    $($PendingUsers.Count)"
    Write-Host "Already Configured: $($AlreadyConfigured.Count)"
    Write-Host "Invalid Users:      $($InvalidUsers.Count)"
    Write-Host ""


    # ========================================================
    # STOP IF NOTHING NEEDS TO CHANGE
    # ========================================================

    if ($PendingUsers.Count -eq 0) {

        Write-Host "No mailbox permission changes are required."

        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - No changes required"

        return
    }


    # ========================================================
    # CONFIRM CHANGES
    # ========================================================

    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    $Confirmation =
        Read-Host "Type APPLY to grant the pending permissions"


    if ($Confirmation -ne "APPLY") {

        Write-Host ""
        Write-Host "Operation cancelled. No changes were made."


        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - Operation cancelled"

        return
    }


    # ========================================================
    # APPLY PERMISSIONS
    # ========================================================

    $Completed = @()
    $Failed    = @()


    foreach ($User in $PendingUsers) {

        try {

            # =================================================
            # GRANT FULL ACCESS
            # =================================================

            if (
                (
                    $PermissionType -eq "FullAccess" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                !$User.FullAccess
            ) {

                Add-MailboxPermission `
                    -Identity $Mailbox.Identity `
                    -User $User.Email `
                    -AccessRights FullAccess `
                    -InheritanceType All `
                    -AutoMapping:$true `
                    -ErrorAction Stop


                Write-Host ""
                Write-Host "Granted Full Access:"
                Write-Host $User.Email
            }


            # =================================================
            # GRANT SEND AS
            # =================================================

            if (
                (
                    $PermissionType -eq "SendAs" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                !$User.SendAs
            ) {

                Add-RecipientPermission `
                    -Identity $Mailbox.Identity `
                    -Trustee $User.Email `
                    -AccessRights SendAs `
                    -Confirm:$false `
                    -ErrorAction Stop


                Write-Host ""
                Write-Host "Granted Send As:"
                Write-Host $User.Email
            }


            # =================================================
            # POST-CHANGE VERIFICATION
            # =================================================

            $VerifiedFullAccess = $false
            $VerifiedSendAs     = $false


            # Re-query mailbox permissions

            $UpdatedMailboxPermissions =
                Get-MailboxPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction Stop


            $VerifiedFullAccessEntry =
                $UpdatedMailboxPermissions |
                Where-Object {

                    $_.User.ToString() -eq $User.Email -and
                    $_.AccessRights -contains "FullAccess" -and
                    $_.Deny -eq $false
                }


            if ($VerifiedFullAccessEntry) {

                $VerifiedFullAccess = $true
            }


            # Re-query Send As permissions

            $UpdatedRecipientPermissions =
                Get-RecipientPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction Stop


            $VerifiedSendAsEntry =
                $UpdatedRecipientPermissions |
                Where-Object {

                    $_.Trustee.ToString() -eq $User.Email -and
                    $_.AccessRights -contains "SendAs"
                }


            if ($VerifiedSendAsEntry) {

                $VerifiedSendAs = $true
            }


            # =================================================
            # STORE SUCCESS RESULT
            # =================================================

            $Completed +=
                [PSCustomObject]@{

                    Email =
                        $User.Email

                    FullAccessVerified =
                        $VerifiedFullAccess

                    SendAsVerified =
                        $VerifiedSendAs
                }


            # =================================================
            # WRITE AUDIT LOG
            # =================================================

            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - User: $($User.Email) - FullAccessVerified: $VerifiedFullAccess - SendAsVerified: $VerifiedSendAs"
        }

        catch {

            Write-Host ""
            Write-Host "FAILED:"
            Write-Host $User.Email
            Write-Host $_.Exception.Message


            $Failed +=
                [PSCustomObject]@{

                    Email =
                        $User.Email

                    Error =
                        $_.Exception.Message
                }


            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - FAILED - Mailbox: $($Mailbox.PrimarySmtpAddress) - User: $($User.Email) - Error: $($_.Exception.Message)"
        }
    }


    # ========================================================
    # GENERATE TICKET NOTES
    # ========================================================

    $CompletedUserList =
        if ($Completed.Count -gt 0) {

            ($Completed.Email -join ", ")
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

Shared Mailbox Permission Update

Mailbox:
$($Mailbox.DisplayName)

Mailbox Address:
$($Mailbox.PrimarySmtpAddress)

Permission Requested:
$PermissionType

Users Requested:
$($ChangePlan.Count)

Changes Completed:
$($Completed.Count)

Successfully Processed:
$CompletedUserList

Already Configured:
$($AlreadyConfigured.Count)

Invalid Recipients:
$($InvalidUsers.Count)

Failed Changes:
$($Failed.Count)

Failed Users:
$FailedUserList

Technician:
$Technician

Completed:
$(Get-Date)

Mailbox permissions were validated before the change and verified after completion.

"@


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

    Write-Host "Completed:          $($Completed.Count)"
    Write-Host "Already Configured: $($AlreadyConfigured.Count)"
    Write-Host "Invalid:            $($InvalidUsers.Count)"
    Write-Host "Failed:             $($Failed.Count)"

    Write-Host ""
    Write-Host "Audit Log:"
    Write-Host $AuditLog

    Write-Host ""
    Write-Host "Ticket Note:"
    Write-Host $TicketNotePath

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

    Write-Host ""
    Write-Host "Disconnecting from Exchange Online..."

    Disconnect-ExchangeOnline `
        -Confirm:$false `
        -ErrorAction SilentlyContinue
}
