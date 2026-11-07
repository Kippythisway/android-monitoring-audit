# 发布材料包（维护者用）

本文件是"发到 GitHub 时手边需要的东西"清单：名称、简介、标签、首屏文案、自检、发布命令、发布后动作。

---

## 1. 仓库名（三选一）

| 名称 | 适合 |
|---|---|
| `android-monitoring-audit` | 直白、好搜，**推荐** |
| `android-bloatware-audit` | 贴近"预装软件"这一常见说法，受众更广 |
| `phone-privacy-playbook` | 强调"方法论"而非工具，弱化机型依赖 |

## 2. 仓库描述（About 栏，选一条）

**中文**

> 手机预装监控组件盘查：一份可交给 AI Agent 执行的自查提示词。
> 按权限分级（T0 无调试 → T1 adb → T2 临时 root → T3 持久 root → T4 改镜像），
> 每级写清能做到什么、怎么验证、什么时候该停；并附"以反诈为名"的系统组件权限审计。
> 含 vivo X100 Ultra（Android 16）脱敏案例。

**英文**

> Audit and remediate preinstalled Android telemetry — organized as a privilege ladder
> (no-debug → adb → session root → persistent root → custom image). Each tier states what's
> achievable, how to verify, and when escalation is worth the cost.

## 3. Topics（GitHub 仓库页右上角，选 10–15 个）

```
android  adb  privacy  bloatware  debloat  telemetry  audit  security
playbook  forensics  mobile-security  reverse-engineering  vivo  originos
anti-fraud  prompt  ai-agent  self-audit
```

## 4. 首屏文案（README 前 10 行决定 90% 的 star）

当前 README 的顺序已按这个原则排好：

```
标题（一句人话）→ 一句话定位 → 三层结论表（L1/L2/L3）→ 关键判断（大多数人要 L1 不是 L3）
```

如果要进一步强化，可加一行"实测结果"：

> 实测：某运营商 DM 客户端（预装、不在应用列表里、上报 IMEI+基站）用一条
> `pm uninstall --user 0` 移除，重启后未复活。

**注意**：这类"一句话战果"最抓人，但必须脱敏且不点名到可识别设备。

## 5. 发布前自检（务必跑）

```powershell
cd <repo 目录>

# 形状匹配（不是真实值）：IMEI / 私网 IP / MAC / 手机号 / 邮箱
$patterns = @(
  '\b\d{15}\b',
  '\b(10|172|192)\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
  '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b',
  '\b1[3-9]\d{9}\b',
  '[\w.+-]+@[\w-]+\.[\w.]+'
)
Get-ChildItem -Recurse -File | Select-String -Pattern $patterns |
  Select-Object Path,LineNumber,Line
```

无输出 = 干净。再人工确认：

- [ ] 无设备序列号、手机号、IMEI/ICCID/IMSI
- [ ] 无内网 IP、Wi-Fi 名称、MAC
- [ ] 无真实姓名、邮箱、单位、地区
- [ ] 无用户自行安装的第三方应用清单（银行、社交、办公）
- [ ] 无 APK、数据库、日志原件、截图原图
- [ ] 案例章节明确写"仅同固件同内核成立"

## 6. 发布命令

```powershell
cd <repo 目录>
git init
git add .
git commit -m "docs: preinstalled monitoring audit playbook (privilege ladder)"
git remote add origin https://github.com/<你的用户名>/android-monitoring-audit.git
git branch -M main
git push -u origin main
```

装 GitHub CLI 后可一条命令建仓：

```powershell
winget install --id GitHub.cli
gh auth login
gh repo create android-monitoring-audit --public --source=. --remote=origin --push `
  --description "Audit and remediate preinstalled Android telemetry — privilege ladder from adb-only to custom images"
gh repo edit --add-topic android,adb,privacy,bloatware,debloat,telemetry,audit,security,playbook,forensics
```

## 7. 发布后动作（按顺序做，前两条最重要）

1. **加 Issue 模板** `.github/ISSUE_TEMPLATE/device-report.md`（收集机型案例，只收脱敏文本）
2. **README 顶部或 Issue 模板里写明**：不同品牌组件命名差异极大，本仓库给的是方法论与检索式
3. **打 tag**：`git tag -a v1.0.0 -m "initial" && git push --tags`
4. **开 Discussions**（可选）：比 Issue 更适合"你们机型有没有 X"这类开放讨论
5. **不要**开 PR 欢迎"帮我删某台设备上的某个包"——这类请求一律指回手册

## 8. 需要准备但不进仓库的东西

| 物料 | 用途 | 注意 |
|---|---|---|
| 脱敏后的前后对比表 | 首屏/README 配图 | 数值可保留（如"进程数 1 → 0"），不要留设备标识 |
| 一张架构图（权限阶梯） | README 中部 | 用 Mermaid 画在 md 里即可，不需要图片文件 |
| 案例的报错截图 | 附录 | 必须裁掉状态栏、时间、设备名 |
| 录屏 | 社交平台扩散 | 同样需要脱敏，且不要出现通知内容 |

## 9. 一版可直接发的社交文案（备用）

> 折腾了一天，把"手机里那些看不见的系统应用"整理成了一份按权限分级的手册：
> 只用 adb 能查到什么、能删到什么程度、什么时候必须解 BL、解了之后又为什么要付 OTA 和支付的代价。
> 结论是：90% 的人只需要第一级，而且它零风险可回滚。
> 仓库：<链接>
