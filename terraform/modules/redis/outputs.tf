output "redis_endpoint" {
  description = "Endereço DNS do nó Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Porta do Redis"
  value       = aws_elasticache_cluster.redis.port
}

output "redis_url" {
  description = "REDIS_URL pronta para o evaluation-service"
  value       = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.port}/0"
}

output "redis_security_group_id" {
  description = "Security Group do Redis"
  value       = aws_security_group.redis.id
}
