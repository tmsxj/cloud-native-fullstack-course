#!/bin/bash
# Monit 专用：检查僵尸进程数量
# 退出码: 0=正常(<=5), 1=异常(>5)

Z=$(ps aux | awk '$8~/^Z/' | wc -l)
Z=$(echo "$Z" | tr -d ' ')

if [ "$Z" -le 5 ]; then
    exit 0
else
    echo "僵尸进程数: $Z (阈值: 5)"
    exit 1
fi
