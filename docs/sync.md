# 数据与同步契约

本文件是协议、持久化与反馈状态的现行契约。服务端为单用户数据权威，REST 与 MCP 共用 SQLite Store；手动排序是 Mac 本机偏好。

## 事项与事务

公开字段为 `id`（UUID）、`title`、可空 `notes`、`status`、`priority`、可空 `dueAt`、`createdAt`、`updatedAt`、可空 `completedAt`。内部字段 `deletedAt` 表示永久墓碑，`version` 是服务端变更序列。状态为 `todo`／`inProgress`／`done`／`backlog`；优先级为 `none`／`low`／`medium`／`high`。

所有 REST／MCP 写入在一次 `BEGIN IMMEDIATE` 事务中提交事项、追加变更记录与幂等回执。SQLite 使用 WAL、FULL synchronous 与 15 秒 busy timeout。时间由服务端按 UTC 分配，设备时钟不参与冲突裁决。完成历史保留到显式删除；v1 回执与墓碑永久保留。

`POST /v1/mutations` 接受 `{mutationId, taskId, kind, baseVersion, patch}`。`kind` 为 create／update／delete；创建要求标题和 baseVersion 0。更新只改变所提供字段，null 可清空 notes／dueAt，其他必需字段不可为空。相同 mutationId 与内容返回最初回执，内容不同返回 409。

更新按 baseVersion 比较；`version_conflict` 包含 `current`，由调用者决定如何重基。删除优先于并发编辑，不依赖旧 baseVersion；旧离线写入不能复活墓碑。离线创建后再删除可直接产生墓碑。

## 增量读取与恢复保护

`GET /v1/changes?after=0&limit=200` 返回 `{changes, cursor, hasMore, serverId, cursorDigest}`，包含完成事项与墓碑。每页数据、cursor 与可选摘要必须在本地同一事务提交；下一次以 `cursor_digest` 发送已保存摘要。写入回执不能推进读取游标，因为更早还有其他事项变更。

摘要标识游标处的确切变更。旧备份追平并重用序列号时，摘要不符返回 `history_diverged`；游标超过高水位返回 `cursor_ahead`；serverId 检测不同数据库。任一不符均先暂停上传，保留缓存与队列以供导出对账，不能自动重置。完整 SQLite 恢复保留身份与回执。

兼容边界：无摘要的旧客户端不能检测历史分叉。已有非零游标的客户端在首次升级拉取时建立摘要，不能追溯验证升级前区间；客户端和服务端均需升级后才具备该保护。

REST 便利接口：POST `/v1/tasks` 支持可选 UUID `Idempotency-Key`（建议提供）；GET `/v1/tasks/{id}`；PATCH 与 DELETE 使用 `version`、`mutationId` 查询参数。列表支持 status、due_before、limit、offset。MCP 更新需要 patch 对象与当前版本，修改前先读取；创建可提供稳定 task id／mutationId。

截止时间以带时区 RFC 3339 表示，按 UTC 精确到微秒、包含边界比较，支持等价偏移格式。游标、offset 与写入版本限制在 SQLite 有符号 64 位范围。MCP 将完整数据库操作放入工作线程，避免 SQLite 锁等待阻塞共享事件循环；REST 与 MCP 仍使用相同事务。

## Mac 离线与确认

SwiftData 在显式事务中保存事项与 PendingMutation，TaskStore 使用的 context 关闭 autosave。请求一旦准备，正文和 UUID 在重试与重开后保持不变；上传中的新编辑产生后续队列条目。

拉取的事项先持久化标准服务端快照，再叠加本地未确认补丁。回执只删除它确认的队列条目，然后用标准快照重建视图并叠加后续补丁。若写入已提交但响应丢失，后来拉取到更高版本，旧幂等回执不能覆盖该标准快照或把旧本地内容误报为已同步。快照跨进程重开保留；旧缓存若缺少所需标准快照，则暂停并保留请求供导出对账。

引擎先拉取、验证身份，再处理最多 100 个操作，最后再次拉取。CAS 拒绝以新 mutationId 将原本改变的字段重基到当前服务端版本，保留无关远端字段；同字段并发时，后来被接受的本地补丁获胜。被远端删除覆盖的编辑成为阻塞条目，保留在导出中，事项继续隐藏；人工恢复文字需创建新 UUID。

本地保存后 300 ms 防抖触发同步，网络恢复、唤醒和前台激活触发重试，远端检查间隔 60 秒。网络失败、认证／校验错误与未知服务端错误保留队列。缓存固定服务 URL 和数据库身份；迁移需先对账。本地 version 0 的存量记录在首次连接时补入队列，上游存储不会自动打开。

## 展示与录入

菜单栏观察实际录入结果与类型化同步活动。本地提交成功触发纸张落入；服务端成功是独立确认。有效上传或导入持续超过 600 ms 才显示传输动画；最后拉取成功且待处理／阻塞均为零后才短暂显示对勾。空轮询不改变图形或增加成功反馈计数。部分批次、保存错误、连接失败和删除冲突不产生成功反馈。`lastSuccess` 只记录完全追平的一轮。

开启 Reduce Motion 后使用静态状态，无重复动画计时器。错误有三种不同形状：断开插头、抽屉大叉、分开纸张；文字状态提供原因。

Tasks 与 Backlog 在长生命周期面板状态中分别保留标题和优先级。切换标签与临时销毁输入视图不会清空，成功本地提交或显式取消仅清除对应草稿。未提交草稿仅在会话内；提交后才具有 SwiftData／outbox 的原子持久化保证。

`dueAt` 是任务元数据，当前未调度本地提醒；Hermes 提醒工作流需另行配置。
