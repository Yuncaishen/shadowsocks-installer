#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 错误处理
handle_error() {
    echo -e "${RED}错误：$1${NC}"
    exit 1
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        handle_error "命令 $1 未找到，请检查安装"
    fi
}

# 检查端口是否可用
check_port() {
    if netstat -tuln | grep ":$1 " >/dev/null 2>&1; then
        handle_error "端口 $1 已被占用"
    fi
}

# 检查网络连接
check_network() {
    echo -e "${YELLOW}正在检查网络连接...${NC}"
    if ! curl -s --connect-timeout 5 http://checkip.amazonaws.com > /dev/null; then
        handle_error "网络连接失败，请检查网络设置"
    fi
    echo -e "${GREEN}网络连接正常${NC}"
}

# 安装必要的包
install_dependencies() {
    echo -e "${GREEN}[1/5] 正在安装依赖...${NC}"
    yum update -y || handle_error "系统更新失败"
    yum install python3 python3-pip curl net-tools -y || handle_error "依赖安装失败"
    
    # 检查安装结果
    for cmd in python3 pip3 curl netstat; do
        check_command $cmd
    done
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 安装 Shadowsocks
install_shadowsocks() {
    echo -e "${GREEN}[2/5] 正在安装 Shadowsocks...${NC}"
    pip3 install shadowsocks || handle_error "Shadowsocks 安装失败"
    check_command ssserver
    echo -e "${GREEN}Shadowsocks 安装完成${NC}"
}

# 创建配置文件
create_config() {
    echo -e "${GREEN}[3/5] 正在创建配置文件...${NC}"
    check_port 8388
    cat > /etc/shadowsocks.json << EOF || handle_error "配置文件创建失败"
{
    "server": "0.0.0.0",
    "port_password": {
        "8388": "wayde"
    },
    "timeout": 300,
    "method": "aes-256-cfb",
    "fast_open": false
}
EOF
    if [ ! -f /etc/shadowsocks.json ]; then
        handle_error "配置文件不存在"
    fi
    echo -e "${GREEN}配置文件创建完成${NC}"
}

# 修复 OpenSSL 问题
fix_openssl() {
    echo -e "${GREEN}[4/5] 正在修复 OpenSSL 问题...${NC}"
    OPENSSL_FILE="/usr/local/lib/python3.9/site-packages/shadowsocks/crypto/openssl.py"
    if [ ! -f "$OPENSSL_FILE" ]; then
        handle_error "OpenSSL 文件不存在"
    fi
    sed -i 's/EVP_CIPHER_CTX_cleanup/EVP_CIPHER_CTX_reset/g' "$OPENSSL_FILE" || handle_error "OpenSSL 修复失败"
    echo -e "${GREEN}OpenSSL 修复完成${NC}"
}

# 启动服务
start_service() {
    echo -e "${GREEN}[5/5] 正在启动服务...${NC}"
    ssserver -c /etc/shadowsocks.json -d start || handle_error "服务启动失败"
    
    # 检查服务是否正在运行
    sleep 2
    if ! netstat -ntlp | grep ":8388 " > /dev/null; then
        handle_error "服务未能正常启动"
    fi
    echo -e "${GREEN}服务启动完成${NC}"
}

# 生成 SS URI 链接
generate_uri() {
    METHOD="aes-256-cfb"
    PASSWORD="wayde"
    PORT="8388"
    IP=$(curl -s http://checkip.amazonaws.com)
    if [ -z "$IP" ]; then
        handle_error "无法获取公网 IP"
    fi
    BASE64_STR=$(echo -n "$METHOD:$PASSWORD" | base64 | tr -d '\n')
    SS_URI="ss://${BASE64_STR}@$IP:$PORT"
    
    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}Shadowsocks 配置信息：${NC}"
    echo -e "服务器: ${RED}$IP${NC}"
    echo -e "端口: ${RED}$PORT${NC}"
    echo -e "密码: ${RED}$PASSWORD${NC}"
    echo -e "加密方式: ${RED}$METHOD${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}SS URI 链接（适用于 Shadowrocket）：${NC}"
    echo -e "${RED}$SS_URI${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${YELLOW}请确保在 AWS 安全组中开放 $PORT 端口${NC}"
}

# 检查是否为 root 用户
check_root() {
    if [ $EUID -ne 0 ]; then
        handle_error "请使用 root 用户运行此脚本"
    fi
}

# 检查 AWS 安全组设置
check_aws_security_group() {
    echo -e "${YELLOW}请确保已在 AWS 安全组中添加以下规则：${NC}"
    echo -e "类型：自定义 TCP"
    echo -e "端口：8388"
    echo -e "来源：0.0.0.0/0"
    read -p "已确认安全组设置？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        handle_error "请先配置 AWS 安全组"
    fi
}

# 主函数
main() {
    clear
    echo -e "${GREEN}开始安装 Shadowsocks...${NC}"
    check_root
    check_network
    check_aws_security_group
    install_dependencies
    install_shadowsocks
    create_config
    fix_openssl
    start_service
    generate_uri
    echo -e "\n${GREEN}安装完成！${NC}"
    
    # 最终检查
    echo -e "\n${YELLOW}正在进行最终检查...${NC}"
    if netstat -ntlp | grep ":8388 " > /dev/null; then
        echo -e "${GREEN}服务运行正常！${NC}"
    else
        echo -e "${RED}警告：服务可能未正常运行，请检查日志${NC}"
    fi
}

# 运行主函数
main
