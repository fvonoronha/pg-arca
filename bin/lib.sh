#!/usr/bin/env bash
# Funções e configuração comuns a todos os comandos do arca. É "sourced", não executado.
#
# Toda a configuração vem de variáveis de ambiente (ver .env.example). O armazenamento é feito
# pelo rclone, com um remoto chamado "arca" montado aqui a partir das variáveis STORAGE_*: assim
# o mesmo código grava na AWS S3, na Cloudflare R2, em qualquer serviço compatível com S3, num
# disco local ou em qualquer um dos ~70 serviços que o rclone suporta.

set -o errexit -o nounset -o pipefail

ARCA_VERSION="${ARCA_VERSION:-dev}"

# ------------------------------------------------------------------ log

log() { printf '%s [arca] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { log "AVISO: $*" >&2; }
die() {
    log "ERRO: $*" >&2
    exit 1
}

# Lê VAR ou, se existir, o arquivo apontado por VAR_FILE (Docker secrets).
read_secret() {
    local name="$1" file_var="${1}_FILE"
    if [ -n "${!file_var:-}" ]; then
        [ -r "${!file_var}" ] || die "$file_var aponta para um arquivo que não existe: ${!file_var}"
        printf '%s' "$(cat "${!file_var}")"
    else
        printf '%s' "${!name:-}"
    fi
}

# Nomes de banco e de arquivo aceitos nos comandos (evita caminho "../" no armazenamento e nomes
# estranhos criados por engano).
valid_name() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,62}$'; }
require_name() { valid_name "$1" || die "nome inválido: '$1' (use letras, números, _ . -)"; }

# Chaves de acesso nunca têm espaço, quebra de linha ou aspas: vindos do copiar/colar ou do .env
# (KEY="valor" vira valor COM aspas em vários orquestradores), quebrariam a assinatura da AWS
# ("SignatureDoesNotMatch") sem nenhuma pista. Só para credenciais de armazenamento; a senha do
# Postgres pode ter qualquer caractere.
clean_key() {
    local value
    value="$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$value" in \"*\" | \'*\') value="${value:1:${#value}-2}" ;; esac
    printf '%s' "$value"
}

is_true() { case "${1:-}" in true | TRUE | True | 1 | yes | sim) return 0 ;; *) return 1 ;; esac }

# ------------------------------------------------------------------ Postgres

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
PGPASSWORD="$(read_secret PGPASSWORD)"
export PGPASSWORD
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-15}"

BACKUP_DATABASES="${BACKUP_DATABASES:-all}"
BACKUP_GLOBALS="${BACKUP_GLOBALS:-true}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-6}"
PG_DUMP_EXTRA_ARGS="${PG_DUMP_EXTRA_ARGS:-}"
# Nome que identifica este servidor nos arquivos/pastas (vários servidores no mesmo bucket).
BACKUP_NAME="${BACKUP_NAME:-$PGHOST}"

# Bancos a copiar: lista do .env ou, com "all", todos menos os modelos e os de sistema.
list_databases() {
    if [ "$BACKUP_DATABASES" != "all" ]; then
        local name
        for name in $(printf '%s' "$BACKUP_DATABASES" | tr ',' ' '); do
            require_name "$name"
            printf '%s\n' "$name"
        done
        return
    fi
    psql -X -At -d postgres -c "SELECT datname FROM pg_database
        WHERE datallowconn AND NOT datistemplate AND datname NOT IN ('postgres')
        AND datname NOT LIKE 'prisma_migrate_shadow%'
        AND datname ~ '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,62}$' ORDER BY datname"
}

# ------------------------------------------------------------------ armazenamento (rclone)

STORAGE_PROVIDER="${STORAGE_PROVIDER:-}"
STORAGE_PREFIX="${STORAGE_PREFIX:-postgres-backups}"
STORAGE_PREFIX="${STORAGE_PREFIX#/}"
STORAGE_PREFIX="${STORAGE_PREFIX%/}"

# Classe de armazenamento mínima por tier (dias). Apagar antes disso é cobrado como se o arquivo
# tivesse ficado o período inteiro (AWS S3 / R2 IA).
min_days_for_class() {
    case "${1:-}" in
        STANDARD_IA | ONEZONE_IA) echo 30 ;;
        GLACIER_IR | GLACIER) echo 90 ;;
        DEEP_ARCHIVE) echo 180 ;;
        *) echo 0 ;;
    esac
}

