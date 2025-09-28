import pytest
import json
import os
from unittest.mock import patch, MagicMock

# Set environment variables for testing
os.environ['FLASK_ENV'] = 'development'
os.environ['AWX_API_ENDPOINT'] = 'https://test.example.com'
os.environ['AWX_USERNAME'] = 'test'
os.environ['AWX_PASSWORD'] = 'test'
os.environ['AWX_TEMPLATE_NAME'] = 'test-template'

from ansible_agent.app import app, sanitize_hostname

@pytest.fixture
def client():
    with app.test_client() as client:
        yield client

def test_health_endpoint(client):
    """Test the health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'
    assert 'timestamp' in data

def test_provision_missing_hostname(client):
    """Test provision endpoint with missing hostname"""
    response = client.post('/provision', json={})
    assert response.status_code == 400
    data = json.loads(response.data)
    assert 'hostname parameter is required' in data['error']

def test_provision_invalid_hostname(client):
    """Test provision endpoint with invalid hostname"""
    invalid_hostnames = [
        '',
        'a' * 300,  # Too long
        'host..name',  # Double dots
        '-hostname',  # Starts with hyphen
        'hostname-',  # Ends with hyphen
        'host name',  # Space
        'host@name',  # Invalid character
    ]
    
    for hostname in invalid_hostnames:
        response = client.post('/provision', json={'hostname': hostname})
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'Invalid hostname format' in data['error']

@patch('ansible_agent.app.trigger_awx_job')
def test_provision_valid_hostname(mock_trigger, client):
    """Test provision endpoint with valid hostname"""
    mock_trigger.return_value = {
        'success': True,
        'job_id': 123,
        'job_type': 'template',
        'hostname': 'testhost'
    }
    
    response = client.post('/provision', json={'hostname': 'testhost.example.com'})
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['success'] is True
    assert data['hostname'] == 'testhost.example.com'
    assert data['job_id'] == 123

def test_sanitize_hostname():
    """Test hostname sanitization function"""
    # Valid hostnames
    assert sanitize_hostname('test.example.com') == 'test.example.com'
    assert sanitize_hostname('TEST.EXAMPLE.COM') == 'test.example.com'
    assert sanitize_hostname('  test.example.com  ') == 'test.example.com'
    assert sanitize_hostname('host-name') == 'host-name'
    assert sanitize_hostname('123test') == '123test'
    
    # Invalid hostnames
    assert sanitize_hostname('') is None
    assert sanitize_hostname(None) is None
    assert sanitize_hostname('a' * 300) is None
    assert sanitize_hostname('host..name') is None
    assert sanitize_hostname('-hostname') is None
    assert sanitize_hostname('hostname-') is None
    assert sanitize_hostname('host name') is None
    assert sanitize_hostname('host@name') is None