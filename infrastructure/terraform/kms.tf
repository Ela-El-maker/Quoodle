resource "aws_kms_key" "app" {
  description             = "Secure Device Control app key"
  deletion_window_in_days = 7
}