# Monta o remoto "arca" do rclone só com variáveis de ambiente (RCLONE_CONFIG_ARCA_*): nada de
# arquivo de configuração com credenciais no disco.
setup_storage() {
    local key secret
    key="$(clean_key "$(read_secret STORAGE_ACCESS_KEY_ID)")"
    secret="$(clean_key "$(read_secret STORAGE_SECRET_ACCESS_KEY)")"

    case "$STORAGE_PROVIDER" in
        aws | r2 | s3)
            [ -n "${STORAGE_BUCKET:-}" ] || die "STORAGE_BUCKET não definido"
            export RCLONE_CONFIG_ARCA_TYPE=s3
            # O bucket já existe: não pede permissão de criar/listar buckets (credencial mínima).
            export RCLONE_CONFIG_ARCA_NO_CHECK_BUCKET=true
            if [ -n "$key" ]; then
                export RCLONE_CONFIG_ARCA_ACCESS_KEY_ID="$key"
                export RCLONE_CONFIG_ARCA_SECRET_ACCESS_KEY="$secret"
            else
                # Sem chaves: usa a credencial do ambiente (perfil IAM da máquina, AWS_*).
                export RCLONE_CONFIG_ARCA_ENV_AUTH=true
            fi
            [ -n "${STORAGE_CLASS:-}" ] && export RCLONE_CONFIG_ARCA_STORAGE_CLASS="$STORAGE_CLASS"
            case "$STORAGE_PROVIDER" in
                aws)
                    export RCLONE_CONFIG_ARCA_PROVIDER=AWS
                    export RCLONE_CONFIG_ARCA_REGION="${STORAGE_REGION:-us-east-1}"
                    # Criptografia no próprio S3 (além da nossa, opcional).
                    export RCLONE_CONFIG_ARCA_SERVER_SIDE_ENCRYPTION="${STORAGE_SERVER_SIDE_ENCRYPTION:-AES256}"
                    ;;
                r2)
                    export RCLONE_CONFIG_ARCA_PROVIDER=Cloudflare
                    export RCLONE_CONFIG_ARCA_REGION=auto
                    if [ -n "${STORAGE_ENDPOINT:-}" ]; then
                        export RCLONE_CONFIG_ARCA_ENDPOINT="$STORAGE_ENDPOINT"
                    else
                        [ -n "${STORAGE_R2_ACCOUNT_ID:-}" ] || die "Para r2, defina STORAGE_R2_ACCOUNT_ID (ou STORAGE_ENDPOINT)"
                        export RCLONE_CONFIG_ARCA_ENDPOINT="https://${STORAGE_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
                    fi
                    ;;
                s3)
                    [ -n "${STORAGE_ENDPOINT:-}" ] || die "Para s3 (compatível), defina STORAGE_ENDPOINT"
                    export RCLONE_CONFIG_ARCA_PROVIDER="${STORAGE_S3_PROVIDER:-Other}"
                    export RCLONE_CONFIG_ARCA_ENDPOINT="$STORAGE_ENDPOINT"
                    export RCLONE_CONFIG_ARCA_REGION="${STORAGE_REGION:-us-east-1}"
                    is_true "${STORAGE_FORCE_PATH_STYLE:-true}" && export RCLONE_CONFIG_ARCA_FORCE_PATH_STYLE=true
                    ;;
            esac
            REMOTE="arca:${STORAGE_BUCKET}/${STORAGE_PREFIX}"
            ;;
        local)
            [ -n "${STORAGE_PATH:-}" ] || die "Para local, defina STORAGE_PATH (pasta, de preferência um volume)"
            export RCLONE_CONFIG_ARCA_TYPE=local
            REMOTE="arca:${STORAGE_PATH%/}/${STORAGE_PREFIX}"
            ;;
        rclone)
            # Qualquer serviço do rclone: o remoto "arca" é descrito pelas variáveis
            # RCLONE_CONFIG_ARCA_* (TYPE, e as opções daquele tipo), e STORAGE_PATH é o caminho
            # dentro dele (bucket/pasta).
            [ -n "${RCLONE_CONFIG_ARCA_TYPE:-}" ] || die "Para rclone, defina RCLONE_CONFIG_ARCA_TYPE e as opções do serviço"
            REMOTE="arca:${STORAGE_PATH:+${STORAGE_PATH%/}/}${STORAGE_PREFIX}"
            ;;
        "") die "STORAGE_PROVIDER não definido (aws, r2, s3, local ou rclone)" ;;
        *) die "STORAGE_PROVIDER inválido: $STORAGE_PROVIDER (use aws, r2, s3, local ou rclone)" ;;
    esac
    REMOTE="${REMOTE%/}"
    # Sem arquivo de config: tudo vem do ambiente.
    export RCLONE_CONFIG=/dev/null
}

