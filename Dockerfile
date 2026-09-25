# O pg_dump precisa ser da MESMA versão maior do servidor (um pg_dump mais novo gera comandos que
# o servidor antigo não entende na hora de restaurar). Gere uma imagem por versão:
#   docker build --build-arg PG_MAJOR=16 -t pg-arca:pg16 .
ARG PG_MAJOR=17
FROM postgres:${PG_MAJOR}-alpine

ARG ARCA_VERSION=dev

LABEL org.opencontainers.image.title="pg-arca" \
      org.opencontainers.image.description="Backup de PostgreSQL agendado e cifrado para AWS S3, Cloudflare R2, qualquer S3 compatível, disco local ou qualquer serviço do rclone" \
      org.opencontainers.image.source="https://github.com/fvonoronha/pg-arca" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${ARCA_VERSION}"

# rclone: fala com S3, R2, qualquer compatível com S3 e ~70 outros serviços.
# age: criptografia com chave pública (o servidor só cifra; decifrar exige a chave privada).
RUN apk add --no-cache bash rclone age curl tzdata ca-certificates gzip

ENV ARCA_VERSION=${ARCA_VERSION} \
    TZ=America/Sao_Paulo \
    TMPDIR=/tmp

COPY bin/ /usr/local/lib/arca/
RUN chmod 755 /usr/local/lib/arca/arca && ln -s /usr/local/lib/arca/arca /usr/local/bin/arca

# Só faz sentido no modo agendado (cron, o padrão): confere se o crond está vivo.
HEALTHCHECK --interval=5m --timeout=10s CMD pgrep crond > /dev/null || exit 1

ENTRYPOINT ["arca"]
CMD ["cron"]
