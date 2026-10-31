# ---------------------------------------------------------------------------
# ADDONS DO CLUSTER  —  habilita os ITENS 2 e 3
#
# Metrics Server .... pré-requisito do HPA (Fase 2, item 5)
# KEDA .............. escala o analytics pelo tamanho da fila SQS
# Nginx Ingress ..... acesso externo; provisiona o NLB na AWS
# ArgoCD ............ motor de GitOps (Fase 3, item 3)
#
# Vive numa stack separada (environments/dev-addons) de propósito: os
# providers helm/kubernetes precisam de um cluster que JÁ exista. Configurar
# provider a partir de output de recurso na mesma stack é o anti-padrão que
# quebra plan e destroy no Terraform.
#
# ORDEM DE DESTRUIÇÃO: destrua ESTA stack antes da stack de infra. O Nginx
# cria um NLB que o Terraform da infra não conhece; se ele continuar de pé,
# a VPC não é apagada e o NLB segue custando.
# ---------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"

  wait    = true
  timeout = 600
}

resource "helm_release" "ingress_nginx" {
  count = var.enable_ingress_nginx ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true

  # NLB: mais barato e mais rápido de provisionar que o ALB, e suficiente
  # porque quem faz o roteamento por path é o próprio Nginx.
  set = [
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
    },
    {
      name  = "controller.replicaCount"
      value = tostring(var.ingress_replica_count)
    },
  ]

  wait    = true
  timeout = 900
}

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # ClusterIP + port-forward evita um segundo Load Balancer (e seu custo).
  # Para expor pela URL pública, troque por um Ingress apontando ao Nginx.
  set = [
    {
      name  = "server.service.type"
      value = var.argocd_service_type
    },
    {
      name  = "configs.params.server\\.insecure"
      value = "true"
    },
  ]

  wait    = true
  timeout = 900

  depends_on = [helm_release.ingress_nginx]
}

# ---------------------------------------------------------------------------
# KEDA — escala orientada a evento
#
# O HPA padrão só enxerga CPU e memória. O analytics-service consome uma
# fila: a CPU dele pode estar baixa com milhares de mensagens acumuladas.
# O KEDA lê o tamanho da fila SQS direto e escala por ele — inclusive de 0.
#
# Sem isto instalado, o ScaledObject do analytics falha com
# "no matches for kind ScaledObject in version keda.sh/v1alpha1".
# ---------------------------------------------------------------------------

resource "helm_release" "keda" {
  count = var.enable_keda ? 1 : 0

  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  namespace        = var.keda_namespace
  create_namespace = true

  wait    = true
  timeout = 900
}
