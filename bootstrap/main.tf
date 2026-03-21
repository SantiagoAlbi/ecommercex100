# bootstrap/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# El bucket que va a guardar el tfstate del proyecto principal
resource "aws_s3_bucket" "tfstate" {
  bucket = "x100-ecommerce-tfstate"
}

# Sin versionado no podés recuperar un state corrompido
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# El state contiene nombres de recursos, ARNs, a veces passwords — nunca público
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# LockID es la clave que Terraform escribe cuando alguien corre apply
# Si la clave ya existe, el segundo proceso recibe error en vez de pisar el primero
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
