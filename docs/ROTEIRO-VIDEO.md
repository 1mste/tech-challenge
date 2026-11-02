# Roteiro do vídeo — Tech Challenge Fase 3

Limite de 20 minutos. O orçamento abaixo soma ~15, deixando folga.

| Cena | Assunto | Tempo |
|---|---|---|
| 0 | Abertura | 1 min |
| 1 | Infraestrutura como código | 5 min |
| 2 | Pipeline reprovando e passando | 5 min |
| 3 | CI atualizando o GitOps | 2 min |
| 4 | ArgoCD sincronizando | 3 min |

---

## Antes de ligar a câmera

```bash
cd ~/Projetos/tech-challenge
git status                      # precisa estar limpo e sincronizado
kubectl get applications -n argocd        # 5x Synced/Healthy
kubectl get scaledobject -n analytics-service   # READY=True
```

Abra e deixe prontas estas abas:

1. O repositório no GitHub, aba **Actions**
2. O console da AWS, região **N. Virginia (us-east-1)**, logado como
   `eksctl-admin` — **não como root**, senão o EKS não mostra pods e nós
3. Um terminal no diretório do projeto
4. O ArgoCD, com o port-forward já rodando:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

---

## Cena 0 · Abertura · 1 min

Diga em uma frase o que o sistema faz e o que mudou nesta fase:

> "O ToggleMaster liga e desliga funcionalidades sem republicar a aplicação.
> Na Fase 2 a infraestrutura foi criada à mão no console. Nesta fase, nada é
> criado clicando: está tudo em código, e o deploy acontece sozinho."

---

## Cena 1 · Infraestrutura como código · 5 min

### 1.1 A estrutura, no editor (~1 min 30)

Abra a árvore do `terraform/` e percorra os três níveis.

```
terraform/
├── bootstrap/        o cofre do state — roda UMA vez na vida do projeto
│
├── modules/          as peças. Cada pasta sabe construir UMA coisa:
│   ├── network/        VPC, 4 subnets, IGW, NAT, route tables, endpoints
│   ├── eks/            cluster, node group, OIDC, addons, access entries
│   ├── rds/            3 PostgreSQL + senhas no Secrets Manager
│   ├── redis/          ElastiCache do evaluation
│   ├── dynamodb/       tabela de eventos do analytics
│   ├── sqs/            fila + DLQ
│   ├── ecr/            5 repositórios de imagem
│   ├── irsa/           permissões AWS dos pods, sem access key
│   ├── github-oidc/    permissão do pipeline publicar no ECR
│   └── k8s-addons/     Nginx, ArgoCD, KEDA, Metrics Server
│
└── environments/     as receitas que juntam as peças:
    ├── dev/            monta a infraestrutura      <- 85 recursos
    └── dev-addons/     instala os componentes do cluster
```

### O que dizer, em três pontos

**1. Por que `modules/` e `environments/` são separados.**

> "Os módulos são genéricos — o módulo de RDS sabe criar um banco, não sabe
> quantos nem de que tamanho. Quem decide isso é o `environments/dev`.
> Para criar produção amanhã, é uma pasta nova reaproveitando as mesmas dez
> peças, com máquinas maiores. Nada é copiado e colado."

**2. Por que são 85 recursos para "sete itens" do enunciado.**

Vale mostrar a conta, porque o número impressiona e pode parecer inchaço:

| Módulo | Recursos | O que o enunciado chama disso |
|---|---:|---|
| `network` | 19 | "VPC, subnets, IGW e route tables" |
| `rds` | 16 | "3 instâncias RDS" |
| `eks` | 14 | "cluster EKS e node groups" |
| `irsa` | 12 | *(não está na lista — permissão dos pods)* |
| `ecr` | 10 | "5 repositórios" |
| `github_oidc` | 6 | *(não está na lista — habilita o item 2)* |
| `redis` | 5 | "1 ElastiCache" |
| `sqs` | 2 | "1 fila" (a segunda é a DLQ) |
| `dynamodb` | 1 | "1 tabela" |

> "Uma linha do enunciado vira vários recursos. 'Três bancos RDS' são 16:
> as 3 instâncias, o subnet group, o security group com suas regras, e as
> senhas sorteadas e guardadas no Secrets Manager."

**3. Por que são duas stacks, e não uma.**

Esse é o ponto técnico que diferencia a entrega:

> "Os addons precisam de um cluster que já exista. Se eu configurasse o
> provider do Helm apontando para um cluster criado na mesma stack, o
> Terraform não conseguiria montar o plano — ele resolve os providers antes
> dos recursos. E no `destroy` seria pior: o cluster sai primeiro e o
> provider fica tentando falar com um endereço morto."

