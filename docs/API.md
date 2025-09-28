# API Documentation

The Ansible Agent provides a simple REST API for triggering AWX jobs.

## Endpoints

### GET /health

Health check endpoint for monitoring and load balancers.

**Response:**
```json
{
    "status": "healthy",
    "timestamp": 1234567890.123
}
```

### POST /provision

Main endpoint for triggering provisioning jobs.

**Request:**
```json
{
    "hostname": "server01.example.com"
}
```

**Successful Response (200):**
```json
{
    "success": true,
    "hostname": "server01.example.com",
    "job_id": 123,
    "job_type": "template",
    "message": "Job triggered successfully for server01.example.com"
}
```

**Error Responses:**

**400 Bad Request - Missing hostname:**
```json
{
    "error": "hostname parameter is required"
}
```

**400 Bad Request - Invalid hostname:**
```json
{
    "error": "Invalid hostname format"
}
```

**429 Too Many Requests - Rate limited:**
```json
{
    "error": "Rate limit exceeded",
    "message": "Too many requests. Please try again later.",
    "retry_after": 300
}
```

**500 Internal Server Error:**
```json
{
    "success": false,
    "hostname": "server01.example.com",
    "error": "AWX API error: Connection timeout"
}
```

## Security

- **Rate Limiting**: Requests are rate limited both per-IP and globally
- **Hostname Validation**: Hostnames are validated against RFC 1123 standards
- **Input Sanitization**: All input is sanitized and validated
- **No Authentication**: The endpoint is intentionally unauthenticated for simplicity

## Rate Limits

Default rate limits:
- **Per-IP**: 1 request per 5 minutes
- **Global**: 100 requests per hour

These can be configured via environment variables `PER_IP_RATE_LIMIT` and `GLOBAL_RATE_LIMIT`.

## Hostname Validation

Hostnames must:
- Be 1-253 characters long
- Contain only letters, numbers, hyphens, and dots
- Start and end with alphanumeric characters
- Follow RFC 1123 standards
- Not contain suspicious patterns (consecutive dots, etc.)

Invalid hostnames will return a 400 error.