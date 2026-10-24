# NOSR_Bark

自建 Bark 推送服务的 Cloudflare Workers 副本。

- **上游**：[cwxiaos/bark-worker](https://github.com/cwxiaos/bark-worker)（GPL-3.0），本仓库是派生副本，追踪上游 `v2.2.6`
- **线上地址**：`https://bark.nosr.top`（Worker `nosr-bark` + Custom Domain，走 Cloudflare 边缘）
- **存储**：D1 数据库 `NOSR_Bark`（绑定名 `database`）
- **用途**：服务器告警、定时任务、脚本通知推送到 iPhone

## 部署方式（本仓库的实际路径）

1. 点上游 README 的 **Deploy to Cloudflare** 按钮 → CF 自动建 Worker、建 D1、跑迁移、部署，并把源码导入成本仓库
2. 之后所有变更用 `wrangler` 手动部署（本仓库已含 `wrangler.json`，DB 与绑定已写死）

> 上游手动路径（Create Worker → Edit Code 粘贴 `main.js` → 建 D1 → 绑定名必须叫 `database`）也能用，但 `wrangler` 更稳，因为它同时管理 vars 与绑定。

## 配置（`wrangler.json` → `vars`）

| 变量 | 值 | 说明 |
|---|---|---|
| `ALLOW_NEW_DEVICE` | `false` | 关闭自助注册，防止他人把设备写入本库、借用 APNs 凭据 |
| `ALLOW_QUERY_NUMS` | `true` | 允许查询设备数量（`/info`，已被 WAF 拦） |
| `ROOT_PATH` | `/` | 保持 `/`。该变量只做路径前缀剥离，**不是访问控制**（实测设成随机前缀后旧的 `/ping` 仍可访问） |
| `BASIC_AUTH` | 未设置 | 可选，设了会给推送与 `/info` 加 Basic 认证；需确认客户端支持 `user:pass@host` 再开 |

## 常用命令

```bash
export CLOUDFLARE_API_TOKEN=<token>            # 需要 Workers Scripts:Edit + D1:Edit
export CLOUDFLARE_ACCOUNT_ID=549a4fc4cbcf521ed0b9b91bd4827855

wrangler deploy                                  # 部署
wrangler d1 migrations apply database --remote   # 升级时若有新迁移必须跑
wrangler tail                                    # 看实时日志
```

查设备（只读）：

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACC/d1/database/80b3ed41-0779-42a2-8bec-f41edf687584/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"sql":"SELECT id, key, length(token) FROM devices"}'
```

## 已验证的状态（2026-10-24）

- `GET /ping` → `{"code":200,"message":"pong"}`
- `POST /<key>`（JSON 体）→ 推送成功，APNs 返回 200
- `GET /info`、`GET /register` → 被 Cloudflare WAF 规则 `bark: block /register and /info` 拦截（403）
- 设备 1 台（本人 iPhone）；迁移 `001_create_authorization.sql`、`002_create_devices.sql` 均已应用

## 安全须知

- 本 Worker 用的是上游（Bark 作者）的 APNs 凭据，公开共享、无法轮换；因此**必须**保持 `ALLOW_NEW_DEVICE=false`
- 设备 key 是 22 位随机串，等同推送密码，泄露即可被推垃圾通知 → 不要写进公开仓库或截图
- 关注册后推送接口仍无鉴权（Bark 的设计），防护靠「key 保密 + 关注册 + 管理面 WAF 拦截」

## 升级流程

```bash
git remote add upstream https://github.com/cwxiaos/bark-worker   # 只需一次
# 取上游新版本 main.js，对比后替换
diff --strip-trailing-cr main.js /path/to/upstream/main.js
wrangler deploy
```

历次部署时间点可从提交历史查到：`git log --format="%h %ad %s" --date=iso`
