# 1. S3 Bucket — the source where you upload images
resource "aws_s3_bucket" "image_bucket" {
  bucket = "my-bedrock-image-tagger-bucket"
}

# 2. IAM Role — identity that Lambda assumes at runtime
resource "aws_iam_role" "lambda_role" {
  name = "bedrock-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 2a. IAM Policy — grants Lambda permission to call Bedrock and read S3
resource "aws_iam_role_policy" "lambda_policy" {
  name = "bedrock-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObjectTagging"]
        Resource = "${aws_s3_bucket.image_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 3. Package the Python file into a zip for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lamdba_function.py"
  output_path = "${path.module}/lamdba_function.zip"
}

# 3a. Lambda Function — runs your Python logic when triggered
resource "aws_lambda_function" "image_tagger" {
  function_name    = "bedrock-image-tagger"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lamdba_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# 4. Allow S3 to invoke the Lambda function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_tagger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_bucket.arn
}

# 4a. S3 Bucket Notification — the trigger that fires Lambda on new uploads
resource "aws_s3_bucket_notification" "image_upload_trigger" {
  bucket = aws_s3_bucket.image_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_tagger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
