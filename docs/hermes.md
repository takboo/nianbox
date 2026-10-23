# Hermes connection

Hermes supports native remote Streamable HTTP (`url` plus `headers`); no adapter is needed. Verified against this machine's source checkout `v0.22.2+canary.20261019T071120Z-385-g0b10b9f815`. The runtime imports the MCP SDK HTTP transport in `tools/mcp_tool.py`; `${ENV_VAR}` substitution is documented and implemented in the current configuration loader. Sources: [Hermes MCP guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp), [configuration reference](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/mcp-config-reference.md).

Merge this single entry into the active Hermes profile's `config.yaml` (preserve other entries):

```yaml
mcp_servers:
  nianbox:
    url: "https://nianbox.example.ts.net/mcp/"
    headers:
      Authorization: "Bearer ${NIANBOX_API_TOKEN}"
```

Provide `NIANBOX_API_TOKEN` securely in the environment of the always-on Hermes process (or its protected profile `.env`). Use a real HTTPS host reachable from that process, not the Mac's loopback. Restart/reload MCP in Hermes and verify discovery of all six tools. The server remains reachable while the Mac app is stopped because neither its database nor MCP process lives in the app.

Suggested Hermes instruction:

> Use NianBox as my memory inbox. Capture with only a title by default. For an unscheduled idea use backlog; otherwise todo. Resolve natural-language dates using my timezone, and send an RFC 3339 date with timezone only when intended. Read task id/version before updating. Completed tasks keep history. Delete only on explicit request. For retries reuse UUID mutationId (and task id for creates). On a version conflict reread before deciding how to apply the requested change.

Examples: “帮我记一下，明天处理服务器证书”; “记录一个灵感，暂时不安排时间”; “我现在还有什么没完成的事？”; “把刚才那个任务标记为完成”. List `todo`, `inProgress` and optionally `backlog` separately; `done` remains queryable.

End-to-end testing and any remaining device/deployment gates are recorded in [verification](verification.md). No personal Hermes source or live configuration is edited by this repository.
