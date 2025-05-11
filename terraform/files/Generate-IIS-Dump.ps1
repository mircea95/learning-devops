#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automatically generates a memory dump for a deployed IIS website.
.DESCRIPTION
    This script identifies the worker process for a specified IIS website and
    creates a memory dump file. It requires administrator privileges to run.
.PARAMETER SiteName
    The name of the IIS website to dump. If not specified, the script will attempt to use the default website.
.PARAMETER DumpFolder
    The folder where the dump file will be saved. Defaults to C:\IIS-Dumps.
.PARAMETER DumpType
    The type of dump to create: Full or Mini. Defaults to Mini.
.EXAMPLE
    .\Generate-IIS-Dump.ps1 -SiteName "Default Web Site"
.EXAMPLE
    .\Generate-IIS-Dump.ps1 -SiteName "MyWebApp" -DumpFolder "D:\Diagnostics\Dumps" -DumpType "Full"
#>

param (
    [string]$SiteName = "",
    [string]$DumpFolder = "C:\IIS-Dumps",
    [ValidateSet("Mini", "Full")]
    [string]$DumpType = "Mini"
)

# Function to log messages with timestamp
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
    Add-Content -Path "$DumpFolder\dump_log.txt" -Value "[$timestamp] $Message"
}

# Check for administrative privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script requires administrator privileges." -ForegroundColor Red
    exit 1
}

# Create dump folder if it doesn't exist
if (-not (Test-Path -Path $DumpFolder)) {
    try {
        New-Item -Path $DumpFolder -ItemType Directory -Force | Out-Null
        Write-Log "Created dump folder: $DumpFolder"
    }
    catch {
        Write-Host "Error: Failed to create dump folder: $_" -ForegroundColor Red
        exit 1
    }
}

# Ensure IIS Module is available
try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Log "Successfully imported WebAdministration module"
}
catch {
    Write-Log "Error: WebAdministration module not available. Trying to install..."
    try {
        Install-WindowsFeature Web-Scripting-Tools -ErrorAction Stop
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "Successfully installed and imported WebAdministration module"
    }
    catch {
        Write-Log "Error: Failed to install WebAdministration module: $_"
        exit 1
    }
}

# Get website information
try {
    # If site name not provided, try to get the default website
    if ([string]::IsNullOrEmpty($SiteName)) {
        $website = Get-Website | Select-Object -First 1
        if ($website) {
            $SiteName = $website.Name
            Write-Log "No site name provided. Using first website found: $SiteName"
        }
        else {
            Write-Log "Error: No websites found on this server."
            exit 1
        }
    }
    else {
        $website = Get-Website -Name $SiteName -ErrorAction Stop
        Write-Log "Found website: $SiteName"
    }
}
catch {
    Write-Log "Error: Failed to get website information for '$SiteName': $_"
    exit 1
}

