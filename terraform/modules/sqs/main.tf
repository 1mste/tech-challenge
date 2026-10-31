# ---------------------------------------------------------------------------
# SQS — fila de eventos de avaliação.
#
# Produtor: evaluation-service (sqs.go)
# Consumidor: analytics-service (app.py), que grava no DynamoDB.
#
# A DLQ não é exigida pelo enunciado, mas evita que uma mensagem
# problemática fique em loop infinito e inflacione a métrica que o
# HPA/KEDA usa para escalar.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name = "${var.queue_name}-dlq"

  message_retention_seconds = 1209600 # 14 dias, o máximo
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.queue_name}-dlq"
  }
}

resource "aws_sqs_queue" "main" {
  name = var.queue_name

  # Precisa ser >= ao tempo que o analytics leva para processar e apagar a
  # mensagem, senão outro pod recebe a mesma mensagem e duplica no DynamoDB.
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  # Long polling: menos chamadas vazias, menos custo de API.
  receive_wait_time_seconds = var.receive_wait_time_seconds

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = var.queue_name
  }
}
