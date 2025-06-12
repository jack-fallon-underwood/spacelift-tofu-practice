provider "aws" {
  region = "us-east-2"
}

resource "aws_db_instance" "postgresql" {
  identifier              = "db-9994"
  engine                  = "postgres"
  engine_version          = "17.4"
  instance_class          = "db.t3.micro"              # Free-tier eligible (check your account)
  allocated_storage       = 20                         # Minimum for PostgreSQL
  storage_type            = "gp2"
 
  db_name                 = "devdb"                    # Name of your DB inside the instance
  username                = "postgresadmin"
  password                = "SuperSecure123!"
  port                    = 5432

  publicly_accessible     = false                      # Set to true only if needed
  skip_final_snapshot     = true                       # Allow deletion without snapshot
  deletion_protection     = false                      # Turned off for easy testing

  backup_retention_period = 0                          # No backups for now
  multi_az                = false                      # Stay in single AZ (cheaper)
  auto_minor_version_upgrade = true
}

output "rds_endpoint" {
  value = aws_db_instance.postgresql.endpoint
}
