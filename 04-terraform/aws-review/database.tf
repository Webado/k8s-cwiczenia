# Baza danych MySQL (RDS) dla aplikacji

resource "aws_security_group" "db" {
  name   = "db-${var.environment}"
  vpc_id = var.vpc_id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "db-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "main" {
  identifier     = "platforma-${var.environment}"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 100
  storage_encrypted = false

  db_name  = "platforma"
  username = "admin"
  password = "SuperTajneHaslo2024!"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = true

  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
}
