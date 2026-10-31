output "queue_name" {
  description = "Nome da fila principal"
  value       = aws_sqs_queue.main.name
}

output "queue_url" {
  description = "URL da fila — valor da variável AWS_SQS_URL dos serviços"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN da fila principal"
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" {
  description = "URL da dead-letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN da dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}
