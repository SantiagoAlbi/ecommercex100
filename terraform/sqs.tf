# Dead Letter Queue — recibe mensajes que fallaron demasiadas veces
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 días para investigar qué falló
}

# Queue principal — buffer entre S3 y Lambda
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-queue"
  visibility_timeout_seconds = 180   # 6x el timeout de Lambda (30s) — regla fija
  message_retention_seconds  = 86400 # 1 día

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # 3 intentos fallidos → va a DLQ
  })
}

# S3 necesita permiso explícito para escribir en la queue
# Sin esto el evento S3 → SQS falla silenciosamente
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.main.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.raw.arn
        }
      }
    }]
  })
}
