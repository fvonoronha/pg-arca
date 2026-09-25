# Segurança

O pg-arca guarda cópias de bancos de dados, então segurança é prioridade.

## Como relatar uma falha

**Não abra uma issue pública.** Use o [relato privado de vulnerabilidades do GitHub](../../security/advisories/new) (aba *Security* → *Report a vulnerability*). Responderemos o mais rápido possível e combinaremos a correção e a divulgação.

## Boas práticas ao usar

- Ligue a criptografia (`BACKUP_ENCRYPTION_RECIPIENTS`) e guarde a **chave privada fora do servidor**.
- Use uma credencial de armazenamento **só para o backup**, sem permissão de apagar, e apague os antigos por regra do bucket (veja o README).
- Deixe o bucket privado.
- Rode `arca verify --full` de tempos em tempos: backup que nunca foi restaurado não é backup.
