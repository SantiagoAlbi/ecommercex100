data "archive_file" "presigned_url" {
  type        = "zip"
  source_file = "${path.module}/../lambda/presigned_url/handler.py"
  output_path = "${path.module}/../lambda/presigned_url/handler.zip"
}

resource "aws_lambda_function" "presigned_url" {
  function_name    = "${var.project_name}-presigned-url"
  role             = aws_iam_role.presigned_url.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.presigned_url.output_path
  source_code_hash = data.archive_file.presigned_url.output_base64sha256

  # 128MB es suficiente — esta función no procesa datos, solo genera una URL
  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.bucket
    }
  }
}

data "archive_file" "image_processor" {
  type        = "zip"
  source_file = "${path.module}/../lambda/image_processor/handler.py"
  output_path = "${path.module}/../lambda/image_processor/handler.zip"
}

resource "aws_lambda_function" "image_processor" {
  function_name    = "${var.project_name}-image-processor"
  role             = aws_iam_role.image_processor.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.image_processor.output_path
  source_code_hash = data.archive_file.image_processor.output_base64sha256

  # Pillow necesita más memoria para procesar imágenes en memoria
  memory_size = 512
  timeout     = 30

  # Klayers provee Pillow como Layer — no necesitamos empaquetar la librería en el zip
  # Ventaja: el zip es liviano, el layer se reutiliza entre funciones
  layers = ["arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-Pillow:6"]

  environment {
    variables = {
      RAW_BUCKET       = aws_s3_bucket.raw.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      DYNAMODB_TABLE   = aws_dynamodb_table.metadata.name
      #CLOUDFRONT_URL   = "https://placeholder.cloudfront.net"
      CLOUDFRONT_URL = "https://${aws_cloudfront_distribution.main.domain_name}"
    }
  }
}

# SQS dispara Lambda cuando llegan mensajes
# batch_size 5: Lambda procesa hasta 5 mensajes por invocación
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.image_processor.arn
  batch_size       = 5
}
