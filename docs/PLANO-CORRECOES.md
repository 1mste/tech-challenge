# Plano para resolver os problemas pendentes

Levantado em 31/10/2026, depois de verificar o cluster e o pipeline em
funcionamento.

> ### ✅ Executado em 02/11/2026
> **Parte 1 (KEDA)** e **Parte 2 (pipeline)** foram aplicadas. O que falta
> validar está no fim deste documento, em "O que ainda não foi testado".

**Onde estamos:** a infraestrutura está completa e o GitOps está no ar — os
5 microsserviços rodam no cluster, sincronizados pelo ArgoCD. Sobraram dois
focos de problema: o autoescalonamento do `analytics-service` e o pipeline
de CI, que atende cerca de um terço do que o enunciado pede.

| Requisito | Situação | O que falta |
|---|---|---|
| 1 — Infraestrutura como código | ✅ completo | — |
| 2 — Pipeline CI/DevSecOps | 🔴 ~35% | 2 estágios inteiros + 4 defeitos |
| 3 — GitOps / ArgoCD | 🟡 quase | o KEDA e a atualização automática da tag |

---

## Parte 1 — O KEDA não consegue ler a fila

### O que está acontecendo

O `analytics-service` aparece como `Degraded` no ArgoCD. O programa em si
está rodando — o problema é o **autoescalonamento**.

A ideia era: quando a fila SQS encher, o KEDA percebe e cria mais cópias do
analytics. Para isso ele precisa perguntar à AWS "quantas mensagens há na
fila?". E é aí que falha:

```
awsSqsQueueScaler: GetQueueAttributes ... no EC2 IMDS role found
```

Traduzindo: *"tentei perguntar à AWS, mas ninguém me deu crachá"*.

### Por que aconteceu

Este foi um **erro de projeto meu**. Configurei assim:

```yaml
podIdentity:
  provider: aws
  identityOwner: workload     # <- a origem do problema
```

`identityOwner: workload` quer dizer "KEDA, use o crachá da aplicação que
você está escalando". Parece elegante — o `analytics-sa` já tem permissão de
ler a fila, por que criar outro crachá?

O detalhe que me escapou: **para pegar emprestado o crachá de alguém, você
precisa primeiro ter um crachá seu.** O KEDA roda com uma ServiceAccount
própria (`keda-operator`), e ela não tinha nenhuma identidade AWS. Sem
credencial de partida, ele não consegue nem iniciar a troca.

### Como resolver

Dar ao KEDA um crachá próprio, com permissão mínima: ler o tamanho da fila.
Três mudanças pequenas.

**1. Criar a role no Terraform** (`terraform/modules/irsa/`)

Acrescentar uma entrada para a ServiceAccount do KEDA:

```hcl
keda = {
  namespace       = "keda"
  service_account = "keda-operator"
}
```

E a permissão — apenas leitura de metadados da fila, nada mais:

```hcl
data "aws_iam_policy_document" "keda" {
  statement {
    sid       = "ReadQueueDepth"
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [var.sqs_queue_arn]
  }
}
```

> Repare: o KEDA **não** recebe permissão de ler ou apagar mensagens. Ele só
> precisa saber *quantas* existem. Quem consome a fila é a aplicação.

**2. Anotar a ServiceAccount do KEDA** (`terraform/modules/k8s-addons/`)

O Helm do KEDA aceita a annotation por parâmetro:

```hcl
set = [{
  name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
  value = var.keda_role_arn
}]
```

**3. Simplificar o `TriggerAuthentication`**
(`gitops/analytics-service/analytics-keda-auth.yaml`)

```yaml
spec:
  podIdentity:
    provider: aws
    # identityOwner: operator é o padrão — o KEDA usa o próprio crachá
```

### Como saber se funcionou

```bash
kubectl get scaledobject -n analytics-service
```

A coluna `READY` precisa virar `True` (hoje está `False`). Depois, o teste
de verdade — mande mensagens e veja escalar:

```bash
QUEUE=$(terraform -chdir=terraform/environments/dev output -raw sqs_queue_url)
for i in $(seq 1 60); do
  aws sqs send-message --queue-url "$QUEUE" --message-body "{\"teste\":$i}" >/dev/null
done
kubectl get pods -n analytics-service -w
```

Em ~30 segundos o número de pods deve subir. **É exatamente esta cena que o
vídeo da entrega precisa mostrar.**