rc() { rclone --retries 5 --low-level-retries 10 --stats 0 "$@"; }

# Envio de um arquivo novo. --no-check-dest: não pergunta antes se o destino já existe (os nomes
# têm data e hora). Numa credencial de IAM mínima (ListBucket só dentro do prefixo), a AWS
# responde 403 em vez de 404 para essa pergunta, e o envio falhava.
upload() { rc copyto --no-check-dest "$1" "$2"; }

# ------------------------------------------------------------------ criptografia (age)

# Chave(s) pública(s) age: só cifram. A chave privada NÃO fica no servidor; é usada só na
# restauração (AGE_IDENTITY / AGE_IDENTITY_FILE).
encryption_enabled() { [ -n "${BACKUP_ENCRYPTION_RECIPIENTS:-}" ]; }

encrypt_stream() {
    local args=() recipient
    for recipient in $(printf '%s' "$BACKUP_ENCRYPTION_RECIPIENTS" | tr ',' ' '); do
        args+=(-r "$recipient")
    done
    age "${args[@]}"
}

# Arquivo temporário com a identidade (chave privada) para decifrar.
identity_file() {
    if [ -n "${AGE_IDENTITY_FILE:-}" ]; then
        [ -r "$AGE_IDENTITY_FILE" ] || die "AGE_IDENTITY_FILE não encontrado: $AGE_IDENTITY_FILE"
        printf '%s' "$AGE_IDENTITY_FILE"
    elif [ -n "${AGE_IDENTITY:-}" ]; then
        local file="$WORK_DIR/identity.txt"
        (umask 077 && printf '%s\n' "$AGE_IDENTITY" > "$file")
        printf '%s' "$file"
    else
        die "Backup cifrado: defina AGE_IDENTITY ou AGE_IDENTITY_FILE (a chave PRIVADA) para restaurar"
    fi
}

# ------------------------------------------------------------------ arquivos de trabalho e trava

new_work_dir() {
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arca.XXXXXX")"
    chmod 700 "$WORK_DIR"
    trap 'rm -rf "$WORK_DIR"' EXIT
}

# Trava por diretório (portável): impede dois backups ao mesmo tempo (cron + manual).
LOCK_DIR="${TMPDIR:-/tmp}/arca.lock"
acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        die "Já existe um backup em andamento (trava em $LOCK_DIR). Se não houver, apague a pasta."
    fi
    trap 'rm -rf "$WORK_DIR" "$LOCK_DIR"' EXIT
}

human_size() {
    awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'
}

# ------------------------------------------------------------------ aviso (Uptime Kuma push etc.)

# HEALTHCHECK_URL: chamado ao fim de cada backup com status=up|down&msg=... (formato do monitor
# "Push" do Uptime Kuma). Falha no aviso nunca derruba o backup.
notify() {
    local status="$1" message="$2"
    [ -n "${HEALTHCHECK_URL:-}" ] || return 0
    local sep='?'
    case "$HEALTHCHECK_URL" in *\?*) sep='&' ;; esac
    local encoded
    encoded="$(printf '%s' "$message" | sed 's/%/%25/g; s/ /%20/g; s/&/%26/g; s/?/%3F/g; s/=/%3D/g; s/#/%23/g; s/+/%2B/g')"
    curl -fsS -m 15 --retry 3 -o /dev/null "${HEALTHCHECK_URL}${sep}status=${status}&msg=${encoded}" ||
        warn "não foi possível chamar HEALTHCHECK_URL"
}
