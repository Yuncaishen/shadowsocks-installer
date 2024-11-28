#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 安装必要的包
install_dependencies() {
    echo -e "${GREEN}[1/5] 正在安装依赖...${NC}"
    yum update -y
    yum install python3 python3-pip curl -y
}

# 安装 Shadowsocks
install_shadowsocks() {
    echo -e "${GREEN}[2/5] 正在安装 Shadowsocks...${NC}"
    pip3 install shadowsocks
}

# 创建配置文件
create_config() {
    echo -e "${GREEN}[3/5] 正在创建配置文件...${NC}"
    cat > /etc/shadowsocks.json << EOF
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
}

# 修复 OpenSSL 问题
fix_openssl() {
    echo -e "${GREEN}[4/5] 正在修复 OpenSSL 问题...${NC}"
    sed -i 's/EVP_CIPHER_CTX_cleanup/EVP_CIPHER_CTX_reset/g' /usr/local/lib/python3.9/site-packages/shadowsocks/crypto/openssl.py
}

# 启动服务
start_service() {
    echo -e "${GREEN}[5/5] 正在启动服务...${NC}"
    ssserver -c /etc/shadowsocks.json -d start
}

# 生成 SS URI 链接
generate_uri() {
    METHOD="aes-256-cfb"
    PASSWORD="wayde"
    PORT="8388"
    IP=$(curl -s http://checkip.amazonaws.com)
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
    echo -e "${GREEN}请确保在 AWS 安全组中开放 $PORT 端口${NC}"
}

# 检查是否为 root 用户
check_root() {
    if [ $EUID -ne 0 ]; then
        echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

# 主函数
main() {
    clear
    echo -e "${GREEN}开始安装 Shadowsocks...${NC}"
    check_root
    install_dependencies
    install_shadowsocks
    create_config
    fix_openssl
    start_service
    generate_uri
    echo -e "\n${GREEN}安装完成！${NC}"
}

# 运行主函数
main 
