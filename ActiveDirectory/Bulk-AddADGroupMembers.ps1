Import-Module ActiveDirectory

$Group = Read-Host "Enter the AD group name"

$UserInput = Read-Host "Enter usernames separated by commas"

$Users = $UserInput -split "," |
    ForEach-Object { $_.Trim() }

$LogPath = "C:\Temp\RBAC-Group-Audit.log"

foreach ($User in $Users) {

    try {

        $ADUser = Get-ADUser `
            -Identity $User `
            -ErrorAction Stop

        $AlreadyMember = Get-ADGroupMember `
            -Identity $Group |
            Where-Object {
                $_.SamAccountName -eq $User
            }

        if ($AlreadyMember) {

            $Message =
                "$User is already a member of $Group"
        }

        else {

            Add-ADGroupMember `
                -Identity $Group `
                -Members $User `
                -ErrorAction Stop

            $Message =
                "Added $User to $Group"
        }

        Write-Host $Message

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - $Message"
    }

    catch {

        $ErrorMessage =
            "FAILED for $User - $($_.Exception.Message)"

        Write-Host $ErrorMessage

        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date) - $ErrorMessage"
    }
}
