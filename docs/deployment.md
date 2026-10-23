# Deploy, backup and restore

Run Compose on an always-on Linux host so Hermes can work while the Mac is off. The loopback-only default is intentional. Copy `.env.example` to `.env`, generate a secret with `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'` and set `NIANBOX_API_TOKEN`. Restrict `.env` permissions (`chmod 600 .env`). Add the actual HTTPS hostname to `NIANBOX_ALLOWED_HOSTS`; never commit this file. Use the same token in Mac settings and the Hermes environment.

```sh
docker compose up -d --build
docker compose ps
```

Prefer Tailscale Serve on the host (Tailscale installed, signed in, HTTPS enabled for the tailnet):

```sh
tailscale serve --bg http://127.0.0.1:8088
```

Use the HTTPS URL reported by Serve, with `/mcp/` for Hermes and the URL origin for the Mac. Tailnet ACLs should allow only your devices and the Hermes host. Keep Bearer authentication enabled. Do not enable Funnel or publish port 8000/8088 to the internet. Reference: [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve).

For your own HTTPS reverse proxy, use `deploy/Caddyfile.example` on a host with a valid DNS name and certificates. Caddy should run on the host (its upstream is loopback); retain firewall restrictions appropriate to your network. TLS termination belongs at the proxy, and the server validates Host and rejects browser Origin headers. Do not log Authorization headers or request bodies. No browser client or CORS access is provided.

## Backup

Use SQLite's online backup API so WAL changes are included:

```sh
docker compose exec server python -m nianbox backup /data/backup-2026-10-23.sqlite
docker compose cp server:/data/backup-2026-10-23.sqlite ./backup-2026-10-23.sqlite
docker compose exec server python -m nianbox export /data/export-2026-10-23.json
docker compose cp server:/data/export-2026-10-23.json ./export-2026-10-23.json
```

Pick fresh filenames; commands refuse to overwrite backups/exports. Store off-host copies securely. JSON export is portable user data including tombstones; SQLite backup is the supported full-fidelity recovery format, including change history and idempotency receipts. Copying only the live `.sqlite` file can omit committed WAL data.

## Restore

Stop writes and stop the service. Preserve the existing data volume. Create a NEW volume, populate it with the backed-up SQLite database named `nianbox.sqlite`, set ownership to UID/GID 10001, and use a Compose override that mounts the new volume at `/data`. Start against this copy and verify health, task counts, completed history, tombstones and authenticated MCP before switching clients. Retain the previous volume for rollback. Never use `docker compose down -v` as part of upgrades.

A restore to an earlier point may leave Mac cursors ahead: the client must stop and preserve its local store/outbox. Reconcile the missing interval before resuming. Do not silently reset cursors and upload an old cache. Moving to another server is a deliberate data migration, not a settings-only change. Token rotation requires updating server, Mac and Hermes; it does not change task data.
