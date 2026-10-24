#!/usr/bin/env bash
# bark 双通道推送
#   自建: https://bark.nosr.top   (Cloudflare Worker nosr-bark, D1 NOSR_Bark)
#   官方: https://api.day.app     (兜底通道，自建挂了也能收到)
#
# 用法:
#   ./notify.sh "标题" "正文"
#   ./notify.sh "磁盘告警" "占用 92%" critical
#
# 参数: $1 标题  $2 正文  $3 级别(active|timeSensitive|critical，默认 timeSensitive)
#
# 配置: 同目录 .env
#   BARK_KEY_SELF=<自建服务器里拿到的 22 位 key>
#   BARK_KEY_OFFICIAL=<官方 api.day.app 的 key>
#
# 编码说明（重要）:
#   本机系统代码页是 936(GBK)。MSYS2 把参数交给 curl.exe 时会转成 GBK，
#   导致中文/emoji 变乱码。因此这里绝不把正文放进命令行参数：
#   1) bash 里先 base64（纯 ASCII）→ 2) node 解码后写成 UTF-8 文件 → 3) curl -d @文件。
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"

TITLE="${1:-通知}"
BODY="${2:-}"
LEVEL="${3:-timeSensitive}"
GROUP="${BARK_GROUP:-运维}"

TITLE_B64=$(printf '%s' "$TITLE" | base64 -w0)
BODY_B64=$(printf '%s' "$BODY"   | base64 -w0)
GROUP_B64=$(printf '%s' "$GROUP" | base64 -w0)

PAYLOAD=$(mktemp)
TITLE_B64="$TITLE_B64" BODY_B64="$BODY_B64" GROUP_B64="$GROUP_B64" LEVEL="$LEVEL" PAYLOAD="$PAYLOAD" node -e '
  const fs = require("fs");
  const d = (s) => Buffer.from(s, "base64").toString("utf8");
  fs.writeFileSync(process.env.PAYLOAD, JSON.stringify({
    title: d(process.env.TITLE_B64),
    body:  d(process.env.BODY_B64),
    group: d(process.env.GROUP_B64),
    level: process.env.LEVEL,
    sound: "minuet"
  }), "utf8");
'

send() {  # $1=名称 $2=base-url $3=key
  [ -z "${3:-}" ] && { echo "  - $1: 未配置 key，跳过"; return 0; }
  local out code
  out=$(mktemp)
  code=$(curl -s -o "$out" -w "%{http_code}" -X POST "$2/$3" \
         -H "Content-Type: application/json; charset=utf-8" --data-binary "@$PAYLOAD")
  if [ "$code" = "200" ]; then
    echo "  ✓ $1 已送达"
  else
    echo "  ✗ $1 失败 HTTP $code → $(head -c 160 "$out" 2>/dev/null)"
  fi
  rm -f "$out"
}

echo "推送: $TITLE"
send "自建 bark.nosr.top" "https://bark.nosr.top" "${BARK_KEY_SELF:-}"
send "官方 api.day.app"    "https://api.day.app"  "${BARK_KEY_OFFICIAL:-}"
rm -f "$PAYLOAD"
