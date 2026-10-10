# Private RDS for PostgreSQL, reachable only through an SSM port-forwarding session.
#
#   laptop --(HTTPS 443, SSM)--> VPC endpoints --> bastion EC2 --(5432)--> RDS
#
# - Dedicated VPC with private subnets only: no internet gateway, no NAT, no public IPs.
# - The bastion has no SSH key and no inbound rules; it talks to SSM through interface endpoints.
# - The RDS master password is managed by RDS in Secrets Manager, so it never lands in Terraform state.
# Built for a one-evening demo: no backups, no final snapshot, easy to destroy.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2) # RDS subnet groups need 2 AZs
}

# ---------- Network: private-only VPC ----------

resource "aws_vpc" "demo" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for the endpoints' private DNS names

  tags = { Name = "${var.identifier}-vpc" }
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.demo.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  tags = { Name = "${var.identifier}-private-${local.azs[count.index]}" }
}

# The VPC's main route table only has the local route, so these subnets have no way out.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "${var.identifier}-private" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Lock down the default security group so nothing uses it by accident.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.demo.id
}

# ---------- Security groups ----------
# Rules are separate resources so the groups can reference each other without a cycle.

resource "aws_security_group" "bastion" {
  name        = "${var.identifier}-bastion"
  description = "SSM bastion: no inbound, outbound only to endpoints and RDS"
  vpc_id      = aws_vpc.demo.id
  tags        = { Name = "${var.identifier}-bastion" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.identifier}-endpoints"
  description = "SSM interface endpoints"
  vpc_id      = aws_vpc.demo.id
  tags        = { Name = "${var.identifier}-endpoints" }
}

resource "aws_security_group" "rds" {
  name        = "${var.identifier}-rds"
  description = "PostgreSQL, from the bastion only"
  vpc_id      = aws_vpc.demo.id
  tags        = { Name = "${var.identifier}-rds" }
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_endpoints" {
  security_group_id            = aws_security_group.bastion.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "SSM endpoints"
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_rds" {
  security_group_id            = aws_security_group.bastion.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_bastion" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the bastion"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the bastion"
}

# ---------- SSM interface endpoints ----------
# One AZ is enough for a demo (each endpoint is billed per AZ).

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id              = aws_vpc.demo.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.identifier}-${each.key}" }
}

# ---------- Bastion EC2 (SSM only) ----------

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.identifier}-bastion"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.identifier}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value # SSM agent preinstalled
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.identifier}-bastion" }

  # The agent must reach the endpoints on first boot, or it takes a while to register.
  depends_on = [aws_vpc_endpoint.ssm]

  lifecycle {
    ignore_changes = [ami] # don't replace the bastion when a newer AMI comes out
  }
}

# ---------- RDS parameters ----------
# Same settings as the local docker-compose, so plans and timings match the slides.
# shared_buffers is left at the RDS default (25% of RAM = 2 GB on db.t4g.large).
# random_page_cost stays at the default 4 on purpose: the slides' plans were tested with it.

resource "aws_db_parameter_group" "demo" {
  name   = "${var.identifier}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "top"
  }

  parameter {
    name  = "track_io_timing"
    value = "1"
  }

  parameter {
    name  = "work_mem"
    value = "65536" # KB = 64 MB
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "524288" # KB = 512 MB, faster CREATE INDEX and VACUUM during the demo
  }

  parameter {
    name  = "max_wal_size"
    value = "4096" # MB, avoids checkpoint storms while loading 10M rows
  }

  parameter {
    name  = "log_autovacuum_min_duration"
    value = "0" # every autovacuum run shows up in the log, useful for the VACUUM section
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "0" # keep 0: the long-transaction demo needs an idle session
  }
}

# ---------- RDS instance ----------

resource "aws_db_subnet_group" "demo" {
  name       = "${var.identifier}-private"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "demo" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3" # 3000 IOPS / 125 MB/s baseline below 400 GB
  storage_encrypted = true

  db_name                     = "demo"
  username                    = "demo_admin"
  manage_master_user_password = true # password lives in Secrets Manager, not in state
  port                        = 5432

  parameter_group_name   = aws_db_parameter_group.demo.name
  db_subnet_group_name   = aws_db_subnet_group.demo.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # free tier

  backup_retention_period = 0 # no automated backups: faster to create, nothing to keep
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
  copy_tags_to_snapshot   = true
}
