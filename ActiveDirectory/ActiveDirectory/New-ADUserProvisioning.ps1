Import-Module ActiveDirectory

$FirstName = Read-Host "Enter first name"
$LastName = Read-Host "Enter last name"
$Username = Read-Host "Enter username"
$Department = Read-Host "Enter department"
$Title = Read-Host "Enter job title"
$TemplateUser = Read-Host "Enter reference/template username"

$OUPath = "OU=Corp Users,DC=corp,DC=kameronlab,DC=test"
$UPNSuffix = "corp.kameronlab.test"

$Technician = $env:USERNAME
$LogPath = "C:\Temp\AD-Account-Audit.log"

try {

    # Make sure username does not already exist
    $ExistingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$Username'" `
        -ErrorAction Stop

    if ($ExistingUser) {
        throw "Username $Username already exists."
    }

    # Validate template user
    $Template = Get-ADUser `
        -Identity $TemplateUser `
        -Properties Department, Title `
        -ErrorAction Stop

    # Only copy approved RBAC groups
    $TemplateGroups = Get-ADPrincipalGroupMembership $TemplateUser |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Select-Object -ExpandProperty Name

    Write-Host ""
    Write-Host "======================================"
    Write-Host "       NEW USER PROVISIONING"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "Name:       $FirstName $LastName"
    Write-Host "Username:   $Username"
    Write-Host "Department: $Department"
    Write-Host "Title:      $Title"
    Write-Host "OU:         $OUPath"
    Write-Host "Template:   $TemplateUser"

    Write-Host ""
    Write-Host "RBAC groups to assign:"
    Write-Host ""

    if ($TemplateGroups) {
        foreach ($Group in $TemplateGroups) {
            Write-Host "  + $Group"
        }
    }
    else {
        Write-Host "No approved RBAC groups found."
    }

    Write-Host ""
    Write-Host "NO CHANGES HAVE BEEN MADE."
    Write-Host ""

    $Confirm = Read-Host "Type CREATE to provision this account"

    if ($Confirm -ne "CREATE") {

        Write-Host "Provisioning cancelled."

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - Technician: $Technician - Provisioning cancelled for $Username"

        return
    }

    # Securely enter temporary password
    $Password = Read-Host `
        "Enter temporary password" `
        -AsSecureString

    # Create account
    New-ADUser `
        -Name "$FirstName $LastName" `
        -GivenName $FirstName `
        -Surname $LastName `
        -DisplayName "$FirstName $LastName" `
        -SamAccountName $Username `
        -UserPrincipalName "$Username@$UPNSuffix" `
        -Department $Department `
        -Title $Title `
        -Path $OUPath `
        -AccountPassword $Password `
        -Enabled $true `
        -ChangePasswordAtLogon $true `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Created account: $Username"

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - Created AD user $Username"

    # Assign approved groups
    foreach ($Group in $TemplateGroups) {

        try {

            Add-ADGroupMember `
                -Identity $Group `
                -Members $Username `
                -ErrorAction Stop

            Write-Host "Added $Username to $Group"

            Add-Content `
                -Path $LogPath `
                -Value "$(Get-Date) - Technician: $Technician - Added $Username to $Group"
        }
        catch {

            Write-Host "FAILED group assignment: $Group"

            Add-Content `
                -Path $LogPath `
                -Value "$(Get-Date) - Technician: $Technician - FAILED $Username -> $Group - $($_.Exception.Message)"
        }
    }

    # Verification
    $NewUser = Get-ADUser `
        -Identity $Username `
        -Properties Department, Title, Enabled, PasswordLastSet

    Write-Host ""
    Write-Host "======================================"
    Write-Host "       PROVISIONING COMPLETE"
    Write-Host "======================================"
    Write-Host ""

    $NewUser |
        Select-Object `
            Name,
            SamAccountName,
            UserPrincipalName,
            Department,
            Title,
            Enabled |
        Format-List

    Write-Host "Assigned RBAC Groups:"
    Write-Host ""

    Get-ADPrincipalGroupMembership $Username |
        Where-Object {
            $_.Name -like "RBAC-*"
        } |
        Select-Object Name |
        Format-Table -AutoSize
}
catch {

    $ErrorMessage =
        "FAILED provisioning for $Username - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
