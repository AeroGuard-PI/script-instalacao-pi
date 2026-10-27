#!/usr/bin/env bash
set -euo pipefail
umask 077

BASE_DIR=/opt/aeroguard
CONFIG_DIR="$BASE_DIR/config"

if [ "$EUID" -ne 0 ]; then
    echo "Execute com sudo."
    exit 1
fi
. /etc/os-release
if [ "$ID" != ubuntu ]; then
    echo "Este instalador foi preparado para uma EC2 Ubuntu."
    exit 1
fi
exec 9>/var/lock/aeroguard-cliente.lock
flock -n 9 || { echo "Já existe uma instalação de cliente em andamento."; exit 1; }

echo "Iniciando instalação dos coletores AeroGuard"
echo "[1/8] Instalando ferramentas"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git

echo "[2/8] Preparando Docker"
if ! command -v docker >/dev/null; then
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod 644 /etc/apt/keyrings/docker.asc
    cat > /etc/apt/sources.list.d/aeroguard-docker.sources <<DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER
    chmod 644 /etc/apt/sources.list.d/aeroguard-docker.sources
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi
systemctl enable --now docker

echo "[3/8] Baixando os repositórios dos coletores"
FONTES="$(mktemp -d)"
trap 'rm -rf "$FONTES"' EXIT
for projeto in java-client script-python; do
    git clone --depth 1 --branch main "https://github.com/AeroGuard-PI/$projeto.git" "$FONTES/$projeto"
done
if [ ! -f "$FONTES/java-client/pom.xml" ] || [ ! -f "$FONTES/java-client/Dockerfile" ] || \
   [ ! -f "$FONTES/script-python/configurar.py" ] || [ ! -f "$FONTES/script-python/Dockerfile" ]; then
    echo "Os arquivos dos coletores estão incompletos. Atualize java-client e script-python antes da instalação."
    exit 1
fi
install -d -m 755 "$BASE_DIR"
install -d -m 700 "$CONFIG_DIR"

echo "[4/8] Construindo as imagens"
docker build -t aeroguard-java:poc "$FONTES/java-client"
docker build -t aeroguard-python:poc "$FONTES/script-python"

echo "[5/8] Identificando a empresa e esta EC2"
docker run --rm -it --network host --uts host \
    -e HOST_ROOT=/host -e AEROGUARD_ENV=/config/coletor.env \
    --mount type=bind,src=/,dst=/host,readonly \
    --mount "type=bind,src=$CONFIG_DIR,dst=/config" \
    aeroguard-python:poc python configurar.py --configurar

echo "[6/8] Preparando a execução em segundo plano"
for nome in aeroguard-java aeroguard-python; do
    if docker inspect "$nome" >/dev/null 2>&1; then
        docker rm -f "$nome"
    fi
done
ultima="$(docker run --rm --network host --env-file "$CONFIG_DIR/coletor.env" \
    --mount "type=bind,src=$CONFIG_DIR,dst=/config,readonly" \
    -e AEROGUARD_ENV=/config/coletor.env aeroguard-python:poc python configurar.py --ultima)"

echo "[7/8] Iniciando Java e Python"
for nome in java python; do
    docker run -d --name "aeroguard-$nome" --label aeroguard.instalacao=poc \
        --network host --uts host --restart unless-stopped \
        --env-file "$CONFIG_DIR/coletor.env" -e HOST_ROOT=/host \
        --mount type=bind,src=/,dst=/host,readonly "aeroguard-$nome:poc"
done

echo "[8/8] Conferindo novas capturas"
docker run --rm --network host --env-file "$CONFIG_DIR/coletor.env" \
    -e AEROGUARD_ENV=/config/coletor.env \
    --mount "type=bind,src=$CONFIG_DIR,dst=/config,readonly" \
    aeroguard-python:poc python configurar.py --aguardar "$ultima"
for nome in aeroguard-java aeroguard-python; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$nome")" != true ]; then
        echo "O coletor $nome não está em execução. Confira docker logs $nome."
        exit 1
    fi
done
echo "Coletores instalados e configurados para iniciar com a EC2."
