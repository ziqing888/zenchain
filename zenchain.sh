#!/bin/bash

# 设置颜色和样式
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"
信息="${CYAN}[信息]${RESET}"
成功="${GREEN}[成功]${RESET}"
警告="${YELLOW}[警告]${RESET}"
错误="${RED}[错误]${RESET}"

# 节点名称
NODENAME="zenchain"

# 显示分隔符
print_separator() {
    echo -e "${BOLD}${BLUE}============================================${RESET}"
}

# 输出步骤信息
print_step() {
    print_separator
    echo -e "${BOLD}${YELLOW}[步骤] $1...${RESET}"
}

print_成功() {
    echo -e "${成功} $1 ${RESET}"
}

print_错误() {
    echo -e "${错误} $1 ${RESET}"
}

# 设置环境
setup() {
    print_separator
    echo -e "${BOLD}${GREEN}欢迎使用 ZenChain 节点设置脚本${RESET}"
    print_separator

    curl -s https://raw.githubusercontent.com/ziqing888/logo.sh/refs/heads/main/logo.sh | bash
    sleep 2

    print_step "更新并升级系统软件包"
    sudo apt update -y && sudo apt upgrade -y
    print_成功 "系统更新完成"

    print_step "创建节点数据目录"
    cd $HOME
    [ -d "node" ] || mkdir node && print_成功 "已创建 'node' 目录"
    cd node
    [ -d "$NODENAME" ] || mkdir $NODENAME && print_成功 "已创建 '$NODENAME' 目录"
    cd $NODENAME
}

# 安装依赖
install_requirements() {
    print_step "检查并安装 Docker 和 jq"

    # Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${信息} 安装 Docker 中，请稍等..."
        sudo apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt update -y && sudo apt install -y docker-ce
        sudo systemctl enable docker --now
        print_成功 "Docker 安装成功"
    else
        print_成功 "Docker 已安装"
    fi

    # jq
    if ! command -v jq &> /dev/null; then
        sudo apt install -y jq
        print_成功 "jq 安装成功"
    else
        print_成功 "jq 已安装"
    fi
}

# 配置并启动节点
process() {
    print_step "配置节点文件并启动临时容器"

    # 创建数据目录
    mkdir -p "chain-data" && chmod 777 "chain-data"

    # 输入验证器名称
    read -p "请输入您的验证器名称: " VALIDATORNAME
    echo "YOURVALIDATORNAME=$VALIDATORNAME" > .env
    print_成功 ".env 文件已创建，验证器名称: $VALIDATORNAME"

    # 生成 docker-compose-pre.yaml 文件
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
EOF
    print_成功 "docker-compose-pre.yaml 文件已生成"

    # 启动临时节点
    docker-compose -f docker-compose-pre.yaml up -d
    print_step "等待临时 ZenChain 节点启动..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        echo -e "${信息} 等待 ZenChain 容器启动..."
    done
    print_成功 "临时节点已启动"

    # 发送 RPC 请求
    print_step "发送 RPC 请求以获取会话密钥"
    RESPONSE=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' http://localhost:9944)
    if [ $? -ne 0 ]; then
        print_错误 "RPC 请求失败，请检查节点状态。"
        exit 1
    fi

    SESSION_KEY=$(echo $RESPONSE | jq -r '.result')
    print_成功 "会话密钥: ${SESSION_KEY:2}"

    echo -e "\n请发送 0 个 Token 到以下地址："
    echo -e "📨 地址: 0x0000000000000000000000000000000000000802"
    echo -e "🔑 输入数据: 0xf1ec919c...${SESSION_KEY:2}\n"

    # 等待用户操作
    read -p "完成交易后按 Enter 继续..." _
    print_step "停止临时节点并清理容器"
    docker stop zenchain && docker rm zenchain
    print_成功 "临时节点已停止"

    # 创建最终 docker-compose.yaml
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
    command: ./usr/bin/zenchain-node --base-path=/chain-data --validator --name=$VALIDATORNAME
    restart: always
EOF

    docker-compose -f docker-compose.yaml up -d
    print_成功 "最终节点已启动！"
}

# 完成设置
finish() {
    print_separator
    echo -e "${BOLD}${GREEN}🎉 节点设置完成！${RESET}"
    echo -e "📂 数据目录: $(pwd)"
    echo -e "📊 查看日志: docker logs -f zenchain"
    echo -e "🌐 仪表板: https://node.zenchain.io/#/staking"
    print_成功 "设置成功！LFG！"
}

setup
install_requirements
process
finish
