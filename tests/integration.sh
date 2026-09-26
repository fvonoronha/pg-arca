#!/usr/bin/env bash
# Teste de ponta a ponta com Docker: gera a imagem e, contra um Postgres de verdade, faz backup
# (disco local e S3), confere, restaura e roda o modo agendado (cron).
#
#   PG_MAJOR=16 tests/integration.sh
#
# Precisa só de Docker. O "S3" é o próprio rclone da imagem (rclone serve s3).

set -o errexit -o nounset -o pipefail

PG_MAJOR="${PG_MAJOR:-17}"
IMAGE="pg-arca:test-pg${PG_MAJOR}"
NET="arca-test-$$"
PG="arca-pg-$$"
S3="arca-s3-$$"
CRON="arca-cron-$$"
WORK="$(mktemp -d)"
PASS=0

cleanup() {
    docker rm -f "$PG" "$S3" "$CRON" > /dev/null 2>&1 || true
    docker network rm "$NET" > /dev/null 2>&1 || true
    # Os arquivos do armazenamento local foram criados pelo root do container.
    docker run --rm -v "$WORK:/work" --entrypoint rm "$IMAGE" -rf /work/storage > /dev/null 2>&1 || true
    rm -rf "$WORK" || true
}
trap cleanup EXIT

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗ %s\033[0m\n' "$*"; exit 1; }

step "Imagem (Postgres $PG_MAJOR)"
docker build -q --build-arg PG_MAJOR="$PG_MAJOR" --build-arg ARCA_VERSION=test -t "$IMAGE" . > /dev/null
docker run --rm "$IMAGE" version | grep -q "arca test" || fail "imagem"
ok "imagem gerada"

docker network create "$NET" > /dev/null
docker run -d --name "$PG" --network "$NET" -e POSTGRES_PASSWORD=segredo "postgres:${PG_MAJOR}-alpine" > /dev/null
docker run -d --name "$S3" --network "$NET" --entrypoint rclone "$IMAGE" \
    serve s3 /data --addr :9000 --auth-key chave,segredo-s3 > /dev/null
# A imagem oficial sobe o Postgres uma vez para inicializar, desliga e sobe de novo: esperar a
# mensagem do fim da inicialização, senão o teste pode pegar o servidor "shutting down".
for _ in $(seq 1 90); do
    if docker logs "$PG" 2>&1 | grep -q "PostgreSQL init process complete" &&
        docker exec "$PG" pg_isready -U postgres > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
docker exec "$PG" psql -U postgres -q -c "CREATE DATABASE loja" \
    -c "CREATE ROLE app LOGIN PASSWORD 'x'"
docker exec "$PG" psql -U postgres -d loja -q \
    -c "CREATE TABLE pedido (id serial PRIMARY KEY, cliente text, total numeric)" \
    -c "INSERT INTO pedido (cliente, total) SELECT 'cliente ' || g, g * 1.5 FROM generate_series(1, 2000) g"
ok "Postgres com dados de teste"

docker run --rm --entrypoint age-keygen "$IMAGE" > "$WORK/chave.txt" 2> /dev/null
PUBLIC="$(grep -o 'age1[a-z0-9]*' "$WORK/chave.txt")"
chmod 644 "$WORK/chave.txt"

base_env=(-e PGHOST="$PG" -e PGPASSWORD=segredo -e BACKUP_NAME=teste -e BACKUP_ENCRYPTION_RECIPIENTS="$PUBLIC")
arca() { docker run --rm --network "$NET" "${base_env[@]}" "${storage_env[@]}" -v "$WORK:/work" "$IMAGE" "$@"; }
# Mesmo comando, com a chave PRIVADA (só para ler/restaurar).
arca_key() { docker run --rm --network "$NET" "${base_env[@]}" "${storage_env[@]}" -e AGE_IDENTITY_FILE=/work/chave.txt -v "$WORK:/work" "$IMAGE" "$@"; }
count() { docker exec "$PG" psql -U postgres -At -d "$1" -c "SELECT count(*) FROM pedido"; }

run_suite() {
    local label="$1"
    step "Armazenamento: $label"
    arca check > "$WORK/out" 2>&1 || { cat "$WORK/out"; fail "check"; }
    ok "check"
    arca backup > "$WORK/out" 2>&1 || { cat "$WORK/out"; fail "backup"; }
    if ! grep -q "loja: .* enviado" "$WORK/out" || ! grep -q "globais: enviado" "$WORK/out"; then
        cat "$WORK/out"; fail "backup incompleto"
    fi
    ok "backup (banco + papéis)"
    arca list loja | grep -q "loja_.*\.dump\.age" || fail "list"
    ok "list"
    arca verify loja > "$WORK/out" 2>&1 && fail "verify sem chave privada deveria falhar"
    ok "sem a chave privada não abre"
    arca_key verify loja --full > "$WORK/out" 2>&1 || { cat "$WORK/out"; fail "verify --full"; }
    ok "verify --full (restauração de teste)"
    arca_key restore loja --into "loja_${label}" > "$WORK/out" 2>&1 || { cat "$WORK/out"; fail "restore"; }
    [ "$(count "loja_${label}")" = "2000" ] || fail "restore --into: contagem errada"
    ok "restore --into (2000 linhas)"
    arca_key restore loja > "$WORK/out" 2>&1 && fail "sobrescrever sem --yes deveria falhar"
    ok "sobrescrever exige --yes"
}

storage_env=(-e STORAGE_PROVIDER=local -e STORAGE_PATH=/work/storage)
run_suite local

storage_env=(-e STORAGE_PROVIDER=s3 -e STORAGE_ENDPOINT="http://$S3:9000" -e STORAGE_BUCKET=backups
    -e STORAGE_ACCESS_KEY_ID=chave -e STORAGE_SECRET_ACCESS_KEY=segredo-s3)
docker run --rm --network "$NET" -e RCLONE_CONFIG_M_TYPE=s3 -e RCLONE_CONFIG_M_PROVIDER=Other \
    -e RCLONE_CONFIG_M_ENDPOINT="http://$S3:9000" -e RCLONE_CONFIG_M_ACCESS_KEY_ID=chave \
    -e RCLONE_CONFIG_M_SECRET_ACCESS_KEY=segredo-s3 --entrypoint rclone "$IMAGE" mkdir m:backups
run_suite s3

step "Modo agendado (cron)"
docker run -d --name "$CRON" --network "$NET" "${base_env[@]}" "${storage_env[@]}" \
    -e BACKUP_SCHEDULE="* * * * *" -e BACKUP_NAME=cron "$IMAGE" > /dev/null
for _ in $(seq 1 90); do
    docker logs "$CRON" 2>&1 | grep -q "Backup concluído" && break
    sleep 2
done
docker logs "$CRON" 2>&1 | grep -q "Backup concluído" || { docker logs "$CRON"; fail "o cron não rodou o backup"; }
ok "o cron rodou o backup sozinho (ambiente repassado ao job)"

printf '\n\033[32m%s verificações passaram (Postgres %s)\033[0m\n' "$PASS" "$PG_MAJOR"
