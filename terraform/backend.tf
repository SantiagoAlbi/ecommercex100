terraform {
  backend "s3" {
    bucket         = "x100-ecommerce-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
