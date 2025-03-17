#!/bin/bash
Version="v1.4.4"
Date="2025-03-17"
Info="NODES 数组变量替换"

# 定义颜色输出
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# 检测操作系统类型
OS_TYPE=$(uname)
if [[ "$OS_TYPE" == "Darwin" ]]; then
    # macOS - 使用函数替代简单变量
    sed_cmd() {
        sed -i '' "$1" "$2"
    }
else
    # Linux
    sed_cmd() {
        sed -i "$1" "$2"
    }
fi

# 定义全局变量
NODES=("198.19.249.92" "198.19.249.19" "198.19.249.130")
STORAGE_INSERT_ADDR=":8400"
STORAGE_SELECT_ADDR=":8401"
STORAGE_ADDR=":8482"
INSERT_ADDR=":8480"
SELECT_ADDR=":8481"
AUTH_ADDR=":8427"
STORAGE_DATA_PATH="./vmstorage-data"
SELECT_CACHE_PATH="./tmp/vmselect"
BACKUP_PATH="./backup"
RETENTION_PERIOD="180d"
LOG_DIR="log"
AUTH_CONF="./vmauth.conf"
PWD=$(pwd)
PidFile="./victoriametrics.pid"
FirstNode=${NODES[0]}
MinScrapeInterval="15s" # vmstorage, vmselect 去重间隔，-dedup.minScrapeInterval, 需要和vmagent的采集频率一致
ReplicationFactor=2 # vmselect and vminsert replicationFactor


# 创建 start.sh
cat > start.sh << 'EOF'
#!/bin/bash

# Version: "${Version}"
# Date: "${Date}"
# Author: "${Author}"
# Info: "${Info}"
# vmui: "http://${FirstNode}:8427/select/0/vmui"

if [[ ! "$1" == "-dryRun" ]]; then
  set -x
fi

# variables
nodes=(${NODES[@]})
storageInsertAddr="${STORAGE_INSERT_ADDR}"
storageSelectAddr="${STORAGE_SELECT_ADDR}"
storageAddr="${STORAGE_ADDR}"
insertAddr="${INSERT_ADDR}"
selectAddr="${SELECT_ADDR}"
authAddr="${AUTH_ADDR}"
minScrapeInterval="${MinScrapeInterval}"

# storage
retentionPeriod=${RETENTION_PERIOD}
storageDataPath='${STORAGE_DATA_PATH}'
if [[ ! -d $storageDataPath ]]; then
  mkdir -p $storageDataPath
fi
storageSNConfig="-retentionPeriod=$retentionPeriod -httpListenAddr=${storageAddr} -storageDataPath=$storageDataPath -vminsertAddr=$storageInsertAddr -vmselectAddr=$storageSelectAddr -dedup.minScrapeInterval=${minScrapeInterval}"

# insert and select
insertSNConfig="-httpListenAddr=${insertAddr} "
selectSNConfig="-httpListenAddr=${selectAddr} "
selectCachePath='${SELECT_CACHE_PATH}'
for i in "${nodes[@]}"; do
  insertSNConfig+="-storageNode=$i${storageInsertAddr} "
  selectSNConfig+="-storageNode=$i${storageSelectAddr} "
done
insertSNConfig+="-replicationFactor=${ReplicationFactor} "
selectSNConfig+="-cacheDataPath=$selectCachePath -dedup.minScrapeInterval=${minScrapeInterval} -replicationFactor=${ReplicationFactor} "
if [[ ! -d $selectCachePath ]]; then
  mkdir -p $selectCachePath
fi

# auth
authConf="${AUTH_CONF}"
authSNConfig="-httpListenAddr=${authAddr} -auth.config=$authConf"

function vmauthConfig() {
  configText="unauthorized_user:\n  url_map:"
  configText+="\n    - src_paths:\n      - \"/insert/.+\"\n      url_prefix:"
  for node in "${nodes[@]}"; do
    configText+="\n        - \"http://${node}${insertAddr}/\""
  done
  configText+="\n    - src_paths:\n      - \"/select/.+\"\n      url_prefix:"
  for node in "${nodes[@]}"; do
    configText+="\n        - \"http://${node}${selectAddr}/\""
  done
  echo -e "$configText" > $authConf
  if [[ $? -ne 0 ]]; then
    echo "配置文件生成失败, failed"
    exit 1
  else
    echo "配置文件生成成功, success"
  fi
}

if [[ (! -f $authConf) && (! $1 == "-dryRun") ]]; then
  echo "auth config file not found, create it"
  vmauthConfig
fi

