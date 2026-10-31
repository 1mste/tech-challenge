# ---------------------------------------------------------------------------
# IRSA — IAM Roles for Service Accounts
#
# Dá permissão AWS ao POD (não ao nó) via OIDC. Nenhuma access key envolvida.
#
# Evolução sobre a Fase 2: lá o cluster.yaml do eksctl anexava
# AmazonSQSFullAccess e AmazonDynamoDBFullAccess. Aqui as policies são
# mínimas e apontam para o ARN exato da fila e da tabela.
#
# Para usar, o Deployment precisa referenciar a ServiceAccount e a
# ServiceAccount precisa da annotation:
#   eks.amazonaws.com/role-arn: <role_arn deste módulo>
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  for_each = var.service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Trava a role para UMA service account de UM namespace específico.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.service_accounts

  name               = "${var.project_name}-${var.environment}-${each.key}-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = {
    Name           = "${var.project_name}-${var.environment}-${each.key}-irsa"
    ServiceAccount = "${each.value.namespace}/${each.value.service_account}"
  }
}

# --------------------------------------------------
# analytics-service: CONSOME da fila SQS e GRAVA no DynamoDB
# --------------------------------------------------

data "aws_iam_policy_document" "analytics" {
  statement {
    sid    = "ConsumeEvaluationQueue"
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ChangeMessageVisibility",
    ]

    resources = compact([var.sqs_queue_arn, var.sqs_dlq_arn])
  }

  statement {
    sid    = "WriteAnalyticsTable"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]

    resources = [
      var.dynamodb_table_arn,
      "${var.dynamodb_table_arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "analytics" {
  name   = "${var.project_name}-${var.environment}-analytics-policy"
  role   = aws_iam_role.this["analytics"].id
  policy = data.aws_iam_policy_document.analytics.json
}

# --------------------------------------------------
# evaluation-service: apenas PRODUZ mensagens na fila
# --------------------------------------------------

data "aws_iam_policy_document" "evaluation" {
  statement {
    sid    = "PublishEvaluationEvents"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]

    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "evaluation" {
  name   = "${var.project_name}-${var.environment}-evaluation-policy"
  role   = aws_iam_role.this["evaluation"].id
  policy = data.aws_iam_policy_document.evaluation.json
}
