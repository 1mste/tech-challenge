# ---------------------------------------------------------------------------
# RDS POSTGRESQL — um banco por microsserviço com estado relacional.
#
# auth-service ......... auth_db
# flag-service ......... flags_db      (plural, conforme o docker-compose)
# targeting-service .... targeting_db
#
# O evaluation-service NÃO entra aqui: o estado dele é cache em Redis.
#
# Segurança: a senha não é entrada do Terraform nem fica em tfvars. É gerada
# com random_password e publicada no Secrets Manager, de onde a aplicação
# (via External Secrets / CSI driver) ou o operador a lê. Isso resolve a dor
# citada no enunciado da Fase 3: "credenciais em arquivos de texto".
# ---------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}"

  databases = {
    auth = {
      db_name = "auth_db"
    }
    flag = {
      db_name = "flags_db"
    }
    targeting = {
      db_name = "targeting_db"
    }
  }
}

# --------------------------------------------------
# SENHAS GERADAS
# --------------------------------------------------

resource "random_password" "db" {
  for_each = local.databases

  length  = 24
  special = true
  # O RDS proíbe / @ " e espaço; os demais caracteres também quebrariam a
  # montagem da DATABASE_URL, então restringimos a um conjunto seguro.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# --------------------------------------------------
# REDE
# --------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Acesso ao PostgreSQL a partir dos nos do EKS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

# Regra precisa: só o security group do cluster entra na 5432.
resource "aws_vpc_security_group_ingress_rule" "from_cluster" {
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL a partir do cluster EKS"

  referenced_security_group_id = var.cluster_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Escotilha opcional para acesso administrativo (bastion/VPN). Vazio = fechado.
resource "aws_vpc_security_group_ingress_rule" "extra" {
  for_each = toset(var.extra_allowed_cidrs)

  security_group_id = aws_security_group.rds.id
  description       = "Acesso administrativo autorizado"

  cidr_ipv4   = each.value
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.rds.id
  description       = "Saida liberada"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-rds-subnets"
  description = "Subnets privadas para os bancos PostgreSQL"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${local.name}-rds-subnets"
  }
}

# --------------------------------------------------
# INSTÂNCIAS
# --------------------------------------------------

resource "aws_db_instance" "postgres" {
  for_each = local.databases

  identifier = "${local.name}-${each.key}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = each.value.db_name
  username = var.db_master_username
  password = random_password.db[each.key].result

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Ambiente de estudo: sem backup, sem snapshot final, destroy limpo.
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  # Desligados de propósito: ambos geram custo adicional.
  performance_insights_enabled = false
  monitoring_interval          = 0

  auto_minor_version_upgrade = true

  tags = {
    Name    = "${local.name}-${each.key}-postgres"
    Service = "${each.key}-service"
  }
}

# --------------------------------------------------
# SECRETS MANAGER — uma secret por banco, com a DATABASE_URL pronta
# --------------------------------------------------

resource "aws_secretsmanager_secret" "db" {
  for_each = local.databases

  name        = "${local.name}/rds/${each.key}"
  description = "Credenciais do PostgreSQL do ${each.key}-service"

  # 0 = apaga na hora no destroy. Sem isso a secret fica 30 dias em
  # "scheduled deletion" e bloqueia recriar com o mesmo nome.
  recovery_window_in_days = 0

  tags = {
    Name    = "${local.name}-${each.key}-db-secret"
    Service = "${each.key}-service"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  for_each = local.databases

  secret_id = aws_secretsmanager_secret.db[each.key].id

  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db[each.key].result
    host     = aws_db_instance.postgres[each.key].address
    port     = aws_db_instance.postgres[each.key].port
    dbname   = each.value.db_name
    # Formato exato que auth/flag/targeting esperam em DATABASE_URL.
    DATABASE_URL = format(
      "postgres://%s:%s@%s:%d/%s?sslmode=require",
      var.db_master_username,
      urlencode(random_password.db[each.key].result),
      aws_db_instance.postgres[each.key].address,
      aws_db_instance.postgres[each.key].port,
      each.value.db_name,
    )
  })
}