# log
logDir="${LOG_DIR}"
insertLogName="vminsert.log"
selectLogName="vmselect.log"
storageLogName="vmstorage.log"
authLogName="vmauth.log"

# 检查所有所需的可执行文件
for cmd in ./vmstorage ./vminsert ./vmselect ./vmauth; do
  if [[ ! -x $cmd ]]; then
    echo "错误: $cmd 不存在或没有执行权限"
    exit 1
  fi
done

# print cmd
if [[ "$1" == "-dryRun" ]]; then
  echo "nohup ./vmstorage $storageSNConfig &> $logDir/$storageLogName &"
  echo "nohup ./vminsert $insertSNConfig &> $logDir/$insertLogName &"
  echo "nohup ./vmselect $selectSNConfig &> $logDir/$selectLogName &"
  echo "nohup ./vmauth $authSNConfig &> $logDir/$authLogName &"
  exit 0
fi

# 启动所有服务
if [[ ! -d $logDir ]]; then
  mkdir -p $logDir
fi
echo "启动 vmstorage..."
nohup ./vmstorage $storageSNConfig &> $logDir/$storageLogName &
storagePID=$!
echo "vmstorage 已启动，PID: $storagePID"

# 等待 vmstorage 完全启动
sleep 2
echo "启动 vminsert..."
nohup ./vminsert $insertSNConfig &> $logDir/$insertLogName &
insertPID=$!
echo "vminsert 已启动，PID: $insertPID"

echo "启动 vmselect..."
nohup ./vmselect $selectSNConfig &> $logDir/$selectLogName &
selectPID=$!
echo "vmselect 已启动，PID: $selectPID"

echo "启动 vmauth..."
nohup ./vmauth $authSNConfig &> $logDir/$authLogName &
authPID=$!
echo "vmauth 已启动，PID: $authPID"

# 保存进程ID到文件
if [[ -f ${PidFile} ]]; then
  > ${PidFile}
fi
echo "$storagePID $insertPID $selectPID $authPID" > ${PidFile}
echo "所有服务已启动，PID已保存到 ${PidFile}"
echo "vmui: "http://${FirstNode}:8427/select/0/vmui""

set +x
EOF

# 替换变量 - 使用检测到的 SED_CMD
sed_cmd "s|\${Version}|${Version}|g" start.sh
sed_cmd "s|\${Date}|${Date}|g" start.sh
sed_cmd "s|\${Author}|${Author}|g" start.sh
sed_cmd "s|\${Info}|${Info}|g" start.sh
NODE_LIST=$(printf "'%s' " "${NODES[@]}" | sed 's/ $//')
sed_cmd "s|\${NODES\[@\]}|${NODE_LIST}|g" start.sh
sed_cmd "s|\${STORAGE_INSERT_ADDR}|${STORAGE_INSERT_ADDR}|g" start.sh
sed_cmd "s|\${STORAGE_SELECT_ADDR}|${STORAGE_SELECT_ADDR}|g" start.sh
sed_cmd "s|\${STORAGE_ADDR}|${STORAGE_ADDR}|g" start.sh
sed_cmd "s|\${INSERT_ADDR}|${INSERT_ADDR}|g" start.sh
sed_cmd "s|\${SELECT_ADDR}|${SELECT_ADDR}|g" start.sh
sed_cmd "s|\${AUTH_ADDR}|${AUTH_ADDR}|g" start.sh
sed_cmd "s|\${RETENTION_PERIOD}|${RETENTION_PERIOD}|g" start.sh
sed_cmd "s|\${STORAGE_DATA_PATH}|${STORAGE_DATA_PATH}|g" start.sh
sed_cmd "s|\${SELECT_CACHE_PATH}|${SELECT_CACHE_PATH}|g" start.sh
sed_cmd "s|\${AUTH_CONF}|${AUTH_CONF}|g" start.sh
sed_cmd "s|\${LOG_DIR}|${LOG_DIR}|g" start.sh
sed_cmd "s|\${PidFile}|${PidFile}|g" start.sh
sed_cmd "s|\${FirstNode}|${FirstNode}|g" start.sh
sed_cmd "s|\${MinScrapeInterval}|${MinScrapeInterval}|g" start.sh
sed_cmd "s|\${ReplicationFactor}|${ReplicationFactor}|g" start.sh

# 创建 stop.sh
cat > stop.sh << 'EOF'
#!/bin/bash

# Version: "${Version}"
# Date: "${Date}"
# Author: "${Author}"
# Info: "${Info}"

if [[ ! -f ${PidFile} ]]; then
  echo "错误：${PidFile} 文件不存在"
  exit 1
fi

