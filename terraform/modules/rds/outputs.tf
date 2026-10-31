output "db_addresses" {
  description = "Endereços DNS das instâncias PostgreSQL, por serviço"
  value = {
    for name, db in aws_db_instance.postgres : name => db.address
  }
}

output "db_endpoints" {
  description = "Endpoints (host:porta) das instâncias PostgreSQL"
  value = {
    for name, db in aws_db_instance.postgres : name => db.endpoint
  }
}

output "db_names" {
  description = "Nome do banco criado em cada instância"
  value = {
    for name, cfg in local.databases : name => cfg.db_name
  }
}

output "secret_arns" {
  description = "ARNs das secrets com as credenciais — consumidos pelo External Secrets no GitOps"
  value = {
    for name, secret in aws_secretsmanager_secret.db : name => secret.arn
  }
}

output "secret_names" {
  description = "Nomes das secrets no Secrets Manager"
  value = {
    for name, secret in aws_secretsmanager_secret.db : name => secret.name
  }
}

output "security_group_id" {
  description = "Security Group das instâncias RDS"
  value       = aws_security_group.rds.id
}

output "database_urls" {
  description = "DATABASE_URL completa por serviço. Sensível: não aparece no console sem -json."
  sensitive   = true
  value = {
    for name, cfg in local.databases : name => format(
      "postgres://%s:%s@%s:%d/%s?sslmode=require",
      var.db_master_username,
      urlencode(random_password.db[name].result),
      aws_db_instance.postgres[name].address,
      aws_db_instance.postgres[name].port,
      cfg.db_name,
    )
  }
}
