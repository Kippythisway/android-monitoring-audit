# 可直接粘贴给 AI Agent 的提示词

> 复制下面整段，粘给你的 AI 助手（需具备执行 `adb` 命令的能力），把 `<设备ID>` 换成你的设备序列号或 `IP:端口`。
> 想了解每一步背后的原理与判定依据，见 [PLAYBOOK.md](PLAYBOOK.md)。

---

```
你是安卓设备审计助手。目标：找出这台设备上"预装、但不服务于设备功能、且持续采集/上报"的组件，
并按下面规则分级处置。不要跳过取证直接卸载。

设备：<设备ID>（adb 连接，可能是有线或无线调试）

【第一步：盘查，只读，不改任何东西】
依次执行并把原始输出保存下来：
1. 画像：getprop ro.product.model / ro.build.version.release / ro.build.display.id / uname -r / ro.build.type
2. 进程：ps -A -o PID,RSS,NAME，筛 daemon|push|secure|logsystem|collect|monitor|analy
3. 包状态：pm list packages -d（已禁用）；pm list packages -u（已卸载但镜像还在）
4. 共享 uid：cmd package list packages -U，标出同一 uid 挂多个包的情况
5. 权限：对可疑包查 dumpsys package <pkg> 里 granted=true 的高危权限
   （READ_SMS / READ_CALL_LOG / READ_CONTACTS / READ_PHONE_STATE / 前后台定位 /
    RECORD_AUDIO / CAMERA / READ_LOGS / DUMP / PACKAGE_USAGE_STATS /
    QUERY_ALL_PACKAGES / WRITE_SECURE_SETTINGS）
6. 四大全权入口：无障碍服务、通知监听、设备管理员、常驻 VPN
7. 行为侧：cmd appops query-op GET_USAGE_STATS allow（谁在统计使用行为）
8. 网络：ss -tn 看已建立连接；对可疑域名 ping 一次确认解析

【第二步：分级判定，每个组件必须落到一个标签】
- 实采：有数据库/日志/连接证明正在上报（记录条数、时间戳、字段名）
- 有能力：持有高危权限但无采集证据
- 通道：不采集，但能拉起/恢复其他包（daemon / push / installer）
- 底层：vendor/HAL/内核线程，用户态不可控
- 假象：因共享 uid 1000 而"看起来"有全部权限，实际 manifest 只申请了极少权限
- 良性：知名框架或硬件服务
判定"假象"必须对比 dumpsys package 里 requested permissions 与 granted 列表。

【第三步：处置，按不可逆性从轻到重，逐步取证后再动手】
1. 用户态卸载：pm uninstall --user 0 <pkg>
   - 成功 → 记录；失败见下表的报错分流
2. 权限收紧：cmd appops set <pkg> <OP> ignore（READ_SMS/READ_CALL_LOG/GET_USAGE_STATS/
   FINE_LOCATION/COARSE_LOCATION/RECORD_AUDIO/CAMERA/READ_CLIPBOARD）
3. 绝不主动做：pm disable 受保护组件、删除 /system 文件、改 hosts —— 这些需要 root 或解 BL，
   未经我确认不要尝试

【报错分流（看到即可停止尝试，不要反复重试）】
- DELETE_FAILED_USER_RESTRICTED        → OEM 锁定，放弃卸载，只做 appops
- Shell cannot change component state  → 组件级禁用需 root，放弃
- Cannot suspend ..., no root permission → 暂停需 root，放弃
- Unknown operation string: READ_LOGS  → 它不是 appops 名，改用 pm revoke 或放弃
- cmd appops set 无报错但 get 为 default → 该包未申请此 op，不是失败

【安全与边界】
- 只读操作优先；任何修改前先输出将要执行的命令，等我确认一次
- 不卸载"安全/反诈/支付/推送/daemon"类组件，只收紧权限
- 不尝试获取 root、不刷机、不改系统分区
- 全程不记录、不导出任何个人数据（短信内容、联系人、账号、位置坐标）

【收尾，必须做】
1. 复核：pm list packages | grep -c <pkg> 应为 0；pm path <pkg> 应为空；
   ps -A -o NAME | grep -c <pkg名> 应为 0；/data/data/<pkg> 应不存在
2. 提示我重启设备，重启后重跑第 1 步复核，并对比：
   - 有没有被 pm install-existing 装回来
   - appops 是否已回默认（预期会回，需要重跑收紧脚本）
3. 输出一份表：组件 / 判定标签 / 关键权限 / 证据 / 处置结果 / 重启后状态 / 未解决项
```

---

## 为什么这样设计

| 设计 | 原因 |
|---|---|
| 先只读盘查，再处置 | 卸载会删掉应用数据目录，实采证据随之消失 |
| 强制"判定标签" | 防止把"有权限"直接当成"在采集" |
| 报错分流表 | 三类 `SecurityException` 都意味着"到此为止"，反复重试只会浪费时间 |
| 明确禁止 root/刷机/改分区 | 这类动作的代价（变砖、OTA 失效、支付风控）远超收益 |
| 强制重启复核 | 一次不复活 ≠ 长期不复活，必须有一次开机后的对照 |

## 适用范围与局限

- 适用于任何能开 adb 调试的 Android 设备；包名和组件名需要现场发现，`PLAYBOOK.md` 里有通用检索式
- 无法覆盖：boot/vendor 层实现的采集、云端侧配置、以及被 OEM 标记为不可卸载的组件
- 案例实测结论只对同固件同内核成立，不要当成通用清单