# Get worker process information
try {
    # Get application pool name
    $appPoolName = $website.applicationPool
    Write-Log "Website '$SiteName' is using application pool: $appPoolName"

    # Get worker process ID - using more reliable methods
    $workerProcesses = $null

    # Method 1: Try to get worker processes using appcmd
    try {
        $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
        if (Test-Path $appcmd) {
            Write-Log "Trying to get worker process using appcmd..."
            $appcmdOutput = & $appcmd list wp
            if ($appcmdOutput) {
                # Parse the output to find the process ID for our app pool
                $wpInfo = $appcmdOutput | Where-Object { $_ -match "APP_POOL_CONFIG:$appPoolName" }
                if ($wpInfo) {
                    $pidMatch = $wpInfo | Select-String -Pattern 'PID:(\d+)'
                    if ($pidMatch -and $pidMatch.Matches.Groups.Count -gt 1) {
                        $processId = $pidMatch.Matches.Groups[1].Value
                        Write-Log "Found worker process with PID: $processId using appcmd"
                    }
                }
            }
        }
    } catch {
        Write-Log "Could not get worker process using appcmd: $_"
    }

    # Method 2: If we don't have a process ID yet, try using Get-Process and command line filtering
    if (-not $processId) {
        Write-Log "Trying to get worker process using Get-Process and command line inspection..."
        $w3wpProcesses = Get-Process -Name w3wp -ErrorAction SilentlyContinue | Where-Object {$_ -ne $null}

        if ($w3wpProcesses) {
            # If we have multiple w3wp processes, try to find the one for our app pool
            foreach ($process in $w3wpProcesses) {
                # Get command line for the process
                $commandLine = $null
                try {
                    $wmiProcess = Get-WmiObject -Class Win32_Process -Filter "ProcessId = $($process.Id)"
                    $commandLine = $wmiProcess.CommandLine
                    if ($commandLine -match [regex]::Escape("-ap `"$appPoolName`"")) {
                        $processId = $process.Id
                        Write-Log "Found worker process with PID: $processId for app pool $appPoolName"
                        break
                    }
                } catch {
                    Write-Log "Error getting command line for process $($process.Id): $_"
                }
            }

            # If we still don't have a process ID, just use the first w3wp process
            if (-not $processId -and $w3wpProcesses.Count -gt 0) {
                $processId = $w3wpProcesses[0].Id
                Write-Log "Could not identify exact process for app pool. Using first w3wp process found with PID: $processId"
            }
        }
    }

    # Final fallback - if we still don't have any worker processes
    if (-not $processId) {
        Write-Log "Warning: No active worker processes found for application pool '$appPoolName'."
        Write-Log "Error: No IIS worker processes (w3wp.exe) found."
        exit 1
    }
}
catch {
    Write-Log "Error: Failed to get worker process information: $_"
    exit 1
}

# Create timestamp for dump filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
# Clean site name for filename (remove invalid characters)
$cleanSiteName = $SiteName -replace '[\\/:*?"<>|]', '_'
$dumpFileName = "$DumpFolder\IIS_$cleanSiteName`_$timestamp.dmp"

# Set dump type parameter
$dumpTypeParam = if ($DumpType -eq "Full") { "/ma" } else { "/mm" }

# Generate dump file using procdump
try {
    # Check if procdump is available
    $procdumpPath = "$env:ProgramFiles\SysinternalsSuite\procdump.exe"
    if (-not (Test-Path -Path $procdumpPath)) {
        $procdumpPath = "$env:windir\System32\procdump.exe"
        if (-not (Test-Path -Path $procdumpPath)) {
            # Download procdump if not available
            Write-Log "Procdump not found. Downloading from Microsoft..."
            $tempDir = [System.IO.Path]::GetTempPath()
            $procdumpZip = Join-Path $tempDir "procdump.zip"
            $procdumpFolder = Join-Path $tempDir "procdump"

            # Create the download URL
            $procdumpUrl = "https://download.sysinternals.com/files/Procdump.zip"

            # Download the file
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $procdumpUrl -OutFile $procdumpZip

            # Extract the zip file
            if (-not (Test-Path -Path $procdumpFolder)) {
                New-Item -Path $procdumpFolder -ItemType Directory -Force | Out-Null
            }
            Expand-Archive -Path $procdumpZip -DestinationPath $procdumpFolder -Force

            # Set the path to the extracted procdump.exe
            $procdumpPath = Join-Path $procdumpFolder "procdump.exe"
            Write-Log "Procdump downloaded to: $procdumpPath"
        }
    }

    Write-Log "Generating $DumpType dump file using procdump..."
    $procdumpCommand = "& '$procdumpPath' -accepteula $dumpTypeParam $processId '$dumpFileName'"
    Write-Log "Executing: $procdumpCommand"

    # Execute procdump command
    $result = Invoke-Expression $procdumpCommand
    Write-Log "Procdump output: $result"

    if (Test-Path -Path $dumpFileName) {
        Write-Log "Successfully created dump file: $dumpFileName"
        Write-Host "Dump file created successfully at: $dumpFileName" -ForegroundColor Green
    }
    else {
        Write-Log "Error: Dump file was not created."
        Write-Host "Error: Dump file was not created." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Log "Error: Failed to generate dump file: $_"
    Write-Host "Error: Failed to generate dump file: $_" -ForegroundColor Red
    exit 1
}

Write-Log "Script execution completed successfully."
Write-Host "IIS dump generation completed successfully." -ForegroundColor Green