A `dev-addons` descobre o cluster **pelo nome**, com data source — é isso que
mantém os dois estados independentes.

### Dois arquivos que vale abrir

Se houver tempo, abra estes dois — eles mostram decisão, não configuração:

**`modules/irsa/main.tf`** — a condição que trava cada role:

```hcl
condition {
  test     = "StringEquals"
  variable = "${var.oidc_provider_url}:sub"
  values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
}
```

> "Igualdade exata, não curinga. Essa role só pode ser assumida por uma
> ServiceAccount específica, de um namespace específico. Na Fase 2 os pods
> tinham `AmazonSQSFullAccess`."

**`modules/rds/main.tf`** — a senha que ninguém conhece:

```hcl
resource "random_password" "db" { ... }
resource "aws_secretsmanager_secret_version" "db" { ... }
```

> "A senha não é entrada do Terraform: é saída. Ele sorteia, guarda no
> Secrets Manager e ninguém da equipe chega a vê-la. O enunciado abre
> citando 'credenciais em arquivos de texto' como o problema a resolver."

### 1.2 O plano (~1 min)

```bash
terraform -chdir=terraform/environments/dev plan
```

Mostre terminando em `No changes` e diga por quê:

> "Nada mudou porque o que está na AWS é exatamente o que está no código.
> É essa a garantia da infraestrutura imutável."

### 1.3 O resultado na AWS (~2 min 30)

Percorra os links abaixo. Em cada um, aponte a tag `ManagedBy: Terraform`.

