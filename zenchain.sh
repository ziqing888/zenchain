#!/bin/bash

# 定义颜色和格式
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"
CYAN="\e[36m"

NODENAME="zenchain"

# 打印脚本头部信息
print_header() {
    echo -e "\n${BOLD}${GREEN}============================================${RESET}"
    echo -e "${BOLD}${GREEN}       ZenChain 节点设置脚本 ${RESET}"
    echo -e "${BOLD}${GREEN}============================================${RESET}\n"
}

# 记录并显示消息
log_info() {
    echo -e "${CYAN}[INFO] $1${RESET}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${RESET}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${RESET}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${RESET}"
}

# 设置环境
setup() {
    print_header  # 输出脚本标题
    sleep 1

    log_info "正在更新和升级系统软件包..."
    sudo apt update -y && sudo apt upgrade -y

    cd $HOME
    if [ -d "node" ]; then
        log_info "'node' 目录已存在。"
    else
        mkdir node
        log_success "创建了 'node' 目录。"
    fi
    cd node

    if [ -d "$NODENAME" ]; then
        log_info "'$NODENAME' 目录已存在。"
    else
        mkdir $NODENAME
        log_success "创建了 '$NODENAME' 目录。"
    fi
    cd $NODENAME
}

# 安装必要的软件
installRequirements(){
    if ! command -v docker &> /dev/null; then
        log_info "正在安装 Docker..."
        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
            sudo apt-get remove -y $pkg
        done

        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        
        sudo apt update -y && sudo apt install -y docker-ce
        sudo systemctl start docker
        sudo systemctl enable docker

        log_success "Docker 安装成功。"
    else
        log_info "Docker 已安装。"
    fi

    if ! command -v jq &> /dev/null; then
        log_info "正在安装 jq..."
        sudo apt install -y jq
        log_success "jq 安装成功。"
    else
        log_info "jq 已安装。"
    fi
}

# 处理节点相关操作
process(){
    mkdir -p "chain-data"
    chmod -R 777 "chain-data"
    log_success "创建了 'chain-data' 目录。"

    read -p "请输入您的验证人名称： " VALIDATORNAME
    echo "YOURVALIDATORNAME=$VALIDATORNAME" > .env
    log_success ".env 文件已创建，包含验证人名称：$VALIDATORNAME"
    
    log_info "正在创建 docker-compose-pre.yaml 文件..."
cat <<EOF > docker-compose-pre.yaml
version: '3'
services:
  zenchain:
    image: ghcr.io/zenchain-protocol/zenchain-testnet:latest
    container_name: zenchain
    ports:
      - "9944:9944"
    volumes:
      - ./chain-data:/chain-data
    command: >
      ./usr/bin/zenchain-node
      --base-path=/chain-data
      --rpc-cors=all
      --rpc-methods=unsafe
      --unsafe-rpc-external
      --name=$VALIDATORNAME
      --bootnodes=/dns4/node-7242611732906999808-0.p2p.onfinality.io/tcp/26266/p2p/12D3KooWLAH3GejHmmchsvJpwDYkvacrBeAQbJrip5oZSymx5yrE
      --chain=zenchain_testnet
EOF

    log_success "docker-compose-pre.yaml 文件已创建，包含验证人名称：$VALIDATORNAME"

    log_info "使用 PRE Docker Compose 启动 ZenChain 节点..."
    docker-compose -f docker-compose-pre.yaml up -d
    log_info "正在等待 ZenChain 节点容器启动..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        log_info "等待 ZenChain 容器启动..."
    done

    log_success "ZenChain 节点容器已启动！"
    log_info "正在等待日志中显示 'Prometheus exporter started'..."
    while true; do
        if docker logs zenchain 2>&1 | grep -q "Prometheus exporter started"; then
            log_success "'Prometheus exporter started' 信息已在日志中找到。"
            break
        fi
        sleep 2
    done

    log_info "发送 RPC 请求以轮换密钥并获取会话密钥..."
    RESPONSE=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' http://localhost:9944)

    if [ $? -ne 0 ]; then
        log_error "Curl 请求失败。退出脚本。"
        exit 1
    fi

    # 从响应中提取会话密钥（去掉 '0x' 前缀）
    SESSION_KEY=$(echo $RESPONSE | jq -r '.result | select(. != null)')
    log_success "会话密钥：$SESSION_KEY"

    if [[ $SESSION_KEY =~ ^0x ]]; then
        SESSION_KEY=${SESSION_KEY:2}
    fi

    log_success "去除 '0x' 前缀后的会话密钥：$SESSION_KEY"

    log_info "继续下一步，请按照以下信息设置您的以太坊账户密钥，并通过发送 0 Tokens 到 Zenchain 网络进行验证："
    echo -e "\n发送到：'0x0000000000000000000000000000000000000802'"
    echo -e "\n输入数据：0xf1ec919c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060$SESSION_KEY"
    echo -e "\n"
    while true; do
        read -p "按 Enter 键继续： " user_input
        if [[ -z "$user_input" ]]; then
            log_info "正在继续下一步..."
            log_info "停止 ZenChain 容器..."
            docker stop zenchain
            log_info "移除 ZenChain 容器..."
            docker rm zenchain
            break
        fi
    done

    log_info "正在创建 docker-compose.yaml 文件..."

cat <<EOF > docker-compose.yaml
version: '3'

services:
  zenchain:
    image: ghcr.io/zenchain-protocol/zenchain-testnet:latest
    container_name: zenchain
    ports:
      - "9944:9944"
    volumes:
      - ./chain-data:/chain-data
    command: ./usr/bin/zenchain-node \
      --base-path=/chain-data \
      --validator \
      --name="$VALIDATORNAME" \
      --bootnodes=/dns4/node-7242611732906999808-0.p2p.onfinality.io/tcp/26266/p2p/12D3KooWLAH3GejHmmchsvJpwDYkvacrBeAQbJrip5oZSymx5yrE \
      --chain=zenchain_testnet
    restart: always
EOF

    log_success "docker-compose.yaml 文件已创建，包含您的验证人名称：$VALIDATORNAME"
    log_info "使用 Docker Compose 启动 ZenChain 节点..."
    docker-compose -f docker-compose.yaml up -d
    log_info "正在等待 ZenChain 节点容器启动..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        log_info "等待 ZenChain 容器启动..."
    done

    log_success "ZenChain 节点容器已启动！"
}

# 完成安装
finish() {
    NODEPATH=$(pwd) 
    
    log_success "安装完成"
    log_info "您的节点路径在 $NODEPATH"
    echo ""
    log_info "使用以下命令查看节点日志： 'docker logs -f zenchain'"
    log_info "现在，前往验证人仪表板： https://node.zenchain.io/#/staking"
    log_info "点击 'Stake' > 'Click To Your Account' > 'Click Become a Validator' > 输入您希望质押的金额 > 点击 'Start Staking'"
    log_success "完成！加油！"
}

# 执行脚本步骤
setup
installRequirements
process
finish
