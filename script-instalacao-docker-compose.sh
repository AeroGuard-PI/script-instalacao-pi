#!/bin/bash
set -e

echo "======================================================"
echo "    Iniciando Instalacao da Central AeroGuard        "
echo "======================================================"

# 1. Atualizacao do Sistema Operacional
echo "[ 1/5 ] Atualizando pacotes do sistema..."
sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1

# 2. Instalacao do Docker e dependencias
echo "[ 2/5 ] Instalando Docker..."
sudo apt install -y docker.io curl > /dev/null 2>&1
sudo systemctl start docker > /dev/null 2>&1
sudo systemctl enable docker > /dev/null 2>&1

# 3. Instalacao do Docker Compose (Material SPTech)
echo "[ 3/5 ] Baixando e instalando o Docker Compose..."
sudo curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 4. Baixar o docker-compose.yml atualizado do repositorio
echo "[ 4/5 ] Baixando arquivo docker-compose.yml atualizado..."
curl -fsSL "https://raw.githubusercontent.com/AeroGuard-PI/docker-compose/main/docker-compose.yml" -o docker-compose.yml

# 5. Gerar arquivo .env para o ambiente
echo "[ 5/5 ] Gerando arquivo .env da aplicacao..."
cat > .env << 'ENV'
AMBIENTE_PROCESSO=producao
APP_PORT=8080
DB_HOST=aeroguard-db
DB_PORT=3306
DB_DATABASE=AeroGuard
DB_USER=aeroguard_user
DB_PASSWORD=AeroGuard@2026
ENV

# 6. Subir os servicos com Docker Compose
echo "-> Subindo containers da Central..."
sudo docker-compose up -d > /dev/null 2>&1

# Identificar IP publico da EC2 para exibir o link correto
ip_publico=$(curl -s --max-time 3 https://ifconfig.me || echo "localhost")

echo "======================================================"
echo "    Instalacao Concluida com Sucesso!                 "
echo "    Acesse no seu navegador: http://${ip_publico}:8080"
echo "======================================================"
