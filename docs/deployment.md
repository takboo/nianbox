# Deploy, backup and restore

Run Compose on an always-on Linux host so Hermes can work while the Mac is off. The loopback-only default is intentional. Copy `.env.example` to `.env`, generate a secret with `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'` and set `NIANBOX_API_TOKEN`. Restrict `.env` permissions (`chmod 600 .env`). Add the actual HTTPS hostname to `NIANBOX_ALLOWED_HOSTS`; never commit this file. Use the same token in Mac settings and the Hermes environment.

```sh
docker compose pull
docker compose up -d --no-build
docker compose ps
```

## Images from GitHub

The public source repository is `takboo/nianbox`; server images are published to `ghcr.io/takboo/nianbox`. Deployment only needs `compose.yaml` and a private `.env`, not Python, Xcode, the source checkout or a local image build. GitHub Container Registry supports anonymous pulls of public packages ([GitHub documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)). Package visibility is separate from repository visibility; verify an anonymous pull after the first publication.

Pushes to `main` and version tags run the server suite and restricted-container checks on native Linux AMD64 and ARM64 runners, plus macOS unit tests. Only after those jobs pass does CI publish the multi-platform `:main` and `:sha-<full-commit>` tags, with revision metadata, provenance and an SBOM. CI uses its short-lived `GITHUB_TOKEN` with `packages: write`; no registry credential belongs in this repository. Pull requests and other branches run checks without publishing. Version tags also build a Universal DMG and publish a GitHub Release; `stable` is promoted only after the DMG and image checks pass. See [release workflow](releases/README.md). Routine main pushes do not move `stable`.

Publishing uses fresh builds and disables the QEMU image cache. It does not require GitHub Actions cache download capacity. Superseded runs are cancelled automatically; Dependabot uses pull-request checks without a duplicate branch-push run.

For deployment, `.env.example` selects `ghcr.io/takboo/nianbox:stable`. For a deployment you want to reproduce or roll back, take the digest from the successful workflow summary and set:

```dotenv
NIANBOX_IMAGE=ghcr.io/takboo/nianbox@sha256:<published-index-digest>
```

The first verified public image is commit `b60a7dd36fc05bcd85f2ef63b0c29a83f2cf8a84`, index digest `sha256:325d335d39d5969af3d773d2309a51cb0e57f8919ee716911a0973c04d75ea50`. Its AMD64/ARM64 layers each require approximately 53 MB on a cold pull. See [verification](verification.md) for the exact artifact and test evidence; `:main` will advance with subsequent successful publications.

Back up first, record the current digest, change `NIANBOX_IMAGE`, then run `docker compose pull && docker compose up -d --no-build`. Check health and authenticated data before accepting the upgrade. To roll back the binary, restore the previous digest; preserve the data volume and check schema compatibility before downgrading. Never use `down -v` for upgrades. A public image contains application code and locked dependencies; user tasks and tokens are supplied only at runtime.

To build local changes instead:

```sh
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

### Runtime footprint

The runtime uses the official Python 3.12 slim image pinned by multi-platform digest, SQLite and one Uvicorn process. Only pinned production dependencies and `nianbox/*.py` enter the image; wheel-only installation fails rather than introducing a compiler toolchain. There are no test packages, Node, Git, Redis or worker services. Bytecode compilation and pip caches are disabled during installation. The image retains the standard Python slim runtime, including its shell and pip; it is not a distroless or absolutely smallest image. A separate build stage would currently leave the same runtime dependencies, since no compilation occurs.

Compose runs as UID/GID 10001, with a read-only root, a 16 MiB temporary filesystem, all Linux capabilities dropped, no privilege escalation and a PID limit. Only `/data` persists; the host port binds to loopback. Image size and measured memory are recorded in [verification](verification.md). The automated image check also runs under a 128 MiB memory limit and 0.5 CPU; this is a smoke-test constraint, not a production capacity guarantee. Size, process RSS, container memory and download bytes are different measures.

Pinned base images need updates. Dependabot checks Docker and Actions dependencies weekly; review and run the full checks before accepting updates. Rebuild and redeploy deliberately to receive fixes.

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

### Concrete recovery commands

After obtaining a standalone backup, run on the Docker host (replace the date and filename; choose a fresh volume name):

```sh
docker compose stop server
docker volume create nianbox-restored-20261023
docker run --rm --user 0 \
  -v nianbox-restored-20261023:/restore \
  -v "$PWD/backup-2026-10-23.sqlite:/backup.sqlite:ro" \
  python:3.12-slim python -c 'from pathlib import Path; import shutil,os; p=Path("/restore/nianbox.sqlite"); assert not p.exists(); shutil.copyfile("/backup.sqlite",p); os.chown(p,10001,10001); os.chown("/restore",10001,10001)'
```

Create an untracked `restore.override.yaml`:

```yaml
services:
  server:
    volumes:
      - nianbox-restored:/data
volumes:
  nianbox-restored:
    external: true
    name: nianbox-restored-20261023
```

Start with `docker compose -f compose.yaml -f restore.override.yaml up -d --no-build`. The `/data` mount is replaced with the new volume; the old named volume remains untouched. Verify through authenticated REST and Hermes before pointing the Mac at this restored service. To roll back, stop the restored service and run `docker compose up -d --no-build` without the override. Keep both volumes until reconciliation is accepted.

## Mac local data

Settings → Export local data writes tasks (including retained history/tombstones) and every pending/blocked mutation. It excludes the API token. Recover a deleted task's retained text deliberately into a new UUID; editing the old tombstone cannot restore it.

For a complete local cache backup, quit NianBox first, then copy its entire `NianBox` Application Support directory, including any store sidecars and supporting files. A sandboxed app normally uses `~/Library/Containers/org.nianbox.NianBox/Data/Library/Application Support/NianBox/`; an unsigned development app uses `~/Library/Application Support/NianBox/`. Preserve the current directory before restoring the whole backup with the app stopped and the same app version. Keep the original server URL/identity; the durable outbox and receipts handle retries. A server restored behind the local cursor requires reconciliation as described above. Export first before attempting a version downgrade or moving to another server.
