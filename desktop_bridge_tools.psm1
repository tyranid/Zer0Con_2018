#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
Import-Module NtObjectManager

function Check-FullTrust {
    param([xml]$Manifest)
    if ($Manifest -eq $null) {
        return $false
    }
    $nsmgr = [System.Xml.XmlNamespaceManager]::new($Manifest.NameTable)
    $nsmgr.AddNamespace("rescap", "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities")
    $Manifest.SelectSingleNode("//rescap:Capability[@Name='runFullTrust']", $nsmgr) -ne $null
}

function Get-AppExtensions {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [xml]$Manifest
    )
    PROCESS {
        if ($Manifest -eq $null) {
            return
        }
        $nsmgr = [System.Xml.XmlNamespaceManager]::new($Manifest.NameTable)
        $nsmgr.AddNamespace("desktop", "http://schemas.microsoft.com/appx/manifest/desktop/windows10")
        $nodes = $Manifest.SelectNodes("//desktop:Extension[@Category='windows.fullTrustProcess']", $nsmgr)
        foreach($node in $nodes) {
            Write-Output $node.GetAttribute("Executable")
        }
    }
}

function Get-FullTrustApplications {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [xml]$Manifest,
        [parameter(Mandatory)]
        [string]$PackageFamilyName
    )
    PROCESS {
        if ($Manifest -eq $null) {
            return
        }
        $nsmgr = [System.Xml.XmlNamespaceManager]::new($Manifest.NameTable)
        $nsmgr.AddNamespace("app", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
        $nodes = $Manifest.SelectNodes("//app:Application[@EntryPoint='Windows.FullTrustApplication']", $nsmgr)
        foreach($node in $nodes) {
            $id = $node.GetAttribute("Id")
            $props = @{
                ApplicationUserModelId="$PackageFamilyName!$id";
                Executable=$node.GetAttribute("Executable");
            }

            Write-Output $(New-Object psobject -Property $props)
        }
    }
}

function Read-DesktopAppxManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        $Package,
        [switch]$AllUsers
    )
    PROCESS {
        $Manifest = Get-AppxPackageManifest $Package
        if (-not $(Check-FullTrust $Manifest)) {
            return
        }
        $install_location = $Package.InstallLocation
        $profile_dir = ""
        if (-not $AllUsers) {
            $profile_dir = "$env:LOCALAPPDATA\Packages\$($Package.PackageFamilyName)"
        }
        $props = @{
            Name=$Package.Name;
            Architecture=$Package.Architecture;
            Version=$Package.Version;
            Publisher=$Package.Publisher;
            PackageFamilyName=$Package.PackageFamilyName;
            InstallLocation=$install_location;
            Manifest=Get-AppxPackageManifest $Package;
            Applications=Get-FullTrustApplications $Manifest $Package.PackageFamilyName;
            Extensions=Get-AppExtensions $Manifest;
            VFSFiles=Get-ChildItem -Recurse "$install_location\VFS";
            HasRegistry=Test-Path "$install_location\registry.dat";
            ProfileDir=$profile_dir;
        }

        New-Object psobject -Property $props
    }
}

<#
.SYNOPSIS
Get a list AppX packages with Desktop Bridge components.
.DESCRIPTION
This cmdlet gets a list of installed AppX packages which are either directly full trust applications or 
have an extension which can be used to run full trust applications.
.PARAMETER AllUsers
Specify getting information for all users, needs admin privileges.
.INPUTS
None
.OUTPUTS
Package results.
.EXAMPLE
Get-DesktopBridgeAppX
Get all desktop bridge AppX packages for current user.
.EXAMPLE
Get-DesktopBridgeAppX -AllUsers
Get all desktop bridge AppX packages for all users.
#>
function Get-DesktopBridgeAppX {
    param([switch]$AllUsers)
    Get-AppxPackage -AllUsers:$AllUsers | Read-DesktopAppxManifest -AllUsers:$AllUsers
}

Export-ModuleMember -Function Get-DesktopBridgeAppX

$src = @"
using NtApiDotNet;
using System;
using System.Runtime.InteropServices;

public enum ActivationOptions
{
    None = 0,
    RunAs = 1,
}

public static class StartDesktopAppx
{

