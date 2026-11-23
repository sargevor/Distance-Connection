# server-power-settings.ps1
# Run in PowerShell as Administrator.
# Keeps the Windows host awake while plugged in (screen may still turn off).

powercfg /change standby-timeout-ac 0      # never sleep
powercfg /change hibernate-timeout-ac 0    # never hibernate
powercfg /hibernate off                    # disable hibernation entirely
powercfg /change monitor-timeout-ac 10     # screen off after 10 min (fine for a server)

Write-Host "Current sleep setting (0x00000000 = never):"
powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String "Current AC Power Setting Index"

Write-Host ""
Write-Host "Also do by hand:"
Write-Host " - Device Manager > Network adapters > Power Management > untick 'Allow the computer to turn off this device'"
Write-Host " - Windows Update > Advanced options > wide Active hours + 'Notify me when a restart is required'"
Write-Host " - BIOS/UEFI: 'Restore on AC Power Loss' = Power On"
