# Bedrock AI Image Tagger Lab

Automatically tags images using Amazon Bedrock (Claude 3 Sonnet) when uploaded to S3.

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
3. Sends it to Claude 3 Sonnet via Bedrock
4. Prints the 5 AI-generated tags to CloudWatch Logs

It must be zipped before deployment — Terraform handles this with `archive_file`.

### 4. S3 Bucket Notification
This is the **glue** between S3 and Lambda. Without it, uploading an image does nothing. This resource tells S3: *"whenever a new object is created, invoke this Lambda function."*

`aws_lambda_permission` is also required — it grants S3 the right to invoke Lambda. Without it, S3 would be blocked even with the notification configured.

## Deploy

```bash
terraform init
terraform apply
```

## Verify Bedrock Model Access is Working

### Option 1 — AWS Console
1. Go to **Amazon Bedrock** → **Model access** (left sidebar)
2. Confirm `Claude 3 Sonnet` shows status **Access granted**

### Option 2 — AWS CLI
```bash
aws bedrock list-foundation-models --region us-east-1 --query "modelSummaries[?modelId=='anthropic.claude-3-5-sonnet-20240620-v1:0']"
```
If it returns the model details, access is enabled.

### Option 3 — Test the full pipeline end-to-end
1. Upload a `.jpg` to your S3 bucket:
```bash
aws s3 cp my-photo.jpg s3://my-bedrock-image-tagger-bucket/
```
2. Go to **CloudWatch** → **Log groups** → `/aws/lambda/bedrock-image-tagger`
3. Open the latest log stream — you should see a line like:
```
AI Tags for my-photo.jpg: 1. outdoor 2. sunset 3. landscape 4. nature 5. sky
```
If you see that output, everything is working end-to-end.

### Option 4 — Quick Bedrock invoke test via CLI
```bash
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-5-sonnet-20240620-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"say hi"}]}' \
  --cli-binary-format raw-in-base64-out \
  output.json && cat output.json
```
A successful response confirms your model access is active.
