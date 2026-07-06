#!/bin/bash
# Monit 专用：检查是否有失败的 systemd 服务
# 退出码: 0=正常(无失败), 1=异常(有失败服务)

C=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l)
C=$(echo "$C" | tr -d ' ')

if [ "$C" -eq 0 ]; then
    exit 0
else
    echo "失败服务数: $C"
    systemctl list-units --state=failed --no-legend 2>/dev/null
    exit 1
fi
