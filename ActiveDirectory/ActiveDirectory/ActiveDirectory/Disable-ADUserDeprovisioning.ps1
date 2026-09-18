Import-Module ActiveDirectory

$Username = Read-Host "Enter username to deprovision"

$DisabledOU = "OU=Disabled Users,DC=corp,DC=kameronlab,DC=test"
$Technician = $env:USERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$LogPath = "C:\Temp\AD-Account-Audit.log"
$ReportFolder = "C:\Temp\ADReports"

if (!(Test-Path $ReportFolder)) {
    New-Item `
        -ItemType Directory `
        -Path $ReportFolder |
        Out-Null
}

try {

    # Validate user
    $User = Get-ADUser `
        -Identity $Username `
        -Properties DisplayName,
                    Enabled,
                    Department,
                    Title,
                    DistinguishedName `
        -ErrorAction Stop

    # Get current RBAC groups
    $RBACGroups = Get-ADPrincipalGroupMembership $Username |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Sort-Object Name

    Write-Host ""
    Write-Host "======================================"
    Write-Host "       DEPROVISIONING PREVIEW"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "Name:       $($User.DisplayName)"
    Write-Host "Username:   $Username"
    Write-Host "Department: $($User.Department)"
    Write-Host "Title:      $($User.Title)"
    Write-Host "Enabled:    $($User.Enabled)"

    Write-Host ""
    Write-Host "RBAC access to be removed:"
    Write-Host ""

    if ($RBACGroups) {

        foreach ($Group in $RBACGroups) {
            Write-Host "  - $($Group.Name)"
        }

    }
    else {
        Write-Host "No RBAC groups assigned."
    }

    Write-Host ""
    Write-Host "Planned actions:"
    Write-Host "  1. Export current RBAC membership"
    Write-Host "  2. Remove approved RBAC memberships"
    Write-Host "  3. Disable account"
    Write-Host "  4. Move account to Disabled Users OU"
    Write-Host ""

    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    $Confirmation =
        Read-Host "Type DISABLE to continue"

    if ($Confirmation -ne "DISABLE") {

        Write-Host "Deprovisioning cancelled."

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - Technician: $Technician - Deprovisioning cancelled for $Username"

        return
    }

    # Export RBAC access before changes
    $ReportPath =
        "$ReportFolder\$($Username)_PreDeprovisionAccess_$Timestamp.csv"

    $RBACGroups |
        Select-Object Name,
                      GroupScope,
                      GroupCategory |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation

    Write-Host ""
    Write-Host "Pre-change access report saved:"
    Write-Host $ReportPath

    # Remove RBAC groups
    foreach ($Group in $RBACGroups) {

        try {

            Remove-ADGroupMember `
                -Identity $Group.Name `
                -Members $Username `
                -Confirm:$false `
                -ErrorAction Stop

            $Message =
                "Removed $Username from $($Group.Name)"

            Write-Host $Message

            Add-Content `
                -Path $LogPath `
                -Value "$(Get-Date) - Technician: $Technician - $Message"
        }

        catch {

            $ErrorMessage =
                "FAILED removing $Username from $($Group.Name) - $($_.Exception.Message)"

            Write-Host $ErrorMessage

            Add-Content `
                -Path $LogPath `
                -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
        }
    }

    # Disable user
    Disable-ADAccount `
        -Identity $Username `
        -ErrorAction Stop

    Write-Host "Disabled account: $Username"

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - Disabled account $Username"

    # Move user
    $UpdatedUser = Get-ADUser `
        -Identity $Username `
        -ErrorAction Stop

    Move-ADObject `
        -Identity $UpdatedUser.DistinguishedName `
        -TargetPath $DisabledOU `
        -ErrorAction Stop

    Write-Host "Moved account to Disabled Users OU."

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - Moved $Username to Disabled Users OU"

    # Verification
    $FinalUser = Get-ADUser `
        -Identity $Username `
        -Properties Enabled,
                    DistinguishedName

    $RemainingRBACGroups =
        Get-ADPrincipalGroupMembership $Username |
        Where-Object {
            $_.Name -like "RBAC-*"
        }

    Write-Host ""
    Write-Host "======================================"
    Write-Host "       DEPROVISIONING COMPLETE"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "Username: $Username"
    Write-Host "Enabled:  $($FinalUser.Enabled)"
    Write-Host "Location: $($FinalUser.DistinguishedName)"
    Write-Host ""

    if (!$RemainingRBACGroups) {
        Write-Host "RBAC access successfully removed."
    }
    else {
        Write-Host "WARNING: Some RBAC memberships remain."
    }
}

catch {

    $ErrorMessage =
        "FAILED deprovisioning for $Username - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
