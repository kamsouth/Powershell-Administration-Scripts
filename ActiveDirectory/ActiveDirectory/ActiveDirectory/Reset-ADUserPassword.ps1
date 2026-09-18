Import-Module ActiveDirectory

$Username = Read-Host "Enter the username"
$LogPath = "C:\Temp\AD-Account-Audit.log"
$Technician = $env:USERNAME

try {

    $User = Get-ADUser `
        -Identity $Username `
        -Properties Enabled `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "User found: $($User.Name)"
    Write-Host "Account enabled: $($User.Enabled)"
    Write-Host ""

    $NewPassword = Read-Host `
        "Enter the new temporary password" `
        -AsSecureString

    $Confirm = Read-Host `
        "Reset password for $($User.SamAccountName)? (Y/N)"

    if ($Confirm -ne "Y") {
        Write-Host "Password reset cancelled."
        return
    }

    Set-ADAccountPassword `
        -Identity $Username `
        -Reset `
        -NewPassword $NewPassword `
        -ErrorAction Stop

    Set-ADUser `
        -Identity $Username `
        -ChangePasswordAtLogon $true `
        -ErrorAction Stop

    $Message = "Password reset completed for $Username. Change at next logon enabled."

    Write-Host $Message

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $Message"
}
catch {

    $ErrorMessage =
        "FAILED password reset for $Username - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
