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

if ! grep -q "^SLACK_BOT_TOKEN=" coletor.env 2>/dev/null; then
    read -p "Token do Bot Slack (opcional, Enter para pular): " SLACK_TOKEN_INPUT
    echo "SLACK_BOT_TOKEN=${SLACK_TOKEN_INPUT}" >> coletor.env
fi

# 6. Subindo os containers em segundo plano com restart automatico
echo "-> Iniciando monitoramento em segundo plano..."
sudo docker rm -f aeroguard-python aeroguard-java > /dev/null 2>&1 || true

sudo docker run -d --name aeroguard-python --network host --restart always \
    --env-file coletor.env -v /:/host:ro -e HOST_ROOT=/host \
    aeroguard-python python script-coleta-python.py --coletar > /dev/null 2>&1

sudo docker run -d --name aeroguard-java --network host --restart always \
    --env-file coletor.env -v /:/host:ro -e HOST_ROOT=/host \
    aeroguard-java > /dev/null 2>&1

# 7. Configurando comando global 'aeroguard' e aliases de apresentacao
echo "-> Configurando comando global 'aeroguard' e aliases..."
ENV_FILE="$(pwd)/coletor.env"
PY_DIR="$(pwd)/script-python"

sudo tee /usr/local/bin/aeroguard > /dev/null << EOF
#!/bin/bash
set -e
ENV_FILE="${ENV_FILE}"
PY_DIR="${PY_DIR}"

mostrar_status() {
    echo "=== CONTAINERS DE TELEMETRIA ==="
    sudo docker ps -a --filter "name=aeroguard-" --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "=== TELEMETRIA HARDWARE (PYTHON) ==="
    sudo docker logs --tail 5 aeroguard-python 2>/dev/null || true
    echo ""
    echo "=== TELEMETRIA REDE (JAVA) ==="
    sudo docker logs --tail 5 aeroguard-java 2>/dev/null || true
}

