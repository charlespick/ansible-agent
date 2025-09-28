# Installation Guide

## Relay Service Installation

### Kubernetes (Recommended)

1. **Prepare configuration:**
   ```bash
   # Edit the secret with your AWX credentials
   # Base64 encode your values first:
   echo -n "https://your-awx.example.com" | base64
   
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/secret.yaml      # Edit this first!
   kubectl apply -f k8s/configmap.yaml
   ```

2. **Deploy the service:**
   ```bash
   kubectl apply -f k8s/rbac.yaml
   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   kubectl apply -f k8s/ingress.yaml     # Edit domain first!
   ```

3. **Verify deployment:**
   ```bash
   kubectl -n ansible-system get pods
   kubectl -n ansible-system get svc
   curl -k https://ansible-agent.your-domain.com/health
   ```

### Docker

1. **Create environment file:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Run with Docker:**
   ```bash
   docker build -t ansible-agent .
   docker run -d --name ansible-agent \
     --env-file .env \
     -p 5000:5000 \
     ansible-agent
   ```

### Virtual Environment

1. **Set up Python environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Run the service:**
   ```bash
   # Development
   python src/ansible_agent/app.py
   
   # Production with gunicorn
   gunicorn --bind 0.0.0.0:5000 --workers 4 ansible_agent.app:app
   ```

## Linux Agent Installation

### Automated Installation

1. **Download and extract:**
   ```bash
   wget https://github.com/charlespick/ansible-agent/releases/latest/download/ansible-agent-linux-latest.tar.gz
   tar -xzf ansible-agent-linux-latest.tar.gz
   cd ansible-agent-linux
   ```

2. **Install as root:**
   ```bash
   sudo ./install.sh
   ```

3. **Configure:**
   ```bash
   sudo vi /etc/ansible-agent/config.conf
   # Set RELAY_URL to your relay service URL
   ```

4. **Enable and start:**
   ```bash
   sudo systemctl enable ansible-agent
   sudo systemctl start ansible-agent
   sudo systemctl status ansible-agent
   ```

### Manual Installation

1. **Create user and directories:**
   ```bash
   sudo useradd -r -s /bin/false ansible-agent
   sudo mkdir -p /opt/ansible-agent /etc/ansible-agent
   ```

2. **Copy files:**
   ```bash
   sudo cp ansible-agent /opt/ansible-agent/
   sudo cp config.conf /etc/ansible-agent/
   sudo chmod 755 /opt/ansible-agent/ansible-agent
   sudo chmod 640 /etc/ansible-agent/config.conf
   ```

3. **Create systemd service:**
   ```bash
   sudo cp ansible-agent.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

### Configuration

Edit `/etc/ansible-agent/config.conf`:
```bash
RELAY_URL="https://your-relay-service.com"
INTERVAL_HOURS=24
ENABLED=true
```

### Management

```bash
# Start/stop service
sudo systemctl start ansible-agent
sudo systemctl stop ansible-agent
sudo systemctl restart ansible-agent

# View status and logs
sudo systemctl status ansible-agent
sudo journalctl -u ansible-agent -f

# Test configuration
sudo -u ansible-agent /opt/ansible-agent/ansible-agent test

# Run once manually
sudo -u ansible-agent /opt/ansible-agent/ansible-agent once
```

## Windows Agent Installation

### Automated Installation

1. **Download and extract:**
   Download `ansible-agent-windows-latest.zip` from the releases page and extract to a folder.

2. **Run installer as Administrator:**
   ```powershell
   # Open PowerShell as Administrator
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   .\install.ps1
   ```

3. **Configure:**
   Edit `C:\Program Files\Ansible Agent\config.json`:
   ```json
   {
       "RelayUrl": "https://your-relay-service.com",
       "IntervalHours": 24,
       "Enabled": true,
       "HostnameOverride": null
   }
   ```

4. **Start service:**
   ```powershell
   Start-Service -Name AnsibleAgent
   Get-Service -Name AnsibleAgent
   ```

### Manual Installation

1. **Create directories:**
   ```powershell
   New-Item -ItemType Directory -Path "$env:ProgramFiles\Ansible Agent" -Force
   New-Item -ItemType Directory -Path "$env:ProgramData\Ansible Agent" -Force
   ```

2. **Copy files:**
   ```powershell
   Copy-Item "ansible-agent.ps1" "$env:ProgramFiles\Ansible Agent\"
   Copy-Item "config.json" "$env:ProgramFiles\Ansible Agent\"
   ```

3. **Create Windows service:**
   ```powershell
   $servicePath = "powershell.exe"
   $serviceArgs = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:ProgramFiles\Ansible Agent\ansible-agent.ps1`" daemon"
   sc.exe create AnsibleAgent binPath= "$servicePath $serviceArgs" DisplayName= "Ansible Agent" start= auto
   ```

### Management

```powershell
# Start/stop service
Start-Service -Name AnsibleAgent
Stop-Service -Name AnsibleAgent
Restart-Service -Name AnsibleAgent

# View service status
Get-Service -Name AnsibleAgent

# View logs
Get-EventLog -LogName Application -Source "Ansible Agent" -Newest 10

# Test configuration
& "$env:ProgramFiles\Ansible Agent\ansible-agent.ps1" test

# Run once manually
& "$env:ProgramFiles\Ansible Agent\ansible-agent.ps1" once
```

## Troubleshooting

### Common Issues

**Service won't start:**
- Check configuration file syntax
- Verify relay service URL is accessible
- Check system logs for errors

**Agent not checking in:**
- Verify network connectivity to relay service
- Check rate limiting settings
- Verify hostname is valid

**Permission denied errors (Linux):**
- Ensure ansible-agent user exists
- Check file ownership and permissions
- Verify systemd service configuration

**PowerShell execution policy (Windows):**
- Set execution policy: `Set-ExecutionPolicy RemoteSigned`
- Or run with `-ExecutionPolicy Bypass`

### Logs

**Linux:**
```bash
# Service logs
journalctl -u ansible-agent -f

# Application logs
tail -f /var/log/ansible-agent.log
```

**Windows:**
```powershell
# Service logs
Get-EventLog -LogName Application -Source "Ansible Agent" -Newest 20

# Application logs
Get-Content "$env:ProgramData\Ansible Agent\ansible-agent.log" -Tail 20 -Wait
```