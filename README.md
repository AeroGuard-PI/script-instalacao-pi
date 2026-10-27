# Instalação AeroGuard

Este repositório tem dois scripts para EC2s Ubuntu, preferencialmente 24.04. A central hospeda MySQL e site. As outras EC2s executam os coletores Java e Python.

A EC2 baixa o que está publicado no GitHub.

## Preparar as EC2s

As instâncias precisam de saída para a internet para baixar pacotes, repositórios e imagens. Use a mesma VPC, que é a rede privada das EC2s. Configure os Security Groups antes da instalação:

| Destino | Porta TCP | Origem permitida |
| --- | --- | --- |
| Central: site e instalação | 8080 | EC2s monitoradas e seu IP para abrir o site |
| Central: MySQL | 3306 | EC2s monitoradas |
| EC2s: acesso SSH | 22 | Seu IP de acesso |

Nas regras internas, use os IPs privados ou o Security Group das EC2s monitoradas como origem. Não abra 3306 para a internet. 

Em cada EC2, clone apenas este repositório:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/AeroGuard-PI/script-instalacao-pi.git
cd script-instalacao-pi
```

## Central

```bash
sudo bash script-instalacao.sh
```

O script instala Docker quando necessário, prepara MySQL 26.10.0, o banco AeroGuard, os seeds e o site na porta 8080. Os seeds são executados somente quando o volume do banco está vazio. Não é necessário instalar Java, Maven ou Python no host.

Ao terminar, ele mostra o endereço interno, como `http://172.31.10.10:8080`. Use esse endereço nas EC2s monitoradas. Para abrir o site no navegador do seu computador, use `http://IP_PUBLICO_DA_CENTRAL:8080` e permita seu IP no Security Group.

## Servidores monitorados

Em cada outra EC2:

```bash
sudo bash script-instalacao-cliente.sh
```

Informe o endereço interno da central e faça login com um usuário cadastrado no site. O instalador obtém a empresa do usuário, identifica o MAC da interface principal e prepara a mesma configuração para Java e Python. Não é necessário informar CNPJ ou MAC nem editar um .env. A senha pessoal não é salva.

| Usuário de demonstração | Senha | Empresa |
| --- | --- | --- |
| joao.silva@email.com | SenhaSegura123 | Aeroporto de Guarulhos |
| maria.oliveira@email.com | SenhaSegura456 | Aeroporto de Congonhas |

Cada EC2 entra como uma nova máquina pelo par empresa + MAC normalizado. Os servidores fictícios do seed permanecem como demonstração. Hostname não identifica a máquina.

Java coleta download e upload em Mbps por interface. Python coleta CPU, memória e ocupação do disco principal da EC2. Os componentes são configurados separadamente: disponibilidade 1 permite coletar e 0 permanece inativo, inclusive após reinstalação.

Os containers compartilham a rede e o hostname da EC2 e leem o sistema de arquivos do host em /host, somente para leitura. Os dados medidos são da VM EC2. Os containers iniciam com a EC2, desde que não tenham sido parados manualmente.

## Atualizar e acompanhar

Na pasta script-instalacao-pi:

```bash
git pull --ff-only
```

Depois reexecute o script correspondente à EC2. Ele baixa novamente os projetos necessários e reconstrói as imagens. O cliente preserva a empresa e o MAC já configurados, sem pedir login novamente. Se o MAC salvo não estiver na EC2, a instalação para; não copie a configuração entre servidores.

Na central:

```bash
sudo docker logs --tail 100 aeroguard-db
sudo docker logs --tail 100 aeroguard-site
```

Nos servidores monitorados:

```bash
sudo docker logs --tail 100 aeroguard-java
sudo docker logs --tail 100 aeroguard-python
```

A configuração fica em /opt/aeroguard/config e contém credenciais técnicas.