rodar_script() {
    local ALVO="\$1"
    shift || true
    if [ -z "\$ALVO" ]; then
        echo ""
        echo "Scripts Python disponiveis (pasta atual e script-python):"
        ls -1 *.py "\${PY_DIR}"/*.py 2>/dev/null | sort -u || true
        echo ""
        read -p "Digite o nome ou caminho do arquivo .py: " ALVO
    fi
    if [ ! -f "\$ALVO" ] && [ -f "\${PY_DIR}/\$ALVO" ]; then
        ALVO="\${PY_DIR}/\$ALVO"
    fi
    if [ ! -f "\$ALVO" ]; then
        echo "Arquivo nao encontrado: \$ALVO"
        exit 1
    fi
    local CAMINHO_REAL="\$(realpath "\$ALVO")"
    local PASTA_SCRIPT="\$(dirname "\$CAMINHO_REAL")"
    local NOME_SCRIPT="\$(basename "\$CAMINHO_REAL")"
    local ARGS="\$*"
    if [ -z "\$ARGS" ]; then
        read -p "Parametros extras (opcional, Enter para nenhum): " ARGS
    fi
    echo "Como deseja rodar \${NOME_SCRIPT}?"
    echo "  1) Agora na tela (teste rapido)"
    echo "  2) Em segundo plano 24h (junto com o coletor principal)"
    read -p "Escolha [1/2]: " MODO
    if [ "\$MODO" = "2" ]; then
        local NOME_CONTAINER="aeroguard-\$(echo "\${NOME_SCRIPT%.py}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
        sudo docker rm -f "\$NOME_CONTAINER" > /dev/null 2>&1 || true
        sudo docker run -d --name "\$NOME_CONTAINER" --network host --restart always \
            --env-file "\${ENV_FILE}" -v /:/host:ro -e HOST_ROOT=/host \
            -v "\${PY_DIR}:/app" -v "\${PASTA_SCRIPT}:/extra" -e PYTHONPATH=/app \
            aeroguard-python python "/extra/\${NOME_SCRIPT}" \$ARGS
        echo "Container '\${NOME_CONTAINER}' iniciado em segundo plano!"
        echo "Para ver os logs: sudo docker logs -f \${NOME_CONTAINER}"
    else
        sudo docker run --rm -it --network host \
            --env-file "\${ENV_FILE}" -v /:/host:ro -e HOST_ROOT=/host \
            -v "\${PY_DIR}:/app" -v "\${PASTA_SCRIPT}:/extra" -e PYTHONPATH=/app \
            aeroguard-python python "/extra/\${NOME_SCRIPT}" \$ARGS
    fi
}

atualizar_python() {
    read -p "Baixar alteracoes do GitHub (git pull) antes de rebuildar? [s/N]: " PULL
    if [[ "\$PULL" =~ ^[sS]$ ]]; then
        git -C "\${PY_DIR}" pull
    fi
    echo "-> Rebuildando imagem aeroguard-python..."
    sudo docker build -t aeroguard-python "\${PY_DIR}"
    echo "-> Reiniciando coletor principal..."
    sudo docker rm -f aeroguard-python > /dev/null 2>&1 || true
    sudo docker run -d --name aeroguard-python --network host --restart always \
        --env-file "\${ENV_FILE}" -v /:/host:ro -e HOST_ROOT=/host \
        aeroguard-python python script-coleta-python.py --coletar > /dev/null 2>&1
    echo "Coletor Python atualizado e rodando!"
}

trocar_banco() {
    local ATUAL=\$(grep "^DB_HOST=" "\${ENV_FILE}" | cut -d= -f2-)
    echo "DB_HOST atual: \${ATUAL}"
    read -p "Novo IP do banco (Enter para manter): " NOVO_IP
    [ -z "\$NOVO_IP" ] && return 0
    NOVO_IP="\${NOVO_IP#http://}"
    NOVO_IP="\${NOVO_IP#https://}"
    NOVO_IP="\${NOVO_IP%%/*}"
    NOVO_IP="\${NOVO_IP%:8080}"
    sed -i "s|^DB_HOST=.*|DB_HOST=\${NOVO_IP}|" "\${ENV_FILE}"
    echo "DB_HOST atualizado para \${NOVO_IP}. Reiniciando coletores..."
    sudo docker rm -f aeroguard-python > /dev/null 2>&1 || true
    sudo docker run -d --name aeroguard-python --network host --restart always \
        --env-file "\${ENV_FILE}" -v /:/host:ro -e HOST_ROOT=/host \
        aeroguard-python python script-coleta-python.py --coletar > /dev/null 2>&1
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^aeroguard-java$"; then
        sudo docker rm -f aeroguard-java > /dev/null 2>&1 || true
        sudo docker run -d --name aeroguard-java --network host --restart always \
            --env-file "\${ENV_FILE}" -v /:/host:ro -e HOST_ROOT=/host \
            aeroguard-java > /dev/null 2>&1
    fi
    echo "Coletores reiniciados com DB_HOST=\${NOVO_IP}!"
}

case "\$1" in
    status) mostrar_status ;;
    rodar) shift; rodar_script "\$@" ;;
    atualizar) atualizar_python ;;
    banco) trocar_banco ;;
    *)
        echo "=========================================="
        echo "         AeroGuard - Painel Cliente       "
        echo "=========================================="
        echo "  1) Ver status e logs dos coletores"
        echo "  2) Rodar outro script Python (.py)"
        echo "  3) Atualizar / Rebuildar coletor Python"
        echo "  4) Trocar IP do banco de dados"
        echo "  0) Sair"
        echo "=========================================="
        read -p "Escolha uma opcao: " OPCAO
        case "\$OPCAO" in
            1) mostrar_status ;;
            2) rodar_script ;;
            3) atualizar_python ;;
            4) trocar_banco ;;
            0) exit 0 ;;
            *) echo "Opcao invalida." ;;
        esac
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/aeroguard

sudo tee /etc/profile.d/aeroguard.sh > /dev/null << EOF
# Aliases globais de apresentacao - Cliente Edge AeroGuard
alias cliente='aeroguard status'
alias py='sudo docker run --rm -it --network host --env-file ${ENV_FILE} -v /:/host:ro -e HOST_ROOT=/host -v ${PY_DIR}:/app aeroguard-python python script-coleta-python.py'
EOF
sudo chmod +x /etc/profile.d/aeroguard.sh

echo "======================================================"
echo "    Coletores Instalados e Monitorando com Sucesso!   "
echo "    CPU, Memoria, Disco e Rede ativos em background.  "
echo "    Digite 'aeroguard' no terminal para gerenciar.    "
echo "======================================================"
