#!/bin/bash
set -e

echo "======================================================"
echo "    Iniciando Instalacao do Cliente AeroGuard         "
echo "======================================================"

# 1. Atualizacao do Sistema
echo "[ 1/5 ] Atualizando pacotes do sistema..."
sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1

# 2. Instalacao do Docker e Git
echo "[ 2/5 ] Instalando Docker e Git..."
sudo apt install -y docker.io git curl > /dev/null 2>&1
sudo systemctl start docker > /dev/null 2>&1
sudo systemctl enable docker > /dev/null 2>&1

# 3. Baixando os repositorios dos coletores
echo "[ 3/5 ] Baixando os projetos dos coletores..."
mkdir -p aeroguard-cliente && cd aeroguard-cliente
git clone --depth 1 https://github.com/AeroGuard-PI/java-client.git > /dev/null 2>&1
git clone --depth 1 https://github.com/AeroGuard-PI/script-python.git > /dev/null 2>&1

# 4. Construindo imagens locais - aqui o docker builda o jar automaticamente
echo "[ 4/5 ] Construindo imagens dos coletores Java e Python..."
sudo docker build -t aeroguard-java ./java-client > /dev/null 2>&1
sudo docker build -t aeroguard-python ./script-python > /dev/null 2>&1

# 5. Configuracao interativa (Login da Central e MAC da EC2)
echo "======================================================"
echo "    Configuracao da Empresa e Maquina                 "
echo "======================================================"
sudo docker run --rm -it --network host \
    -v "$(pwd)":/config \
    -v /:/host:ro \
    -e HOST_ROOT=/host \
    -e AEROGUARD_ENV=/config/coletor.env \
    aeroguard-python python configurar.py --configurar

# 6. Subindo os containers em segundo plano com restart automatico
echo "-> Iniciando monitoramento em segundo plano..."
sudo docker rm -f aeroguard-python aeroguard-java > /dev/null 2>&1 || true

sudo docker run -d --name aeroguard-python --network host --restart always \
    --env-file coletor.env -v /:/host:ro -e HOST_ROOT=/host \
    aeroguard-python python script-coleta-python.py --coletar > /dev/null 2>&1

sudo docker run -d --name aeroguard-java --network host --restart always \
    --env-file coletor.env -v /:/host:ro -e HOST_ROOT=/host \
    aeroguard-java > /dev/null 2>&1

echo "======================================================"
echo "    Coletores Instalados e Monitorando com Sucesso!   "
echo "    CPU, Memoria, Disco e Rede ativos em background.  "
echo "======================================================"
