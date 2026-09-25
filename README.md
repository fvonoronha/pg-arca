<div align="center">

# 🛟 pg-arca

**Backup automático de PostgreSQL, cifrado, para qualquer nuvem.<br>Um container, um `.env`, e seus dados dormem tranquilos.**

[![CI](https://github.com/fvonoronha/pg-arca/actions/workflows/ci.yml/badge.svg)](https://github.com/fvonoronha/pg-arca/actions/workflows/ci.yml)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg)](LICENSE)
[![Postgres 15 | 16 | 17](https://img.shields.io/badge/postgres-15%20%7C%2016%20%7C%2017-336791?logo=postgresql&logoColor=white)](#-imagens)
[![amd64 | arm64](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-555)](#-imagens)

[**Começar**](#-em-1-minuto) · [Onde guardar](#-guarde-onde-quiser) · [Restaurar](#-restaurar) · [Qual tier usar?](#-qual-tier-usar-aws-s3) · [English](README.en.md)

</div>

---

**AWS S3? Cloudflare R2? Backblaze, Wasabi, MinIO? Um HD, um SFTP, o Google Drive?** O pg-arca guarda seus backups onde você quiser: é só trocar uma linha do `.env`. Por baixo, usa o [rclone](https://rclone.org), que fala com mais de 70 serviços de armazenamento.

E ele guarda **cifrado com chave pública**: o servidor só consegue *trancar* os backups. A chave que *abre* fica com você. Se alguém invadir o servidor, leva arquivos ilegíveis.

## ✨ Por que o pg-arca

|  |  |
| --- | --- |
| ☁️ **Qualquer armazenamento** | `aws`, `r2`, `s3` (qualquer compatível), `local` ou `rclone` (Drive, SFTP, Azure...). O tier do S3 também é escolhido no `.env`. |
| 🔐 **Cifrado de verdade** | [age](https://age-encryption.org) com chave pública. O servidor não consegue abrir nem os próprios backups. |
| ♻️ **Restauração tudo ou nada** | Roda numa única transação: se algo falhar no meio, nada muda. Sobrescrever um banco exige `--yes`. |
| ✅ **Backup testado** | `arca verify --full` restaura num banco temporário e apaga depois. Backup que nunca foi restaurado não é backup. |
| 🔔 **Avisa quando falha** | Integração com o monitor *Push* do [Uptime Kuma](https://github.com/louislam/uptime-kuma): `up` no sucesso, `down` na falha. E o silêncio também avisa: se o backup parar, o Kuma percebe. |
| 🧯 **Retenção com piso** | Apaga os antigos, mas nunca os N mais novos de cada banco. Se o backup parar por um mês, você não fica sem nada. |
| 🩺 **Falha cedo** | Ao subir, o container confere senha, bucket e chave. Erro aparece na hora, não às 3h da manhã. |
| 🐘 **Postgres 15, 16 e 17** | Uma imagem por versão (o `pg_dump` tem de ser da mesma versão do servidor), em amd64 e arm64. |

## 🚀 Em 1 minuto

**1. Gere a chave** (a pública vai no `.env`; a privada, no seu cofre de senhas):

```bash
docker run --rm --entrypoint age-keygen ghcr.io/fvonoronha/pg-arca:latest
# Public key: age1...              <- BACKUP_ENCRYPTION_RECIPIENTS
# AGE-SECRET-KEY-1...              <- guarde bem guardado. NÃO vai no servidor.
```

**2. Crie o `.env`** (exemplo com AWS S3; todas as opções estão em [`.env.example`](.env.example)):

```env
PGHOST=meu-postgres
PGUSER=postgres
PGPASSWORD=senha-do-banco

STORAGE_PROVIDER=aws
STORAGE_BUCKET=meus-backups
STORAGE_REGION=sa-east-1
STORAGE_CLASS=GLACIER_IR
STORAGE_ACCESS_KEY_ID=AKIA...
STORAGE_SECRET_ACCESS_KEY=...

BACKUP_ENCRYPTION_RECIPIENTS=age1...
BACKUP_SCHEDULE=0 3 * * *
```

**3. Suba** (na mesma rede do Postgres, e na **mesma versão**: `pg15`, `pg16` ou `pg17`):

```bash
docker run -d --name arca --env-file .env --network minha-rede ghcr.io/fvonoronha/pg-arca:pg16
docker logs arca          # confira o "Tudo certo."
docker exec arca arca backup    # quer um backup agora?
```

Pronto: todo dia às 3h, cada banco vira um arquivo cifrado no seu bucket. 🎉

<details>
<summary><b>Com docker compose</b></summary>

```yaml
services:
  arca:
    image: ghcr.io/fvonoronha/pg-arca:pg16
    env_file: .env
    restart: unless-stopped
```

</details>

## 🧰 Comandos

```bash
arca backup                       # backup agora
arca list [banco]                 # o que está guardado
arca restore <banco> [arquivo|latest] [--into <destino>] [--yes]
arca verify [banco] [--full]      # o backup abre? (--full: restaura num banco temporário)
arca prune                        # aplica a retenção
arca check                        # confere Postgres, armazenamento e chave
```

No container: `docker exec arca arca <comando>`, ou `docker run --rm --env-file .env ... ghcr.io/fvonoronha/pg-arca:pg16 <comando>`.

## ☁️ Guarde onde quiser

| `STORAGE_PROVIDER` | Para | Variáveis |
| --- | --- | --- |
| `aws` | Amazon S3 | `STORAGE_BUCKET`, `STORAGE_REGION`, `STORAGE_CLASS`, chaves (ou papel IAM da máquina) |
| `r2` | Cloudflare R2 | `STORAGE_BUCKET`, `STORAGE_R2_ACCOUNT_ID`, chaves, `STORAGE_CLASS` (`STANDARD`/`STANDARD_IA`) |
| `s3` | Backblaze B2, Wasabi, MinIO, DigitalOcean Spaces, Scaleway... | `STORAGE_BUCKET`, `STORAGE_ENDPOINT`, chaves |
| `local` | Disco, NAS, volume | `STORAGE_PATH` |
| `rclone` | [Qualquer um dos 70+ do rclone](https://rclone.org/overview/): Google Drive, SFTP, Azure, Dropbox... | `RCLONE_CONFIG_ARCA_TYPE` + opções em `RCLONE_CONFIG_ARCA_*`, `STORAGE_PATH` |

<details>
<summary><b>Exemplos</b></summary>

```env
# Cloudflare R2
STORAGE_PROVIDER=r2
STORAGE_R2_ACCOUNT_ID=abc123
STORAGE_BUCKET=backups
STORAGE_ACCESS_KEY_ID=...
STORAGE_SECRET_ACCESS_KEY=...

# Backblaze B2 (S3 compatível)
STORAGE_PROVIDER=s3
STORAGE_ENDPOINT=https://s3.us-west-004.backblazeb2.com
STORAGE_BUCKET=backups

# SFTP (via rclone)
STORAGE_PROVIDER=rclone
RCLONE_CONFIG_ARCA_TYPE=sftp
RCLONE_CONFIG_ARCA_HOST=backup.exemplo.com
RCLONE_CONFIG_ARCA_USER=backup
RCLONE_CONFIG_ARCA_KEY_FILE=/run/secrets/ssh_key
STORAGE_PATH=/home/backup
```

</details>

Os arquivos ficam organizados assim: `<bucket>/<STORAGE_PREFIX>/<BACKUP_NAME>/<banco>/<banco>_<data>.dump.age`, com os papéis e usuários em `_globals/`.

## 💰 Qual tier usar (AWS S3)

| Tier | Guardar (US$/GB·mês*) | Cobrança mínima | Restaurar |
| --- | --- | --- | --- |
| `STANDARD` | 0,023 | - | na hora |
| `STANDARD_IA` | 0,0125 | 30 dias | na hora (US$ 0,01/GB) |
| **`GLACIER_IR`** ⭐ | **0,004** | **90 dias** | **na hora** (US$ 0,03/GB) |
| `GLACIER` | 0,0036 | 90 dias | minutos a horas, precisa "descongelar" antes |
| `DEEP_ARCHIVE` | 0,00099 | 180 dias | 12 a 48 horas |

<sub>* us-east-1, aproximado; outras regiões variam (São Paulo custa cerca de 1,5 a 2 vezes isso). Confira em [aws.amazon.com/s3/pricing](https://aws.amazon.com/s3/pricing/).</sub>

**Recomendação: `GLACIER_IR`, guardando por 90 dias ou mais.** Custa cerca de 6 vezes menos que o Standard e ainda restaura na hora. Quando o banco cai, você quer seus dados em minutos, não em 12 horas.

Exemplo: 50 MB por dia, guardados por 90 dias, dão cerca de **US$ 0,02 por mês**.

> ⚠️ Apagar um arquivo `GLACIER_IR` antes de 90 dias custa como se ele tivesse ficado os 90. Por isso a retenção deve ser de 90 dias ou mais; o arca avisa se estiver menor.

## 🔐 Segurança

**1. Credencial que não consegue apagar.** Dê ao backup só estas permissões. Mesmo quem invadir o servidor não consegue destruir seus backups:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": "arn:aws:s3:::MEU-BUCKET/postgres-backups/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::MEU-BUCKET",
      "Condition": { "StringLike": { "s3:prefix": "postgres-backups/*" } }
    }
  ]
}
```

**2. Os antigos saem por regra do bucket**, não pelo arca: S3 → bucket → *Management* → *Lifecycle rules* → prefixo `postgres-backups/`, *expire* após **91 dias**. Deixe `BACKUP_RETENTION_DAYS=0`.

**3. Bucket privado**, com *Block all public access* ligado.

Senhas e chaves também podem vir de arquivo, compatível com Docker secrets: por exemplo, `PGPASSWORD_FILE=/run/secrets/pg`.

## ♻️ Restaurar

```bash
# O mais recente, num banco NOVO (seguro: não toca no atual)
docker run --rm --env-file .env --network minha-rede \
  -e AGE_IDENTITY_FILE=/chave.txt -v ./chave-privada.txt:/chave.txt:ro \
  ghcr.io/fvonoronha/pg-arca:pg16 restore meu_banco --into meu_banco_restaurado
```

- **Por cima do banco atual:** `restore meu_banco --yes`
- **Um arquivo específico:** `restore meu_banco meu_banco_20260925T060000Z.dump.age --into ...`
- **Servidor novo:** restaure primeiro os papéis e usuários, com `age -d -i chave.txt globals_....sql.gz.age | gunzip | psql`.

A restauração roda numa **transação única**: ou entra tudo, ou nada muda.

## ⚙️ Configuração

Tudo é configurado por variáveis de ambiente, e cada uma está comentada no [`.env.example`](.env.example). As principais:

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `BACKUP_DATABASES` | `all` | Bancos a copiar (`all` ou `a,b,c`) |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Quando rodar (cron), no fuso `TZ` (padrão `America/Sao_Paulo`) |
| `BACKUP_ENCRYPTION_RECIPIENTS` | - | Chave(s) pública(s) age |
| `STORAGE_CLASS` | - | Tier (`GLACIER_IR`, `STANDARD_IA`...) |
| `BACKUP_RETENTION_DAYS` / `BACKUP_KEEP_MIN` | `0` / `3` | Retenção e piso |
| `HEALTHCHECK_URL` | - | Monitor Push do Uptime Kuma |
| `BACKUP_ON_STARTUP` | `false` | Backup ao subir o container |
| `BACKUP_GLOBALS` | `true` | Papéis e usuários (precisa de superusuário) |

## 🐳 Imagens

`ghcr.io/fvonoronha/pg-arca`, para amd64 e arm64:

| Tag | Uso |
| --- | --- |
| `pg15`, `pg16`, `pg17` | Última versão para cada Postgres. **Use a do seu servidor.** |
| `v1.0.0-pg16` | Versão fixa, para produção previsível |
| `latest` | Postgres 17 |

## 🤝 Contribua

O projeto é aberto e contribuições são muito bem-vindas: bugs, ideias, documentação, novos exemplos. Leia o [CONTRIBUTING.md](CONTRIBUTING.md). Todo PR passa por um teste de ponta a ponta com Postgres de verdade (15, 16 e 17), e você roda o mesmo teste localmente com `tests/integration.sh`.

Achou uma falha de segurança? Relate em privado, como explica o [SECURITY.md](SECURITY.md).

## 💙 Créditos

Inspirado no [postgresql-backup-s3-cron](https://github.com/marcelofmatos/postgresql-backup-s3-cron), de [Marcelo Matos](https://github.com/marcelofmatos). Feito sobre ombros de gigantes: [PostgreSQL](https://www.postgresql.org), [rclone](https://rclone.org) e [age](https://age-encryption.org).

Licença [MIT](LICENSE): use, modifique e compartilhe.
