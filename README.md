# ToggleMaster — Tech Challenge Fase 3

Infraestrutura do ToggleMaster **inteiramente em código**. Terraform provisiona
VPC, cluster EKS, 3 bancos RDS PostgreSQL, ElastiCache Redis, DynamoDB, fila
SQS e 5 repositórios ECR; o state vive num bucket S3 remoto.

> "Se não está no código, não existe." Os scripts imperativos da Fase 2 foram
> substituídos integralmente por Terraform.

**Monorepo:** código das aplicações, infraestrutura e manifestos no mesmo
repositório. É o que faz o pipeline de CI e a pasta `gitops/` conviverem sem
precisar de token cruzado.

---

## 1. Estrutura

Monorepo: código das aplicações, infraestrutura e manifestos no mesmo
repositório. Isso faz o pipeline de CI e a pasta `gitops/` viverem juntos —
o passo que atualiza a tag da imagem usa o `GITHUB_TOKEN` padrão, sem PAT.

```
auth-service/  flag-service/  targeting-service/     # os 5 microsserviços
evaluation-service/  analytics-service/
docker-compose.yml                                   # ambiente local (Fase 2)
postgres/                                            # scripts de init dos bancos

terraform/
├── bootstrap/                 # cria o bucket S3 do state (roda 1x, state local)
├── modules/
│   ├── network/               # VPC, subnets, IGW, NAT, route tables, endpoints
│   ├── eks/                   # cluster, node group, OIDC, addons
│   ├── irsa/                  # permissões AWS dos pods (least privilege)
│   ├── rds/                   # 3 PostgreSQL + senhas no Secrets Manager
│   ├── redis/                 # ElastiCache
│   ├── dynamodb/              # ToggleMasterAnalytics
│   ├── sqs/                   # fila + DLQ
│   ├── ecr/                   # 5 repositórios
│   ├── github-oidc/           # [item 2] push no ECR sem access key
│   └── k8s-addons/            # [item 3] Metrics Server, Nginx, ArgoCD
└── environments/
    ├── dev/                   # stack de infraestrutura
    └── dev-addons/            # stack dos addons (precisa do cluster de pé)

gitops/                        # [item 3] manifestos que o ArgoCD observa
├── auth-service/ ... analytics-service/   # 1 namespace por serviço
└── argocd/                                # as 5 Applications
scripts/                       # render, secrets, outputs, destroy, custos
docs/                          # guias, custos, desafios, handoff
```

Para rodar o ambiente local da Fase 2: `docker compose up` na raiz (5 apps +
2 PostgreSQL + Redis + DynamoDB Local).

**Por que duas stacks?** Os providers `helm`/`kubernetes` precisam de um
cluster que já exista. Configurar provider a partir de output de recurso da
mesma stack é o anti-padrão clássico que quebra `plan` e `destroy`.

---

> **Nunca mexeu com AWS, Terraform ou Kubernetes?** Comece pelo
> [`docs/COMO-TESTAR.md`](docs/COMO-TESTAR.md) — explica o projeto do zero,
> sem jargão, e leva do clone até o sistema no ar.

## 2. Pré-requisitos

- Terraform >= 1.10 (o `use_lockfile` do backend S3 depende disso)
- AWS CLI v2 configurado (`aws configure`), kubectl, helm
- Conta AWS **pessoal**, com permissão de criar IAM roles

> AWS Academy não serve: o código cria roles de IAM (Opção B do enunciado).
> Para a Opção A seria preciso trocar as roles por `data.aws_iam_role.labrole`.

---

## 3. Subir o ambiente

**Caminho curto** — um comando faz tudo (bootstrap, infra, addons, imagens,
secrets, manifestos e ArgoCD):

```bash
./scripts/provision-all.sh
```

Idempotente: se parar no meio, rode de novo. `--help` lista as opções.

**Caminho detalhado**, se quiser entender cada etapa:

```bash
# --- 3.1 Backend remoto (uma vez por conta) ---
cd terraform/bootstrap
terraform init
terraform apply                       # cria o bucket do state
terraform output bucket_name          # confira se bate com o backend.tf

# --- 3.2 Infraestrutura ---
cd ../environments/dev
terraform init                        # conecta no backend S3
terraform plan -out=tfplan            # ~70 recursos
terraform apply tfplan                # ~20 min (o EKS é o gargalo)

# --- 3.3 Acesso ao cluster ---
$(terraform output -raw kubeconfig_command)
kubectl get nodes                     # esperado: 2 nós Ready

# --- 3.4 Addons: Metrics Server, Nginx Ingress e ArgoCD ---
cd ../dev-addons
terraform init && terraform apply
```

Depois, para ver tudo que a aplicação precisa:

```bash
./scripts/outputs.sh
```

---

## 4. Destruir (importante)

