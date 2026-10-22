# DEMO ONLY - intentionally misconfigured Terraform to trigger IaC findings.
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "public_data" {
  bucket = "frogbot-demo-public-data"
  acl    = "public-read-write"
}

resource "aws_security_group" "open_to_world" {
  name        = "frogbot-demo-open-sg"
  description = "Allows all inbound traffic"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "unencrypted" {
  allocated_storage   = 10
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  username            = "admin"
  password            = "Sup3rS3cr3tP@ssw0rd!2026"
  storage_encrypted   = false
  publicly_accessible = true
  skip_final_snapshot = true
}
