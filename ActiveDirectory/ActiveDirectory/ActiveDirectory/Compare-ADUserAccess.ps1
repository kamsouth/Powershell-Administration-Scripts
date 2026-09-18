Import-Module ActiveDirectory

$SourceUser = Read-Host "Enter source/reference username"
$TargetUser = Read-Host "Enter target username"

$Technician = $env:USERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFolder = "C:\Temp\ADReports"
$LogPath = "C:\Temp\AD-Account-Audit.log"

if (!(Test-Path $ReportFolder)) {
    New-Item -ItemType Directory -Path $ReportFolder | Out-Null
}

try {

    # Validate both users
    $Source = Get-ADUser `
        -Identity $SourceUser `
        -Properties DisplayName, Department, Title `
        -ErrorAction Stop

    $Target = Get-ADUser `
        -Identity $TargetUser `
        -Properties DisplayName, Department, Title `
        -ErrorAction Stop

    # Get group memberships
    $SourceGroups = Get-ADPrincipalGroupMembership $SourceUser |
        Select-Object -ExpandProperty Name |
        Sort-Object

    $TargetGroups = Get-ADPrincipalGroupMembership $TargetUser |
        Select-Object -ExpandProperty Name |
        Sort-Object

    # Groups both users share
    $SharedGroups = Compare-Object `
        -ReferenceObject $SourceGroups `
        -DifferenceObject $TargetGroups `
        -IncludeEqual |
        Where-Object SideIndicator -eq "==" |
        Select-Object -ExpandProperty InputObject

    # Groups only source user has
    $SourceOnlyGroups = Compare-Object `
        -ReferenceObject $SourceGroups `
        -DifferenceObject $TargetGroups |
        Where-Object SideIndicator -eq "<=" |
        Select-Object -ExpandProperty InputObject

    # Groups only target user has
    $TargetOnlyGroups = Compare-Object `
        -ReferenceObject $SourceGroups `
        -DifferenceObject $TargetGroups |
        Where-Object SideIndicator -eq "=>" |
        Select-Object -ExpandProperty InputObject

    Write-Host ""
    Write-Host "====================================="
    Write-Host "       AD ACCESS COMPARISON"
    Write-Host "====================================="
    Write-Host ""

    Write-Host "SOURCE USER"
    Write-Host "Name:       $($Source.DisplayName)"
    Write-Host "Username:   $SourceUser"
    Write-Host "Department: $($Source.Department)"
    Write-Host "Title:      $($Source.Title)"

    Write-Host ""

    Write-Host "TARGET USER"
    Write-Host "Name:       $($Target.DisplayName)"
    Write-Host "Username:   $TargetUser"
    Write-Host "Department: $($Target.Department)"
    Write-Host "Title:      $($Target.Title)"

    Write-Host ""
    Write-Host "===== SHARED GROUPS ====="

    if ($SharedGroups) {
        $SharedGroups | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        Write-Host "No shared groups found."
    }

    Write-Host ""
    Write-Host "===== GROUPS SOURCE HAS THAT TARGET DOES NOT ====="

    if ($SourceOnlyGroups) {
        $SourceOnlyGroups | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        Write-Host "No additional source-user groups found."
    }

    Write-Host ""
    Write-Host "===== GROUPS TARGET HAS THAT SOURCE DOES NOT ====="

    if ($TargetOnlyGroups) {
        $TargetOnlyGroups | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        Write-Host "No additional target-user groups found."
    }

    # Build report
    $Results = @()

    foreach ($Group in $SharedGroups) {
        $Results += [PSCustomObject]@{
            GroupName = $Group
            Status    = "Shared"
        }
    }

    foreach ($Group in $SourceOnlyGroups) {
        $Results += [PSCustomObject]@{
            GroupName = $Group
            Status    = "Source Only"
        }
    }

    foreach ($Group in $TargetOnlyGroups) {
        $Results += [PSCustomObject]@{
            GroupName = $Group
            Status    = "Target Only"
        }
    }

    $ReportPath =
        "$ReportFolder\$($SourceUser)_vs_$($TargetUser)_$Timestamp.csv"

    $Results |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation

    $Message =
        "Compared AD access: $SourceUser vs $TargetUser"

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $Message"

    Write-Host ""
    Write-Host "Comparison complete."
    Write-Host "Report saved to:"
    Write-Host $ReportPath
}
catch {

    $ErrorMessage =
        "FAILED comparison: $SourceUser vs $TargetUser - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
