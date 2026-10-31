# Imagens das aplicações no ECR

> Gerado automaticamente por `05-build-push-ecr.sh` em 2026-10-31 10:19:51.
> Registry: `698172256617.dkr.ecr.us-east-1.amazonaws.com` · Região: `us-east-1` · Tag: `0398244`

## Referências das imagens

| Serviço | Repositório ECR | Tag | Referência (campo `image:`) | Digest (pin imutável) |
|---|---|---|---|---|
| auth-service | auth-service | 0398244 | `698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service:0398244` | `auth-service@sha256:159ae72af723f377291598b470ced0f07aa703723e814b57703dc69aac8d19ff` |
| flag-service | flag-service | 0398244 | `698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service:0398244` | `flag-service@sha256:0308685a44bc5e4af97888b79eaf79cb948e859eb7671ffe2adbd34560b14053` |
| targeting-service | targeting-service | 0398244 | `698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service:0398244` | `targeting-service@sha256:b4a160c0be413b88c13a9a1e6c208122c25ebf951e93b3c6a9b96310fd74c8b6` |
| evaluation-service | evaluation-service | 0398244 | `698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:0398244` | `evaluation-service@sha256:8f05eb1d8e0211a1ef06d370eeca6853806a675ba6a60a20166280cb979b85cb` |
| analytics-service | analytics-service | 0398244 | `698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service:0398244` | `analytics-service@sha256:b75dc5adae5c30886ae9877e1a9fcd70542617c5b7926a1b671c764c5764761a` |

## Blocos prontos para o Deployment

Recomendado: fixar (pin) pela **tag específica** ou pelo **digest**
(`@sha256:...`). Evite `:latest` em produção — dificulta rollback.

### auth-service

```yaml
    containers:
      - name: auth-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service:0398244          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service@sha256:159ae72af723f377291598b470ced0f07aa703723e814b57703dc69aac8d19ff   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### flag-service

```yaml
    containers:
      - name: flag-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service:0398244          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service@sha256:0308685a44bc5e4af97888b79eaf79cb948e859eb7671ffe2adbd34560b14053   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### targeting-service

```yaml
    containers:
      - name: targeting-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service:0398244          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service@sha256:b4a160c0be413b88c13a9a1e6c208122c25ebf951e93b3c6a9b96310fd74c8b6   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### evaluation-service

```yaml
    containers:
      - name: evaluation-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:0398244          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service@sha256:8f05eb1d8e0211a1ef06d370eeca6853806a675ba6a60a20166280cb979b85cb   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### analytics-service

```yaml
    containers:
      - name: analytics-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service:0398244          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service@sha256:b75dc5adae5c30886ae9877e1a9fcd70542617c5b7926a1b671c764c5764761a   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

## Para quem usa Kustomize

Cole em `kustomization.yaml` para injetar as imagens sem editar cada Deployment:

```yaml
images:
  - name: auth-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service
    newTag: "0398244"
  - name: flag-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service
    newTag: "0398244"
  - name: targeting-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service
    newTag: "0398244"
  - name: evaluation-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service
    newTag: "0398244"
  - name: analytics-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service
    newTag: "0398244"
```

## Lembretes de deploy

- **IRSA (permissão AWS sem chave):** o Deployment do **analytics** deve usar
  `serviceAccountName: analytics-sa` (namespace `analytics-service`) e o do
  **evaluation** deve usar `serviceAccountName: evaluation-sa` (namespace
  `evaluation-service`) para herdar as permissões de SQS/DynamoDB.
- **Pull do ECR:** os nós do cluster já têm permissão de leitura do ECR —
  **não** é preciso `imagePullSecret`.
- **Variáveis de ambiente** (endpoints de RDS/Redis, URL do SQS, tabela do
  DynamoDB): veja a saída do `04-outputs.sh` e a tabela de handoff no `README.md`.
