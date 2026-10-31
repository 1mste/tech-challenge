output "table_name" {
  description = "Nome da tabela — valor da variável AWS_DYNAMODB_TABLE"
  value       = aws_dynamodb_table.analytics.name
}

output "table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.arn
}
