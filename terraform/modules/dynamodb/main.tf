# ---------------------------------------------------------------------------
# DYNAMODB — tabela de eventos do analytics-service.
#
# A partition key é IMUTÁVEL depois de criada e precisa ser exatamente
# 'event_id': é a chave que o analytics-service monta em app.py antes do
# put_item. Errar aqui faz todo put falhar com ValidationException.
#
# PAY_PER_REQUEST: sem capacidade provisionada parada gerando custo.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "analytics" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  deletion_protection_enabled = false

  tags = {
    Name    = var.table_name
    Service = "analytics-service"
  }
}
