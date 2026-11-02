# Imagens das aplicações no ECR

> Gerado automaticamente por `05-build-push-ecr.sh` em 2026-11-02 12:23:57.
> Registry: `698172256617.dkr.ecr.us-east-1.amazonaws.com` · Região: `us-east-1` · Tag: `b7b230b`

## Referências das imagens

| Serviço | Repositório ECR | Tag | Referência (campo `image:`) | Digest (pin imutável) |
|---|---|---|---|---|
| auth-service | auth-service | b7b230b | `698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service:b7b230b` | `auth-service@sha256:fe6599662b89ab0e55356bd1c44a0639cbba65aac802e6f60dfb9d0dd0141dbf` |
| flag-service | flag-service | b7b230b | `698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service:b7b230b` | `flag-service@sha256:95514f3abbdb0dba060a63ffd298590265e90c834d20b8c8207e45fb45e3600d` |
| targeting-service | targeting-service | b7b230b | `698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service:b7b230b` | `targeting-service@sha256:4cd8a2fe14f54123f45cf29cf4addb3c248b5a452e2f4645871a66b636bbe9c5` |
| evaluation-service | evaluation-service | b7b230b | `698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:b7b230b` | `evaluation-service@sha256:718401836e45a11f56315d60c5d1a569b37e1c1f478afb356c8a0406dbc3eb2e` |
| analytics-service | analytics-service | b7b230b | `698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service:b7b230b` | `analytics-service@sha256:e72f10bbaf4f3c97189afa0b9b1ea3733c15a179235f6bb263b3ca8ee9999260` |

## Blocos prontos para o Deployment

Recomendado: fixar (pin) pela **tag específica** ou pelo **digest**
(`@sha256:...`). Evite `:latest` em produção — dificulta rollback.

### auth-service

```yaml
    containers:
      - name: auth-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service:b7b230b          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service@sha256:fe6599662b89ab0e55356bd1c44a0639cbba65aac802e6f60dfb9d0dd0141dbf   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### flag-service

```yaml
    containers:
      - name: flag-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service:b7b230b          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service@sha256:95514f3abbdb0dba060a63ffd298590265e90c834d20b8c8207e45fb45e3600d   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### targeting-service

```yaml
    containers:
      - name: targeting-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service:b7b230b          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service@sha256:4cd8a2fe14f54123f45cf29cf4addb3c248b5a452e2f4645871a66b636bbe9c5   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### evaluation-service

```yaml
    containers:
      - name: evaluation-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:b7b230b          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service@sha256:718401836e45a11f56315d60c5d1a569b37e1c1f478afb356c8a0406dbc3eb2e   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

### analytics-service

```yaml
    containers:
      - name: analytics-service
        image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service:b7b230b          # pin por tag
        # image: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service@sha256:e72f10bbaf4f3c97189afa0b9b1ea3733c15a179235f6bb263b3ca8ee9999260   # (alternativa) pin por digest
        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest
```

## Para quem usa Kustomize

Cole em `kustomization.yaml` para injetar as imagens sem editar cada Deployment:

```yaml
images:
  - name: auth-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/auth-service
    newTag: "b7b230b"
  - name: flag-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/flag-service
    newTag: "b7b230b"
  - name: targeting-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/targeting-service
    newTag: "b7b230b"
  - name: evaluation-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/evaluation-service
    newTag: "b7b230b"
  - name: analytics-service
    newName: 698172256617.dkr.ecr.us-east-1.amazonaws.com/analytics-service
    newTag: "b7b230b"
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
