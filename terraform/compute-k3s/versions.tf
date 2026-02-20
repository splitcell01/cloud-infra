terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "cole-tf-state-us-east-1"
    key            = "compute-k3s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
