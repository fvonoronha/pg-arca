# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.0] - 2026-09-25

Primeira versão.

- Backup agendado (cron) de um, vários ou todos os bancos, com `pg_dump` no formato custom e os papéis/usuários à parte.
- Armazenamento: AWS S3, Cloudflare R2, qualquer compatível com S3, disco local ou qualquer serviço do rclone, escolhido pelo `.env`, com a classe de armazenamento (tier) configurável.
- Criptografia com chave pública (age): o servidor não consegue abrir os próprios backups.
- `restore` tudo ou nada (numa transação), `verify --full`, `list`, `prune` com piso de segurança e `check`.
- Aviso no Uptime Kuma (monitor Push).
- Imagens para Postgres 15, 16 e 17, em amd64 e arm64.
