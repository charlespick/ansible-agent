#!/usr/bin/env python3
"""
Ansible Agent - AWX Relay Service
A lightweight Python service that receives hostname callbacks and triggers AWX workflows
"""

import os
import re
import hashlib
import logging
import time
from typing import Optional, Dict, Any

import requests
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from dotenv import load_dotenv
import redis

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Redis configuration for rate limiting
redis_client = None
try:
    redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
    redis_client = redis.from_url(redis_url)
    redis_client.ping()
    logger.info("Connected to Redis for rate limiting")
except Exception as e:
    logger.warning(f"Redis connection failed, using in-memory rate limiting: {e}")

# Initialize rate limiter
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=redis_url if redis_client else None,
    default_limits=[]
)
limiter.init_app(app)

# Configuration
class Config:
    AWX_API_ENDPOINT = os.getenv('AWX_API_ENDPOINT')
    AWX_USERNAME = os.getenv('AWX_USERNAME')
    AWX_PASSWORD = os.getenv('AWX_PASSWORD')
    AWX_TOKEN = os.getenv('AWX_TOKEN')
    AWX_TEMPLATE_NAME = os.getenv('AWX_TEMPLATE_NAME')
    AWX_WORKFLOW_NAME = os.getenv('AWX_WORKFLOW_NAME')
    
    # Rate limiting configuration
    GLOBAL_RATE_LIMIT = os.getenv('GLOBAL_RATE_LIMIT', '100 per hour')
    PER_IP_RATE_LIMIT = os.getenv('PER_IP_RATE_LIMIT', '1 per 5 minutes')
    
    # Security configuration
    MAX_HOSTNAME_LENGTH = int(os.getenv('MAX_HOSTNAME_LENGTH', '253'))
    MIN_HOSTNAME_LENGTH = int(os.getenv('MIN_HOSTNAME_LENGTH', '1'))
    
    @classmethod
    def validate(cls):
        """Validate required configuration"""
        if not cls.AWX_API_ENDPOINT:
            raise ValueError("AWX_API_ENDPOINT is required")
        
        if not (cls.AWX_USERNAME and cls.AWX_PASSWORD) and not cls.AWX_TOKEN:
            raise ValueError("Either AWX_USERNAME/AWX_PASSWORD or AWX_TOKEN is required")
        
        if not cls.AWX_TEMPLATE_NAME and not cls.AWX_WORKFLOW_NAME:
            raise ValueError("Either AWX_TEMPLATE_NAME or AWX_WORKFLOW_NAME is required")
        
        if cls.AWX_TEMPLATE_NAME and cls.AWX_WORKFLOW_NAME:
            raise ValueError("Cannot specify both AWX_TEMPLATE_NAME and AWX_WORKFLOW_NAME")

# Skip validation in development - allow app to start without AWX config
try:
    Config.validate()
    logger.info("Configuration validation passed")
except ValueError as e:
    logger.warning(f"Configuration validation failed: {e}")
    if os.getenv('FLASK_ENV') != 'development':
        raise

def sanitize_hostname(hostname: str) -> Optional[str]:
    """
    Sanitize and validate hostname according to RFC standards
    
    Args:
        hostname: Raw hostname string
        
    Returns:
        Sanitized hostname if valid, None if invalid
    """
    if not hostname:
        return None
    
    # Remove whitespace and convert to lowercase
    hostname = hostname.strip().lower()
    
    # Check length constraints
    if len(hostname) < Config.MIN_HOSTNAME_LENGTH or len(hostname) > Config.MAX_HOSTNAME_LENGTH:
        logger.warning(f"Hostname length invalid: {len(hostname)} characters")
        return None
    
    # RFC 1123 compliant hostname pattern
    # Allow letters, numbers, hyphens, and dots
    # Must start and end with alphanumeric characters
    hostname_pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
    
    if not re.match(hostname_pattern, hostname):
        logger.warning(f"Hostname does not match RFC 1123 pattern: {hostname}")
        return None
    
    # Additional security checks - reject suspicious patterns
    suspicious_patterns = [
        r'\.\.+',  # Multiple consecutive dots
        r'^-',     # Starting with hyphen
        r'-$',     # Ending with hyphen
        r'[^a-zA-Z0-9\.-]',  # Invalid characters
    ]
    
    for pattern in suspicious_patterns:
        if re.search(pattern, hostname):
            logger.warning(f"Hostname contains suspicious pattern: {hostname}")
            return None
    
    return hostname

def get_awx_auth_headers() -> Dict[str, str]:
    """Get authentication headers for AWX API"""
    if Config.AWX_TOKEN:
        return {'Authorization': f'Bearer {Config.AWX_TOKEN}'}
    else:
        import base64
        credentials = base64.b64encode(f"{Config.AWX_USERNAME}:{Config.AWX_PASSWORD}".encode()).decode()
        return {'Authorization': f'Basic {credentials}'}

