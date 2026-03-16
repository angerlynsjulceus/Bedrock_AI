import json
import boto3
import base64
import re

# Initialize clients
s3 = boto3.client('s3')
bedrock = boto3.client(service_name='bedrock-runtime', region_name='us-east-1')

def lambda_handler(event, context):
    # 1. Get the bucket and file name from the S3 event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    # 2. Download the image from S3
    image_object = s3.get_object(Bucket=bucket, Key=key)
    image_bytes = image_object['Body'].read()

    # 3. Prepare the request for Claude 3 Sonnet
    encoded_image = base64.b64encode(image_bytes).decode('utf-8')

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 500,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": encoded_image
                        }
                    },
                    {"type": "text", "text": "Provide exactly 5 single-word descriptive tags for this image. Reply only with a numbered list, one tag per line."}
                ]
            }
        ]
    })

    # 4. Invoke Bedrock
    response = bedrock.invoke_model(
        modelId="anthropic.claude-3-haiku-20240307-v1:0",
        body=body
    )

    # 5. Parse the 5 tags from Claude's response
    response_body = json.loads(response.get('body').read())
    raw_text = response_body['content'][0]['text']

    # Extract words from numbered list (e.g. "1. sunset" -> "sunset")
    tags = re.findall(r'\d+\.\s*(\w+)', raw_text)[:5]

    # 6. Print to CloudWatch Logs
    print(f"AI Tags for {key}: {tags}")

    # 7. Write tags back to the S3 object
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={
            "TagSet": [{"Key": f"tag{i+1}", "Value": tag} for i, tag in enumerate(tags)]
        }
    )

    return {"statusCode": 200, "body": "Success"}
