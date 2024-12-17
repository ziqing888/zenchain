#!/bin/bash

# 设置颜色和样式
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"
INFO="${CYAN}[INFO]${RESET}"
SUCCESS="${GREEN}[SUCCESS]${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"
ERROR="${RED}[ERROR]${RESET}"

# 节点名称
NODENAME="zenchain"

# 显示信息函数
print_header() {
    echo -e "\n${BOLD}${GREEN}============================================${RESET}"
    echo -e "${BOLD}${GREEN}       ZenChain 节点设置脚本 ${RESET}"
    echo -e "${BOLD}${GREEN}============================================${RESET}\n"
}

print_step() {
    echo -e "${BOLD}${YELLOW}正在执行步骤: $1...${RESET}"
}

print_success() {
    echo -e "${SUCCESS}$1${RESET}"
}

print_error() {
    echo -e "${ERROR}$1${RESET}"
}

# 设置环境
setup() {
    print_header
    curl -s https://raw.githubusercontent.com/ziqing888/logo.sh/refs/heads/main/logo.sh | bash
    sleep 3

    print_step "更新并升级系统软件包"
    sudo apt update -y && sudo apt upgrade -y

    # 创建节点文件夹
    cd $HOME
    if [ -d "node" ]; then
        print_success "'node' 目录已存在。"
    else
        mkdir node
        print_success "已创建 'node' 目录。"
    fi
    cd node

    if [ -d "$NODENAME" ]; then
        print_success "'$NODENAME' 目录已存在。"
    else
        mkdir $NODENAME
        print_success "已创建 '$NODENAME' 目录。"
    fi
    cd $NODENAME
}

# 安装依赖
installRequirements(){
    # 安装 Docker
    if ! command -v docker &> /dev/null; then
        print_step "安装 Docker"
        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
            sudo apt-get remove -y $pkg
        done

        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        
        sudo apt update -y && sudo apt install -y docker-ce
        sudo systemctl start docker
        sudo systemctl enable docker

        print_success "Docker 安装成功。"
    else
        print_success "Docker 已安装。"
    fi

    # 安装 jq
    if ! command -v jq &> /dev/null; then
        print_step "安装 jq"
        sudo apt install -y jq
    fi
}

# 配置并启动节点
process(){
    # 创建链数据目录
    mkdir -p "chain-data"
    chmod -R 777 "chain-data"
    print_success "'chain-data' 目录已创建。"

    # 获取用户输入
    read -p "请输入您的验证器名称: " VALIDATORNAME
    echo "YOURVALIDATORNAME=$VALIDATORNAME" > .env
    print_success ".env 文件已创建，验证器名称: $VALIDATORNAME"

    # 创建 docker-compose-pre.yaml 文件
    print_step "创建 docker-compose-pre.yaml 文件"
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

    print_success "docker-compose-pre.yaml 文件已创建。"

    # 启动 ZenChain 节点
    print_step "启动 ZenChain 节点，使用 PRE Docker Compose 配置"
    docker-compose -f docker-compose-pre.yaml up -d
    print_step "等待 ZenChain 节点容器启动..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        echo -e "${INFO}等待 ZenChain 容器启动..."
    done

    print_success "ZenChain 节点容器已启动！"
    print_step "等待日志中出现 'Prometheus exporter started' 信息..."
    while true; do
        if docker logs zenchain 2>&1 | grep -q "Prometheus exporter started"; then
            print_success "'Prometheus exporter started' 信息已在日志中找到。"
            break
        fi
        sleep 2
    done

    # 发送 RPC 请求
    print_step "发送 RPC 请求以旋转密钥并获取会话密钥"
    RESPONSE=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' http://localhost:9944)

    if [ $? -ne 0 ]; then
        print_error "Curl 请求失败，退出。"
        exit 1
    fi

    # 提取会话密钥
    SESSION_KEY=$(echo $RESPONSE | jq -r '.result | select(. != null)')
    print_success "会话密钥 : $SESSION_KEY"

    if [[ $SESSION_KEY =~ ^0x ]]; then
        SESSION_KEY=${SESSION_KEY:2}
    fi

    print_success "会话密钥（无 '0x' 前缀）: $SESSION_KEY"

    echo -e "\n为了继续，请将0个Token发送到Zenchain网络上的以下地址，并使用以下详细信息："
    echo -e "\n发送到：'0x0000000000000000000000000000000000000802'"
    echo -e "\n输入数据：0xf1ec919c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060$SESSION_KEY"
    echo -e "\n"

    while true; do
        read -p "按 Enter 继续: " user_input
        if [[ -z "$user_input" ]]; then
            print_success "正在继续下一步..."
            print_step "停止 ZenChain 容器"
            docker stop zenchain
            print_step "删除 ZenChain 容器"
            docker rm zenchain
            break
        fi
    done

    # 创建并启动最终的docker-compose.yaml文件
    print_step "创建 docker-compose.yaml 文件"
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

    print_success "docker-compose.yaml 文件已创建。"
    print_step "启动 ZenChain 节点，使用 Docker Compose 配置"
    docker-compose -f docker-compose.yaml up -d
    print_step "等待 ZenChain 节点容器启动..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        echo -e "${INFO}等待 ZenChain 容器启动..."
    done

    print_success "ZenChain 节点容器已启动！"
}

finish() {
    NODEPATH=$(pwd)

    print_success "节点设置完成！"
    echo -e "您的节点目录位于 $NODEPATH"
    print_success "查看节点日志：'docker logs -f zenchain'"
    echo -e "现在，访问验证器仪表板： https://node.zenchain.io/#/staking"
    echo -e "点击 'Stake' > 点击 'To Your Account' > 点击 'Become a Validator' > 输入您希望质押的数量 > 点击 'Start Staking'"
    print_success "完成，开始质押吧！LFG！"
}

setup
installRequirements
process
finish
