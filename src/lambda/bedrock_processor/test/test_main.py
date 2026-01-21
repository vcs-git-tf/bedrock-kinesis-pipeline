import json
import pytest
from unittest.mock import Mock, patch
from main import handler

@pytest.fixture
def s3_event():
    return{
        'Records': [{
            's3': {
                'bucket': {'name': 'test-bucket'},
                'object': {'key': 'test-key.json'}
            }
        }]
    }

@patch('main.s3')
@patch('main.bedrock')
def test_handler_success(mock_bedrock, mock_s3, s3_event):
    # Mock S3 get_object
    mock_s3.get_object.return_value = {
        'Body': Mock(read=lambda: b'{"result}: "processed"}')
    }

    # Call handler
    response = handler(s3_event, None)

    # Assertion
    assert response['statusCode']  == 200
    mock_s3.put_object.assert_caller_once()