```bash
./scripts/destroy-all.sh     # respeita a ordem correta
./scripts/check-costs.sh     # confirma que nada ficou de pé
```

**A ordem importa.** O Nginx Ingress cria um NLB que o Terraform da infra não
conhece. Se ele continuar existindo, o NLB segue custando e a VPC não é
apagada (ENIs presas) — o `destroy` trava no timeout depois de ~20 minutos.
Por isso a stack de addons é destruída primeiro.

O bucket de state não é apagado pelo script (custa ~US$ 0 e guarda o
histórico). Para removê-lo: `aws s3 rb s3://<bucket> --force`.

---

## 5. Decisões de projeto

| Decisão | Motivo |
|---|---|
| **NAT Gateway** (1, compartilhado) | Nós em subnet privada sem rota default nunca ficam `Ready`. Único NAT custa metade de um por AZ. |
| **VPC Endpoints S3 + DynamoDB** | Gratuitos; tiram do NAT o tráfego de pull de imagem e de escrita do analytics. |
| **Senhas via `random_password` + Secrets Manager** | O enunciado cita "credenciais em arquivos de texto" como a dor a resolver. Nenhuma senha em tfvars ou no Git. |
| **IRSA com policy mínima** | A Fase 2 usava `AmazonSQSFullAccess`. Aqui a permissão aponta para o ARN exato da fila e da tabela. |
| **`t3.medium`, 2 nós (máx. 4)** | `t3.small` não comporta 5 serviços + ingress + metrics-server; o limite de ENI deixaria pods em `Pending`. |
| **Versões fixas** (EKS 1.36, PG 16, Redis 7.1) | Sem pin, dois `apply` em dias diferentes geram ambientes diferentes. |
| **Log group do EKS declarado** | Define retenção de 7 dias e garante que o `destroy` não deixe resíduo. |
| **ECR sem prefixo no nome** | Mantém compatibilidade com `05-build-push-ecr.sh` e com os manifestos. |

---

## 6. Mapa do enunciado → código

### Item 1 — IaC (completo)

| Requisito | Onde |
|---|---|
| VPC, subnets pub/priv, IGW, route tables | `modules/network` |
| Cluster EKS + Node Groups | `modules/eks` |
| 3 RDS PostgreSQL | `modules/rds` (auth_db, flags_db, targeting_db) |
| 1 ElastiCache Redis | `modules/redis` |
| 1 DynamoDB `ToggleMasterAnalytics` | `modules/dynamodb` |
| 1 Fila SQS | `modules/sqs` (+ DLQ) |
| 5 repositórios ECR | `modules/ecr` |
| Backend S3 remoto com lock | `terraform/bootstrap` + `environments/dev/backend.tf` |

### Item 2 — CI/CD & DevSecOps 🟡

Pronto para usar:
- `modules/github-oidc` — role assumida pelo GitHub Actions, com permissão
  restrita aos 5 repositórios ECR. **Sem access key.**
- ECR com `scan_on_push` ligado.

Para habilitar a role, quando o repositório existir:
```bash
terraform apply -var='github_repositories=["SUA-ORG/SEU-REPO"]'
terraform output -raw github_actions_role_arn   # → variável AWS_ROLE_ARN no GitHub
```

**Falta fazer:** os 5 workflows em `.github/workflows/`. É o único requisito
que ainda não tem nada escrito.

### Item 3 — GitOps & ArgoCD ✅

- `modules/k8s-addons` instala ArgoCD, Nginx, Metrics Server e **KEDA**.
- `gitops/<serviço>-service/` — os 5 serviços completos: ConfigMap,
  Deployment com requests/limits e probes, Service, Ingress com reescrita de
  caminho, e ServiceAccount com IRSA onde há acesso à AWS.
- `gitops/argocd/` — as 5 Applications com `prune` e `selfHeal`.
- Autoescalonamento: HPA por CPU no `evaluation`, **KEDA pela fila SQS** no
  `analytics`.
- `./scripts/render-gitops.sh` preenche os endereços a partir do Terraform.

**Falta fazer:** apontar o `repoURL` das Applications para o seu repositório.

---

## 7. Custos

**~US$ 0,32/hora** (R$ 1,72) com tudo de pé; o teste completo sai por ~R$ 3,50.
Suba, grave e destrua com `./scripts/destroy-all.sh` — depois confirme com
`./scripts/check-costs.sh`. A lista de itens para a calculadora da AWS está no
fim do [`COMO-TESTAR.md`](docs/COMO-TESTAR.md).

---

## 8. Documentação

| Documento | Para quem |
|---|---|
| [`docs/COMO-TESTAR.md`](docs/COMO-TESTAR.md) | **Tudo em um lugar:** o que é o projeto, o que faz cada pasta, como subir, como testar, como desligar, e o que falta para a entrega |
