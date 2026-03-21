# cloudfront.tf

# OAC — permite a CloudFront leer S3 sin hacer el bucket público
# OAC usa firmas SigV4, es el método actual recomendado por AWS (reemplaza OAI)
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.processed.bucket_regional_domain_name
    origin_id                = "processed-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  # Cache policy explícita — ignora query strings, cookies y headers innecesarios
  # Cada variación en estos parámetros genera un cache miss distinto
  # Si no los ignorás, dos requests idénticos con headers distintos no comparten caché
  default_cache_behavior {
    target_origin_id       = "processed-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400    # 1 día
    max_ttl     = 31536000 # 1 año
  }

  # S3 devuelve 403 cuando el objeto no existe con OAC — lo mapeamos a 404
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy — solo acepta requests firmados por esta distribución CloudFront
# Sin esta policy el bucket processed es inaccesible aunque CloudFront tenga OAC
resource "aws_s3_bucket_policy" "processed" {
  bucket = aws_s3_bucket.processed.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.processed.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
