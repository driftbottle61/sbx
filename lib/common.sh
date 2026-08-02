#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
END="\033[0m"

info() {
    echo -e "${BLUE}[INFO]${END} $1"
}

ok() {
    echo -e "${GREEN}[ OK ]${END} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${END} $1"
}

error() {
    echo -e "${RED}[FAIL]${END} $1"
}

pause() {
    echo
    read -p "按回车继续..."
}

root_check() {

    if [ "$EUID" != 0 ]; then

        error "请使用 root 运行"

        exit 1

    fi

}
