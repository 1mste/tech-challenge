# Como testar tudo, do zero

Guia passo a passo para alguém que **nunca mexeu** com AWS, Terraform ou
Kubernetes. Cada passo tem um "como saber se deu certo".

Ao final você terá: a infraestrutura no ar na AWS, os 5 programas rodando,
um endereço público respondendo, e verá o sistema se multiplicar sozinho
quando a carga aumenta.

> ### 💰 Leia antes de começar
> A partir do Passo 4, a AWS começa a cobrar: **cerca de R$ 1,72 por hora.**
> Não é por mês — é por hora ligado. O Passo 11 ensina a desligar.
> Faça tudo numa sentada e desligue no fim. O teste inteiro custa ~R$ 3,50.

### Neste guia

**Com pressa?**
- [Atalho: um comando só](#atalho-um-comando-só)

**Entender primeiro** (leitura, ~10 min)
- [O que é este projeto](#o-que-é-este-projeto)
- [O que tem em cada pasta](#o-que-tem-em-cada-pasta)

**Preparar** (sem custo)
- [Passo 0 — Instalar as ferramentas](#passo-0--instalar-as-ferramentas)
- [Passo 1 — Baixar o repositório](#passo-1--baixar-o-repositório)
- [Passo 2 — Testar na sua máquina](#passo-2--testar-na-sua-máquina-grátis-opcional)
- [Passo 3 — Criar o "cofre"](#passo-3--criar-o-cofre-uma-vez-por-conta)

**Construir** 💰 (~40 min)
- [Passo 4 — Construir a infraestrutura](#passo-4--construir-a-infraestrutura-)
- [Passo 5 — Conectar no cluster](#passo-5--conectar-no-cluster)
- [Passo 6 — Instalar os componentes](#passo-6--instalar-os-componentes-do-cluster-)
- [Passo 7 — Criar as senhas](#passo-7--criar-as-senhas-no-cluster)
- [Passo 7b — Criar as tabelas](#passo-7b--criar-as-tabelas-nos-bancos)
- [Passo 8 — Preencher os endereços](#passo-8--preencher-os-endereços-nos-manifestos)
- [Passo 9 — Ligar o ArgoCD](#passo-9--ligar-o-argocd-nos-5-serviços)

**Testar e desligar**
- [Passo 10 — Testar de verdade](#passo-10--testar-de-verdade)
- [Passo 11 — Desligar tudo](#passo-11--desligar-tudo-) ← **não pule este**
- [Se algo der errado](#se-algo-der-errado)
- [Resumo de bolso](#resumo-de-bolso)
- [O que ainda falta para a entrega](#o-que-ainda-falta-para-a-entrega)

> Com pressa? Pule direto para o [Resumo de bolso](#resumo-de-bolso) — são os
> comandos em sequência, sem explicação.

---

## Atalho: um comando só

Se você já tem as ferramentas instaladas (Passo 0) e o repositório clonado
(Passo 1), existe um script que executa **todos os passos de 3 a 9** de uma vez:

```bash
./scripts/provision-all.sh
```

Ele pede confirmação, avisa o custo e leva ~30 minutos. Cada etapa é
**idempotente**: se parar no meio, rode de novo que ele continua de onde
parou, sem duplicar nada.

```
./scripts/provision-all.sh --yes           # sem perguntar
./scripts/provision-all.sh --skip-images   # não constrói as imagens
./scripts/provision-all.sh --help          # as opções
```

> **Mesmo usando o atalho, vale ler o resto deste guia.** O script faz os
> passos; o guia explica o que cada um significa e, principalmente, como
> conferir se deu certo. Quando algo falha, é aqui que está a resposta.

Para desligar, também é um comando — e é o mais importante:

```bash
./scripts/destroy-all.sh && ./scripts/check-costs.sh
```

---

## O que é este projeto

O **ToggleMaster** é um sistema que permite ligar e desligar funcionalidades
de um aplicativo **sem precisar republicá-lo**.

Um exemplo do dia a dia: uma loja virtual quer testar um botão novo de
pagamento, mas só com 10% dos clientes. Em vez de publicar duas versões do
site, ela pergunta ao ToggleMaster "este cliente aqui pode ver o botão
novo?" e ele responde sim ou não.

Para fazer isso, o sistema foi dividido em **cinco programas pequenos**, cada
um com uma responsabilidade — é o que se chama de microsserviços:

| Programa | O que faz | Analogia |
|---|---|---|
| `auth-service` | Confere quem está perguntando e se pode perguntar | o porteiro |
| `flag-service` | Guarda a lista de funcionalidades que existem | o catálogo |
| `targeting-service` | Guarda as regras de **para quem** cada uma liga | o manual de regras |
| `evaluation-service` | Junta tudo e responde **sim ou não**, rapidíssimo | o atendente |
| `analytics-service` | Anota tudo que foi perguntado, para relatórios | o arquivista |

### Onde esses programas rodam

Eles não rodam num computador só. Rodam na nuvem da Amazon (AWS), num
ambiente que precisa ser construído antes. Traduzindo os termos técnicos:

| Termo técnico | O que é, na prática |
|---|---|
| **AWS** | O computador de outra pessoa, alugado por hora |
| **Terraform** | Uma planta de construção. Você escreve o que quer; ele constrói |
| **Imagem Docker** | O programa empacotado com tudo que precisa para rodar |
| **ECR** | O depósito onde essas imagens ficam guardadas |
| **Kubernetes (EKS)** | O gerente: põe os programas para rodar e repõe os que caem |
| **Pod** | Uma cópia de um programa em execução |
| **RDS** | O arquivo de documentos: guarda dados para sempre |
| **Redis** | O bloco de rascunho: guarda pouco, devolve rapidíssimo |
| **DynamoDB** | O caderno infinito: anota evento atrás de evento |
| **SQS** | A fila: um programa deixa recado, outro pega quando puder |
| **NAT Gateway** | A porta de serviço: os programas saem, ninguém entra |
| **Ingress** | A porta da frente: por onde o usuário chega |
| **ArgoCD** | O robô que mantém o que está rodando igual ao que está no Git |

### A ideia central

Nada neste projeto é feito clicando no site da AWS. **Está tudo escrito em
arquivos de texto**, guardados no Git. Um comando constrói, outro destrói, e
o resultado é idêntico todas as vezes.

Isso tem um nome: *Infraestrutura como Código*. E resolve um problema real —
antes, quando alguém montava tudo na mão, três meses depois ninguém lembrava
o que tinha feito, refazer levava dias, e sobravam coisas ligadas custando
dinheiro que ninguém sabia desligar.

---

## O que tem em cada pasta

```
tech-challenge/
│
├── auth-service/          ┐
├── flag-service/          │
├── targeting-service/     ├─ O CÓDIGO dos 5 programas
├── evaluation-service/    │  (cada um com seu "dockerfile")
├── analytics-service/     ┘
│
├── docker-compose.yml     Roda tudo no SEU computador, de graça
├── postgres/              Comandos que criam as tabelas dos bancos
│
├── terraform/             COMO CONSTRUIR o ambiente na AWS
├── gitops/                COMO RODAR os programas no ambiente
├── scripts/               Atalhos para as tarefas repetitivas
└── docs/                  Explicações (você está aqui)
```

### As três pastas que importam

Repare que cada uma responde a uma pergunta diferente:

| Pasta | Responde | Quem usa |
|---|---|---|
| `*-service/` | *O que o programa faz?* | quem escreve código |
| `terraform/` | *Onde isso vai rodar?* | quem cuida da infraestrutura |
| `gitops/` | *Como o programa roda lá?* | o ArgoCD, automaticamente |

### Dentro de `terraform/`

```
terraform/
├── bootstrap/        Cria um "cofre" onde o Terraform anota o que
│                     já construiu. Roda UMA VEZ na vida do projeto.
│
├── modules/          As peças de Lego. Cada pasta constrói UMA coisa:
│   ├── network/        a rua, os terrenos e a porta de serviço
│   ├── eks/            o gerente (o cluster)
│   ├── rds/            os 3 arquivos de documentos
│   ├── redis/          o bloco de rascunho
│   ├── dynamodb/       o caderno infinito
│   ├── sqs/            a fila
│   ├── ecr/            o depósito de imagens
│   ├── irsa/           os crachás: quem abre qual gaveta
│   ├── github-oidc/    crachá para o robô do GitHub
│   └── k8s-addons/     acessórios (porteiro, painel, medidor)
│
└── environments/     As receitas que juntam as peças:
    ├── dev/            monta tudo          <- Passo 4
    └── dev-addons/     os acessórios       <- Passo 6
```

> **Por que `dev` e `dev-addons` são separados?** Os acessórios só podem ser
> instalados depois que o cluster existe. Por isso são dois comandos, em
> dois momentos — é o Passo 4 e o Passo 6 deste guia.

### Dentro de `gitops/`

```
gitops/
├── auth-service/        ┐
├── flag-service/        │  Para cada programa: quantas cópias rodar,
├── targeting-service/   ├─ quanta memória pode usar, como saber se
├── evaluation-service/  │  está saudável, por qual endereço é chamado
├── analytics-service/   ┘
│
└── argocd/              Diz ao robô quais pastas vigiar
```

Esta é a pasta que o **ArgoCD** fica observando. Se você alterar um arquivo
aqui e publicar no Git, ele aplica a mudança no ambiente sozinho — e se
alguém mexer no ambiente por fora, ele **desfaz**. Isso é intencional.

### Dentro de `scripts/`

| Script | Quando usar |
|---|---|
| `provision-all.sh` | **Faz os Passos 3 a 9 de uma vez** |
| `create-secrets.sh` | Passo 7 — leva as senhas do cofre da AWS para o ambiente |
| `apply-schema.sh` | Cria as tabelas nos 3 bancos (as aplicações não criam sozinhas) |
| `render-gitops.sh` | Passo 8 — preenche os endereços nos arquivos de configuração |
| `outputs.sh` | A qualquer momento — mostra todos os endereços |
| `destroy-all.sh` | Passo 11 — **desliga tudo**, na ordem certa |
| `check-costs.sh` | Depois de desligar — confirma que nada ficou cobrando |

---

## Passo 0 — Instalar as ferramentas

| Ferramenta | Para que serve |
|---|---|
| **Git** | Baixar o repositório |
| **AWS CLI** | Conversar com a AWS |
| **Terraform** (1.10+) | Construir a infraestrutura |
| **kubectl** | Conversar com o cluster |
| **helm** | Instalar componentes no cluster |
| **jq** | Ler as respostas em JSON |
| **Docker** | Testar na sua máquina (Passo 2) |

Depois, conecte sua conta:

```bash
aws configure
```

Ele pede 4 coisas: chave de acesso, chave secreta, região (`us-east-1`) e
formato (`json`).

**✅ Como saber se deu certo:**

```bash
aws sts get-caller-identity
```

Deve aparecer um número de conta e seu usuário. Se der erro, as chaves estão
erradas.

---

## Passo 1 — Baixar o repositório

```bash
git clone https://github.com/SUA-ORG/tech-challenge.git
cd tech-challenge
```

**✅ Como saber se deu certo:** rode `ls`. Devem aparecer as pastas
`terraform`, `gitops`, `scripts` e as cinco `*-service`.

---

## Passo 2 — Testar na sua máquina (grátis, opcional)

Antes de gastar na AWS, veja o sistema funcionando localmente:

```bash
docker compose up -d
docker compose ps
```

**✅ Como saber se deu certo:** devem aparecer **9 contêineres** — os 5
programas mais 2 bancos PostgreSQL, 1 Redis e 1 DynamoDB local.

Para desligar:

```bash
docker compose down
```

> Isso não custa nada: roda tudo no seu computador.

---

## Passo 3 — Criar o "cofre" (uma vez por conta)

O Terraform precisa anotar em algum lugar o que já construiu.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Ele mostra o que pretende fazer e pergunta. Digite **`yes`**.

**✅ Como saber se deu certo:** termina com `Apply complete! Resources: 5 added`
e mostra o nome de um bucket.

**⚠️ Importante:** copie esse nome e confira se bate com o que está em
`terraform/environments/dev/backend.tf`. Se for diferente, edite o arquivo.

---

## Passo 4 — Construir a infraestrutura 💰

> **Aqui começa a cobrança.**

```bash
cd ../environments/dev
terraform init
terraform plan -out=tfplan
```

O `plan` **não constrói nada** — só mostra a lista.

**✅ Deve terminar com:** `Plan: 70 to add, 0 to change, 0 to destroy.`

Agora construa:

```bash
terraform apply tfplan
```

**⏱️ Demora cerca de 20 minutos.** O cluster sozinho leva 10. É normal a
tela ficar parada em `Still creating...`. **Não interrompa.**

**✅ Como saber se deu certo:** `Apply complete! Resources: 70 added.`

---

## Passo 5 — Conectar no cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name togglemaster-dev-eks
kubectl get nodes
```

**✅ Deve aparecer:**

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-11-174.ec2.internal   Ready    <none>   78s   v1.36.5-eks
ip-10-0-12-90.ec2.internal    Ready    <none>   77s   v1.36.5-eks
```

Duas máquinas, ambas `Ready`. Se aparecer `NotReady`, espere 2 minutos e
tente de novo.

---

## Passo 6 — Instalar os componentes do cluster 💰

```bash
cd ../dev-addons
terraform init
terraform apply
```

Instala quatro coisas: o **recepcionista** (Nginx, que cria o endereço
público), o **medidor de uso** (Metrics Server), o **painel de controle**
(ArgoCD) e o **KEDA** (que escala pela fila).

**⏱️ ~5 minutos.**

**✅ Como saber se deu certo:**

```bash
kubectl get pods -n ingress-nginx
kubectl get pods -n argocd
kubectl get pods -n keda
```

Todos devem estar `Running`.

---

## Passo 7 — Criar as senhas no cluster

As senhas dos bancos **não estão no repositório** — o Terraform as sorteou e
guardou num cofre da AWS. Este script traz para o cluster:

```bash
cd ../../..
./scripts/create-secrets.sh
```

**✅ Como saber se deu certo:**

```bash
kubectl get secrets -A | grep -- -secret
```

Devem aparecer 4: `auth-secret`, `flag-secret`, `targeting-secret` e
`evaluation-secret`.

> O `analytics-service` não aparece — e está certo. Ele acessa a AWS por
> crachá automático (IRSA), sem senha nenhuma.

---

## Passo 7b — Criar as tabelas nos bancos

As aplicações **não criam as próprias tabelas**. Os arquivos em `postgres/`
só são aplicados sozinhos pelo `docker compose`, no seu computador. Na AWS,
é preciso rodar:

```bash
./scripts/apply-schema.sh
```

**✅ Como saber se deu certo:** termina com `Os 3 schemas foram aplicados.`

> **Por que isso engana:** sem as tabelas, os pods sobem `Running` e
> `Healthy` — porque o `/health` não consulta o banco. O erro só aparece na
> primeira chamada de verdade, como um 500 sem explicação.

---

## Passo 8 — Preencher os endereços nos manifestos

Os manifestos vêm com lacunas tipo `<REDIS_URL>`. Este script preenche com
os valores reais:

```bash
./scripts/render-gitops.sh
```

**✅ Como saber se deu certo:** ele lista cada serviço com o endereço da
imagem, e no fim diz quais marcadores sobraram. Deve sobrar **apenas**
`SUA-ORG` nos arquivos de `gitops/argocd/`.

Agora ajuste o endereço do seu repositório:

```bash
sed -i 's|https://github.com/SUA-ORG/tech-challenge.git|SEU-ENDERECO-AQUI|' gitops/argocd/*.yaml
```

E publique — **este passo é essencial**: o ArgoCD lê do GitHub, não do seu
computador.

```bash
git add -A
git commit -m "chore: preenche enderecos da infraestrutura"
git push
```

---

## Passo 9 — Ligar o ArgoCD nos 5 serviços

```bash
kubectl apply -f gitops/argocd/
```

Isso diz ao ArgoCD: "vigie estas 5 pastas no GitHub e mantenha o cluster
igual a elas".

**✅ Como saber se deu certo:**

```bash
kubectl get applications -n argocd
```

Os 5 devem ficar `Synced` e `Healthy` em 1–2 minutos.

### Ver o painel do ArgoCD

```bash
# Senha do usuário admin:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Abrir o painel:
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Abra **http://localhost:8080** no navegador. Usuário `admin`, senha a de
cima. Devem aparecer os 5 serviços em verde.

---

## Passo 10 — Testar de verdade

### 10.1 Os programas estão rodando?

```bash
kubectl get pods -A | grep -- -service
```

**✅** Devem aparecer 9 pods (2 de cada, exceto analytics com 1), todos
`Running`.

### 10.2 Descobrir o endereço público

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

Sai algo como `a1b2c3.elb.us-east-1.amazonaws.com`. Guarde:

```bash
export URL=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

> ⏱️ Pode levar 2–3 minutos até o endereço existir. Se vier vazio, espere.

### 10.3 Chamar pela internet

```bash
curl -i http://$URL/auth/health
curl -i http://$URL/flag/health
curl -i http://$URL/evaluation/health
```

**✅** Deve responder **200 OK**. Se vier **404**, o Ingress ainda está
subindo — espere um minuto.

### 10.4 Ver o sistema se multiplicar (HPA)

Em um terminal, fique observando:

```bash
kubectl get hpa -n evaluation-service -w
```

Em outro, gere carga:

```bash
kubectl run carga --rm -it --image=williamyeh/hey --restart=Never -- \
  -z 3m -c 50 http://evaluation-service.evaluation-service.svc.cluster.local/health
```

**✅** Em 1–2 minutos a coluna `REPLICAS` sobe de 2 para 4, 6, 8…

### 10.5 Ver o KEDA escalar pela fila

Mande mensagens para a fila:

```bash
QUEUE=$(terraform -chdir=terraform/environments/dev output -raw sqs_queue_url)
for i in $(seq 1 60); do
  aws sqs send-message --queue-url "$QUEUE" \
    --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"teste\",\"result\":true}" >/dev/null
done
kubectl get pods -n analytics-service -w
```

**✅** Em ~30 segundos o número de pods do analytics sobe sozinho — porque a
fila encheu, não porque a CPU subiu.

### 10.6 Confirmar que os dados chegaram

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics \
  --region us-east-1 --max-items 5
```

**✅** Devem aparecer registros com `event_id`.

---

## Passo 11 — Desligar tudo 💰

**Este é o passo mais importante do guia.**

```bash
./scripts/destroy-all.sh
```

Ele pede para digitar **`destruir`**. Leva ~20 minutos.

Depois, **sempre confira**:

```bash
./scripts/check-costs.sh
```

**✅ O ideal é ver `[ok]` em todas as linhas.** Se alguma disser
`[COBRANDO]`, ainda há algo ligado.

> `terraform destroy` terminar com sucesso **não** significa conta limpa.
> Por isso existe a conferência.

---

## Se algo der errado

| Mensagem | O que significa | O que fazer |
|---|---|---|
| `BucketAlreadyExists` no Passo 3 | O cofre já existe na AWS, mas o Terraform perdeu a anotação dele (o arquivo de estado é local e não vai para o Git) | O `provision-all.sh` resolve sozinho: ele adota o cofre existente. Rodando o passo na mão, use `terraform import` nos 5 recursos |
| `Error acquiring the state lock` | O Terraform foi interrompido e deixou o cofre trancado | Confirme que nenhum Terraform está rodando e use `terraform force-unlock <ID>` com o ID da mensagem |
| `You must be logged in to the server (Unauthorized)` | Suas chaves AWS estão certas, mas você não tem permissão **dentro** do cluster | Peça a quem criou a infraestrutura para incluir você em `team_access_entries` |
| Pod em `CreateContainerConfigError` | Falta a Secret | Rode o Passo 7 |
| Pod em `ImagePullBackOff` | A imagem não está no ECR | Rode `./05-build-push-ecr.sh` |
| Pod em `Pending` | Não cabe mais nos nós | Aumente `node_max_size` |
| `curl` responde 404 | O Ingress ainda está subindo | Espere 1 minuto |
| Nós ficam `NotReady` | Sem saída de internet (NAT) | Confirme `enable_nat_gateway = true` |
| O destroy trava numa subnet | A AWS está liberando conexões | Normal até 10 min; o script trata sozinho |

---

## Resumo de bolso

```bash
# Construir
cd terraform/bootstrap     && terraform init && terraform apply
cd ../environments/dev     && terraform init && terraform apply
aws eks update-kubeconfig --region us-east-1 --name togglemaster-dev-eks
cd ../dev-addons           && terraform init && terraform apply
cd ../../..
./scripts/create-secrets.sh
./scripts/render-gitops.sh && git add -A && git commit -m "chore: enderecos" && git push
kubectl apply -f gitops/argocd/

# Conferir
kubectl get nodes                      # 2x Ready
kubectl get applications -n argocd     # 5x Synced/Healthy
curl -i http://$URL/auth/health        # 200 OK

# Destruir
./scripts/destroy-all.sh
./scripts/check-costs.sh               # tudo [ok]
```

---

## O que ainda falta para a entrega

Seguindo este guia você testa quase tudo. Mas a Fase 3 pede três coisas
técnicas e três entregáveis — e nem todos estão prontos.

### Os três requisitos técnicos

| | O que é | Situação |
|---|---|---|
| **1. Infraestrutura como código** | Construir o ambiente por arquivos, sem clicar no site da AWS | ✅ **pronto** — Passos 3 a 6 deste guia |
| **2. Pipeline automático** | A cada alteração no código: testar, procurar falhas de segurança e publicar | 🟡 **falta a maior parte** |
| **3. Implantação automática** | Um robô mantém o ambiente igual ao que está no Git | ✅ **pronto** — Passos 8 a 10 |

### O que falta no requisito 2 — a parte maior

Hoje, quando alguém altera o código de um programa, **nada acontece
sozinho**. Alguém precisa construir a imagem e publicá-la na mão.

O que a Fase 3 pede é que, a cada alteração, uma sequência rode sozinha:

```
alterou o código
   ↓
1. compila e roda os testes
   ↓
2. confere o estilo do código (lint)
   ↓
3. PROCURA FALHAS DE SEGURANÇA  ← se achar algo CRÍTICO, para tudo aqui
   ↓
4. empacota a imagem e a examina de novo
   ↓
5. publica no depósito (ECR), identificada pela alteração
   ↓
6. troca a identificação aqui no gitops/ → o ArgoCD implanta sozinho
```

**O que já existe:** o crachá que permite ao robô do GitHub publicar no
depósito sem senha (feito no Terraform), e a varredura automática de cada
imagem que chega ao depósito.

**O que falta:** os cinco arquivos de pipeline, um por programa. São o
Requisito 2 inteiro, e é a única parte do projeto sem nada escrito.

> **Reflexo prático neste guia:** o Passo 8 usa a identificação `latest` na
> imagem. Quando o pipeline existir, ele passará a escrever ali a
> identificação exata de cada alteração — que é o que permite saber qual
> versão está no ar e voltar atrás quando algo quebra.

### Os três entregáveis

| Entregável | O que precisa ter | Situação |
|---|---|---|
| **Código no repositório** | Terraform, pipelines e manifestos | 🟡 falta só os pipelines |
| **Vídeo** (até 20 min) | Ver abaixo | ❌ não gravado |
| **Relatório** (.pdf/.txt) | Participantes, links, desafios e **print do custo** | ❌ não escrito |

#### O que o vídeo precisa mostrar

1. O ambiente sendo construído pelo Terraform (ou o resultado na AWS)
2. **O pipeline falhando** na etapa de segurança — e depois passando
3. O pipeline trocando a identificação da imagem no `gitops/`
4. O ArgoCD percebendo e implantando sozinho, com os 5 programas na tela

Os itens **1 e 4** você já consegue gravar hoje, com este guia. Os itens
**2 e 3** dependem do pipeline.

> **Dica para o item 2:** o jeito mais simples de mostrar o pipeline
> reprovando é acrescentar uma biblioteca velha e vulnerável num dos
> programas Python — por exemplo `requests==2.19.1` no `requirements.txt`.
> A etapa de segurança barra, você remove e mostra passando.

#### O que o relatório precisa ter

| Item | Onde buscar |
|---|---|
| Nomes dos participantes | — |
| Link da documentação e do vídeo | — |
| Resumo dos desafios e decisões | Ver abaixo |
| **Print da estimativa de custos** | Reproduzir na [AWS Pricing Calculator](https://calculator.aws) — itens abaixo |

### Duas pendências menores

| Pendência | Efeito se esquecer |
|---|---|
| ~~Aplicar o SQL nos 3 bancos~~ | ✅ resolvido: `./scripts/apply-schema.sh`, já incluído no `provision-all.sh` |
| Apontar o `repoURL` das Applications para o seu repositório | O ArgoCD não encontra os arquivos (Passo 8 avisa) |

### Resumindo

| | Falta | Esforço |
|---|---|---|
| Requisito 1 | — | — |
| Requisito 2 | os 5 pipelines | ~4 h |
| Requisito 3 | — | — |
| Vídeo e relatório | ambos | ~4 h |

#### Itens para a calculadora de custos

| Serviço | Configuração |
|---|---|
| Amazon EKS | 1 cluster |
| Amazon EC2 | 2 × `t3.medium`, Linux, sob demanda, 20 GiB gp3 |
| Amazon RDS | 3 × `db.t3.micro`, PostgreSQL, Single-AZ, 20 GiB gp3 |
| Amazon ElastiCache | 1 × `cache.t3.micro`, Redis |
| VPC NAT Gateway | 1, ~10 GB/mês de tráfego |
| Elastic Load Balancing | 1 Network Load Balancer |
| DynamoDB · SQS · ECR | on-demand, volume baixo (~3 GB no ECR) |

Deve dar perto de **US$ 237/mês**. Vale registrar no relatório que o
ambiente **não fica ligado o mês inteiro** — o uso real da entrega fica
entre **US$ 1 e 3**.

#### Desafios que valem citar no relatório

| Desafio | Decisão tomada |
|---|---|
| Nós em subnet privada não ficavam `Ready` | NAT Gateway único + VPC Endpoints gratuitos para S3 e DynamoDB |
| O código criava `evaluation_db`, mas quem precisa de banco é o `targeting` | Corrigido — o `evaluation` usa Redis, não PostgreSQL |
| Senha de banco em arquivo de texto | Gerada pelo Terraform e guardada no Secrets Manager; ninguém a conhece |
| Pods com `AmazonSQSFullAccess` | IRSA com permissão mínima, apontando para o ARN exato da fila e da tabela |
| Provider do Helm dependia de um cluster inexistente | Duas stacks separadas: infraestrutura e addons |
| `terraform destroy` travando e deixando custo | Ordem correta no script, mais limpeza de Load Balancer órfão e ENI do VPC CNI |
| `t3.small` deixaria pods em `Pending` | `t3.medium`: o limite não era CPU, era a quantidade de IPs por nó |
