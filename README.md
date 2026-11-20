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

## 3. Servidores Monitorados (Coletores Cliente)

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
| EC2s: acesso SSH | 22 | Seu IP de acesso |

Nas regras internas do Security Group, libere a porta 3306 apenas para o Security Group ou bloco de IP privado das EC2s monitoradas. Não exponha a porta 3306 para a internet.

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

Nos servidores monitorados:
```bash
sudo docker logs --tail 100 -f aeroguard-java
sudo docker logs --tail 100 -f aeroguard-python
```
