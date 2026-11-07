# 安卓监控组件处置 · 权限阶梯交接手册

> **给接手 Agent 的作业提示词。**
> 主线：按"你手上能拿到的权限"从低到高推进。每一级写清三件事——
> **能做到什么程度 / 怎么判定成败 / 什么时候该停、什么时候才值得升级**。
>
> 本文不含任何个人数据（无序列号、IP、IMEI、账号、用户安装应用清单）。
> 案例机型：vivo X100 Ultra（`V2366GA` / `PD2366`），Android 16，BL 锁定。

---

## 0. 三条前置原则（违反任何一条都会把你带进坑里）

### 原则一：目标函数是"采不到"，不是"文件消失"

用户说"删干净"，实际诉求几乎总是**这个组件不再采集、不再上报、不再复活**。
文件是否还躺在 `/system` 里，对采集能力没有决定性影响，但对系统完整性影响巨大。
**先确认目标层级，再选手段**（见 §1 阶梯表）。

### 原则二：证据先行

任何 `pm clear` / `pm uninstall` 之前，先落盘：

```sh
adb shell "dumpsys package <pkg> | head -60"        > evidence_pkg.txt
adb shell "pm path <pkg>; pm list packages -u | grep <pkg>" >> evidence_pkg.txt
adb shell "dumpsys package <pkg> | grep -E 'granted=true'"  >> evidence_pkg.txt
adb shell "ls -l /sdcard/Android/data/<pkg>/"        >> evidence_pkg.txt
```

卸载会连带删掉数据目录，数据库里的"实采证据"（记录条数、时间戳、字段名）随之消失。
**没有证据的"它肯定在采集"在报告里等于没写。**

### 原则三：最小不可逆

处置动作按不可逆性排序，能用轻的就不用重的：

```
关设置项 < appops 收紧 < 用户态卸载 < 会话级禁用 < 持久化禁用 < 物理删除 < 改镜像
   ↑ 可逆                                                                    ↓ 不可逆
```

**每一步落地前，先写下这一步的回滚方式。** 写不出来，就不要做。

---

## 1. 阶梯总览（先看这张表决定投入）

| 阶梯 | 你需要什么 | 能到哪一步 | 典型耗时 | 不可逆风险 | 是否需要解 BL |
|---|---|---|---|---|---|
| **T0 无调试** | 只有手机本体 | 只能观察界面/设置，无法取证 | 10 分钟 | 无 | 否 |
| **T1 adb 无 root** | USB 调试或无线调试 | 盘查 + 用户态卸载 + 权限收紧 + 关闭四大入口 | 20–40 分钟 | 极低（`install-existing` 可还原） | 否 |
| **T2 会话级 root** | 内核漏洞 / 官方 root / 工程线 | 读应用私有数据、禁用受保护组件、临时拦截网络 | 30 分钟 + 反复试探 | **中**（panic / 掉数据 / 触发保护） | 否（漏洞路径） |
| **T3 持久 root + 可写系统** | BL 解锁 + 关 verity，或官方 root | systemless 覆盖、持久 hosts、开机脚本、真禁用 | 半天 | 高（OTA 失效、支付风控、保修） | **是**（多数零售机） |
| **T4 改镜像 / 换系统** | BL 解锁 + 刷写能力 | 物理移除、彻底干净、换 ROM | 1–3 天 | 很高（变砖、分区损坏） | **是** |

**决策口诀**：

- 90% 的场景 **停在 T1** 就够了
- 需要"证据"或"临时封一段"→ 值得上 T2，但必须接受"重启归零"
- 只有明确要求"文件也不能留在机器里 / 需要长期生效"→ 才考虑 T3
- T4 只在"系统底层也有后门（boot/vendor/firmware 级）"时才是唯一解

---

## 2. T0：只有手机，没有调试

### 能做到什么

| 动作 | 方法 | 局限 |
|---|---|---|
| 看装了哪些应用 | 设置 → 应用管理（含"显示系统程序"） | 大量组件不显示或名字不可读 |
| 看权限持有者 | 设置 → 隐私 → 权限管理器 | 只看得到申请了"用户可见权限"的应用 |
| 处置后台活动 | 设置 → 电池 → 后台耗电管理；应用 → 强行停止 | 重启/被唤醒后恢复 |
| 关闭采集入口 | 关通知使用权、关无障碍、撤销设备管理器、关闭"用户体验改进计划" | 有效但只能覆盖显性入口 |
| 断网验证 | 飞行模式/Wi-Fi 断开后看是否有异常唤醒 | 无法定位是哪个组件 |

