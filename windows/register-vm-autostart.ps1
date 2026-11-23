# register-vm-autostart.ps1
# Run in PowerShell as Administrator.
# Registers a scheduled task that starts the VirtualBox VM headless at Windows startup,
# even before anyone logs in.

param(
    [string]$VmName   = "kasm1",
    [string]$VBoxPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe",
    [string]$TaskName = "Start Kasm VM"
)

if (-not (Test-Path $VBoxPath)) {
    Write-Error "VBoxManage not found at $VBoxPath"
    exit 1
}

$action   = New-ScheduledTaskAction -Execute $VBoxPath -Argument "startvm `"$VmName`" --type headless"
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# The task must run as the Windows user that owns the VM (VirtualBox VMs are per-user).
$cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" `
        -Message "Windows password for the account that owns the VM"

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Highest -Force

Write-Host "Registered '$TaskName'. Restart Windows (without logging in) to test."
Write-Host "If the VM does not start before login, change the trigger to 'At log on' and enable auto sign-in (netplwiz)."