| # | Recurso | Link |
|---|---|---|
| 1 | **VPC** — use a aba *Resource map* | [vpc-0028333d1c2f16d87](https://console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0028333d1c2f16d87) |
| 2 | **NAT Gateway** | [nat-01ea79357ef2ddae0](https://console.aws.amazon.com/vpcconsole/home?region=us-east-1#NatGatewayDetails:natGatewayId=nat-01ea79357ef2ddae0) |
| 3 | **EKS** — abas *Compute* e *Add-ons* | [togglemaster-dev-eks](https://console.aws.amazon.com/eks/home?region=us-east-1#/clusters/togglemaster-dev-eks) |
| 4 | **RDS** — as 3 instâncias | [databases](https://console.aws.amazon.com/rds/home?region=us-east-1#databases:) |
| 5 | **ElastiCache** | [redis](https://console.aws.amazon.com/elasticache/home?region=us-east-1#/redis) |
| 6 | **DynamoDB** | [ToggleMasterAnalytics](https://console.aws.amazon.com/dynamodbv2/home?region=us-east-1#table?name=ToggleMasterAnalytics) |
| 7 | **SQS** — a fila e a DLQ | [queues](https://console.aws.amazon.com/sqs/v3/home?region=us-east-1#/queues) |
| 8 | **ECR** — os 5 repositórios | [repositories](https://console.aws.amazon.com/ecr/repositories?region=us-east-1) |
| 9 | **Load Balancer** | [add251f6b6ece…](https://console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:) |
| 10 | **S3 do tfstate** | [togglemaster-tfstate-698172256617](https://console.aws.amazon.com/s3/buckets/togglemaster-tfstate-698172256617?region=us-east-1) |

**Dois links que mostram decisão, não só recurso** — valem mais que os outros:

| Recurso | Link | O que apontar |
|---|---|---|
| **IAM → Roles** | [roles](https://console.aws.amazon.com/iam/home#/roles) | Abra `togglemaster-dev-analytics-irsa`, aba **Trust relationships**: a condição trava a role numa única ServiceAccount. É IRSA com permissão mínima |
| **Secrets Manager** | [secrets](https://console.aws.amazon.com/secretsmanager/listsecrets?region=us-east-1) | As 3 secrets `togglemaster-dev/rds/*`. Nenhuma senha está no Git — o Terraform as sorteou |

**Atalho opcional**, se o tempo apertar: o
[Tag Editor](https://console.aws.amazon.com/resource-groups/tag-editor/find-resources?region=us-east-1)
buscando `Project = togglemaster` lista tudo numa tela só.

### 1.4 O cluster funcionando (~30 s)

```bash
kubectl get nodes
kubectl get pods -A | grep -- -service
```

> "Dois nós, nove pods. Os nós estão em subnet privada — é o NAT Gateway
> que permite que eles baixem imagem do ECR e se registrem no cluster."

---

## Cena 2 · Pipeline reprovando e passando · 5 min

A cena mais importante. O enunciado pede explicitamente mostrar o pipeline
**falhando** na etapa de segurança e depois passando.

### 2.1 Introduzir a vulnerabilidade (~30 s)

```bash
printf '\n%s\n' 'Pillow==8.0.0' >> flag-service/requirements.txt
git commit -am "feat: adiciona processamento de imagens"
git push
```

> **Use `printf`, não `echo >>`.** Alguns `requirements.txt` não terminam em
> quebra de linha, e a dependência colaria na linha anterior — o scanner
> ignoraria a linha inválida e o pipeline passaria.

Diga por que o commit tem nome inocente:

> "É assim que acontece na vida real: alguém adiciona uma biblioteca sem
> saber que ela tem falha conhecida."

### 2.2 O pipeline reprovando (~2 min)

Na aba **Actions**, aguarde e mostre:

1. O job `flag-service (python)` **vermelho**, no passo `3a. SCA — dependencias (Trivy)`
2. Abra o log e mostre a tabela: `Pillow 8.0.0`, **8 vulnerabilidades CRITICAL**
3. **No Summary, os jobs `docker` e `update-gitops` como `Skipped`**

> O item 3 é o que prova o *"não prosseguir"* do enunciado. Não pule:
> a imagem vulnerável **nunca chegou ao ECR**.

Aproveite para explicar a diferença, que o pipeline cobre:

| Etapa | Examina | Exemplo |
|---|---|---|
| **SCA** (Trivy) | as bibliotecas | "o Pillow 8.0.0 tem falha conhecida" |
| **SAST** (gosec/bandit) | o seu código | "aqui você monta SQL concatenando string" |
| **Scan da imagem** | a imagem pronta | achou uma CVE na stdlib do Go embutida no binário |

### 2.3 Corrigir (~2 min 30)

```bash
git log --oneline -1          # confirme que o HEAD é o commit da dependência
git revert --no-edit HEAD
git push
```

> **Confira o `git log` antes.** O `revert` desfaz o commit do topo — se for
> outro, você desfaz a coisa errada.

Mostre os três jobs verdes. Essa execução já produz as Cenas 3 e 4.

---

## Cena 3 · CI atualizando o GitOps · 2 min

Emenda direto. No job **`update-gitops`**, abra o log:

```
gitops/flag-service/flag-deployment.yaml -> v1.0.0-<hash>
```

E mostre o commit novo no repositório, assinado por **`github-actions[bot]`**.

A frase que fecha o argumento:

> "O pipeline não roda `kubectl apply`. Ele só troca a tag da imagem no Git.
> Quem decide o que vai para o cluster é o ArgoCD, lendo do repositório."

Mostre também a imagem recém-publicada no
[ECR](https://console.aws.amazon.com/ecr/repositories?region=us-east-1),
com a tag do commit — não `latest`.

---

## Cena 4 · ArgoCD sincronizando · 3 min

No painel (`http://localhost:8080`), com `auth-service` aberto:

1. **Antes** — o app verde, `Synced`, na revisão antiga
2. Clique em **`REFRESH`**

   > O ArgoCD verifica o Git a cada 2 minutos. O botão só antecipa essa
   > checagem — a decisão continua sendo dele.

3. **`APP DIFF`** — o momento mais forte da cena:

   ```diff
   - image: ...flag-service:v1.0.0-<antigo>
   + image: ...flag-service:v1.0.0-<novo>
   ```

4. O status passando por `OutOfSync` → `Progressing` → `Synced`
5. No diagrama, os pods novos subindo e os antigos em `Terminating`

Num terminal ao lado, para mostrar o efeito:

```bash
kubectl get pods -n flag-service -w
```

### Fechamento

```bash
kubectl get deploy flag-service -n flag-service \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

E a aplicação respondendo pela internet:

```bash
curl -i http://add251f6b6ece41009b5c57e902e767a-14a75c8355448d2e.elb.us-east-1.amazonaws.com/flag/health
```

Se sobrar tempo, a aba **`HISTORY AND ROLLBACK`** lista cada implantação com
seu commit — bom argumento sobre rastreabilidade.

---

## Depois de gravar

```bash
./scripts/destroy-all.sh && ./scripts/check-costs.sh
```

---

## Dicas de execução

**Ensaie o ciclo da Cena 2 uma vez antes de gravar.** Você descobre os tempos
reais e não grava esperando.

**Corte as esperas na edição.** São ~4 min de pipeline e ~2 min de ArgoCD.
Mostrar o antes e o depois convence mais que a espera real.

**A ordem de gravação pode ser diferente da ordem do vídeo.** A Cena 2 altera
o código e muda as tags; se gravá-la antes da Cena 1, os valores mostrados lá
ficam defasados.

**Se o `Pillow==8.0.0` não acusar CRITICAL no dia** (a base do Trivy muda),
as reservas verificadas são `pyarrow==0.14.0` e `mlflow==1.11.0`. Confira
antes com:

```bash
./scripts/prep-video.sh --skip-push --skip-provision
```