### 判定与决策

- **判断是否需要升级**：如果用户能接受"只关显性入口"，T0 就够，不必折腾。
- **升级到 T1 的信号**：出现了"应用列表里看不到但它在跑"的怀疑 —— 这在 T0 无法证伪，必须上 adb。

---

## 3. T1：adb，无 root（**主战场**）

这是投入产出比最高的一级，也是**默认应该走完的一级**。

### 3.1 盘查（必做，按顺序）

```sh
# A. 画像
adb shell "getprop ro.product.model; getprop ro.build.version.release; \
           getprop ro.build.display.id; uname -r; getprop ro.build.type"

# B. 进程（daemon/push/secure/logsystem/collect 是通用可疑词）
adb shell "ps -A -o PID,RSS,NAME" | grep -iE "daemon|push|secure|logsystem|collect|monitor|analy"

# C. 包三态（0=默认 1=启用 2=禁用 3=禁用用户）
adb shell "pm list packages -d"          # 已禁用；注意"禁用了但还在跑"
adb shell "pm list packages -u | grep X" # 已卸载但镜像还在（关键判据）

# D. 共享 uid（权限归因的最大陷阱）
adb shell "cmd package list packages -U" | sort -t: -k2 | uniq -f1 -D

# E. 权限
adb shell "dumpsys package <pkg> | grep -E 'android.permission.(READ_SMS|READ_CALL_LOG|\
READ_CONTACTS|READ_PHONE_STATE|READ_PRIVILEGED_PHONE_STATE|ACCESS_FINE_LOCATION|\
ACCESS_BACKGROUND_LOCATION|RECORD_AUDIO|CAMERA|READ_LOGS|DUMP|PACKAGE_USAGE_STATS|\
QUERY_ALL_PACKAGES|WRITE_SECURE_SETTINGS): granted=true'"

# F. 四大"全权入口"
adb shell "settings get secure enabled_accessibility_services"
adb shell "settings get secure enabled_notification_listeners"
adb shell "dumpsys device_policy | grep -E 'Admin|provisioningState'"
adb shell "settings get secure always_on_vpn_app"

# G. 行为侧
adb shell "cmd appops query-op GET_USAGE_STATS allow"     # 谁在统计你用了什么
adb shell "cmd appops query-op ACCESS_FINE_LOCATION allow"
adb shell "cmd appops query-op SYSTEM_ALERT_WINDOW allow"

# H. 网络侧
adb shell "ss -tn"                                        # 已建立/半开连接
adb shell "ping -c1 -W2 <可疑域名>"                        # 解析 + 连通性
```

**静态取证**（判断"上报到哪"最有效）：

```sh
adb shell "pm path <pkg>"        # 拿 APK 路径
adb pull <apk> sample.apk
aapt2 dump xmltree sample.apk --file AndroidManifest.xml | grep -iE 'receiver|service|action'
strings -n 6 sample.apk | grep -iE 'https?://|:80|:443|:18080' | sort -u
```

### 3.2 处置能力（T1 的真实上限）

| 动作 | 命令 | 生效范围 | 重启后 |
|---|---|---|---|
| 用户态卸载（普通预装） | `pm uninstall --user 0 <pkg>` | 应用列表消失、进程无法启动、数据已删 | **保持** |
| 用户态卸载（受保护预装） | 同上 | — | ❌ `DELETE_FAILED_USER_RESTRICTED` |
| 禁用/暂停包 | `pm disable-user` / `pm suspend` | — | ❌ 需 root |
| 权限收紧 | `cmd appops set <pkg> <OP> ignore` | 读短信/定位/相机/麦克风/使用统计/剪贴板 | **丢失**，开机重跑 |
| 撤销权限 | `pm revoke <pkg> <perm>` | 仅加 `REVOKED_COMPAT` 标记 | 部分无效（`SYSTEM_FIXED`） |
| 杀进程 | `am force-stop <pkg>` | 被 `system_server` 绑定的进程无效 | — |
| 关通知监听/无障碍/设备管理员 | 设置内操作或 `cmd notification` 系列 | 全系统 | 保持 |

