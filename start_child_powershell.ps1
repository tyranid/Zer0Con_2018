Import-Module $PSScriptRoot\desktop_bridge_tools.psm1

Use-NtObject($p = Get-DesktopBridgeAppX | ? Name -eq Microsoft.MicrosoftOfficeHub `
            | Select-Object -ExpandProperty Applications | Start-DesktopBridgeAppX) {
    Start-DesktopBridgeAppXChild -Process $p -CommandLine "powershell" -BreakawayFlag Disable
    $p.Terminate(0)
} 
