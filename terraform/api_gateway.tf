resource "aws_api_gateway_rest_api" "main" {
  name = "${var.project_name}-api"
}

# Recurso /upload
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "upload"
}

# Cognito Authorizer — intercepta cada request y valida el JWT
# token_source indica de dónde extrae el token — en este caso el header Authorization
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.project_name}-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}

# Método POST sobre /upload con el authorizer
resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  depends_on = [aws_api_gateway_authorizer.cognito]
}

# Proxy integration — API Gateway pasa el request completo a Lambda sin transformaciones
# Lambda es responsable de armar statusCode, headers y body
resource "aws_api_gateway_integration" "upload_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.presigned_url.invoke_arn
}

# Permiso para que API Gateway invoque la Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [aws_api_gateway_integration.upload_post]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = "prod"
}

resource "aws_api_gateway_method_settings" "prod_throttle" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = 100
    throttling_burst_limit = 200
  }
}



/*
resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = "prod"

  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
}
*/

