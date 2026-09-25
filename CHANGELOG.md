# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.3] - 2026-09-25

### Melhorado
- `check` mostra a credencial recebida sem expô-la: final da access key, tamanho da chave secreta e uma impressão (sha256, 8 caracteres) para comparar com a chave original.
- Access key sem a chave secreta (ou o contrário) é recusada com uma mensagem clara, em vez de virar `SignatureDoesNotMatch`.

## [1.0.2] - 2026-09-25

### Corrigido
- Chaves de armazenamento com espaço, quebra de linha ou aspas em volta (comum ao copiar/colar ou em `.env` com `KEY="valor"`) quebravam a assinatura da AWS (`SignatureDoesNotMatch`). Agora são limpas.

### Melhorado
- `check` explica os erros mais comuns do S3 (chave secreta, access key, permissão, região, bucket, classe).

## [1.0.1] - 2026-09-25

### Corrigido
- Envio para a AWS S3 com a credencial mínima recomendada (ListBucket restrito ao prefixo): o rclone perguntava se o arquivo já existia, a AWS respondia 403 e o backup falhava. O envio não faz mais essa pergunta.

## [1.0.0] - 2026-09-25

Primeira versão.

- Backup agendado (cron) de um, vários ou todos os bancos, com `pg_dump` no formato custom e os papéis/usuários à parte.
- Armazenamento: AWS S3, Cloudflare R2, qualquer compatível com S3, disco local ou qualquer serviço do rclone, escolhido pelo `.env`, com a classe de armazenamento (tier) configurável.
- Criptografia com chave pública (age): o servidor não consegue abrir os próprios backups.
- `restore` tudo ou nada (numa transação), `verify --full`, `list`, `prune` com piso de segurança e `check`.
- Aviso no Uptime Kuma (monitor Push).
- Imagens para Postgres 15, 16 e 17, em amd64 e arm64.
