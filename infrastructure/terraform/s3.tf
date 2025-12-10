resource "aws_s3_bucket_object" "ota_manifest" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "manifests/example.json"
  source = "../docs/specs/MasterBlueprint-v3.json"
}
