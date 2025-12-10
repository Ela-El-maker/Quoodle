provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "secure-device-control-artifacts"
}

resource "aws_kms_key" "signing" {
  description = "KMS key for signing artifacts"
}
