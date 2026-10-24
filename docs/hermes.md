# 连接 Hermes

先按[部署指南](deployment.md)准备独立运行的服务端。Hermes 通过原生 Streamable HTTP MCP 连接，无需适配器。以下配置已用本机安装的 Hermes 原生客户端验证；具体版本与边界见[验证记录](verification.md)。

## 配置

将以下条目合并到所用 Hermes profile 的 `config.yaml`，保留其他配置：

```yaml
mcp_servers:
  nianbox:
    url: "https://nianbox.example.ts.net/mcp/"
    headers:
      Authorization: "Bearer ${NIANBOX_API_TOKEN}"
    strict_redirect_headers: true
```

替换为 Hermes 进程实际可达的 HTTPS 地址。令牌放在该进程的私有环境或受保护的 profile `.env`，与 Mac 和服务端一致。重新加载 MCP 后，检查是否发现以下六个工具：

| 工具 | 用途 |
| --- | --- |
| `list_tasks` | 查询事项，支持状态、截止时间和分页 |
| `get_task` | 读取事项与当前版本 |
| `create_task` | 只需标题即可记录 |
| `update_task` | 按版本更新指定字段 |
| `complete_task` | 完成事项，保留历史 |
| `delete_task` | 显式删除并保留墓碑 |

远程 Hermes 使用常开服务器的地址，不能用 Mac 的 loopback 地址。Mac 停止运行不会关闭独立部署的服务端。

## 使用约定

可加入 Hermes 的个人指令：

> 用念匣记录我的事项。默认只要求标题，暂不安排的想法放入 backlog，其余放入 todo。自然语言日期按我的时区解释，只在明确需要时发送带时区的 RFC 3339 时间。修改前读取 id 和 version；完成保留历史，仅在明确要求时删除。重试沿用 mutationId，创建时也沿用 task id。遇到版本冲突先重读，再判断如何应用本次修改。

例如：“帮我记一下，明天处理服务器证书”“记录一个灵感，暂时不安排时间”“我还有什么没完成的事？”“把刚才那件事标记完成”。查询时区分 `todo`、`inProgress`、`backlog`；完成的 `done` 仍可查阅。

服务端存储结构化字段，Hermes 负责自然语言理解。`dueAt` 是时间信息，不代表念匣已安排提醒；需要提醒时另行配置 Hermes 的提醒工作流。

## 集成验证

`Scripts/hermes_smoke.py` 调用已安装 Hermes 的 `MCPServerTask` 和环境变量替换逻辑。使用独立测试 home、合成令牌和隔离服务，不调用 LLM 或手机渠道：

```sh
export HERMES_HOME="$PWD/.local/hermes-smoke"
export NIANBOX_URL="http://127.0.0.1:18988"
# 安全设置隔离服务的 NIANBOX_API_TOKEN。
/path/to/hermes/python Scripts/hermes_smoke.py \
  --source /path/to/hermes-agent --fixture .local/e2e.json
Scripts/verify_sync.sh .local/e2e.json
```

选择能导入 Hermes 依赖的 Python。首个脚本验证六工具、CRUD、完成历史、幂等与 REST 一致性，写出 mode-0600 测试夹具；第二个编译生产 SwiftData／同步代码，验证磁盘重开、Mac 导入和上传。测试结束删除生成的凭据文件。

面板往返验收在[隔离 VM](macos-vm-testing.md)中进行；每次先生成新的未完成测试事项，因为该检查会完成它。真实手机验收需在目标部署上，通过实际 Hermes 渠道创建、查询、修改并完成独特命名的事项，再启动 Mac 核对；还需在 Mac 关机时重复。原生客户端协议通过不等于手机或断电场景已验收。
