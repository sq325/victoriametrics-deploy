# VictoriaMetrics 集群部署指南

## 基本信息

`deploy.sh` 脚本用于一键生成运维脚本，快速配置并启动 VictoriaMetrics 集群，包含以下组件:

- vmstorage: 存储组件
- vminsert: 写入组件
- vmselect: 查询组件
- vmauth: 负载均衡组件
- vmbackup: 备份组件  
- vmrestore: 恢复组件

## 使用方法

1. 修改 `deploy.sh` 脚本中的 `NODES` 变量，设置集群节点 IP 地址

```bash
# 修改这些变量以适应您的环境
NODES=("192.168.1.10" "192.168.1.11" "192.168.1.12")
```

2. 按需要修改 `deploy.sh` 脚本中的其他变量
3. 执行 `deploy.sh` 脚本，等待脚本生成完成

```bash
./deploy.sh
```

4. 启动集群：

```bash
./start.sh
```

5. 其他操作
1. 查看启动命令: ./start.sh -dryRun
2. 查看服务状态: ./status.sh
3. 备份数据: ./backup.sh
4. 停止服务: ./stop.sh
5. 恢复数据: ./restore.sh

## 配置说明

主要配置参数说明：

| 参数 | 描述 | 默认值 |
|------|------|--------|
| RETENTION_PERIOD | 数据保留时长 | 180d |
| STORAGE_DATA_PATH | 存储数据路径 | ./vmstorage-data |
| BACKUP_PATH | 备份数据路径 | ./backup |
| LOG_DIR | 日志文件目录 | log |
| MinScrapeInterval | 去重间隔 | 15s |
| ReplicationFactor | 复制因子 | 2 |

## Web 访问界面

访问 VictoriaMetrics UI：http://<NodeIP>:8427/select/0/vmui

## 数据管理

### 备份

备份操作会将 VictoriaMetrics 中的数据保存到指定目录：

```bash
./backup.sh
```

备份将存储在 ./backup 目录下。

### 恢复

恢复操作会从备份目录恢复数据：

```bash
./stop.sh       # 首先停止服务
./restore.sh    # 然后恢复数据
./start.sh      # 最后重启服务
```

## 更多信息

[VictoriaMetrics 官方文档](https://docs.victoriametrics.com/)