⏱️ Cerca de 30 minutos, incluindo o teste.

---

## Parte 2 — O pipeline de CI

O enunciado pede 4 estágios. O `ci-cd.yml` atual tem os dois primeiros de
forma incompleta e **não tem os dois últimos**.

```
1. Build & Unit Test        🟡 parcial
2. Linter                   ❌ é só um "echo"
3. SCA + SAST               🟡 SCA sim, SAST não
4. Docker build → ECR       ❌ não existe
5. Atualizar tag no GitOps  ❌ não existe   (requisito 3)
```

### Problema 1 — As linguagens estão trocadas

O workflow assume que só o `analytics` é Python. Mas são três:

| Serviço | Linguagem real | No workflow |
|---|---|---|
| `auth-service` | Go | Go ✅ |
| `evaluation-service` | Go | Go ✅ |
| **`flag-service`** | **Python** | Go ❌ |
| **`targeting-service`** | **Python** | Go ❌ |
| `analytics-service` | Python | Python ✅ |

**Por que isso é grave e silencioso:** o passo de build em Go tem a guarda
`if [ -f go.mod ]`. Como `flag-service` e `targeting-service` não têm
`go.mod`, o passo **não faz nada e passa**. O pipeline fica verde sem ter
compilado nem testado dois dos cinco serviços.

**Correção:** trocar a condição por uma lista explícita.

```yaml
strategy:
  matrix:
    include:
      - { service: auth-service,       lang: go }
      - { service: evaluation-service, lang: go }
      - { service: flag-service,       lang: python }
      - { service: targeting-service,  lang: python }
      - { service: analytics-service,  lang: python }
```

E cada passo passa a usar `if: matrix.lang == 'go'`.

### Problema 2 — O linter não existe

O passo atual:

```yaml
- name: 2. Linter / Static Analysis
  run: |
    echo "Executando linter/análise para ${{ matrix.service }}..."
    cd ${{ matrix.service }}
```

Imprime uma frase e troca de pasta. Nada é verificado.

**Correção:**

```yaml
- name: 2. Linter (Go)
  if: matrix.lang == 'go'
  uses: golangci/golangci-lint-action@v6
  with:
    working-directory: ${{ matrix.service }}

- name: 2. Linter (Python)
  if: matrix.lang == 'python'
  run: |
    pip install flake8
    flake8 ${{ matrix.service }} --max-line-length=120
```

### Problema 3 — Falta o SAST

O passo se chama "SCA & SAST (Trivy)", mas **Trivy não faz SAST**. A
diferença:

| Sigla | O que examina | Exemplo do que encontra |
|---|---|---|
| **SCA** | as **bibliotecas** que você usa | "a versão X do Flask tem falha conhecida" |
| **SAST** | o **seu código** | "aqui você monta SQL concatenando string" |

Hoje só o primeiro roda. O enunciado pede os dois e cita `gosec` e `bandit`.

**Correção:**

```yaml
- name: 3b. SAST (Go)
  if: matrix.lang == 'go'
  uses: securego/gosec@master
  with:
    args: -severity medium ./${{ matrix.service }}/...

- name: 3b. SAST (Python)
  if: matrix.lang == 'python'
  run: |
    pip install bandit
    bandit -r ${{ matrix.service }} -ll
```

### Problema 4 — Um parâmetro escrito errado

```yaml
with:
  scan-dir: '${{ matrix.service }}'    # <- não existe
```

A `trivy-action` não tem `scan-dir`. O nome correto é **`scan-ref`**. Como o
parâmetro é desconhecido, ele é ignorado e o Trivy escaneia a **raiz do
repositório** — ou seja, a matriz de 5 serviços examina cinco vezes a mesma
coisa, e nenhuma delas é o serviço pretendido.

**Correção:** `scan-ref: '${{ matrix.service }}'`.

Aproveitar para unificar os passos 3 e 4, que hoje rodam o mesmo scan duas
vezes — um só, com bloqueio:

```yaml
- name: 3. SCA — dependências
  uses: aquasecurity/trivy-action@0.28.0
  with:
    scan-type: fs
    scan-ref: ${{ matrix.service }}
    severity: CRITICAL
    exit-code: '1'          # reprova o pipeline
    ignore-unfixed: true
```

### Problema 5 — Não há build nem publicação da imagem

