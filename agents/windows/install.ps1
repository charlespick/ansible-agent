#
# Ansible Agent Windows Installation Script
# Requires Administrator privileges
#

param(
    [string]$Action = "install"
)

# Configuration
$ServiceName = "AnsibleAgent"
$ServiceDisplayName = "Ansible Agent"
$InstallPath = "$env:ProgramFiles\Ansible Agent"
$ConfigPath = "$InstallPath\config.json"
$DataPath = "$env:ProgramData\Ansible Agent"

# Function to test if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to write colored output
function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    
    switch ($Type) {
        "Info" { Write-Host "[INFO] $Message" -ForegroundColor Green }
        "Warn" { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        "Error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
    }
}

# Function to install the agent
function Install-Agent {
    Write-Status "Installing Ansible Agent..."
    
    # Check if running as administrator
    if (!(Test-Administrator)) {
        Write-Status "This script must be run as Administrator" "Error"
        exit 1
    }
    
    # Create directories
    Write-Status "Creating directories..."
    if (!(Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    if (!(Test-Path $DataPath)) {
        New-Item -ItemType Directory -Path $DataPath -Force | Out-Null
    }
    
    # Copy agent script
    Write-Status "Installing agent script..."
    Copy-Item "ansible-agent.ps1" "$InstallPath\" -Force
    
    # Copy configuration template if it doesn't exist
    if (!(Test-Path $ConfigPath)) {
        Copy-Item "config.json" "$ConfigPath" -Force
        Write-Status "Installed configuration template"
        Write-Status "Please edit $ConfigPath to configure the agent" "Warn"
    } else {
        Write-Status "Configuration file already exists, not overwriting"
    }
    
    # Create Windows service
    Write-Status "Creating Windows service..."
    
    $servicePath = "powershell.exe"
    $serviceArguments = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallPath\ansible-agent.ps1`" daemon"
    
    # Remove existing service if it exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Status "Removing existing service..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
    
    # Create new service
    $result = sc.exe create $ServiceName binPath= "$servicePath $serviceArguments" DisplayName= $ServiceDisplayName start= auto
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to create service: $result" "Error"
        exit 1
    }
    
    # Set service description
    sc.exe description $ServiceName "Ansible Agent - Callbacks to AWX for configuration management" | Out-Null
    
    # Configure service recovery
    sc.exe failure $ServiceName reset= 86400 actions= restart/30000/restart/60000/restart/120000 | Out-Null
    
    Write-Status "Service created successfully"
    
    Show-PostInstallInstructions
}

# Function to uninstall the agent
function Uninstall-Agent {
    Write-Status "Uninstalling Ansible Agent..."
    
    # Check if running as administrator
    if (!(Test-Administrator)) {
        Write-Status "This script must be run as Administrator" "Error"
        exit 1
    }
    
    # Stop and remove service
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Status "Stopping and removing service..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
    }
    
    # Remove installation directory
    if (Test-Path $InstallPath) {
        Write-Status "Removing installation directory..."
        Remove-Item $InstallPath -Recurse -Force
    }
    
    # Remove data directory
    if (Test-Path $DataPath) {
        Write-Status "Removing data directory..."
        Remove-Item $DataPath -Recurse -Force
    }
    
    Write-Status "Uninstallation completed"
}

# Function to show post-installation instructions
function Show-PostInstallInstructions {
    Write-Status "Installation completed successfully!"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Edit the configuration file: $ConfigPath"
    Write-Host "2. Set your relay service URL and other settings"
    Write-Host "3. Start the service:"
    Write-Host "   Start-Service -Name $ServiceName"
    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  Get-Service -Name $ServiceName     - Check service status"
    Write-Host "  Get-EventLog -LogName Application -Source $ServiceDisplayName - View service logs"
    Write-Host "  & '$InstallPath\ansible-agent.ps1' test - Test configuration"
    Write-Host "  & '$InstallPath\ansible-agent.ps1' once - Run once manually"
    Write-Host ""
    Write-Host "Service Management:"
    Write-Host "  Start-Service -Name $ServiceName   - Start the service"
    Write-Host "  Stop-Service -Name $ServiceName    - Stop the service"
    Write-Host "  Restart-Service -Name $ServiceName - Restart the service"
    Write-Host ""
}

# Function to show service status
function Show-ServiceStatus {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Service Status: $($service.Status)"
        Write-Host "Service Name: $($service.Name)"
        Write-Host "Display Name: $($service.DisplayName)"
        
        # Show recent logs
        Write-Host "`nRecent logs:"
        try {
            $logs = Get-EventLog -LogName Application -Source $ServiceDisplayName -Newest 5 -ErrorAction SilentlyContinue
            $logs | ForEach-Object {
                Write-Host "[$($_.TimeGenerated)] $($_.EntryType): $($_.Message)"
            }
        } catch {
            Write-Host "No recent logs found"
        }
    } else {
        Write-Host "Service not found"
    }
}

# Main function
function Main {
    switch ($Action.ToLower()) {
        "install" {
            Install-Agent
        }
        "uninstall" {
            Uninstall-Agent
        }
        "status" {
            Show-ServiceStatus
        }
        default {
            Write-Host "Usage: .\install.ps1 [install|uninstall|status]"
            Write-Host "  install   - Install the Ansible Agent (default)"
            Write-Host "  uninstall - Remove the Ansible Agent"
            Write-Host "  status    - Show service status"
            exit 1
        }
    }
}

# Run main function
Main