#!/bin/bash
# Production sync sources against the ignored fixture from hermes_smoke.py; no desktop input.
set -euo pipefail
nianbox_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$nianbox_root"
fixture="${1:-.local/e2e.json}"
mkdir -p .local
swiftc -parse-as-library -module-cache-path .local/swift-cache \
  NianBox/Models/TaskItem.swift NianBox/Models/TaskTypes.swift NianBox/Models/SyncRecord.swift \
  NianBox/Services/PersistenceController.swift NianBox/Services/TaskStore.swift NianBox/Services/TaskStore+Sync.swift \
  NianBox/Services/SyncTypes.swift NianBox/Services/ServerClient.swift NianBox/Services/ServerTokenStore.swift \
  NianBox/Services/SyncEngine.swift Scripts/sync_smoke.swift -o .local/sync-smoke
.local/sync-smoke "$fixture"
