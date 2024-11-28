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

# 安装必要的包
install_dependencies() {
    echo -e "${GREEN}[1/5] 正在安装依赖...${NC}"
    
    # 清理并更新系统
    echo -e "${YELLOW}正在更新系统...${NC}"
    yum clean all
    yum update -y --skip-broken || handle_error "系统更新失败"
    
    # 安装依赖包
    echo -e "${YELLOW}正在安装依赖包...${NC}"
    for package in python3 python3-pip curl net-tools; do
        echo -e "${YELLOW}正在安装 $package...${NC}"
        yum install -y --allowerasing $package || handle_error "安装 $package 失败"
    done
    
    # 验证安装
    for cmd in python3 pip3 curl netstat; do
        if ! command -v $cmd &> /dev/null; then
            handle_error "$cmd 未能正确安装"
        fi
    done
    
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 安装 Shadowsocks
install_shadowsocks() {
    echo -e "${GREEN}[2/5] 正在安装 Shadowsocks...${NC}"
    
    # 使用 --break-system-packages 参数安装
    pip3 install --break-system-packages shadowsocks || {
        echo -e "${YELLOW}尝试替代安装方法...${NC}"
        python3 -m pip install --user shadowsocks || handle_error "Shadowsocks 安装失败"
    }
    
    # 添加到 PATH
    export PATH=$PATH:$HOME/.local/bin:/usr/local/bin
    
    # 验证安装
    if ! command -v ssserver &> /dev/null; then
        # 尝试找到 ssserver 的位置
        SSSERVER_PATH=$(find / -name ssserver 2>/dev/null | head -n 1)
        if [ -n "$SSSERVER_PATH" ]; then
            ln -sf "$SSSERVER_PATH" /usr/local/bin/ssserver
        else
            handle_error "Shadowsocks 安装失败，ssserver 命令不可用"
        fi
    fi
}

# 创建配置文件
create_config() {
    echo -e "${GREEN}[3/5] 正在创建配置文件...${NC}"
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

    # 验证配置文件
    if [ ! -f /etc/shadowsocks.json ]; then
        handle_error "配置文件不存在"
    fi
}

# 修复 OpenSSL 问题
fix_openssl() {
    echo -e "${GREEN}[4/5] 正在修复 OpenSSL 问题...${NC}"
    # 查找 openssl.py 文件
    OPENSSL_FILE=$(find / -name openssl.py | grep shadowsocks/crypto/openssl.py 2>/dev/null)
    if [ -z "$OPENSSL_FILE" ]; then
        handle_error "找不到 OpenSSL 文件"
    fi
    
    # 修复文件
    sed -i 's/EVP_CIPHER_CTX_cleanup/EVP_CIPHER_CTX_reset/g' "$OPENSSL_FILE" || handle_error "OpenSSL 修复失败"
    echo -e "${GREEN}OpenSSL 文件已修复：$OPENSSL_FILE${NC}"
}

# 启动服务
start_service() {
    echo -e "${GREEN}[5/5] 正在启动服务...${NC}"
    # 确保 ssserver 在 PATH 中
    export PATH=$PATH:$HOME/.local/bin:/usr/local/bin
    
    # 停止现有服务
    ssserver -c /etc/shadowsocks.json -d stop >/dev/null 2>&1
    
    # 启动服务
    ssserver -c /etc/shadowsocks.json -d start || handle_error "服务启动失败"
    
    # 验证服务是否启动
    sleep 2
    if ! netstat -ntlp | grep ":8388 " > /dev/null; then
        handle_error "服务未能正常启动"
    fi
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

# 检查网络连接
check_network() {
    echo -e "${YELLOW}正在检查网络连接...${NC}"
    if ! curl -s --connect-timeout 5 http://checkip.amazonaws.com > /dev/null; then
        handle_error "网络连接失败，请检查网络设置"
    fi
    echo -e "${GREEN}网络连接正常${NC}"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}开始安装 Shadowsocks...${NC}"
    check_root
    check_network
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
