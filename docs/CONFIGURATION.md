# Configuration Schema

## Relay Service Configuration

The relay service is configured via environment variables.

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWX_API_ENDPOINT` | AWX API base URL | `https://awx.example.com` |
| `AWX_USERNAME` | AWX username (if not using token) | `ansible-agent` |
| `AWX_PASSWORD` | AWX password (if not using token) | `secretpassword` |
| `AWX_TOKEN` | AWX API token (alternative to username/password) | `abc123...` |
| `AWX_TEMPLATE_NAME` | Job template name (use this OR workflow name) | `provision-server` |
| `AWX_WORKFLOW_NAME` | Workflow template name (use this OR template name) | `provision-workflow` |

### Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `GLOBAL_RATE_LIMIT` | Global rate limit | `100 per hour` | `200 per hour` |
| `PER_IP_RATE_LIMIT` | Per-IP rate limit | `1 per 5 minutes` | `2 per 10 minutes` |
| `MAX_HOSTNAME_LENGTH` | Maximum hostname length | `253` | `100` |
| `MIN_HOSTNAME_LENGTH` | Minimum hostname length | `1` | `3` |
| `REDIS_URL` | Redis URL for rate limiting | `redis://localhost:6379` | `redis://redis:6379` |
| `PORT` | Service port | `5000` | `8080` |
| `FLASK_ENV` | Flask environment | `production` | `development` |

## Linux Agent Configuration

Configuration file: `/etc/ansible-agent/config.conf`

```bash
# Relay service URL (required)
RELAY_URL="https://ansible-agent.example.com"

# How often to check in (hours)
INTERVAL_HOURS=24

# Enable/disable the agent
ENABLED=true

# Optional: Override hostname (if not set, will use system hostname)
# HOSTNAME_OVERRIDE="custom-hostname"
```

### Configuration Schema

| Variable | Type | Required | Description | Default |
|----------|------|----------|-------------|---------|
| `RELAY_URL` | string | Yes | URL of the relay service | - |
| `INTERVAL_HOURS` | integer | No | Hours between check-ins | `24` |
| `ENABLED` | boolean | No | Enable/disable agent | `true` |
| `HOSTNAME_OVERRIDE` | string | No | Override system hostname | system hostname |

## Windows Agent Configuration

Configuration file: `C:\Program Files\Ansible Agent\config.json`

```json
{
    "RelayUrl": "https://ansible-agent.example.com",
    "IntervalHours": 24,
    "Enabled": true,
    "HostnameOverride": null
}
```

### Configuration Schema

| Field | Type | Required | Description | Default |
|-------|------|----------|-------------|---------|
| `RelayUrl` | string | Yes | URL of the relay service | - |
| `IntervalHours` | integer | No | Hours between check-ins | `24` |
| `Enabled` | boolean | No | Enable/disable agent | `true` |
| `HostnameOverride` | string | No | Override system hostname | `null` |

## Kubernetes Configuration

### ConfigMap Schema

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansible-agent-config
data:
  GLOBAL_RATE_LIMIT: "100 per hour"
  PER_IP_RATE_LIMIT: "1 per 5 minutes"
  MAX_HOSTNAME_LENGTH: "253"
  MIN_HOSTNAME_LENGTH: "1"
  PORT: "5000"
  FLASK_ENV: "production"
  REDIS_URL: "redis://redis:6379"
```

### Secret Schema

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ansible-agent-secrets
type: Opaque
data:
  # All values must be base64 encoded
  AWX_API_ENDPOINT: <base64-encoded-url>
  AWX_USERNAME: <base64-encoded-username>    # Optional if using token
  AWX_PASSWORD: <base64-encoded-password>    # Optional if using token
  AWX_TOKEN: <base64-encoded-token>          # Optional if using username/password
  AWX_TEMPLATE_NAME: <base64-encoded-name>   # Use this OR workflow name
  AWX_WORKFLOW_NAME: <base64-encoded-name>   # Use this OR template name
```