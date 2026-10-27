#!/usr/bin/env bash
set -euo pipefail
umask 077

BASE_DIR=/opt/aeroguard
CONFIG_DIR="$BASE_DIR/config"
DOCKER_NET=aeroguard-net

if [ "$EUID" -ne 0 ]; then
    echo "Execute com sudo."
    exit 1
fi
. /etc/os-release
if [ "$ID" != ubuntu ]; then
    echo "Este instalador foi preparado para uma EC2 Ubuntu."
    exit 1
fi
exec 9>/var/lock/aeroguard-central.lock
flock -n 9 || { echo "Já existe uma instalação central em andamento."; exit 1; }

echo "Iniciando instalação da central AeroGuard"
echo "[1/8] Instalando ferramentas"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git openssl iproute2

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

echo "[3/8] Conferindo o ambiente central"
if docker inspect aeroguard-db >/dev/null 2>&1; then
    if [ "$(docker inspect -f '{{index .Config.Labels "aeroguard.instalacao"}}' aeroguard-db)" != poc ]; then
        echo "Já existe um banco de uma instalação anterior. Faça backup e revise esse ambiente antes de continuar."
        exit 1
    fi
    if [ ! -f "$CONFIG_DIR/central.env" ]; then
        echo "Restaure /opt/aeroguard/config antes de reutilizar o banco existente."
        exit 1
    fi
elif docker volume inspect aeroguard-mysql-data >/dev/null 2>&1 && [ ! -f "$CONFIG_DIR/central.env" ]; then
    echo "Existe um volume anterior sem sua configuração. O banco não será apagado."
    exit 1
fi
if ! docker network inspect "$DOCKER_NET" >/dev/null 2>&1; then
    docker network create "$DOCKER_NET"
fi

echo "[4/8] Baixando o repositório do site"
FONTES="$(mktemp -d)"
trap 'rm -rf "$FONTES"' EXIT
git clone --depth 1 --branch main https://github.com/AeroGuard-PI/Site.git "$FONTES/Site"
for arquivo in Dockerfile src/database/AeroGuard.sql src/database/seed-componentes.sql src/database/seed-dadosMock.sql; do
    if [ ! -f "$FONTES/Site/$arquivo" ]; then
        echo "Arquivo $arquivo ausente. Atualize o repositório Site antes da instalação."
        exit 1
    fi
done
install -d -m 755 "$BASE_DIR" "$BASE_DIR/banco"
install -d -m 700 "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/central.env" ]; then
    IP_PRIVADO="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
    if [ -z "$IP_PRIVADO" ]; then
        echo "Não foi possível obter o IP privado desta EC2."
        exit 1
    fi
    SENHA_ROOT="$(openssl rand -hex 24)"
    SENHA_SITE="$(openssl rand -hex 24)"
    SENHA_COLETOR="$(openssl rand -hex 24)"
    cat > "$CONFIG_DIR/central.env" <<CONFIG
IP_PRIVADO=$IP_PRIVADO
SENHA_ROOT=$SENHA_ROOT
SENHA_SITE=$SENHA_SITE
SENHA_COLETOR=$SENHA_COLETOR
CONFIG
fi
. "$CONFIG_DIR/central.env"

cat > "$CONFIG_DIR/mysql.env" <<CONFIG
MYSQL_ROOT_PASSWORD=$SENHA_ROOT
MYSQL_ROOT_HOST=localhost
MYSQL_DATABASE=AeroGuard
TZ=UTC
CONFIG
cat > "$CONFIG_DIR/admin.cnf" <<CONFIG
[client]
user=root
password=$SENHA_ROOT
CONFIG
cat > "$CONFIG_DIR/site.env" <<CONFIG
AMBIENTE_PROCESSO=producao
APP_PORT=3333
APP_HOST=0.0.0.0
DB_HOST=aeroguard-db
DB_PORT=3306
DB_DATABASE=AeroGuard
DB_USER=aeroguard_site
DB_PASSWORD=$SENHA_SITE
COLETOR_DB_HOST=$IP_PRIVADO
COLETOR_DB_PORT=3306
COLETOR_DB_USER=aeroguard_coletor
COLETOR_DB_PASSWORD=$SENHA_COLETOR
CONFIG
chmod 600 "$CONFIG_DIR/central.env" "$CONFIG_DIR/mysql.env" "$CONFIG_DIR/admin.cnf" "$CONFIG_DIR/site.env"

