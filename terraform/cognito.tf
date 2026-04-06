resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # El usuario confirma su identidad via email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

# App client — es la "aplicación" que tiene permiso para autenticar usuarios
# Sin client secret porque el flujo es desde CLI o frontend, no server-to-server
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = "test@example.com"

  attributes = {
    email          = "test@example.com"
    email_verified = "true"
  }

  temporary_password = "Test1234!"
  message_action     = "SUPPRESS"
}