pids=$(cat ${PidFile})
if [[ -z "$pids" ]]; then
  echo "警告：PID 文件为空"
  exit 0
fi

for pid in $pids; do
  if ps -p $pid > /dev/null; then
    # 获取进程名称
    proc_name=$(ps -p $pid -o comm= | tr -d ' ')
    echo "停止进程 $pid (${proc_name})..."
    kill $pid
    # 等待进程结束
    for (( i=0; i<8; i++ )); do
      if ! ps -p $pid > /dev/null; then
        echo "进程 $pid (${proc_name}) 已停止"
        break
      fi
      sleep 2
    done
    # 如果进程仍在运行，强制终止
    if ps -p $pid > /dev/null; then
      echo "进程 $pid (${proc_name}) 仍在运行，强制终止"
      kill -9 $pid
    fi
  else
    echo "进程 $pid 不存在"
  fi
done

echo "所有服务已停止"
rm -f ${PidFile}

EOF

# 替换变量
sed_cmd "s|\${Version}|${Version}|g" stop.sh
sed_cmd "s|\${Date}|${Date}|g" stop.sh
sed_cmd "s|\${Author}|${Author}|g" stop.sh
sed_cmd "s|\${Info}|${Info}|g" stop.sh
sed_cmd "s|\${PidFile}|${PidFile}|g" stop.sh

# 创建 backup.sh
cat > backup.sh << 'EOF'
#!/bin/bash

# Version: "${Version}"
# Date: "${Date}"
# Author: "${Author}"
# Info: "${Info}"

set -x
storageDataPath='${PWD}/${STORAGE_DATA_PATH}'
backupPath='${PWD}/${BACKUP_PATH}'

