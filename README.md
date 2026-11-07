# 手机预装监控组件盘查：一份可交给 AI Agent 执行的自查提示词

> —— 含"以反诈为名"的系统组件权限审计
>
> 只用 `adb` 就能跑完的安卓预装监控组件盘查与处置手册。
> 不刷机、不解 BL、不需要 root，先把能查的清、能关的关掉；
> 什么时候必须越线、越线要付什么代价，也一并写清楚。

---

## ⚡ 一键执行（复制一行，粘上就跑）

> 前置：`adb` 已在 PATH 中（没有的话装 [platform-tools](https://developer.android.com/studio/releases/platform-tools)，
> 或把命令里的 `adb` 替换成绝对路径）。手机已开 USB 调试并授权。
> 脚本已在 Android 14 / Android 16 设备上实跑通过，输出约 120 行只读信息。

**A. 命令行盘点当前设备**（只读，不改任何东西；macOS / Linux / Git Bash）

```bash
curl -fsSL https://raw.githubusercontent.com/Kippythisway/android-monitoring-audit/main/scripts/survey.sh -o /tmp/survey.sh && adb push /tmp/survey.sh /data/local/tmp/ >/dev/null && adb shell "sh /data/local/tmp/survey.sh" | tee survey.txt
```

**B. Windows PowerShell**

```powershell
iwr https://raw.githubusercontent.com/Kippythisway/android-monitoring-audit/main/scripts/survey.sh -OutFile "$env:TEMP\survey.sh"; adb push "$env:TEMP\survey.sh" /data/local/tmp/; adb shell "sh /data/local/tmp/survey.sh" | Tee-Object survey.txt
```

**C. 交给 AI 代跑**（把整段提示词粘给你的 AI 助手，它自己执行上面的命令并给出结论）

👉 打开 [PROMPT.md](PROMPT.md)，复制里面的代码块即可。

> 三条都只做盘查，不卸载、不修改系统。看完输出再决定要不要处置——
> 处置命令在下面的[快速开始](#快速开始t120-分钟)里，逐条给。

---

## 先说结论（赶时间看这段）

预装采集组件可以粗暴分成三层，很多人卡住是因为把三层混为一谈：

| 层级 | 目标 | 需要什么 | 重启后 |
|---|---|---|---|
| **L1 功能失效** | 应用列表消失、进程起不来、数据清空 | `pm uninstall --user 0`，adb 即可 | ✅ 保持 |
| **L2 能力收紧** | 应用还在，但读不到短信/位置/使用统计/相机 | `cmd appops set … ignore` | ❌ 丢失，开机重跑 |
| **L3 物理删除** | `/system` 里的 APK 真消失 | root + 关闭 verity + 可写系统（≈ 解 BL） | 永久 |

**关键判断**：绝大多数人真正要的是 L1（它别再上报），而不是 L3（文件消失）。
L1 零风险、可回滚；L3 要付 OTA 失效、支付风控、保修熔断的代价，收益只是几 MB 空间。

---

## 这份手册解决什么问题

厂商预装的"系统应用"里，有一部分不服务于设备功能，而是持续采集并上报：

- 设备标识（IMEI / ICCID / IMSI）
- 基站与定位（TAC / CID / PCI / ARFCN）
- 应用使用行为（装了哪些 App、用了多久）
- 短信与通话元数据

它们通常有这些特征：

- 不在应用列表里显示，或藏在"系统应用"里
- 以 `onBoot` / `SIMState` / `ConnectState` 广播接收器 + 常驻 Service 的形式工作
- 被厂商守护进程保护：卸载被拒、禁用被还原、杀进程后被 `system_server` 重新绑定
- 用共享 uid（`uid 1000`）伪装成"拥有全部系统权限"

而网上能找到的教程大多只给一句 `adb shell pm uninstall --user 0 com.xxx`——
不解释为什么有的成功有的报错，也不解释卸载之后文件还在、还可能被装回来。

---

## 手册的结构：按"你手上的权限"分级

不是按步骤流水，而是按能力分层——你可以随时停在任意一级，并知道停在这里意味着什么。

| 阶梯 | 门槛 | 能力上限 | 不可逆风险 |
|---|---|---|---|
| **T0** 无调试 | 只有手机 | 关闭显性入口（无障碍/通知监听/设备管理员） | 无 |
| **T1** adb 无 root | 调试通道 | 盘查 + 用户态卸载 + 权限收紧 | 极低 |
| **T2** 会话级 root | 内核漏洞 / 官方 root | 读应用私有数据、禁用受保护组件、临时拦截 | 中（panic / 掉数据） |
| **T3** 持久 root | BL 解锁 + 关 verity | systemless 覆盖、持久 hosts、开机脚本 | 高（OTA/支付/保修） |
| **T4** 改镜像 | BL + 刷写 | 物理移除、换 ROM | 很高（变砖） |

每一级都回答三个问题：**能做到什么程度 / 怎么判定成败 / 什么时候该停、什么时候才值得升级**。

---

## 快速开始（T1，20 分钟）

```bash
# 1. 连接（USB 调试，或 Android 11+ 无线调试）
adb devices

# 2. 盘查：进程 / 包状态 / 共享 uid / 权限 / 四大入口 / 网络
adb push scripts/survey.sh /data/local/tmp/
adb shell sh /data/local/tmp/survey.sh

# 3. 处置：先卸载"普通预装"，再对剩下的收紧权限
adb shell "pm uninstall --user 0 <你的目标包>"
adb shell "TARGETS='com.a com.b' sh /data/local/tmp/reapply_appops.sh"

# 4. 复核（重启后必须重跑）
adb reboot && adb wait-for-device
adb shell "pm list packages | grep -c <目标包>"   # 期望 0
```

> 全部脚本都不修改系统分区，最坏情况用 `pm install-existing <pkg>` 一键还原。
>
> **只想动手、不想读原理**：打开 [PROMPT.md](PROMPT.md)，复制那段代码块，粘给 AI 即可。

---

## 案例：vivo X100 Ultra（Android 16）

手册里记录了一台 `V2366GA` / `PD2366`（固件 `PD2366G_A_16.2.19.0.W10`）的实测结果，可作为对照：

| 组件 | 判定 | 关键事实 | 处置结果 |
|---|---|---|---|
| `com.mobiletools.systemhelper` | **实采** | 数据库含 IMEI/ICCID/IMSI/基站三元组；硬编码上报域名 `dm.wo.com.cn:18080`；四个开机/插卡/联网广播接收器 | `pm uninstall --user 0` **成功，跨重启不复活** |
| `com.bbk.iqoo.logsystem` | 有能力 | 持有 `PACKAGE_USAGE_STATS`、`WRITE_SECURE_SETTINGS` | 被 OEM 标 `USER_RESTRICTED`，三条路全拒；只能 appops |
| `com.vivo.abe` | 有能力 | 行为画像引擎，**与系统共用 uid 1000** | 杀不掉（zygote 重生），只 appops |
| `com.vivo.daemonService` | 通道 | 观测到把已禁用的采集包改回 `enabled=1` | 不动（动了会连累装包/更新） |
| vendor/HAL 若干 | 底层 | 厂商日志、工厂 AT、售后诊断服务 | 只记录，无 root 不可控 |

> 该案例只保留机型、固件、包名、权限名、域名字符串等技术事实；
> 不含序列号、IP、IMEI、账号或用户安装的应用清单。

---

## 反诈视角：以"安全"为名的组件，也需要过同一套审计

"反诈"是系统组件里最容易被放过的一类——一旦挂了安全的名义，几乎没人会去问它拿了什么权限。
本次盘查在这一点上抓到了实证：

| 组件 | 反诈相关痕迹 | 同时持有的高危权限 |
|---|---|---|
| `com.vivo.safecenter` | 规则文件 `AntiPhoneFraudRule.json`、白名单 `AntiPhoneFraudWhiteNumber.txt`、提示音 `AIFraudCall.ogg` | `READ_SMS`、`WRITE_SECURE_SETTINGS`、`QUERY_ALL_PACKAGES` |
| `com.iqoo.secure` | 提供 `AntiFraudProvider.xml`，与上一项联动 | `READ_SMS`、`READ_LOGS`、`READ_PHONE_STATE`、`PACKAGE_USAGE_STATS` |
| `com.android.packageinstaller` | 配置文件 `anti_fraud_file.xml`（装包时触发反诈校验） | 装包钩子 |

**审计要点**（对反诈类组件同样适用，不因为"它在防诈骗"就跳过）：

1. **能力 vs 需求的落差**：拦截诈骗短信只需要"收到即判定"，不需要长期留存全部短信正文、
   不需要 `QUERY_ALL_PACKAGES` 枚举你装了哪些应用。**能力大于需求，就要问为什么。**
2. **数据流向才是判据**：用 `strings` 扫 APK 里的域名、用 `ss -tn` 看实际连接。
   只做本地判定的组件不会持续外连；持续外连的，要看连的是哪。
3. **不给"反诈"开例外**：本次盘查里，真正被判定为**实采**的组件（上报 IMEI/基站/使用行为到
   运营商 DM 平台）恰恰没有一个挂"反诈"名义。**名义与行为无关，只看证据。**
4. **处置上仍要克制**：反诈组件属于系统安全链路，卸载会砸掉来电/短信拦截与支付保护，
   也可能触发系统自检。**正确定位是"收权限"，不是"卸载"**——`READ_SMS` / `READ_CALL_LOG` /
   `QUERY_ALL_PACKAGES` 收紧到 `ignore` 即可，见 `scripts/reapply_appops.sh`。

> 一句话：**反诈能不能用是一回事，它拿了多少权限、把数据送到哪是另一回事。**
> 后者任何人都该有资格查，包括用这套提示词让 AI 代查。

---

## 三条最容易踩的坑

**1. "有权限" ≠ "在采集"**
权限表只能证明能力。要证明行为，得看数据库记录条数、最新时间戳、实际网络连接。
而且共享 uid 的包会继承 system 的整个权限集——看起来"持有 READ_LOGS / DUMP / CAMERA"，
实际它的 manifest 可能只申请了一个 `RECEIVE_BOOT_COMPLETED`。

**2. 禁用 ≠ 停用**
`enabled=2` 的包仍可能有进程在跑（被 `system_server` 绑定），`force-stop` 之后 pid 不变。
判定要同时看 `enabled=`、`ps`、`suspended=` 三个维度。

**3. 卸载 ≠ 删除**
`pm list packages -u` 仍能看到 = 系统镜像里的 APK 还在。
想让它彻底消失得动 `/system`，而那要过 dm-verity/AVB——零售机上等价于解 BL。

---

## 这个仓库不承诺什么

- **不承诺"万能包名表"**：不同品牌、不同固件的组件命名差异极大，手册给的是方法论与检索式
- **不承诺"删了就安全"**：预装采集常有云端侧配置，客户端只是采集端之一
- **不承诺"适用于你的机型"**：案例结论只对同固件同内核成立
- **不提供**针对具体设备的破解服务、不提供 APK/数据库样本

---

## 目录

```
.
├── README.md                    你正在看的这份
├── PROMPT.md                    ★ 一屏可复制的提示词：直接粘给 AI Agent 就能开跑
├── PLAYBOOK.md                  主手册：T0–T4 权限阶梯 + 盘查流程 + 处置矩阵 + 决策树
├── PUBLISH.md                   维护者用：发布步骤与自检清单
├── LICENSE                      MIT（文档部分 CC BY 4.0）
└── scripts/
    ├── survey.sh                盘查：进程/包状态/共享 uid/权限/四大入口/网络
    ├── reapply_appops.sh        重启后重收紧权限（幂等，支持自定义目标列表）
    └── debloat_systemhelper.ps1 卸载 + 复核示例（Windows 侧，含失败回退）
```

---

## 贡献

欢迎提交**脱敏后的机型案例**，格式：

```
机型 / 固件 / 内核：
组件包名：
判定标签：实采 / 有能力 / 通道 / 底层 / 假象 / 良性
证据类型：数据库字段名 / 权限表 / 网络连接 / 组件名（不要贴原始数据）
处置结果：成功 / 被拒（附报错字符串）/ 未尝试
重启后状态：
```

**不收**：APK、数据库文件、日志原件、截图原图、任何个人数据。

---

## 免责

仅对自己持有且有权处置的设备使用。卸载/禁用系统组件可能导致功能异常、OTA 失败或数据丢失，
动手前请自行备份并确认官方固件可获取。手册中的实测结论来自特定机型与固件，不构成通用保证。

---

## License

- 文档（`*.md`）：CC BY 4.0
- 脚本（`scripts/*`）：MIT

---

## English summary

A practical, adb-only field guide for auditing and remediating preinstalled telemetry
components on Android devices. It is organized as a **privilege ladder** (T0 no-debug →
T1 adb shell → T2 session-scoped root → T3 persistent root → T4 custom images), and each
tier states what is achievable, how to verify success, when to stop, and when escalation
is actually worth the irreversible cost. Includes a de-identified case study from a vivo
X100 Ultra running Android 16, plus detection heuristics for the three most common
misjudgements: capability vs. behaviour, disabled vs. stopped, and uninstalled vs. deleted.
