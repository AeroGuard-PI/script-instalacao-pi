#!/bin/bash

# Interrompe a execução imediatamente em caso de erro crítico
set -e

# Variáveis do sistema
USER_PI="projeto-pi"
SENHA_PADRAO="alterar"
DOCKER_NET="aeroguard-net"
BASE_DIR="/home/${USER_PI}/aeroguard"

echo "======================================================"
echo "    Iniciando Provisionamento do Ambiente AeroGuard   "
echo "======================================================"

# 1. Atualização do Sistema Operacional
echo "[ 1/8 ] Atualizando pacotes do sistema..."
sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1

# 2. Verificação e Instalação do Docker e Git
echo "[ 2/8 ] Instalando Docker e Git..."

# Garante o git e o openssl instalados
sudo apt install -y git openssl > /dev/null 2>&1

if docker -v > /dev/null 2>&1; then
    echo "Docker já instalado no sistema."
else
    echo "Docker não instalado no sistema."
    echo "Gostaria de instalar o Docker? [s/n]"
    read get
    if [ "$get" == "s" ] || [ "$get" == "S" ]; then
        echo "Instalando Docker..."
        sudo apt install docker.io -y > /dev/null 2>&1
    else
        echo "Instalação do Docker ignorada pelo usuário. O script não pode continuar sem o Docker."
        exit 1
    fi
fi

# 3. Verificação e Instalação do Java
echo "[ 3/8 ] Verificando instalação do Java..."
if java -version > /dev/null 2>&1; then
    echo "Java já instalado no sistema."
else
    echo "Java não instalado."
    echo "Gostaria de instalar o Java? [s/n]"
    read get
    if [ "$get" == "s" ] || [ "$get" == "S" ]; then
        echo "Instalando OpenJDK 17..."
        sudo apt install openjdk-17-jre -y > /dev/null 2>&1
    else
        echo "Instalação do Java ignorada pelo usuário."
    fi
fi

# 4. Habilitação do Serviço Docker
echo "[ 4/8 ] Iniciando serviços Docker..."
sudo systemctl start docker > /dev/null 2>&1
sudo systemctl enable docker > /dev/null 2>&1

# 5. Criação do Usuário do Projeto
echo "[ 5/8 ] Configurando usuário do sistema: ${USER_PI}..."
if id "$USER_PI" &>/dev/null; then
    echo "Usuário ${USER_PI} já existe."
else
    sudo useradd -m -s /bin/bash -p "$(openssl passwd -6 "$SENHA_PADRAO")" "$USER_PI"
    echo "Usuário ${USER_PI} criado com sucesso!"
fi

# Adicionando o usuário ao grupo docker
sudo usermod -aG docker "$USER_PI"

# 6. Criação da Rede Docker
echo "[ 6/8 ] Criando rede Docker (${DOCKER_NET})..."
if ! docker network ls | grep -q "$DOCKER_NET"; then
    docker network create "$DOCKER_NET" > /dev/null 2>&1
    echo "Rede ${DOCKER_NET} criada com sucesso!"
else
    echo "Rede ${DOCKER_NET} já existente."
fi

# 7. Clonagem Direta e Simples dos Repositórios
echo "[ 7/8 ] Clonando repositórios do projeto..."
sudo mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

if [ ! -d "BancodeDados" ]; then
    echo "Clonando Banco de Dados..."
    sudo git clone https://github.com/AeroGuard-PI/BancodeDados.git > /dev/null 2>&1
fi

if [ ! -d "Site" ]; then
    echo "Clonando Site..."
    sudo git clone https://github.com/AeroGuard-PI/Site.git > /dev/null 2>&1
fi

if [ ! -d "script-python" ]; then
    echo "Clonando Script Python..."
    sudo git clone https://github.com/AeroGuard-PI/script-python.git > /dev/null 2>&1
fi

# Ajusta as permissões de tudo para o usuário do projeto
sudo chown -R "$USER_PI":"$USER_PI" "$BASE_DIR"

# 8. Build e Execução dos Contêineres
echo "[ 8/8 ] Executando build e subindo os contêineres..."

# Limpeza de contêineres anteriores para não haver conflito de nomes
docker rm -f aeroguard-db aeroguard-site aeroguard-python 2>/dev/null || true

# 8.1 Banco de Dados (Sobe primeiro com persistência)
echo "-> Subindo Banco de Dados..."
cd "$BASE_DIR/BancodeDados"
docker build -t aeroguard-db:1.0 .
docker run -d \
    --name aeroguard-db \
    --network "$DOCKER_NET" \
    -e MYSQL_ROOT_PASSWORD=urubu100 \
    -e MYSQL_DATABASE=aeroguard \
    -p 3306:3306 \
    -v aeroguard-mysql-data:/var/lib/mysql \
    aeroguard-db:1.0

# Pausa necessária para o MySQL iniciar antes dos outros contêineres
echo "Aguardando estabilização do MySQL (15 segundos)..."
sleep 15

# 8.2 Site 
echo "-> Subindo Site..."
cd "$BASE_DIR/Site"
docker build -t aeroguard-site:1.0 .
docker run -d \
    --name aeroguard-site \
    --network "$DOCKER_NET" \
    -p 8080:3333 \
    --restart always \
    aeroguard-site:1.0

# 8.3 Agente Coletor Python
echo "-> Subindo Script Python..."
cd "$BASE_DIR/script-python"
docker build -t aeroguard-python:1.0 .
docker run -d \
    --name aeroguard-python \
    --network "$DOCKER_NET" \
    -e DB_HOST=aeroguard-db \
    -e DB_USER=root \
    -e DB_PASSWORD=urubu100 \
    -e DB_NAME=aeroguard \
    -v "$BASE_DIR/script-python:/app" \
    --restart always \
    aeroguard-python:1.0

echo "======================================================"
echo "    Provisionamento Concluído com Sucesso!            "
echo "    Site disponível no IP público porta 8080    "
echo "======================================================"
docker ps
