<div align="center">

# 🛟 pg-arca

**Automatic, encrypted PostgreSQL backups to any cloud.<br>One container, one `.env`, and your data sleeps well.**

[![CI](https://github.com/fvonoronha/pg-arca/actions/workflows/ci.yml/badge.svg)](https://github.com/fvonoronha/pg-arca/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Postgres 15 | 16 | 17](https://img.shields.io/badge/postgres-15%20%7C%2016%20%7C%2017-336791?logo=postgresql&logoColor=white)](#images)

[Português](README.md)

</div>

---

**AWS S3, Cloudflare R2, Backblaze, Wasabi, MinIO, a local disk, SFTP, Google Drive?** pg-arca stores your backups wherever you want: change one line in `.env`. Under the hood it uses [rclone](https://rclone.org), which speaks to 70+ storage services.

Backups are **encrypted with a public key** ([age](https://age-encryption.org)): the server can only *lock* them. The key that *opens* them stays with you. If someone breaks into the server, all they get is unreadable files.

## Why pg-arca

- ☁️ **Any storage**: `aws`, `r2`, `s3` (any compatible), `local` or `rclone`. The S3 storage class (tier) is set in `.env` too.
- 🔐 **Real encryption**: public-key age. The server can't read its own backups.
- ♻️ **All-or-nothing restore** in a single transaction. Overwriting a database requires `--yes`.
- ✅ **Tested backups**: `arca verify --full` restores into a throwaway database.
- 🔔 **Alerts** through [Uptime Kuma](https://github.com/louislam/uptime-kuma) *Push* monitors: `up` on success, `down` on failure. Silence alerts too.
- 🧯 **Retention with a floor**: never deletes the N newest backups of each database.
- 🩺 **Fails fast**: checks credentials, bucket and key when the container starts.
- 🐘 **Postgres 15, 16, 17**, amd64 and arm64.

## Quick start

```bash
# 1. Key pair: the public key goes in .env; keep the private key in your password manager
docker run --rm --entrypoint age-keygen ghcr.io/fvonoronha/pg-arca:latest
```

```env
# 2. .env (see .env.example for everything)
PGHOST=my-postgres
PGUSER=postgres
PGPASSWORD=db-password
STORAGE_PROVIDER=aws
STORAGE_BUCKET=my-backups
STORAGE_REGION=us-east-1
STORAGE_CLASS=GLACIER_IR
STORAGE_ACCESS_KEY_ID=AKIA...
STORAGE_SECRET_ACCESS_KEY=...
BACKUP_ENCRYPTION_RECIPIENTS=age1...
BACKUP_SCHEDULE=0 3 * * *
TZ=UTC
```

```bash
# 3. Run it (same network as Postgres, same major version: pg15, pg16 or pg17)
docker run -d --name arca --env-file .env --network my-net ghcr.io/fvonoronha/pg-arca:pg16
docker exec arca arca backup     # backup now
```

## Commands

```bash
arca backup | list [db] | restore <db> [file|latest] [--into <target>] [--yes]
arca verify [db] [--full] | prune | check
```

## Which S3 tier?

**`GLACIER_IR` with 90+ days retention.** It costs about 6 times less than Standard (around $0.004 per GB-month) and still restores **instantly**. Deep Archive is cheaper, but it takes 12 to 48 hours to restore. Note that objects are billed for at least 90 days. The full table, a least-privilege IAM policy (no delete permission) and the lifecycle rule are in the [Portuguese README](README.md#-qual-tier-usar-aws-s3).

## Restore

```bash
docker run --rm --env-file .env --network my-net \
  -e AGE_IDENTITY_FILE=/key.txt -v ./private-key.txt:/key.txt:ro \
  ghcr.io/fvonoronha/pg-arca:pg16 restore my_db --into my_db_restored
```

## Images

`ghcr.io/fvonoronha/pg-arca`: `pg15`, `pg16`, `pg17` (use your server's version), pinned `vX.Y.Z-pgNN`, and `latest` (= pg17). Multi-arch (amd64/arm64).

## Contributing

Issues and PRs are welcome, in English or Portuguese. See [CONTRIBUTING.md](CONTRIBUTING.md). Every PR runs an end-to-end test against real Postgres 15/16/17 (`tests/integration.sh`). Security issues: see [SECURITY.md](SECURITY.md).

Inspired by [postgresql-backup-s3-cron](https://github.com/marcelofmatos/postgresql-backup-s3-cron) by Marcelo Matos. MIT licensed.