echo "[5/8] Preparando SQL e seeds"
install -m 644 "$FONTES/Site/src/database/AeroGuard.sql" "$BASE_DIR/banco/001-schema.sql"
install -m 644 "$FONTES/Site/src/database/seed-componentes.sql" "$BASE_DIR/banco/002-componentes.sql"
install -m 644 "$FONTES/Site/src/database/seed-dadosMock.sql" "$BASE_DIR/banco/003-dados.sql"
cat > "$CONFIG_DIR/acessos.sql" <<SQL
CREATE USER IF NOT EXISTS 'aeroguard_site'@'%' IDENTIFIED BY '$SENHA_SITE';
GRANT SELECT, INSERT, UPDATE, DELETE ON AeroGuard.* TO 'aeroguard_site'@'%';
CREATE USER IF NOT EXISTS 'aeroguard_coletor'@'%' IDENTIFIED BY '$SENHA_COLETOR';
GRANT SELECT ON AeroGuard.empresa TO 'aeroguard_coletor'@'%';
GRANT SELECT ON AeroGuard.componentes TO 'aeroguard_coletor'@'%';
GRANT SELECT ON AeroGuard.discretizacao TO 'aeroguard_coletor'@'%';
GRANT SELECT, INSERT, UPDATE (hostname, so) ON AeroGuard.maquina TO 'aeroguard_coletor'@'%';
GRANT SELECT, INSERT ON AeroGuard.configuracao_maquina TO 'aeroguard_coletor'@'%';
GRANT SELECT, INSERT ON AeroGuard.captura TO 'aeroguard_coletor'@'%';
GRANT SELECT, INSERT ON AeroGuard.historico_alerta TO 'aeroguard_coletor'@'%';
SQL
chmod 644 "$CONFIG_DIR/acessos.sql"

echo "[6/8] Iniciando MySQL"
if docker inspect aeroguard-db >/dev/null 2>&1; then
    docker start aeroguard-db >/dev/null
else
    docker run -d --name aeroguard-db --label aeroguard.instalacao=poc \
        --network "$DOCKER_NET" --restart unless-stopped \
        --env-file "$CONFIG_DIR/mysql.env" -p "$IP_PRIVADO:3306:3306" \
        -v aeroguard-mysql-data:/var/lib/mysql \
        --mount "type=bind,src=$BASE_DIR/banco/001-schema.sql,dst=/docker-entrypoint-initdb.d/001-schema.sql,readonly" \
        --mount "type=bind,src=$BASE_DIR/banco/002-componentes.sql,dst=/docker-entrypoint-initdb.d/002-componentes.sql,readonly" \
        --mount "type=bind,src=$BASE_DIR/banco/003-dados.sql,dst=/docker-entrypoint-initdb.d/003-dados.sql,readonly" \
        --mount "type=bind,src=$CONFIG_DIR/acessos.sql,dst=/docker-entrypoint-initdb.d/004-acessos.sql,readonly" \
        --mount "type=bind,src=$CONFIG_DIR/admin.cnf,dst=/run/secrets/admin.cnf,readonly" \
        mysql:26.10.0
fi
pronto=0
for tentativa in $(seq 1 90); do
    if docker exec aeroguard-db mysql --defaults-extra-file=/run/secrets/admin.cnf \
        --protocol=TCP -h127.0.0.1 -e 'SELECT id FROM AeroGuard.empresa LIMIT 1' >/dev/null 2>&1; then
        pronto=1
        break
    fi
    sleep 2
done
if [ "$pronto" -ne 1 ]; then
    echo "O banco não ficou pronto. Confira: docker logs aeroguard-db"
    exit 1
fi

echo "[7/8] Construindo e iniciando o site"
docker build -t aeroguard-site:poc "$FONTES/Site"
if docker inspect aeroguard-site >/dev/null 2>&1; then
    docker rm -f aeroguard-site
fi
docker run -d --name aeroguard-site --label aeroguard.instalacao=poc \
    --network "$DOCKER_NET" --restart unless-stopped \
    --env-file "$CONFIG_DIR/site.env" -p 8080:3333 aeroguard-site:poc

echo "[8/8] Conferindo site e banco"
pronto=0
for tentativa in $(seq 1 30); do
    if curl -fsS --max-time 3 http://127.0.0.1:8080/saude >/dev/null 2>&1; then
        pronto=1
        break
    fi
    sleep 2
done
if [ "$pronto" -ne 1 ]; then
    echo "O site não ficou pronto. Confira: docker logs aeroguard-site"
    exit 1
fi
echo "Central instalada. Endereço interno: http://$IP_PRIVADO:8080"
echo "Execute script-instalacao-cliente.sh nas EC2s monitoradas."
