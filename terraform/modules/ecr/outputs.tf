output "repository_urls" {
  description = "URLs dos repositórios ECR, por serviço"
  value = {
    for name, repository in aws_ecr_repository.services : name => repository.repository_url
  }
}

output "repository_arns" {
  description = "ARNs dos repositórios ECR"
  value = {
    for name, repository in aws_ecr_repository.services : name => repository.arn
  }
}

output "registry_url" {
  description = "Host do registry, usado no docker login"
  value       = length(aws_ecr_repository.services) > 0 ? split("/", values(aws_ecr_repository.services)[0].repository_url)[0] : ""
}
