Import-Module ActiveDirectory

$Username = Read-Host "Enter the username to unlock"
$LogPath = "C:\Temp\AD-Account-Audit.log"
$Technician = $env:USERNAME

try {

    $User = Get-ADUser `
        -Identity $Username `
        -Properties LockedOut `
        -ErrorAction Stop

    if ($User.LockedOut -eq $true) {

        Unlock-ADAccount `
            -Identity $Username `
            -ErrorAction Stop

        $Message = "Unlocked account: $Username"
        Write-Host $Message
    }
    else {

        $Message = "$Username is not currently locked out"
        Write-Host $Message
    }

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $Message"
}
catch {

    $ErrorMessage = "FAILED for $Username - $($_.Exception.Message)"

    Write-Host $ErrorMessage

    Add-Content `
        -Path $LogPath `
        -Value "$(Get-Date) - Technician: $Technician - $ErrorMessage"
}
