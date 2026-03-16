# Bedrock AI Image Tagger Lab

Automatically tags images using Amazon Bedrock (Claude 3 Haiku) when uploaded to S3.

## Architecture Flow

```
Upload Image → S3 Bucket → S3 Notification → Lambda → Bedrock (Claude) → CloudWatch Logs
```

## Why Each Resource is Needed

### 1. S3 Bucket
The entry point of the pipeline. You upload a `.jpg` image here, which kicks off the entire workflow. Without it, there is no trigger source.

### 2. IAM Role & Policy
Lambda needs **permission** to talk to other AWS services. By default it can't do anything.
- `bedrock:InvokeModel` — lets Lambda call Claude to analyze the image
- `s3:GetObject` — lets Lambda download the image from the bucket
- `logs:*` — lets Lambda write output to CloudWatch so you can see the tags

Without this policy, Lambda would get an `AccessDeniedException` when calling Bedrock.

### 3. Lambda Function
This is the brain. The Python code (`lamdba_function.py`):
1. Receives the S3 event (bucket name + file key)
2. Downloads the image and base64-encodes it
3. Sends it to Claude 3 Haiku via Bedrock
4. Prints the 5 AI-generated tags to CloudWatch Logs
5. Writes the 5 tags back to the S3 object as metadata tags

It must be zipped before deployment — Terraform handles this with `archive_file`.

### 4. S3 Bucket Notification
This is the **glue** between S3 and Lambda. Without it, uploading an image does nothing. This resource tells S3: *"whenever a new object is created, invoke this Lambda function."*

`aws_lambda_permission` is also required — it grants S3 the right to invoke Lambda. Without it, S3 would be blocked even with the notification configured.

## Deploy

> All commands below were run on **PowerShell**. The backslash `\` line continuation used in bash does not work in PowerShell, so all commands are written as a single line.

```powershell
terraform init
terraform apply
```

## Verify Bedrock Model Access is Working

### Console
1. Go to **Amazon Bedrock** → **Model access** (left sidebar)
2. Confirm `Claude 3 Haiku` shows status **Access granted**

### AWS CLI
```powershell
aws bedrock list-foundation-models --region us-east-1 --query "modelSummaries[?modelId=='anthropic.claude-3-haiku-20240307-v1:0']"
```
If it returns the model details, access is enabled.

## Where to Find the AI Tags

### CloudWatch Logs (printed by Lambda)
1. Go to **CloudWatch** → **Log groups** → `/aws/lambda/bedrock-image-tagger`
2. Click the latest log stream
3. Look for a line like:
```
AI Tags for my-photo.jpg: ['outdoor', 'sunset', 'landscape', 'nature', 'sky']
```

#### PowerShell — View CloudWatch Tags
```powershell
# Step 1: Get the latest log stream name
aws logs describe-log-streams --log-group-name /aws/lambda/bedrock-image-tagger --order-by LastEventTime --descending --query "logStreams[0].logStreamName" --output text
```
```powershell
# Step 2: View the log events (replace LOG_STREAM_NAME with output from Step 1)
aws logs get-log-events --log-group-name /aws/lambda/bedrock-image-tagger --log-stream-name 'LOG_STREAM_NAME' --query "events[*].message" --output text
```

### S3 Object Tags (written back by Lambda)
1. Go to **S3** → your bucket → click the image
2. Click the **Properties** tab
3. Scroll down to **Tags** — you will see `tag1` through `tag5`

#### PowerShell — View S3 Object Tags
```powershell
aws s3api get-object-tagging --bucket my-bedrock-image-tagger-bucket --key my-photo.jpg
```
Output will look like:
```json
{
    "TagSet": [
        { "Key": "tag1", "Value": "outdoor" },
        { "Key": "tag2", "Value": "sunset" },
        { "Key": "tag3", "Value": "landscape" },
        { "Key": "tag4", "Value": "nature" },
        { "Key": "tag5", "Value": "sky" }
    ]
}
```