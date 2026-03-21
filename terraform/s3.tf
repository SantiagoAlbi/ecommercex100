# Bucket donde el cliente sube la imagen original
resource "aws_s3_bucket" "raw" {
  bucket = "${var.project_name}-raw"
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# La imagen original no tiene valor después de procesada
# 30 días es suficiente margen si algo falla en el procesamiento
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "expire-raw-images"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

# Bucket donde Lambda guarda las variantes procesadas (WebP)
resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed"
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Las imágenes procesadas se sirven via CloudFront
# Después de 90 días las menos accedidas bajan a IA — mitad de precio por storage
resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "move-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# La notificación depende de que la queue policy exista primero
# Sin depends_on S3 intenta configurar la notificación antes de tener permiso para escribir en SQS
resource "aws_s3_bucket_notification" "raw" {
  bucket = aws_s3_bucket.raw.id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
  }

  depends_on = [aws_sqs_queue_policy.main]
}
