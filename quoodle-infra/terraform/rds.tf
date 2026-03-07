resource "aws_db_instance" "mysql" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = "secure_device"
  username             = "admin"
  password             = var.db_password
  skip_final_snapshot  = true
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}
