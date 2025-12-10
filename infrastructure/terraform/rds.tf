resource "aws_db_instance" "mysql" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  name                 = "secure_device"
  username             = "admin"
  password             = "changeme123"
  skip_final_snapshot  = true
}
