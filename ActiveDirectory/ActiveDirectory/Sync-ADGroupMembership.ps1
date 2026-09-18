Import-Module ActiveDirectory

$SourceUser = Read-Host "Enter source/reference username"
$TargetUser = Read-Host "Enter target username"

$Technician = $env:USERNAME
$LogPath = "C:\Temp\AD-Account-Audit.log"

try {

    # Validate both users
    $Source = Get-ADUser `
        -Identity $SourceUser `
        -ErrorAction Stop

    $Target = Get-ADUser `
        -Identity $TargetUser `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Source User: $($Source.Name)"
    Write-Host "Target User: $($Target.Name)"
    Write-Host ""

    # Only allow approved RBAC groups
    $SourceGroups = Get-ADPrincipalGroupMembership $SourceUser |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Select-Object -ExpandProperty Name

    $TargetGroups = Get-ADPrincipalGroupMembership $TargetUser |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Select-Object -ExpandProperty Name

    # Find groups target is missing
    $MissingGroups = $SourceGroups |
        Where-Object {
            $_ -notin $TargetGroups
        }

    Write-Host "======================================"
    Write-Host "       RBAC MEMBERSHIP PREVIEW"
    Write-Host "======================================"
    Write-Host ""

    if (!$MissingGroups) {

        Write-Host "$TargetUser already has all approved RBAC groups assigned to $SourceUser."

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - Technician: $Technician - No RBAC changes required for $TargetUser"

        return
    }

    Write-Host "The following groups are missing:"
    Write-Host ""

    foreach ($Group in $MissingGroups) {
        Write-Host "  + $Group"
    }

    Write-Host ""
    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    $Confirmation = Read-Host "Type APPLY to add these groups to $TargetUser"

    if ($Confirmation -ne "APPLY") {

        Write-Host ""
        Write-Host "Operation cancelled. No changes were made."

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - Technician: $Technician - RBAC sync cancelled for $TargetUser"

        return
    }

    foreach ($Group in $MissingGroups) {

        try {

            Add-ADGroupMember `
                -Identity $Group `
                -Members $TargetUser `
                -ErrorAction Stop

            # Verify change
            $Verified = Get-ADGroupMember `
                -Identity $Group |
                Where-Object {
                    $_.SamAccountName -eq $TargetUser
                }

            if ($Verified) {

                $Message =
                    "SUCCESS - Added $TargetUser to $Group"

                Write-Host $Message

                Add-Content `
                    -Path $LogPath `
                    -Value "$(Get-Date) - Technician: $Technician - $Message"
            }
            else {

                throw "Membership verification failed."
            }
        }
        catch {

            $ErrorMessage =
                "FAILED - $TargetUser -> $Group - $($_.Exception.Message)"

            Write-Host $ErrorMessage

            Add-Content `
                -Path $LogPath `
                -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
        }
    }

    Write-Host ""
    Write-Host "======================================"
    Write-Host "       FINAL RBAC MEMBERSHIP"
    Write-Host "======================================"
    Write-Host ""

    Get-ADPrincipalGroupMembership $TargetUser |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Select-Object Name, GroupScope, GroupCategory |
        Format-Table -AutoSize
}
catch {

    $ErrorMessage =
        "FAILED RBAC sync: $SourceUser -> $TargetUser - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
