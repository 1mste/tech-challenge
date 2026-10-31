module "k8s_addons" {
  source = "../../modules/k8s-addons"

  enable_metrics_server = true
  enable_ingress_nginx  = true
  enable_argocd         = var.enable_argocd
  enable_keda           = var.enable_keda

  argocd_service_type = var.argocd_service_type
}