**关键认知**：`pm uninstall --user 0` 是 T1 唯一能"跨重启保持"的卸载手段，
但它的语义是"这个用户下不再安装"，文件仍在镜像里，一次 `pm install-existing` 即可还原。

### 3.3 判定表：看到什么报错就是什么结论

| 输出 | 含义 | 下一步 |
|---|---|---|
| `Success` + `pm list` 无 + `pm path` 空 | 用户态卸载成功 | 重启后复查；观察是否被守护装回 |
| `DELETE_FAILED_USER_RESTRICTED` | OEM 标记为不可卸载 | 放弃卸载，走 appops；需要真禁用只能 T2/T3 |
| `SecurityException: Shell cannot change component state` | 组件级禁用需 root | 同上 |
| `SecurityException: Cannot suspend ..., no root permission` | 暂停需 root | 同上 |
| `cmd appops set` 无报错但 `get` 仍 `default` | 该包未申请此 op（不是失败） | 无需处理 |
| `Unknown operation string: READ_LOGS` | `READ_LOGS` 不是 appops 名 | 它是权限，只能 revoke 或 root |

### 3.4 决策：什么时候停在 T1

**满足以下全部条件，就停在 T1，不要升级**：

1. 目标组件已被 user 0 卸载，且重启后 `pm list` 仍为 0
2. 剩余组件的权限已 appops 收紧
3. 用户能接受"每次开机重跑一次 appops 脚本"

**这是大多数人的最优解**：零变砖风险、零保修影响、可完全回滚。

### 3.5 对象分类处置矩阵（T1 可用手段）

| 对象类型 | 典型 | T1 该做什么 | 不要做什么 |
|---|---|---|---|
| **采集类**（上报 IMEI/基站/使用行为） | 运营商 DM 客户端、统计 SDK | user 0 卸载 + 复查 | 不要反复卸载安装循环 |
| **安全/反诈类** | 安全中心、反诈模块 | 只 appops 收紧 | 不要卸载（砸功能、触发自检） |
| **通道类**（daemon/push/installer） | 包状态维护、推送 | 不动 | 卸载会导致应用装不上、通知收不到 |
| **底层**（vendor/HAL/内核线程） | 厂商日志服务 | 只记录 | 无 root 动不了，强行干预会砸硬件功能 |

---

## 4. T2：会话级 root（内核漏洞 / 官方 root / 工程线）

### 4.1 它到底给了你什么

**"root" 不是一个布尔值。** 会话级 root = 当前这次开机内拿到 uid 0，重启归零。

| 能力 | T1 有没有 | T2 有没有 | 备注 |
|---|---|---|---|
| 读 `/data/data/<pkg>/databases` | ❌ | ✅ | 这是"实采"证据的唯一来源 |
| `pm disable` 受保护组件 | ❌ | ✅ | 可让安全中心/日志系统真正停 |
| 杀被 `system_server` 绑定的进程 | ❌ | ✅ | 但会被重新拉起 |
| 改 hosts / iptables 阻断域名 | ❌ | ✅（会话内） | 重启丢失 |
| 改 `/system` 里的文件 | ❌ | ❌ | verity 保护，见 §5 |
| 开机自动生效 | ❌ | ❌ | 需要 T3 |

### 4.2 升级到 T2 的正当理由（只有这三种）

1. **需要硬证据**：必须读出数据库里的记录条数/时间戳/字段名，否则报告站不住
2. **需要临时封禁**：某个组件在 T1 卸不掉也禁不了，但你想在这次开机内让它停
3. **需要定位复活源**：观察是哪个进程把已禁用的包改回 `enabled=1`

**不是**正当理由：想"更彻底"、想删系统文件、想长期生效 —— 前者做不到，后两者属于 T3。

### 4.3 上 T2 前的三个硬性准备

```
1. 数据备份：至少把相册/聊天记录的可恢复副本放在别的设备上
2. 回滚路径：确认官方固件包可获取（救砖用）
3. 止损条件：写下来——连续 N 次失败 / 单次 panic 后未恢复 / 电量低于 X% 就停
```