É o estágio 4 do enunciado, inteiro. Hoje as imagens vão para o ECR pelo
`05-build-push-ecr.sh`, rodado na mão — exatamente o que a Fase 3 quer
eliminar.

**Correção:** um job novo, que só roda se tudo acima passar.

```yaml
docker:
  needs: security-and-quality
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  permissions:
    id-token: write        # obrigatório para o OIDC
    contents: read
  steps:
    - uses: actions/checkout@v4

    - id: meta
      run: echo "tag=v1.0.0-$(git rev-parse --short HEAD)" >> "$GITHUB_OUTPUT"

    - run: docker build -t ${{ matrix.service }}:${{ steps.meta.outputs.tag }} \
             -f ${{ matrix.service }}/dockerfile ${{ matrix.service }}

    - name: Scan da imagem pronta
      uses: aquasecurity/trivy-action@0.28.0
      with:
        image-ref: ${{ matrix.service }}:${{ steps.meta.outputs.tag }}
        severity: CRITICAL
        exit-code: '1'

    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ vars.AWS_ROLE_ARN }}
        aws-region: us-east-1

    - uses: aws-actions/amazon-ecr-login@v2
    # docker tag + docker push
```

> **O scan da imagem é diferente do scan do código.** Ele pega falhas da
> imagem base — por exemplo uma vulnerabilidade no `python:3.11-slim` —, que
> o scan do código-fonte não enxerga.

**Pré-requisito, já pronto no Terraform.** A role que permite publicar no
ECR sem senha existe; falta habilitá-la:

```bash
cd terraform/environments/dev
terraform apply -var='github_repositories=["1mste/tech-challenge"]'
terraform output -raw github_actions_role_arn
```

Guarde o ARN no GitHub em **Settings → Secrets and variables → Actions →
Variables**, com o nome `AWS_ROLE_ARN`. É *Variable*, não *Secret*: um ARN
não é segredo, e a segurança vem da condição na política de confiança, que
só aceita este repositório.

### Problema 6 — O CI não fecha o ciclo com o GitOps

Requisito 3: *"ao final do pipeline de CI, adicione um passo que atualiza a
tag da imagem no repositório de GitOps"*.

Hoje a tag em `gitops/` é escrita pelo `render-gitops.sh`, na mão.

**Correção:** um último job.

```yaml
update-gitops:
  needs: docker
  permissions:
    contents: write        # só este job escreve
  steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github.ref_name }}
    - run: |
        sed -i -E "s|(image: .*/${SERVICE}):.*|\1:${TAG}|" \
          gitops/${SERVICE}/${SERVICE%-service}-deployment.yaml
        git config user.name "github-actions[bot]"
        git commit -am "chore(${SERVICE}): imagem ${TAG}" || exit 0
        git push
```

**Três detalhes que quebram a primeira execução:**

| Detalhe | O que acontece sem ele |
|---|---|
| `ref: ${{ github.ref_name }}` no checkout | o runner fica em HEAD destacado e o `git push` falha com *"src refspec main does not match any"* |
| `contents: write` **neste job** | o topo do workflow concede só leitura; o push é rejeitado |
| `id-token: write` no job do Docker | o OIDC não emite o token e a autenticação na AWS falha |

**Não há risco de loop infinito:** um push feito com o `GITHUB_TOKEN` não
dispara workflows.

⏱️ Cerca de 4 horas para o pipeline completo.

---

## Ordem sugerida

| # | Etapa | Tempo | Por que nesta ordem |
|---|---|---|---|
| 1 | Corrigir o KEDA | 30 min | É infraestrutura e dá para validar agora, com o cluster no ar |
| 2 | Habilitar a role do GitHub Actions | 10 min | O job do Docker depende dela |
| 3 | Corrigir os estágios 1 a 3 | 1 h | Linguagens, linter, SAST, `scan-ref` |
| 4 | Acrescentar o estágio 4 (Docker → ECR) | 1 h 30 | — |
| 5 | Acrescentar o passo de GitOps | 1 h | Fecha o ciclo |
| 6 | Ensaiar a demonstração do vídeo | 30 min | — |

**Total: ~4 h 40.**

---

## Como provar que funcionou

O vídeo precisa de quatro cenas. Depois destas correções, todas ficam
possíveis:

