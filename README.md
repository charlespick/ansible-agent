# Ansible Agent

A complete system for lightweight configuration management callbacks to AWX, consisting of:

* **Relay Service**: Kubernetes-ready Python Flask app that receives agent callbacks and triggers AWX jobs
* **Linux Agent**: Systemd service that periodically calls back for configuration management
* **Windows Agent**: Windows service that periodically calls back for configuration management

## Features

### 🔒 Secure by Design
- Heavy rate limiting (per-IP and global)
- RFC 1123 compliant hostname validation and sanitization
- Input validation and security filtering
- No authentication required (by design for simplicity)
- Low-privilege AWX credentials recommended

### 🚀 Production Ready
- Container packaging with multi-architecture support
- Kubernetes manifests with RBAC, health checks, and security contexts
- Automated CI/CD with GitHub Actions
- Comprehensive logging and monitoring
- Zero-state service that scales horizontally

### 🖥️ Cross-Platform Agents
- **Linux**: Bash-based agent with systemd integration
- **Windows**: PowerShell-based agent with Windows service
- **No runtime dependencies**: Uses only standard system tools
- **Smart scheduling**: Uses hostname hash to distribute callback times

## Quick Start

### Deploy Relay Service (Kubernetes)

1. Configure your AWX credentials:
   ```bash
   # Edit k8s/secret.yaml with base64 encoded values
   echo -n "https://your-awx.com" | base64
   ```

2. Deploy to Kubernetes:
   ```bash
   kubectl apply -f k8s/
   ```

### Install Linux Agent

```bash
wget https://github.com/charlespick/ansible-agent/releases/latest/download/ansible-agent-linux-latest.tar.gz
tar -xzf ansible-agent-linux-latest.tar.gz
cd ansible-agent-linux
sudo ./install.sh
```

Edit `/etc/ansible-agent/config.conf` and set your relay URL, then:
```bash
sudo systemctl enable --now ansible-agent
```

### Install Windows Agent

Download and extract `ansible-agent-windows-latest.zip`, then run as Administrator:
```powershell
.\install.ps1
```

Edit `C:\Program Files\Ansible Agent\config.json` and set your relay URL, then:
```powershell
Start-Service -Name AnsibleAgent
```

## Architecture

```
┌─────────────────┐    HTTP POST    ┌─────────────────┐    AWX API    ┌─────────────────┐
│  Agent (Linux)  │ ────────────► │  Relay Service  │ ────────────► │      AWX        │
│ Agent (Windows) │   /provision   │   (Flask App)   │   Launch Job  │   Templates     │
└─────────────────┘                └─────────────────┘               └─────────────────┘
```

### How It Works

1. **Agents** run on managed hosts, making periodic callbacks with their hostname
2. **Relay Service** receives callbacks, validates hostnames, and triggers AWX jobs
3. **AWX** executes the job/workflow limited to the calling host
4. **Smart Timing**: Agents use hostname hashing to spread out callback times

## Security Model

Even without authentication, the system remains secure because:

- **Rate Limiting**: 1 call per IP per 5 minutes (configurable)
- **Hostname Validation**: Strict RFC compliance and pattern filtering  
- **Input Sanitization**: All inputs are validated and sanitized
- **Limited Scope**: Only one template/workflow can be triggered
- **Inventory Control**: Hosts must exist in AWX inventory
- **Low Privileges**: AWX credentials should have minimal permissions

## Configuration

### Relay Service Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `AWX_API_ENDPOINT` | AWX API URL | Yes |
| `AWX_USERNAME` / `AWX_PASSWORD` | AWX credentials | Yes* |
| `AWX_TOKEN` | AWX API token (alternative) | Yes* |
| `AWX_TEMPLATE_NAME` | Job template to trigger | Yes** |
| `AWX_WORKFLOW_NAME` | Workflow template to trigger | Yes** |
| `PER_IP_RATE_LIMIT` | Per-IP rate limit | No (default: 1 per 5 minutes) |
| `GLOBAL_RATE_LIMIT` | Global rate limit | No (default: 100 per hour) |

*Either username/password OR token required  
**Either template name OR workflow name required

### Agent Configuration

**Linux**: `/etc/ansible-agent/config.conf`
```bash
RELAY_URL="https://ansible-agent.example.com"
INTERVAL_HOURS=24
ENABLED=true
```

**Windows**: `C:\Program Files\Ansible Agent\config.json`
```json
{
    "RelayUrl": "https://ansible-agent.example.com",
    "IntervalHours": 24,
    "Enabled": true
}
```

## API

### POST /provision
Trigger a provisioning job for a hostname.

**Request:**
```json
{
    "hostname": "server01.example.com"
}
```

**Response:**
```json
{
    "success": true,
    "hostname": "server01.example.com", 
    "job_id": 123,
    "job_type": "template"
}
```

### GET /health
Health check endpoint for load balancers.

## Documentation

- [📖 Installation Guide](docs/INSTALLATION.md)
- [⚙️ Configuration Reference](docs/CONFIGURATION.md)
- [🔌 API Documentation](docs/API.md)

## Development

```bash
# Set up development environment
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# Run tests
pytest

# Run locally
export FLASK_ENV=development
export AWX_API_ENDPOINT=https://your-awx.com
# ... other config
python src/ansible_agent/app.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## License

GPL-3.0 License - see [LICENSE](LICENSE) file. 
