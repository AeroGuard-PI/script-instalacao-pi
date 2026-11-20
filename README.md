# Instalação AeroGuard

Este repositório possui os scripts de instalação automatizada para instâncias EC2 Ubuntu (preferencialmente 24.04).

Existem duas formas de instalar a Central (onde ficam o banco e o site) e um script dedicado para os servidores monitorados (onde rodam os coletores de telemetria Java e Python).

---

## 1. Central (Modo Docker Compose - Recomendado)

Sobe a Central completa usando imagens pré-compiladas do Docker Hub (`hnrq7/aeroguard-db:1.2` e `hnrq7/aeroguard-site:1.2`), criando a rede, volumes persistentes e gerando o `.env` de produção de forma automática.

Execute o comando em linha única:

```bash
curl -fsSL "https://raw.githubusercontent.com/AeroGuard-PI/script-instalacao-pi/main/script-instalacao-docker-compose.sh" -o script-instalacao-docker-compose.sh && chmod +x script-instalacao-docker-compose.sh && sudo ./script-instalacao-docker-compose.sh
```

---

## 2. Central (Modo Tradicional / Build Local)

Instala o Docker, clona os fontes do repositório, compila as imagens localmente na instância e configura os containers diretamente via script.

Execute o comando em linha única:

```bash
curl -fsSL "https://raw.githubusercontent.com/AeroGuard-PI/script-instalacao-pi/main/script-instalacao.sh" -o script-instalacao.sh && chmod +x script-instalacao.sh && sudo ./script-instalacao.sh
```

---

## 3. Central de testes (Docker Compose e branch especifica)

Este instalador cria uma Central **paralela e isolada** para validar uma branch do repositório do site. Ele clona somente a branch informada, constrói localmente a imagem `aeroguard-site-teste` com o `Dockerfile` daquela branch e inicializa um banco novo com `AeroGuard.sql`, `seed-componentes.sql` e `seed-dadosMock.sql` da mesma branch. Não utiliza a imagem `hnrq7/aeroguard-site`, nem compartilha containers, rede, volume ou `.env` com a produção.

Informe a branch no comando (não há branch padrão):

```bash
curl -fsSL "https://raw.githubusercontent.com/AeroGuard-PI/script-instalacao-pi/main/script-instalacao-docker-compose-teste.sh" -o script-instalacao-docker-compose-teste.sh && chmod +x script-instalacao-docker-compose-teste.sh && sudo ./script-instalacao-docker-compose-teste.sh nome-da-branch
```

Também é possível executar sem argumento; o script solicitará a branch e a validará no GitHub antes de continuar. Os recursos exclusivos são `aeroguard-site-teste`, `aeroguard-db-teste`, `aeroguard-net-teste` e `aeroguard-data-teste`. Uma nova execução não sobrescreve uma instalação de testes ou dados existentes; isso evita recriações acidentais.

Acesse a aplicação em `http://IP_PUBLICO:8081`.

Para os coletores que precisarem acessar esse banco de testes externamente, use `COLETOR_DB_PORT=3307`; internamente o site usa `DB_HOST=aeroguard-db-teste` e `DB_PORT=3306`.

---

## 4. Servidores Monitorados (Coletores Cliente)

Deve ser executado em cada EC2 que será monitorada. O instalador solicita o IP interno da Central e as credenciais de um usuário cadastrado no site para associar a máquina à empresa e iniciar a coleta de CPU, memória, disco e rede.

Execute o comando em linha única:

```bash
curl -fsSL "https://raw.githubusercontent.com/AeroGuard-PI/script-instalacao-pi/main/script-instalacao-cliente.sh" -o script-instalacao-cliente.sh && chmod +x script-instalacao-cliente.sh && sudo ./script-instalacao-cliente.sh
```

> Na instalação, após informar o IP da Central (ex: `52.2.223.49:8080`) e login, o script pergunta o IP do banco de dados: basta apertar **Enter** para usar o mesmo IP da Central (com porta `3306` automática) ou digitar outro IP caso o banco esteja em outra máquina.

### Gerenciar e Rodar Outros Scripts Python (`aeroguard`)

Após instalar, digite `aeroguard` em qualquer pasta do terminal para abrir o painel simples (sem precisar saber comandos Docker):

| Opção / Atalho | O que faz |
| --- | --- |
| `aeroguard` (opção `1`) ou `cliente` | Mostra se os coletores estão rodando e os últimos logs |
| `aeroguard` (opção `2`) ou `aeroguard rodar arquivo.py` | Roda qualquer script `.py` (da pasta atual ou de `script-python/`) na tela ou em segundo plano 24h |
| `aeroguard` (opção `3`) ou `aeroguard atualizar` | Atualiza do GitHub (opcional), rebuilda o container Python e reinicia o coletor principal |
| `aeroguard` (opção `4`) ou `aeroguard banco` | Troca o IP do banco (`DB_HOST`) no `coletor.env` e reinicia os coletores |
| `py <flags>` | Executa o `script-coleta-python.py` com parâmetros extras (ex: `py --help`) |

**Exemplo rápido — criei um script novo (`touch novo-script.py`):**
1. Crie e cole seu código em qualquer pasta: `nano novo-script.py`
2. Na mesma pasta, rode:
   ```bash
   aeroguard rodar novo-script.py
   ```
3. Escolha `1` para testar na tela ou `2` para deixar rodando 24h em segundo plano junto com o coletor principal (ele já recebe `DB_HOST`, `DB_PORT=3306` e todas as variáveis do `coletor.env` automaticamente).

---

## Preparar as EC2s e Security Groups

As instâncias precisam de acesso à internet para instalar pacotes e baixar imagens. Certifique-se de que estão na mesma VPC.

| Destino | Porta TCP | Origem permitida |
| --- | --- | --- |
| Central: site e dashboard | 8080 | EC2s monitoradas e seu IP para abrir o site |
| Central: MySQL | 3306 | EC2s monitoradas |
| Central de testes: site | 8081 | EC2s monitoradas e seu IP para abrir o site de testes |
| Central de testes: MySQL | 3307 | Somente Security Group ou IPs privados das EC2s autorizadas |
| EC2s: acesso SSH | 22 | Seu IP de acesso |

Nas regras internas do Security Group, libere a porta 3306 apenas para o Security Group ou bloco de IP privado das EC2s monitoradas. Não exponha a porta 3306 para a internet.

Para testes, aplique a mesma restrição à porta **3307**: permita-a apenas às EC2s autorizadas a executar coletores de teste. Não abra MySQL para a internet.

---

## Usuários de Demonstração (Seed)

| Usuário | Senha | Empresa |
| --- | --- | --- |
| joao.silva@email.com | SenhaSegura123 | Aeroporto de Guarulhos |
| maria.oliveira@email.com | SenhaSegura456 | Aeroporto de Congonhas |

---

## Acompanhamento de Logs

Na Central:
```bash
sudo docker logs --tail 100 -f aeroguard-db
sudo docker logs --tail 100 -f aeroguard-site
```

Na Central de testes:
```bash
sudo docker logs --tail 100 -f aeroguard-db-teste
sudo docker logs --tail 100 -f aeroguard-site-teste
# ou, no diretório da instalação:
sudo docker compose --env-file /opt/aeroguard-teste/.env -f /opt/aeroguard-teste/docker-compose-teste.yml logs -f
```

Nos servidores monitorados:
```bash
sudo docker logs --tail 100 -f aeroguard-java
sudo docker logs --tail 100 -f aeroguard-python
```
