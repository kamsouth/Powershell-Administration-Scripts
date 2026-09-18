Import-Module ActiveDirectory

$Username = Read-Host "Enter username"
$Technician = $env:USERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFolder = "C:\Temp\ADReports"
$LogPath = "C:\Temp\AD-Account-Audit.log"

if (!(Test-Path $ReportFolder)) {
    New-Item -ItemType Directory -Path $ReportFolder | Out-Null
}

try {

    $User = Get-ADUser `
        -Identity $Username `
        -Properties DisplayName,
                    Enabled,
                    LockedOut,
                    Department,
                    Title,
                    Manager,
                    PasswordLastSet,
                    PasswordNeverExpires,
                    LastLogonDate,
                    DistinguishedName `
        -ErrorAction Stop

    # Get manager
    if ($User.Manager) {
        $Manager = (Get-ADUser $User.Manager).DisplayName
    }
    else {
        $Manager = "No manager assigned"
    }

    # Determine OU
    $OU = ($User.DistinguishedName -split ",", 2)[1]

    # Direct group memberships
    $DirectGroups = Get-ADPrincipalGroupMembership $Username |
        Sort-Object Name |
        Select-Object Name, GroupScope, GroupCategory

    # Account summary
    $Summary = [PSCustomObject]@{
        Username             = $User.SamAccountName
        DisplayName          = $User.DisplayName
        Enabled              = $User.Enabled
        LockedOut            = $User.LockedOut
        Department           = $User.Department
        Title                = $User.Title
        Manager              = $Manager
        OrganizationalUnit   = $OU
        PasswordLastSet      = $User.PasswordLastSet
        PasswordNeverExpires = $User.PasswordNeverExpires
        LastLogonDate        = $User.LastLogonDate
    }

    Write-Host ""
    Write-Host "===== USER ACCESS REPORT ====="
    Write-Host ""

    $Summary | Format-List

    Write-Host ""
    Write-Host "===== GROUP MEMBERSHIPS ====="
    Write-Host ""

    $DirectGroups | Format-Table -AutoSize

    # Export summary
    $SummaryPath =
        "$ReportFolder\$($Username)_AccountReport_$Timestamp.csv"

    $Summary |
        Export-Csv `
            -Path $SummaryPath `
            -NoTypeInformation

    # Export groups
    $GroupPath =
        "$ReportFolder\$($Username)_GroupMembership_$Timestamp.csv"

    $DirectGroups |
        Export-Csv `
            -Path $GroupPath `
            -NoTypeInformation

    $Message =
        "Access report generated for $Username by $Technician"

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - $Message"

    Write-Host ""
    Write-Host "Reports exported:"
    Write-Host $SummaryPath
    Write-Host $GroupPath
}
catch {

    $ErrorMessage =
        "FAILED access report for $Username - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
