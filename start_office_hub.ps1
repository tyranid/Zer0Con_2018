Import-Module $PSScriptRoot\desktop_bridge_tools.psm1

Get-DesktopBridgeAppX | ? Name -eq Microsoft.MicrosoftOfficeHub | Select-Object -ExpandProperty Applications | Start-DesktopBridgeAppX
