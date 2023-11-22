
# Elevate if needed

If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Write-Host "You didn't run this script as an Administrator. This script will self elevate to run as an Administrator and continue."
    Start-Sleep 1
    Write-Host "                                               3"
    Start-Sleep 1
    Write-Host "                                               2"
    Start-Sleep 1
    Write-Host "                                               1"
    Start-Sleep 1
    Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

#no errors throughout
$ErrorActionPreference = 'silentlycontinue'


# Remove Wallpapers
Remove-Item C:\Windows\Web\Wallpaper\*.* -ErrorAction SilentlyContinue
Remove-Item C:\Windows\System32\oobe\INFO\BACKGROUNDS\*.* -ErrorAction SilentlyContinue

# Allow Remote Desktop
(Get-WmiObject -Class "Win32_TerminalServiceSetting" -Namespace root\cimv2\terminalservices).SetAllowTsConnections(1) 
(Get-WmiObject -class "Win32_TSGeneralSetting" -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(1) 
netsh advfirewall Firewall set rule group="Remote Desktop" new enable=yes

# Set UAC to Low
Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA -Value 1
Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\policies\system -Name PromptOnSecureDesktop -Value 0

# Set Windows Updates to Auto Download and Install
$AUSettings=(New-Object -ComObject "Microsoft.Update.AutoUpdate").Settings
$AUSettings.NotificationLevel = 4
$AUSettings.ScheduledInstallationDay=0
$AUSettings.ScheduledInstallationTime=1
$AUSettings.IncludeRecommendedUpdates=$true
$AUSettings.Save()

# Disable Power Saving on NIC
$PhysicalAdapter = Get-WmiObject -Class Win32_NetworkAdapter|Where-Object{$_.PNPDeviceID -notlike "ROOT\*" -and $_.Manufacturer -ne "Microsoft" -and $_.ConfigManagerErrorCode -eq 0 -and $_.ConfigManagerErrorCode -ne 22} 
$PhysicalAdapterName = $PhysicalAdapter.Name
$DeviceID = $PhysicalAdapter.DeviceID
If([Int32]$DeviceID -lt 10) {
	$AdapterDeviceNumber = "000"+$DeviceID
	} Else {
	$AdapterDeviceNumber = "00"+$DeviceID
	}

#check whether the registry path exists.
$KeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}\$AdapterDeviceNumber"
Set-ItemProperty -Path $KeyPath -Name "PnPCapabilities" -Value 56

#Disable PIN
$KeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
if(!(Test-Path $KeyPath)) {
	New-Item -Path $KeyPath -Force | Out-Null
	New-ItemProperty -Path $KeyPath -Name Enabled -Value 0 -PropertyType DWORD -Force | Out-Null
} else {
	New-ItemProperty -Path $KeyPath -Name Enabled -Value 0 -PropertyType DWORD -Force | Out-Null
}

#Delete existing pins
$passportFolder = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"
 
if(Test-Path -Path $passportFolder)
{
Takeown /f $passportFolder /r /d "Y"
ICACLS $passportFolder /reset /T /C /L /Q
 
Remove-Item –path $passportFolder –recurse -force
}

# Auto Enroll MDM
$KeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
if(!(Test-Path $KeyPath)) {
	New-Item -Path $KeyPath -Force | Out-Null
	New-ItemProperty -Path $KeyPath -Name AutoEnrollMDM  -Value 1 -PropertyType DWORD -Force | Out-Null
} else {
	New-ItemProperty -Path $KeyPath -Name AutoEnrollMDM  -Value 1 -PropertyType DWORD -Force | Out-Null
} 
$KeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
if(!(Test-Path $KeyPath)) {
	New-Item -Path $KeyPath -Force | Out-Null
	New-ItemProperty -Path $KeyPath -Name UseAADCredentialType  -Value 1 -PropertyType DWORD -Force | Out-Null
} else {
	New-ItemProperty -Path $KeyPath -Name UseAADCredentialType  -Value 1 -PropertyType DWORD -Force | Out-Null
} 

# Set Background to Black
Add-Type @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;
namespace Wallpaper
{
   public enum Style : int
   {
       Tile, Center, Stretch, NoChange
   }
   public class Setter {
      public const int SetDesktopWallpaper = 20;
      public const int UpdateIniFile = 0x01;
      public const int SendWinIniChange = 0x02;
      [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
      private static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
      public static void SetWallpaper ( string path, Wallpaper.Style style ) {
         SystemParametersInfo( SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange );
         RegistryKey key = Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
         switch( style )
         {
            case Style.Stretch :
               key.SetValue(@"WallpaperStyle", "2") ; 
               key.SetValue(@"TileWallpaper", "0") ;
               break;
            case Style.Center :
               key.SetValue(@"WallpaperStyle", "1") ; 
               key.SetValue(@"TileWallpaper", "0") ; 
               break;
            case Style.Tile :
               key.SetValue(@"WallpaperStyle", "1") ; 
               key.SetValue(@"TileWallpaper", "1") ;
               break;
            case Style.NoChange :
               break;
         }
         key.Close();
      }
   }
}
"@

[Wallpaper.Setter]::SetWallpaper( '', 0 )

# Delete Desktop Icons
Remove-Item $env:PUBLIC\Desktop\*.*

# Disable Offline Files
$objWMI = [wmiclass]"\\localhost\root\cimv2:win32_offlinefilescache"
$objWMI.Enable($false)

# Change Hybernation depending upon Laptop or Desktop
[int[]]$chassisType = Get-CimInstance Win32_SystemEnclosure | Select-Object -ExpandProperty ChassisTypes

switch ($chassisType) {
	{ $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 17, 23 } {
		Write-Host 'Desktop, AIO or Server – Disabling Hibernation'
		POWERCFG /h off
		}
	{ $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 } {
		Write-Host 'Laptop or Tablet – Enabling Hibernation '
		POWERCFG /h on
	}
	Default {
		Write-Warning ("Chassistype is {0}" -f $chassisType)
	}
}

#Change power plan for on battery (DC) or plugged in (AC)
POWERCFG /x monitor-timeout-ac 0
POWERCFG /x monitor-timeout-dc 15
POWERCFG /x disk-timeout-ac 0
POWERCFG /x disk-timeout-dc 15
POWERCFG /x standby-timeout-ac 0
POWERCFG /x standby-timeout-dc 15