def trigger_awx_job(hostname: str) -> Dict[str, Any]:
    """
    Trigger AWX job template or workflow with hostname limit
    
    Args:
        hostname: Validated hostname to limit job to
        
    Returns:
        Dictionary with success status and job details
    """
    headers = {
        'Content-Type': 'application/json',
        **get_awx_auth_headers()
    }
    
    try:
        if Config.AWX_TEMPLATE_NAME:
            # Launch job template
            url = f"{Config.AWX_API_ENDPOINT}/api/v2/job_templates/"
            
            # First, find the template ID
            response = requests.get(f"{url}?name={Config.AWX_TEMPLATE_NAME}", headers=headers, timeout=10)
            response.raise_for_status()
            
            templates = response.json().get('results', [])
            if not templates:
                logger.error(f"Template '{Config.AWX_TEMPLATE_NAME}' not found")
                return {'success': False, 'error': 'Template not found'}
            
            template_id = templates[0]['id']
            
            # Launch the template with hostname limit
            launch_url = f"{url}{template_id}/launch/"
            payload = {
                'limit': hostname,
                'extra_vars': {
                    'target_hostname': hostname
                }
            }
            
            response = requests.post(launch_url, json=payload, headers=headers, timeout=10)
            response.raise_for_status()
            
            job_data = response.json()
            logger.info(f"Launched job template {template_id} for {hostname}, job ID: {job_data.get('id')}")
            
            return {
                'success': True,
                'job_id': job_data.get('id'),
                'job_type': 'template',
                'hostname': hostname
            }
            
        elif Config.AWX_WORKFLOW_NAME:
            # Launch workflow template
            url = f"{Config.AWX_API_ENDPOINT}/api/v2/workflow_job_templates/"
            
            # First, find the workflow ID
            response = requests.get(f"{url}?name={Config.AWX_WORKFLOW_NAME}", headers=headers, timeout=10)
            response.raise_for_status()
            
            workflows = response.json().get('results', [])
            if not workflows:
                logger.error(f"Workflow '{Config.AWX_WORKFLOW_NAME}' not found")
                return {'success': False, 'error': 'Workflow not found'}
            
            workflow_id = workflows[0]['id']
            
            # Launch the workflow with hostname limit
            launch_url = f"{url}{workflow_id}/launch/"
            payload = {
                'limit': hostname,
                'extra_vars': {
                    'target_hostname': hostname
                }
            }
            
            response = requests.post(launch_url, json=payload, headers=headers, timeout=10)
            response.raise_for_status()
            
            job_data = response.json()
            logger.info(f"Launched workflow {workflow_id} for {hostname}, job ID: {job_data.get('id')}")
            
            return {
                'success': True,
                'job_id': job_data.get('id'),
                'job_type': 'workflow',
                'hostname': hostname
            }
    
    except requests.exceptions.Timeout:
        logger.error(f"AWX API timeout for hostname {hostname}")
        return {'success': False, 'error': 'AWX API timeout'}
    
    except requests.exceptions.RequestException as e:
        logger.error(f"AWX API error for hostname {hostname}: {e}")
        return {'success': False, 'error': f'AWX API error: {str(e)}'}
    
    except Exception as e:
        logger.error(f"Unexpected error triggering AWX job for {hostname}: {e}")
        return {'success': False, 'error': f'Unexpected error: {str(e)}'}

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': time.time()})

@app.route('/provision', methods=['POST'])
@limiter.limit(Config.PER_IP_RATE_LIMIT)
@limiter.limit(Config.GLOBAL_RATE_LIMIT, key_func=lambda: 'global')
def provision():
    """
    Main provisioning endpoint
    Accepts hostname and triggers AWX job
    """
    try:
        # Extract hostname from request
        if request.is_json:
            data = request.get_json()
            hostname = data.get('hostname') if data else None
        else:
            hostname = request.form.get('hostname')
        
        if not hostname:
            logger.warning("Missing hostname in request")
            return jsonify({'error': 'hostname parameter is required'}), 400
        
        # Sanitize hostname
        sanitized_hostname = sanitize_hostname(hostname)
        if not sanitized_hostname:
            logger.warning(f"Invalid hostname rejected: {hostname}")
            return jsonify({'error': 'Invalid hostname format'}), 400
        
        # Log the request
        client_ip = get_remote_address()
        logger.info(f"Provisioning request from {client_ip} for hostname: {sanitized_hostname}")
        
        # Trigger AWX job
        result = trigger_awx_job(sanitized_hostname)
        
        if result['success']:
            return jsonify({
                'success': True,
                'hostname': sanitized_hostname,
                'job_id': result.get('job_id'),
                'job_type': result.get('job_type'),
                'message': f'Job triggered successfully for {sanitized_hostname}'
            })
        else:
            return jsonify({
                'success': False,
                'hostname': sanitized_hostname,
                'error': result.get('error')
            }), 500
    
    except Exception as e:
        logger.error(f"Unexpected error in provision endpoint: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.errorhandler(429)
def ratelimit_handler(e):
    """Rate limit error handler"""
    client_ip = get_remote_address()
    logger.warning(f"Rate limit exceeded for IP: {client_ip}")
    return jsonify({
        'error': 'Rate limit exceeded',
        'message': 'Too many requests. Please try again later.',
        'retry_after': getattr(e, 'retry_after', None)
    }), 429

if __name__ == '__main__':
    # Development server - use gunicorn in production
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5000)), debug=False)