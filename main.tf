provider "aws" {
  region = "us-east-2"
}

resource "aws_db_instance" "postgresql" {
  identifier              = "db-9992"
  engine                  = "postgres"
  engine_version          = "17.4"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"

  db_name                 = "devdb"
  username                = "postgresadmin"
  password                = "SuperSecure123!"
  port                    = 5432

  publicly_accessible     = true  # must be accessible from EC2 instance
  skip_final_snapshot     = true
  deletion_protection     = false

  backup_retention_period = 0
  multi_az                = false
  auto_minor_version_upgrade = true
}

resource "aws_security_group" "ec2_sg" {
  name        = "allow_postgres_access"
  description = "Allow outbound to RDS Postgres"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # for SSH (adjust for security)
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_db_instance.postgresql.address] # allow to RDS instance IP
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_instance" "ubuntu" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet_ids.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

  key_name                    = "your-keypair"  # Replace with your SSH keypair name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y postgresql-client
              PGPASSWORD=SuperSecure123! psql -h ${aws_db_instance.postgresql.address} -U postgresadmin -d devdb -p 5432 -c "CREATE TABLE IF NOT EXISTS dummy_data (id SERIAL PRIMARY KEY, info TEXT);"
              PGPASSWORD=SuperSecure123! psql -h ${aws_db_instance.postgresql.address} -U postgresadmin -d devdb -p 5432 -c "INSERT INTO dummy_data (info) VALUES ('Terraform automated dummy data');"
              EOF

  tags = {
    Name = "Ubuntu-For-RDS-Dummy"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

output "rds_endpoint" {
  value = aws_db_instance.postgresql.endpoint
}

output "ubuntu_public_ip" {
  value = aws_instance.ubuntu.public_ip
}