# 移除路径中可能的 './' 前缀
storageDataPath=${storageDataPath/.\//}
backupPath=${backupPath/.\//}

# 检查存储目录
if [[ ! -d $storageDataPath ]]; then
  echo "错误：存储数据目录 $storageDataPath 不存在"
  exit 1
fi

# 创建备份目录
if [[ ! -d $backupPath ]]; then
  echo "创建备份目录 $backupPath"
  mkdir -p $backupPath
fi

# 检查 vmbackup 工具
if [[ ! -x ./vmbackup ]]; then
  echo "错误：vmbackup 不存在或没有执行权限"
  exit 1
fi

# 执行备份
echo "开始备份数据..."
./vmbackup -storageDataPath=$storageDataPath -snapshot.createURL=http://localhost${STORAGE_ADDR}/snapshot/create -dst=fs://$backupPath

if [[ $? -eq 0 ]]; then
  echo "数据备份成功"
else
  echo "数据备份失败"
  exit 1
fi

set +x
EOF

# 替换变量
sed_cmd "s|\${PWD}|${PWD}|g" backup.sh
sed_cmd "s|\${Version}|${Version}|g" backup.sh
sed_cmd "s|\${Date}|${Date}|g" backup.sh
sed_cmd "s|\${Author}|${Author}|g" backup.sh
sed_cmd "s|\${Info}|${Info}|g" backup.sh
sed_cmd "s|\${STORAGE_DATA_PATH}|${STORAGE_DATA_PATH}|g" backup.sh
sed_cmd "s|\${BACKUP_PATH}|${BACKUP_PATH}|g" backup.sh
sed_cmd "s|\${STORAGE_ADDR}|${STORAGE_ADDR}|g" backup.sh

# 创建 restore.sh
cat > restore.sh << 'EOF'
#!/bin/bash

# Version: "${Version}"
# Date: "${Date}"
# Author: "${Author}"
# Info: "${Info}"

set -x

storageDataPath='${PWD}/${STORAGE_DATA_PATH}'
backupPath='${PWD}/${BACKUP_PATH}'
storageDataPath=${storageDataPath/.\//}
backupPath=${backupPath/.\//}

# 检查备份目录
if [[ ! -d $backupPath ]]; then
  echo "错误：备份目录 $backupPath 不存在"
  exit 1
fi

# 检查 vmrestore 工具
if [[ ! -x ./vmrestore ]]; then
  echo "错误：vmrestore 不存在或没有执行权限"
  exit 1
fi

# 检查是否有服务在运行
if [[ -f ${PidFile} ]]; then
  echo "警告：VictoriaMetrics 服务似乎正在运行，请先停止服务"
  echo "用法：./stop.sh 停止服务，然后再恢复数据"
  exit 1
fi

# 确保存储目录存在
if [[ ! -d $storageDataPath ]]; then
  echo "创建存储数据目录 $storageDataPath"
  mkdir -p $storageDataPath
fi

# 执行恢复
echo "开始恢复数据..."
./vmrestore -src=fs://$backupPath -storageDataPath=$storageDataPath

if [[ $? -eq 0 ]]; then
  echo "数据恢复成功"
else
  echo "数据恢复失败"
  exit 1
fi

set +x
EOF

# 替换变量
sed_cmd "s|\${Version}|${Version}|g" restore.sh
sed_cmd "s|\${Date}|${Date}|g" restore.sh
sed_cmd "s|\${Author}|${Author}|g" restore.sh
sed_cmd "s|\${Info}|${Info}|g" restore.sh
sed_cmd "s|\${STORAGE_DATA_PATH}|${STORAGE_DATA_PATH}|g" restore.sh
sed_cmd "s|\${PWD}|${PWD}|g" restore.sh
sed_cmd "s|\${BACKUP_PATH}|${BACKUP_PATH}|g" restore.sh
sed_cmd "s|\${PidFile}|${PidFile}|g" restore.sh

# 创建 status.sh
cat > status.sh << 'EOF'
#!/bin/bash

# Version: "${Version}"
# Date: "${Date}"
# Author: "${Author}"
# Info: "${Info}"

if [[ -f ${PidFile} ]]; then
  pids=$(cat ${PidFile})
  if [[ -z "$pids" ]]; then
    echo "警告：PID 文件为空"
    exit 0
  fi
  
  echo "VictoriaMetrics 进程状态："
  ps -fp $pids
  
  # 检查并显示日志目录状态
  if [[ -d ${LOG_DIR} ]]; then
    echo -e "\n日志文件状态："
    ls -lh ${LOG_DIR}/*.log
  fi
else 
  echo "未找到 ${PidFile} 文件，服务可能未运行"
  
  # 尝试查找可能的相关进程
  echo -e "\n尝试查找相关进程："
  ps aux | grep -E 'vmstorage|vminsert|vmselect|vmauth' | grep -v grep
fi
EOF

# 替换变量
sed_cmd "s|\${Version}|${Version}|g" status.sh
sed_cmd "s|\${Date}|${Date}|g" status.sh
sed_cmd "s|\${Author}|${Author}|g" status.sh
sed_cmd "s|\${Info}|${Info}|g" status.sh
sed_cmd "s|\${LOG_DIR}|${LOG_DIR}|g" status.sh
sed_cmd "s|\${PidFile}|${PidFile}|g" status.sh


# 添加执行权限
chmod +x start.sh stop.sh backup.sh restore.sh status.sh

# 创建 help 内容
help_content=$(cat << EOF
# VictoriaMetrics 集群部署

Version: ${Version}
Date: ${Date}
Author: ${Author}
Info: ${Info}

## 使用方法

1. 首次部署: \`./start.sh\`
2. 打印启动命令: \`./start.sh -dryRun\` 
3. 检查状态: \`./status.sh\`
4. 数据备份: \`./backup.sh\`
5. 停止服务: \`./stop.sh\`
6. 恢复数据: \`./restore.sh\`

## 脚本说明

- **start.sh**: 启动 VictoriaMetrics 集群/打印启动命令
- **stop.sh**: 停止 VictoriaMetrics 集群
- **backup.sh**: 备份 VictoriaMetrics 数据
- **restore.sh**: 恢复 VictoriaMetrics 数据
- **status.sh**: 查看 VictoriaMetrics 进程状态

## 访问界面

- 访问地址: http://${FirstNode}:8427/select/0/vmui
EOF
)

# 同时输出到标准输出和 help.md
echo -e "${GREEN}所有脚本已成功生成:${NC}"
echo "  - start.sh: 启动 VictoriaMetrics 集群/打印启动命令"
echo "  - stop.sh: 停止 VictoriaMetrics 集群"
echo "  - backup.sh: 备份 VictoriaMetrics 数据"
echo "  - restore.sh: 恢复 VictoriaMetrics 数据"
echo "  - status.sh: 查看 VictoriaMetrics 进程状态"
echo -e "${GREEN}使用方法:${NC}"
echo "  1. 首次部署: ./start.sh"
echo "  2. 打印启动命令: ./start.sh -dryRun" 
echo "  3. 检查状态: ./status.sh"
echo "  4. 数据备份: ./backup.sh"
echo "  5. 停止服务: ./stop.sh"
echo "  6. 恢复数据: ./restore.sh"
echo -e "${GREEN}访问地址:${NC} http://${FirstNode}:8427/select/0/vmui"

# 保存到 help.md
echo "$help_content" > help.md
echo -e "${GREEN}说明文档已写入到 help.md${NC}"