    [Guid("72e3a5b0-8fea-485c-9f8b-822b16dba17f")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDesktopAppXActivator
    {
        void Activate(string applicationUserModelId, string packageRelativeExecutable, string arguments, out SafeKernelObjectHandle processHandle);
        void ActivateWithOptions(string applicationUserModelId, string executable, string arguments, ActivationOptions options, int parentProcessId, out SafeKernelObjectHandle processHandle);
    }

    [Guid("168EB462-775F-42AE-9111-D714B2306C2E")]
    [ComImport]
    class DesktopAppxActivator
    {
    }
    
    public static NtProcess Activate(string applicationUserModelId, string executable, string arguments, ActivationOptions options, int parentProcessId) {
        var appx = (IDesktopAppXActivator)new DesktopAppxActivator();
        SafeKernelObjectHandle handle;
        appx.ActivateWithOptions(applicationUserModelId, executable, arguments, options, parentProcessId, out handle);
        return NtProcess.FromHandle(handle);
    }
}
"@

$asm = [NtApiDotNet.NtProcess].Assembly.Location
Add-Type -TypeDefinition $src -ReferencedAssemblies $asm

<#
.SYNOPSIS
Start a Desktop Bridge AppX.
.DESCRIPTION
This cmdlet starts a Desktop Bridge AppX application.
.PARAMETER ApplicationUserModelId
Specify the application model ID.
.PARAMETER Executable
Specify the executable inside the application to run.
.PARAMETER Arguments
Specify optional arguments to pass to application.
.PARAMETER Options
Specify options for activation.
.PARAMETER ParentProcessId
Specify the parent processs ID for the application.
.INPUTS
None
.OUTPUTS
NtApiDotNet.NtProcess - The started process.
.EXAMPLE
Start-DesktopBridgeAppX "PackageName_xxxxx!App" "RunMe.exe"
Start a desktop bridge application.
.EXAMPLE
Start-DesktopBridgeAppX "PackageName_xxxxx!App" "RunMe.exe" -Arguments "Some Args"
Start a desktop bridge application with arguments.
.EXAMPLE
Get-DesktopBridgeAppx | ? Name -Match MyApp | Start-DesktopBridgeAppX
Start desktop bridge applications via a pipeline.
#>
function Start-DesktopBridgeAppX {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)]
        [string]$ApplicationUserModelId,
        [parameter(Mandatory, Position=1, ValueFromPipelineByPropertyName)]
        [string]$Executable,
        [string]$Arguments,
        [ActivationOptions]$Options = "None",
        [int]$ParentProcessId
    )

    PROCESS {
        [StartDesktopAppx]::Activate($ApplicationUserModelId, $Executable, $Arguments, $Options, $ParentProcessId)
    }
}

Export-ModuleMember -Function Start-DesktopBridgeAppX

<#
.SYNOPSIS
Start a child Desktop Bridge application inside the container.
.DESCRIPTION
This cmdlet starts a new process under the container for an existing Desktop Bridge application.
.PARAMETER Process
The Desktop Bridge application.
.PARAMETER CommandLine
The command line to run.
.PARAMETER BreakawayFlag
Specify an explicit breakaway flag for the process.
.OUTPUTS
NtApiDotNet.NtProcess - The started process.
.EXAMPLE
Start-DesktopBridgeAppXChild $process "notepad"
Start notepad as a child of an existing Desktop Bridge application.
#>
function Start-DesktopBridgeAppXChild {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, Position=0)]
        [NtApiDotNet.NtProcess]$Process,
        [parameter(Mandatory, Position=1)]
        [string]$CommandLine,
        [NtApiDotNet.Win32.ProcessDesktopAppBreakawayFlags]$BreakawayFlag = "Disable"
    )

    $config = New-Win32ProcessConfig $CommandLine
    $config.ParentProcess = $Process
    $config.CreationFlags = "NewConsole"
    $config.DesktopAppBreakaway = $BreakawayFlag

    Use-NtObject ($token = Get-NtToken -Primary -Process $Process) {
        Invoke-NtToken $token {
            Use-NtObject ($new_process = New-Win32Process $config) {
                $new_process.Process.Duplicate()
            }
        }
    }
}

Export-ModuleMember -Function Start-DesktopBridgeAppXChild