实测经验：这类内核漏洞利用是**概率性**的，反复尝试会累积 panic，
而 panic 后的设备可能卡在启动早期（USB 只枚举出 CD-ROM gadget），需要长按电源强启。
**每失败一次，等冷启动完成、uptime > 120 秒再试**，不要连跑。

### 4.4 T2 的正确用法（按价值排序）

```
1. 取证：sqlite3 / pull 数据库 → 记录条数 + 最新时间戳 + 字段名（脱敏后入库报告）
2. 真禁用：pm disable <受保护包或组件>，观察是否被守护改回
3. 临时阻断：hosts 指向 127.0.0.1，验证上报是否停止（会话内）
4. 定位复活源：盯 system_server 日志，看谁调用 install-existing / setEnabledSetting
```

**不要**在 T2 做"物理删除系统文件"——即使技术上能写，也会在下次开机 AVB 校验失败。

### 4.5 决策：什么时候从 T2 退回 T1

- 连续 3 次尝试未达成目标 → 停，回 T1 的稳定态
- 出现文件系统异常/应用闪退/基带异常 → 立即停，恢复到官方固件
- 已经拿到证据 → 目的达成，退回 T1 执行处置（不需要一直保持 root）

---

## 5. T3：持久 root + 可写系统（需要解 BL）

### 5.1 前提链条（缺一不可）

```
BL 解锁
  ↓
刷入打过补丁的 boot / 加载 LKM（KernelSU / Magisk）
  ↓
关闭 dm-verity + vbmeta 校验（disable-verity，改 vbmeta）
  ↓
/system 可写 或 走 systemless overlay
```

**任何一环缺失，T3 都不成立。** 多数国行机型在第一环就断了（无官方解锁通道）。

### 5.2 T3 才能做的事

| 能力 | 说明 | 代价 |
|---|---|---|
| systemless 覆盖 | 对系统呈现为"文件被替换"，原文件保留 | 需持久 root；不影响 verity；OTA 正常 |
| 持久 hosts | 域名长期拦截 | 需可写系统或模块 |
| 开机脚本 | appops 重放、组件禁用、日志清理 | 需模块机制 |
| 真 `pm disable` | 受保护包/组件长期禁用 | 系统可能自检 |
| 卸载后不被装回 | 断掉 `install-existing` 路径 | 需改 PMS 行为或劫持调用 |

### 5.3 代价与风险（必须写进报告）

- **OTA 失效**：改过系统后增量更新会校验失败，只能整包升级
- **支付/银行类应用风控**：检测到 unlocked bootloader 或 root 会拒绝运行
- **保修与熔断**：解锁可能触发厂商熔断（不可逆）
- **误操作变砖**：改 vbmeta/分区表出错 → 只能进 EDL/工程模式救

### 5.4 决策：T3 是不是必要

**必要**：用户明确要求"文件不能留在机器里"或"每次开机都要自动生效"。

**不必要**：用户只是"不想它再上报"——T1 的 user 0 卸载已经达成，
再上 T3 是拿 OTA 和支付能力去换一个 4 MB 文件的消失，**性价比为负**。

---

## 6. T4：改镜像 / 换系统

### 6.1 什么时候它是唯一解

- 采集逻辑在 `boot` / `vendor` / `firmware` 层（用户态观察不到）
- 需要"出厂即干净"（例如二手转卖、合规审计留证）
- 系统级后门由 vendor 服务实现，用户态禁用无效

### 6.2 三种做法的风险梯度

| 做法 | 变砖风险 | 组件去除 | 可逆 | 备注 |
|---|---|---|---|---|
| `rm /system/.../X.apk`（解锁后） | **高** | ✅ | 不可逆 | 收益几 MB；AVB 不匹配 → bootloop；OTA 报废 |
| 自改 super 后重打包刷入 | **中高** | ✅ | 可重刷 | 需自签 vbmeta、对齐分区、版本严格匹配 |
| 刷官方原厂包 | 低 | ❌ **组件全回来** | — | 连 T1 的卸载状态也一起清掉 |
| systemless 覆盖（属 T3） | 低 | ✅ 等效 | ✅ | 不动分区，OTA 正常 |

**结论**：想"去预装"，systemless 覆盖优于物理删除；想"回到干净状态"，官方包反而倒退。

---

## 7. 全局决策树

