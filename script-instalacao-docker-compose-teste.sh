#!/usr/bin/env bash
# Instala uma Central AeroGuard de testes sem tocar na instalacao de producao.
set -euo pipefail
umask 077

TEST_DIR=/opt/aeroguard-teste
SITE_DIR="$TEST_DIR/Site"
ENV_FILE="$TEST_DIR/.env"
COMPOSE_FILE="$TEST_DIR/docker-compose-teste.yml"
REPOSITORY=https://github.com/AeroGuard-PI/Site.git

SITE_CONTAINER=aeroguard-site-teste
DB_CONTAINER=aeroguard-db-teste
NETWORK=aeroguard-net-teste
VOLUME=aeroguard-data-teste
SITE_IMAGE=aeroguard-site-teste

fail() {
    echo "Erro: $*" >&2
    exit 1
}

if [ "${EUID}" -ne 0 ]; then
    fail "execute este instalador com sudo"
fi

if [ "$#" -gt 1 ]; then
    fail "uso: sudo $0 [nome-da-branch]"
fi

command -v apt-get >/dev/null 2>&1 || fail "este instalador foi preparado para Ubuntu/Debian com apt"

echo "[ 1/5 ] Atualizando pacotes do sistema..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "[ 2/5 ] Instalando dependencias..."
DEBIAN_FRONTEND=noninteractive apt-get install -y curl git openssl
if ! command -v docker >/dev/null 2>&1; then
    echo "          Instalando Docker..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
fi
systemctl enable --now docker

echo "[ 3/5 ] Conferindo Docker Compose..."
if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    # So instala o binario quando nao existe Compose; assim uma instalacao de
    # producao ja configurada nao tem sua versao global substituida.
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
    read -r -p "Informe a branch de testes: " BRANCH
fi
[ -n "$BRANCH" ] || fail "nenhuma branch foi informada"

command -v git >/dev/null 2>&1 || fail "git nao esta instalado"
command -v docker >/dev/null 2>&1 || fail "Docker nao esta instalado"
command -v openssl >/dev/null 2>&1 || fail "openssl nao esta instalado"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || fail "nome de branch invalido"
docker info >/dev/null 2>&1 || fail "o servico Docker nao esta disponivel"

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    fail "Docker Compose nao esta instalado"
fi

echo "Validando a branch '$BRANCH' no repositorio remoto..."
git ls-remote --exit-code --heads "$REPOSITORY" "refs/heads/$BRANCH" >/dev/null 2>&1 || \
    fail "a branch '$BRANCH' nao existe ou nao pode ser acessada"

# Nunca reutilize recursos cujo estado nao seja conhecido: isso protege dados de
# uma instalacao de testes anterior e, principalmente, a instalacao de producao.
if docker container inspect "$SITE_CONTAINER" >/dev/null 2>&1 || \
   docker container inspect "$DB_CONTAINER" >/dev/null 2>&1; then
    fail "os containers de teste ja existem; este instalador nao os recria. Consulte os logs ou atualize-os manualmente."
fi
if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    fail "o volume '$VOLUME' ja existe sem os containers de teste; ele nao sera alterado por seguranca."
fi
if [ -e "$TEST_DIR" ]; then
    fail "o diretorio '$TEST_DIR' ja existe; ele nao sera sobrescrito por seguranca."
fi

echo "Clonando exclusivamente a branch '$BRANCH'..."
CLONE_DIR="$(mktemp -d)"
if ! git clone --depth 1 --single-branch --branch "$BRANCH" "$REPOSITORY" "$CLONE_DIR/Site" >/dev/null 2>&1; then
    fail "nao foi possivel clonar a branch informada"
fi

# A imagem de banco de producao nao e reutilizada: seus SQLs podem representar
# outra versao. Estes arquivos sao importados pelo MySQL somente no volume novo.
for sql in AeroGuard.sql seed-componentes.sql seed-dadosMock.sql; do
    [ -f "$CLONE_DIR/Site/src/database/$sql" ] || fail "a branch nao contem src/database/$sql"
done
[ -f "$CLONE_DIR/Site/Dockerfile" ] || fail "a branch nao contem Dockerfile"

