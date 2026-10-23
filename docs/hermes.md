# Hermes connection

Hermes supports native remote Streamable HTTP (`url` plus `headers`); no adapter is needed. Verified against this machine's source checkout `v0.22.2+canary.20261019T071120Z-385-g0b10b9f815`. The runtime imports the MCP SDK HTTP transport in `tools/mcp_tool.py`; `${ENV_VAR}` substitution is documented and implemented in the current configuration loader. Sources: [Hermes MCP guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp), [configuration reference](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/mcp-config-reference.md).

Merge this single entry into the active Hermes profile's `config.yaml` (preserve other entries):

```yaml
mcp_servers:
  nianbox:
    url: "https://nianbox.example.ts.net/mcp/"
    headers:
      Authorization: "Bearer ${NIANBOX_API_TOKEN}"
    strict_redirect_headers: true
```

Provide `NIANBOX_API_TOKEN` securely in the environment of the always-on Hermes process (or its protected profile `.env`). Use a real HTTPS host reachable from that process, not the Mac's loopback. Restart/reload MCP in Hermes and verify discovery of all six tools. The server remains reachable while the Mac app is stopped because neither its database nor MCP process lives in the app.

Suggested Hermes instruction:

> Use NianBox as my memory inbox. Capture with only a title by default. For an unscheduled idea use backlog; otherwise todo. Resolve natural-language dates using my timezone, and send an RFC 3339 date with timezone only when intended. Read task id/version before updating. Completed tasks keep history. Delete only on explicit request. For retries reuse UUID mutationId (and task id for creates). On a version conflict reread before deciding how to apply the requested change.

Examples: “帮我记一下，明天处理服务器证书”; “记录一个灵感，暂时不安排时间”; “我现在还有什么没完成的事？”; “把刚才那个任务标记为完成”. List `todo`, `inProgress` and optionally `backlog` separately; `done` remains queryable.

End-to-end testing and any remaining device/deployment gates are recorded in [verification](verification.md). No personal Hermes source or live configuration is edited by this repository.

## Reproduce the installed-client integration check

`Scripts/hermes_smoke.py` runs the existing Hermes native MCP client and its own environment-variable interpolation, with a separate test home. It does not invoke an LLM, edit Hermes, or send phone/chat messages. Supply the installed Hermes environment's Python (the one that can import Hermes dependencies):

```sh
export HERMES_HOME="$PWD/.local/hermes-smoke"
export NIANBOX_URL="http://127.0.0.1:18988" # isolated local test server only
# Securely set NIANBOX_API_TOKEN to the test server's token.
/path/to/hermes/python Scripts/hermes_smoke.py \
  --source /path/to/hermes-agent --fixture .local/e2e.json
```

This discovers six tools, performs CRUD/completion, checks a create retry is idempotent, verifies REST reads the same task, then writes a chmod-600 fixture containing a **test credential**. Keep it out of source control and remove it when finished. `Scripts/verify_sync.sh .local/e2e.json` compiles `Scripts/sync_smoke.swift` with the production model/store/sync sources to verify disk-backed Mac import and upload. The optional `NianBoxUITests.testHermesTaskAppearsAndMacCompletionReachesServer` reads this same fixture and checks panel display and completion; it skips when the fixture is absent. Use a fresh fixture before each UI run because that test completes the diagnostic task.

For phone acceptance after deployment: stop the Mac app, use your actual Hermes phone channel to capture a uniquely named task, query/update/complete it, then start NianBox and verify the visible task/history. Repeat while the Mac is powered off. The local native-client integration check is evidence of protocol compatibility; it does not establish those phone or power-off scenarios.

UI tests send real mouse/keyboard input and can trigger macOS permission prompts. Run them only in a dedicated desktop session without competing user input. They are intentionally excluded from unattended CI.