| Cena | Como produzir |
|---|---|
| Infraestrutura por código | `terraform plan` / `apply`, ou o resultado no console |
| **Pipeline reprovando na segurança** | acrescentar `Pillow==8.0.0` num `requirements.txt`, mostrar o SCA barrar, remover e mostrar passar |
| Pipeline trocando a tag no GitOps | mostrar o commit automático em `gitops/` |
| ArgoCD sincronizando sozinho | a interface com os 5 serviços ficando verdes |

E, para a parte de escalabilidade herdada da Fase 2:

| Cena | Como produzir |
|---|---|
| HPA por CPU | gerar carga no `evaluation-service` com `hey` |
| **KEDA pela fila** | mandar 60 mensagens no SQS e ver os pods subirem |
| Dados no DynamoDB | `Explore items` na tabela `ToggleMasterAnalytics` |

---

## Uma observação sobre custo

Só as etapas 1 e 6 precisam do ambiente no ar (~US$ 0,33/hora). As de 2 a 5
são edição de arquivo e podem ser feitas com tudo desligado.

Se for parar entre uma etapa e outra:

```bash
./scripts/destroy-all.sh && ./scripts/check-costs.sh
```

Subir de novo leva ~5 minutos, já que o state e as imagens continuam
existindo.


---

## O que ainda não foi testado

As correções estão escritas e validadas no que dá para validar offline, mas
duas coisas só se provam executando:

| Item | Como validar | Por que não dá agora |
|---|---|---|
| **KEDA lendo a fila** | `kubectl get scaledobject -n analytics-service` → `READY=True` | a infraestrutura está desligada |
| **O pipeline rodando** | abrir a aba Actions no GitHub | depende de push e da variável `AWS_ROLE_ARN` |

### O que foi verificado offline

- `terraform validate` nas duas stacks, e `plan` mostrando 70 → **72**
  recursos (a role e a policy do KEDA)
- A política do KEDA restrita a `sqs:GetQueueAttributes` e `GetQueueUrl`,
  só na fila principal
- O `sed` do passo de GitOps, testado numa cópia: reescreve as 5 linhas
  `image:` corretamente
- Sintaxe Python dos 3 serviços (equivale ao `E9` do flake8)
- YAML do workflow

### O que falta para ligar o pipeline

```bash
cd terraform/environments/dev
terraform apply -var='github_repositories=["1mste/tech-challenge"]'
terraform output -raw github_actions_role_arn
```

O ARN vai em **Settings → Secrets and variables → Actions → Variables**,
com o nome `AWS_ROLE_ARN`. Sem isso, os estágios 4 e 5 falham na
autenticação com a AWS.

### Um aviso sobre os linters

`golangci-lint` e `flake8` agora rodam de verdade — antes eram um `echo`.
Pode ser que apontem problemas no código existente na primeira execução.
Não consegui testar localmente (Go e flake8 não estão instalados nesta
máquina), então vale rodar uma vez e ajustar.

O `flake8` foi configurado em dois passos de propósito: **bloqueia** apenas
em erro real (`E9,F63,F7,F82` — sintaxe inválida, nome indefinido) e
**reporta sem reprovar** as questões de estilo. Assim o pipeline não fica
vermelho por causa de linha longa.


---

## Verificação da cena de falha (02/11/2026)

Testei a dependência vulnerável contra o mesmo critério do pipeline
(`--severity CRITICAL --ignore-unfixed`):

| Dependência | CRITICAL | Serve? |
|---|---:|---|
| `requests==2.19.1` | 0 | ❌ as falhas dela são HIGH |
| `PyYAML==5.3.1` | 0 | ❌ |
| `Pillow==8.0.0` | **8** | ✅ |
| `pyarrow==0.14.0` | sim | ✅ reserva |
| `mlflow==1.11.0` | sim | ✅ reserva |

**`requests==2.19.1` não serve** — era a sugestão anterior e teria falhado
na gravação.

### Uma armadilha encontrada no caminho

Dois `requirements.txt` não terminavam em quebra de linha. Com isso:

```bash
echo "Pillow==8.0.0" >> flag-service/requirements.txt
# resultado: "requests==2.28.1Pillow==8.0.0"
```

A linha vira inválida, o Trivy a ignora, e **o pipeline passa quando
deveria reprovar** — um falso verde difícil de diagnosticar ao vivo.

Corrigido de duas formas: a quebra de linha foi acrescentada aos arquivos, e
o script usa `printf '\n%s\n'` em vez de `echo`.