install -d -m 700 "$TEST_DIR"
mv "$CLONE_DIR/Site" "$SITE_DIR"
rmdir "$CLONE_DIR"

DB_PASSWORD="$(openssl rand -hex 24)"
DB_ROOT_PASSWORD="$(openssl rand -hex 24)"
PUBLIC_IP="$(curl -fsS --max-time 3 https://ifconfig.me 2>/dev/null || echo localhost)"

cat > "$ENV_FILE" <<EOF
# Arquivo exclusivo da instalacao de testes. Nao copie para producao.
TEST_BRANCH=$BRANCH
AMBIENTE_PROCESSO=teste
APP_PORT=8080
APP_HOST=0.0.0.0
DB_HOST=$DB_CONTAINER
DB_PORT=3306
DB_DATABASE=AeroGuard
DB_USER=aeroguard_user
DB_PASSWORD=$DB_PASSWORD
COLETOR_DB_HOST=$PUBLIC_IP
COLETOR_DB_PORT=3307
COLETOR_DB_USER=aeroguard_user
COLETOR_DB_PASSWORD=$DB_PASSWORD
MYSQL_DATABASE=AeroGuard
MYSQL_USER=aeroguard_user
MYSQL_PASSWORD=$DB_PASSWORD
MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD
EOF
chmod 600 "$ENV_FILE"

cat > "$COMPOSE_FILE" <<'EOF'
services:
  db:
    image: mysql:8.0
    container_name: aeroguard-db-teste
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "3307:3306"
    volumes:
      - aeroguard-data-teste:/var/lib/mysql
      - ./Site/src/database/AeroGuard.sql:/docker-entrypoint-initdb.d/001-schema.sql:ro
      - ./Site/src/database/seed-componentes.sql:/docker-entrypoint-initdb.d/002-componentes.sql:ro
      - ./Site/src/database/seed-dadosMock.sql:/docker-entrypoint-initdb.d/003-dados.sql:ro
    networks:
      - aeroguard-net-teste
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h localhost -uroot -p$$MYSQL_ROOT_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 30

  site:
    build:
      context: ./Site
    image: aeroguard-site-teste
    container_name: aeroguard-site-teste
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      AMBIENTE_PROCESSO: ${AMBIENTE_PROCESSO}
      APP_PORT: ${APP_PORT}
      APP_HOST: ${APP_HOST}
      DB_HOST: ${DB_HOST}
      DB_PORT: ${DB_PORT}
      DB_DATABASE: ${DB_DATABASE}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      COLETOR_DB_HOST: ${COLETOR_DB_HOST}
      COLETOR_DB_PORT: ${COLETOR_DB_PORT}
      COLETOR_DB_USER: ${COLETOR_DB_USER}
      COLETOR_DB_PASSWORD: ${COLETOR_DB_PASSWORD}
    ports:
      - "8081:8080"
    networks:
      - aeroguard-net-teste

networks:
  aeroguard-net-teste:
    name: aeroguard-net-teste

volumes:
  aeroguard-data-teste:
    name: aeroguard-data-teste
EOF
chmod 600 "$COMPOSE_FILE"

echo "Validando Docker Compose e os SQLs da branch..."
(cd "$TEST_DIR" && "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config -q) || \
    fail "a configuracao do Docker Compose e invalida"

echo "Construindo a imagem local '$SITE_IMAGE' e iniciando o ambiente de testes..."
# A primeira subida tambem valida schema e seeds: o MySQL executa os tres SQLs
# no volume novo. Nenhum recurso de producao e referenciado por este Compose.
(cd "$TEST_DIR" && "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build)

echo "Aguardando a validacao do schema e dos seeds pelo MySQL..."
db_ready=0
for attempt in $(seq 1 60); do
    if [ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$DB_CONTAINER" 2>/dev/null)" = "healthy" ]; then
        db_ready=1
        break
    fi
    sleep 2
done
[ "$db_ready" -eq 1 ] || fail "o banco de testes nao ficou saudavel; consulte os logs de $DB_CONTAINER"

echo "Instalacao de testes concluida."
echo "Aplicacao: http://${PUBLIC_IP}:8081"
echo "Logs: sudo ${COMPOSE[*]} --env-file $ENV_FILE -f $COMPOSE_FILE logs -f"
