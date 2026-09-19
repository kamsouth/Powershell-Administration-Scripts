# ============================================================
# Revoke-MailboxPermissions.ps1
#
# Controlled Exchange Online Mailbox Permission Removal Tool
#
# Supports:
#   1 - Full Access
#   2 - Send As
#   3 - Full Access + Send As
#
# Features:
#   - Exchange Online connection
#   - Mailbox validation
#   - Recipient validation
#   - Existing permission detection
#   - Change preview
#   - Explicit REMOVE confirmation
#   - Permission removal
#   - Post-change verification
#   - Audit logging
#   - Ticket note generation
#   - Leaves Exchange Online session connected for verification
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
    "$AuditFolder\MailboxPermission-Removal-TicketNote_$Timestamp.txt"


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
Write-Host "     MAILBOX PERMISSION REMOVAL TOOL"
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
    Write-Host "Select Permission Type to Remove"
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
    Write-Host "Validating users and checking existing permissions..."
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
                            "Pending Full Access Removal"
                    }
                    else {

                        $Status =
                            "No Full Access Permission"
                    }
                }


                "SendAs" {

                    if ($SendAsExists) {

                        $Status =
                            "Pending Send As Removal"
                    }
                    else {

                        $Status =
                            "No Send As Permission"
                    }
                }


                "FullAccessAndSendAs" {

                    if (
                        $FullAccessExists -and
                        $SendAsExists
                    ) {

                        $Status =
                            "Pending Full Access + Send As Removal"
                    }

                    elseif ($FullAccessExists) {

                        $Status =
                            "Pending Full Access Removal"
                    }

                    elseif ($SendAsExists) {

                        $Status =
                            "Pending Send As Removal"
                    }

                    else {

                        $Status =
                            "No Requested Permissions Assigned"
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


    $NoChangeUsers =
        @(
            $ChangePlan |
            Where-Object {
                $_.Status -like "No *"
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
    Write-Host "Pending Changes: $($PendingUsers.Count)"
    Write-Host "No Change:       $($NoChangeUsers.Count)"
    Write-Host "Invalid Users:   $($InvalidUsers.Count)"
    Write-Host ""


    # ========================================================
    # STOP IF NOTHING NEEDS TO CHANGE
    # ========================================================

    if ($PendingUsers.Count -eq 0) {

        Write-Host "No mailbox permissions need to be removed."


        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - No removal changes required"

        return
    }


    # ========================================================
    # CONFIRM REMOVAL
    # ========================================================

    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    Write-Host "WARNING:"
    Write-Host "The permissions shown above will be removed."
    Write-Host ""

    $Confirmation =
        Read-Host "Type REMOVE to continue"


    if ($Confirmation -ne "REMOVE") {

        Write-Host ""
        Write-Host "Operation cancelled. No changes were made."


        Add-Content `
            -Path $AuditLog `
            -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - Permission removal cancelled"

        return
    }


    # ========================================================
    # APPLY REMOVALS
    # ========================================================

    $Completed = @()
    $Failed    = @()


    foreach ($User in $PendingUsers) {

        try {

            # =================================================
            # REMOVE FULL ACCESS
            # =================================================

            if (
                (
                    $PermissionType -eq "FullAccess" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                $User.FullAccess
            ) {

                Remove-MailboxPermission `
                    -Identity $Mailbox.Identity `
                    -User $User.Email `
                    -AccessRights FullAccess `
                    -InheritanceType All `
                    -Confirm:$false `
                    -ErrorAction Stop


                Write-Host ""
                Write-Host "Removed Full Access:"
                Write-Host $User.Email
            }


            # =================================================
            # REMOVE SEND AS
            # =================================================

            if (
                (
                    $PermissionType -eq "SendAs" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                $User.SendAs
            ) {

                Remove-RecipientPermission `
                    -Identity $Mailbox.Identity `
                    -Trustee $User.Email `
                    -AccessRights SendAs `
                    -Confirm:$false `
                    -ErrorAction Stop


                Write-Host ""
                Write-Host "Removed Send As:"
                Write-Host $User.Email
            }


            # =================================================
            # POST-CHANGE VERIFICATION
            # =================================================

            $FullAccessStillExists = $false
            $SendAsStillExists     = $false


            $UpdatedMailboxPermissions =
                Get-MailboxPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction Stop


            $RemainingFullAccess =
                $UpdatedMailboxPermissions |
                Where-Object {

                    $_.User.ToString() -eq $User.Email -and
                    $_.AccessRights -contains "FullAccess" -and
                    $_.Deny -eq $false
                }


            if ($RemainingFullAccess) {

                $FullAccessStillExists = $true
            }


            $UpdatedRecipientPermissions =
                Get-RecipientPermission `
                    -Identity $Mailbox.Identity `
                    -ErrorAction Stop


            $RemainingSendAs =
                $UpdatedRecipientPermissions |
                Where-Object {

                    $_.Trustee.ToString() -eq $User.Email -and
                    $_.AccessRights -contains "SendAs"
                }


            if ($RemainingSendAs) {

                $SendAsStillExists = $true
            }


            # =================================================
            # DETERMINE WHETHER VERIFICATION PASSED
            # =================================================

            $VerificationPassed = $true


            if (
                (
                    $PermissionType -eq "FullAccess" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                $FullAccessStillExists
            ) {

                $VerificationPassed = $false
            }


            if (
                (
                    $PermissionType -eq "SendAs" -or
                    $PermissionType -eq "FullAccessAndSendAs"
                ) -and
                $SendAsStillExists
            ) {

                $VerificationPassed = $false
            }


            if (!$VerificationPassed) {

                throw "Post-removal permission verification failed."
            }


            # =================================================
            # STORE SUCCESS RESULT
            # =================================================

            $Completed +=
                [PSCustomObject]@{

                    Email =
                        $User.Email

                    FullAccessRemaining =
                        $FullAccessStillExists

                    SendAsRemaining =
                        $SendAsStillExists
                }


            # =================================================
            # WRITE AUDIT LOG
            # =================================================

            Add-Content `
                -Path $AuditLog `
                -Value "$(Get-Date) - Technician: $Technician - Mailbox: $($Mailbox.PrimarySmtpAddress) - User: $($User.Email) - FullAccessRemaining: $FullAccessStillExists - SendAsRemaining: $SendAsStillExists"
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
                -Value "$(Get-Date) - Technician: $Technician - FAILED REMOVAL - Mailbox: $($Mailbox.PrimarySmtpAddress) - User: $($User.Email) - Error: $($_.Exception.Message)"
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

Shared Mailbox Permission Removal

Mailbox:
$($Mailbox.DisplayName)

Mailbox Address:
$($Mailbox.PrimarySmtpAddress)

Permission Removal Requested:
$PermissionType

Users Requested:
$($ChangePlan.Count)

Changes Completed:
$($Completed.Count)

Successfully Processed:
$CompletedUserList

Users Requiring No Change:
$($NoChangeUsers.Count)

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

Mailbox permissions were validated before removal and verified after completion.

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

    Write-Host "Completed: $($Completed.Count)"
    Write-Host "No Change: $($NoChangeUsers.Count)"
    Write-Host "Invalid:   $($InvalidUsers.Count)"
    Write-Host "Failed:    $($Failed.Count)"

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

    # ========================================================
    # KEEP SESSION CONNECTED
    # ========================================================

    Write-Host ""
    Write-Host "Exchange Online session remains connected for verification."
    Write-Host ""
    Write-Host "When finished, disconnect manually with:"
    Write-Host "Disconnect-ExchangeOnline -Confirm:`$false"
}
