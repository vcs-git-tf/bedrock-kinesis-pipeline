import json
import boto3
import os
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities import parameters

Logger = Logger()
Tracer = Tracer()

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')

@Logger.inject_lambda_context
@Tracer.capture_lambda_handler
def handler(event, context):
    try:
        # Assume the event contains the S3 bucket and ket of the data to process
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']

        # Read data from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        data = json.loads(response['Body'].read().decode('utf-8'))

        # Process data eith Bedrock
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-v2', # or change to model of choice
            body=json.dumps({
                "prompt": f"Analyze the following data: {data}",
                "max_tokens_to_sample": 250 # Change for performance and cost optimization
            })
        )

        results = json.loads(bedrock_response['body'].read())

        # Store the results back to S3
        output_key = f"processed/{key.split('/')[-1]}"
        s3.put_object(
            Bucket=bucket,
            Key=output_key,
            Body=json.dumps(results)
        )

        return {
            'statusCode' : 200,
            'body': json.dumps('Processing complete!')
        }
    except Exception as e:
        Logger.exception("Error processing data")
        raise