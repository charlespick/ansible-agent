#
# Ansible Agent for Windows
# Calls the Ansible Agent relay service to trigger provisioning
#

param(
    [string]$Action = "daemon",
    [string]$ConfigFile = "$env:ProgramFiles\Ansible Agent\config.json"
)

# Global variables
$Global:LogFile = "$env:ProgramData\Ansible Agent\ansible-agent.log"
$Global:LockFile = "$env:ProgramData\Ansible Agent\ansible-agent.lock"

# Default configuration
$Global:Config = @{
    RelayUrl = ""
    IntervalHours = 24
    Enabled = $true
    HostnameOverride = $null
}

# Function to write log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - [$Level] $Message"
    
    Write-Host $logMessage
    
    # Ensure log directory exists
    $logDir = Split-Path $Global:LogFile -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $Global:LogFile -Value $logMessage
}

# Function to load configuration
function Load-Config {
    if (!(Test-Path $ConfigFile)) {
        Write-Log "Configuration file not found: $ConfigFile" "ERROR"
        exit 1
    }
    
    try {
        $configContent = Get-Content $ConfigFile | ConvertFrom-Json
        
        # Update global config with loaded values
        if ($configContent.RelayUrl) { $Global:Config.RelayUrl = $configContent.RelayUrl }
        if ($configContent.IntervalHours) { $Global:Config.IntervalHours = $configContent.IntervalHours }
        if ($configContent.PSObject.Properties.Name -contains "Enabled") { $Global:Config.Enabled = $configContent.Enabled }
        if ($configContent.HostnameOverride) { $Global:Config.HostnameOverride = $configContent.HostnameOverride }
        
    } catch {
        Write-Log "Failed to parse configuration file: $_" "ERROR"
        exit 1
    }
    
    # Validate required configuration
    if ([string]::IsNullOrWhiteSpace($Global:Config.RelayUrl)) {
        Write-Log "RelayUrl not configured in $ConfigFile" "ERROR"
        exit 1
    }
    
    if (!$Global:Config.Enabled) {
        Write-Log "Agent is disabled in configuration" "INFO"
        exit 0
    }
}

# Function to get hostname
function Get-ComputerHostname {
    if ($Global:Config.HostnameOverride) {
        return $Global:Config.HostnameOverride
    }
    
    try {
        return [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
    } catch {
        return $env:COMPUTERNAME.ToLower()
    }
}

# Function to calculate delay based on hostname hash
function Get-DelayFromHostname {
    param([string]$Hostname)
    
    $intervalSeconds = $Global:Config.IntervalHours * 3600
    
    # Create SHA256 hash of hostname
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Hostname))
    
    # Use last 4 bytes as integer
    $hashInt = [BitConverter]::ToUInt32($hash, $hash.Length - 4)
    $delay = $hashInt % $intervalSeconds
    
    return $delay
}

# Function to make callback to relay service
function Invoke-RelayCallback {
    param([string]$Hostname, [string]$RelayUrl)
    
    Write-Log "Making callback for hostname: $Hostname"
    
    $body = @{ hostname = $Hostname } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$RelayUrl/provision" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 60
        
        Write-Log "Callback successful: $($response | ConvertTo-Json -Compress)"
        return $true
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $responseBody = ""
        
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()
            } catch { }
        }
        
        switch ($statusCode) {
            200 {
                Write-Log "Callback successful: $responseBody"
                return $true
            }
            429 {
                Write-Log "Rate limited by relay service" "WARN"
                return $true
            }
            400 {
                Write-Log "Bad request - invalid hostname format" "ERROR"
                return $false
            }
            500 {
                Write-Log "Relay service internal error: $responseBody" "ERROR"
                return $false
            }
            default {
                Write-Log "Unexpected HTTP response code: $statusCode, body: $responseBody" "ERROR"
                return $false
            }
        }
    }
}

# Function to check if another instance is running
function Test-InstanceLock {
    if (Test-Path $Global:LockFile) {
        try {
            $lockContent = Get-Content $Global:LockFile
            $pid = [int]$lockContent
            
            $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($process) {
                Write-Log "Another instance is already running (PID: $pid)"
                exit 0
            } else {
                Write-Log "Removing stale lock file"
                Remove-Item $Global:LockFile -Force
            }
        } catch {
            Remove-Item $Global:LockFile -Force
        }
    }
    
    # Create lock file with current PID
    $lockDir = Split-Path $Global:LockFile -Parent
    if (!(Test-Path $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }
    
    Set-Content -Path $Global:LockFile -Value $PID
    
    # Register cleanup on exit
    Register-EngineEvent PowerShell.Exiting -Action {
        if (Test-Path $Global:LockFile) {
            Remove-Item $Global:LockFile -Force
        }
    }
}

# Function to run as daemon
function Start-Daemon {
    Write-Log "Starting Ansible Agent daemon"
    
    while ($true) {
        $hostname = Get-ComputerHostname
        $delay = Get-DelayFromHostname -Hostname $hostname
        
        Write-Log "Next callback in $delay seconds ($($Global:Config.IntervalHours)h interval)"
        Start-Sleep -Seconds $delay
        
        # Make the callback
        if (Invoke-RelayCallback -Hostname $hostname -RelayUrl $Global:Config.RelayUrl) {
            Write-Log "Callback completed successfully"
        } else {
            Write-Log "Callback failed, will retry in next cycle" "WARN"
        }
        
        # Calculate remaining time until next full interval
        $intervalSeconds = $Global:Config.IntervalHours * 3600
        $remaining = $intervalSeconds - $delay
        
        if ($remaining -gt 0) {
            Write-Log "Waiting $remaining seconds until next interval"
            Start-Sleep -Seconds $remaining
        }
    }
}

# Function to run once
function Invoke-OneTimeCallback {
    $hostname = Get-ComputerHostname
    Write-Log "Making one-time callback for hostname: $hostname"
    
    if (Invoke-RelayCallback -Hostname $hostname -RelayUrl $Global:Config.RelayUrl) {
        Write-Log "One-time callback completed successfully"
        exit 0
    } else {
        Write-Log "One-time callback failed" "ERROR"
        exit 1
    }
}

# Function to test configuration
function Test-Configuration {
    $hostname = Get-ComputerHostname
    $delay = Get-DelayFromHostname -Hostname $hostname
    
    Write-Host "Hostname: $hostname"
    Write-Host "Relay URL: $($Global:Config.RelayUrl)"
    Write-Host "Interval: $($Global:Config.IntervalHours)h"
    Write-Host "Delay: ${delay}s"
    Write-Host "Config File: $ConfigFile"
    Write-Host "Log File: $($Global:LogFile)"
}

# Main function
function Main {
    # Load configuration
    Load-Config
    
    switch ($Action.ToLower()) {
        "daemon" {
            Test-InstanceLock
            Start-Daemon
        }
        "once" {
            Invoke-OneTimeCallback
        }
        "test" {
            Test-Configuration
        }
        default {
            Write-Host "Usage: .\ansible-agent.ps1 [daemon|once|test]"
            Write-Host "  daemon  - Run as daemon (default)"
            Write-Host "  once    - Make one callback and exit"
            Write-Host "  test    - Test configuration and exit"
            exit 1
        }
    }
}

# Run main function
Main