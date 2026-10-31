# ---------------------------------------------------------------------------
# ELASTICACHE REDIS — cache do evaluation-service (o "hot path").
#
# Nó único cache.t3.micro: o objetivo aqui é latência de leitura, não
# durabilidade. Snapshot desligado porque o dado é descartável por definição.
# ---------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis-sg"
  description = "Acesso ao Redis a partir dos nos do EKS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-redis-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_cluster" {
  security_group_id = aws_security_group.redis.id
  description       = "Redis a partir do cluster EKS"

  referenced_security_group_id = var.cluster_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.redis.id
  description       = "Saida liberada"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.name}-redis-subnets"
  description = "Subnets privadas para o Redis"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${local.name}-redis-subnets"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id = "${local.name}-redis"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = var.parameter_group_name

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  snapshot_retention_limit = 0
  apply_immediately        = true

  tags = {
    Name    = "${local.name}-redis"
    Service = "evaluation-service"
  }
}