```
开始
 │
 ├─ 能否 adb？ ──否──> T0：只关显性入口，记录局限，结束
 │        │是
 │        ▼
 ├─ T1 盘查：找到可疑组件？
 │        │否 ──> 输出"未发现实采证据"报告，结束
 │        ▼是
 ├─ T1 处置：user 0 卸载 + appops 收紧
 │        │
 │        ├─ 全部成功且重启不复活 ──> 停（最优解）
 │        │
 │        ├─ 有 USER_RESTRICTED / 需组件级禁用
 │        │        │
 │        │        ├─ 只需要"它别采集" ──> appops 收紧 + 定期复查，停
 │        │        │
 │        │        └─ 必须让它停 ──> 是否值得冒 T2 风险？
 │        │                 ├─否──> 停，写清"未解决项 + 原因"
 │        │                 └─是──> T2（带止损条件）
 │        │
 │        └─ 用户要求"文件也不能留" ──> BL 可解？
 │                 ├─否──> 告知边界，停（这是硬上限）
 │                 └─是──> T3（systemless 优先，物理删除最后考虑）
 │
 └─ 底层也有采集（boot/vendor） ──> T4，且必须提前确认救砖路径
```

---

## 8. 每级都要做的收尾（否则等于没做）

### 8.1 复核三连（T1 起每级必做）

```sh
adb shell "pm list packages | grep -c <pkg>"    # 应为 0
adb shell "pm path <pkg>"                        # 应为空
adb shell "ps -A -o NAME | grep -c <pkg名>"      # 应为 0
adb shell "ls -d /data/data/<pkg>"               # 应不存在
adb shell "pm list packages -u | grep <pkg>"     # 仍可见 = 镜像里还有（预期）
```

### 8.2 重启验证（唯一能证明"持久"的方式）

```
adb reboot → 等待 boot_completed=1 且 uptime > 120s → 重跑 8.1
```

### 8.3 观察期（文档里最容易被跳过、也最影响可信度的一步）

一次重启不复活 ≠ 长期不复活。至少记录：

- 观察窗口（例如 7 天）
- 每次开机后 `pm list` 的结果
- 是否出现 `install-existing` 调用记录

**报告里写"重启不复活"是不够的，要写"观察 N 天内 M 次开机均未复活"。**

---

## 9. 交接记录模板（交给下一个 Agent 时逐项填）

```markdown
#### 设备
- 机型 / 固件 / 内核 / Android 版本 / BL 状态

#### 当前所处阶梯
- T0 / T1 / T2 / T3 / T4：______
- 为什么停在这一级：______

#### 已完成的处置
| 对象 | 动作 | 结果 | 复核方式 | 重启后 |

#### 未解决项
| 对象 | 阻塞原因 | 需要哪一级权限 | 建议 |

#### 证据
- evidence_pkg.txt / DB 字段清单（脱敏）/ 网络连接快照

#### 下一步（给接手者）
1. ...
2. ...
```

---

## 10. 附录：常见报错 → 归属层级

| 报错 | 含义 | 归属 |
|---|---|---|
| `DELETE_FAILED_USER_RESTRICTED` | OEM 标记不可卸载 | T2/T3 |
| `DELETE_FAILED_INTERNAL_ERROR` | PMS 内部拒绝 | 先查是否系统应用 |
| `Shell cannot change component state` | 组件级禁用需 root | T2/T3 |
| `Cannot suspend ..., no root permission` | 暂停需 root | T2/T3 |
| `Unknown operation string: READ_LOGS` | 不是 appops 名 | 用 `pm revoke` 或 T2 |
| `cmd appops set` 成功但 `get` 为 `default` | 该包未申请该 op | 非错误 |
| `remount /system` 失败 | verity 保护 | T3（需先 disable-verity） |
| 卸载后进程仍在 | `system_server` 绑定 | 正常现象，看 T2 能否杀掉 |

---

## 11. 一句话总结

> **T1 能解决 90% 的问题且没有任何不可逆风险；
> T2 只用来取证和临时处置；
> T3 是"文件级彻底"的唯一路径，代价是 OTA 与支付；
> T4 只在底层也有后门时才值得。
> 每一级都要能独立收尾——不要为了"更彻底"而把设备推向不可逆。**
