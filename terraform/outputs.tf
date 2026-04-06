# terraform/outputs.tf

output "api_endpoint" {
  description = "Endpoint de API Gateway para solicitar presigned URLs"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/upload"
}

output "cloudfront_domain" {
  description = "CloudFront domain — base URL para servir imágenes procesadas"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cognito_user_pool_id" {
  description = "ID del User Pool de Cognito"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "Client ID para autenticarse contra Cognito"
  value       = aws_cognito_user_pool_client.main.id
}

output "raw_bucket_name" {
  description = "Bucket donde se reciben los uploads originales"
  value       = aws_s3_bucket.raw.bucket
}

output "processed_bucket_name" {
  description = "Bucket con las imágenes procesadas (servidas via CloudFront)"
  value       = aws_s3_bucket.processed.bucket
}

output "dynamodb_table_name" {
  description = "Tabla DynamoDB con metadata de imágenes"
  value       = aws_dynamodb_table.metadata.name
}

output "example_image_url" {
  description = "Ejemplo de URL para acceder a una imagen procesada via CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/thumb/PRODUCT_ID/FILENAME.webp"
}
