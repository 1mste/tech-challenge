variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "queue_name" {
  description = "Nome da fila principal"
  type        = string
  default     = "togglemaster-analytics-events"
}

variable "visibility_timeout_seconds" {
  description = "Tempo que a mensagem fica invisível após ser recebida"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "Retenção das mensagens na fila principal"
  type        = number
  default     = 345600
}

variable "receive_wait_time_seconds" {
  description = "Long polling: segundos de espera por mensagem antes de retornar vazio"
  type        = number
  default     = 10
}

variable "max_receive_count" {
  description = "Tentativas antes de mandar a mensagem para a DLQ"
  type        = number
  default     = 3
}
