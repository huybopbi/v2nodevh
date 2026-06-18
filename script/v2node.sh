#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi:${plain} Bạn phải chạy script này bằng người dùng root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}Không phát hiện được phiên bản hệ điều hành, vui lòng liên hệ tác giả script!${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Phát hiện kiến trúc thất bại, dùng kiến trúc mặc định: ${arch}${plain}"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "Phần mềm này không hỗ trợ hệ thống 32-bit (x86). Vui lòng dùng hệ thống 64-bit (x86_64); nếu phát hiện sai, hãy liên hệ tác giả"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng dùng CentOS 7 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Lưu ý: CentOS 7 không thể dùng giao thức hysteria1/2!${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng dùng Ubuntu 16 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng dùng Debian 8 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [mặc định $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Có khởi động lại v2node không" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để quay lại menu chính: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/wyx2685/v2node/master/script/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "Nhập phiên bản chỉ định (mặc định là mới nhất): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/wyx2685/v2node/master/script/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}Cập nhật hoàn tất, v2node đã tự khởi động lại. Vui lòng dùng v2node log để xem log vận hành${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "v2node sẽ tự thử khởi động lại sau khi sửa cấu hình"
    nano /etc/v2node/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "Trạng thái v2node: ${green}đang chạy${plain}"
            ;;
        1)
            echo -e "Phát hiện v2node chưa chạy hoặc tự khởi động lại thất bại, bạn có muốn xem log không? [Y/n]" && echo
            read -e -rp "(mặc định: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "Trạng thái v2node: ${red}chưa cài đặt${plain}"
    esac
}

uninstall() {
    confirm "Bạn chắc chắn muốn gỡ cài đặt v2node chứ?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node stop
        rc-update del v2node
        rm /etc/init.d/v2node -f
    else
        systemctl stop v2node
        systemctl disable v2node
        rm /etc/systemd/system/v2node.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/v2node/ -rf
    rm /usr/local/v2node/ -rf

    echo ""
    echo -e "Gỡ cài đặt thành công. Nếu muốn xóa script này, hãy thoát script rồi chạy ${green}rm /usr/bin/v2node -f${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}v2node đang chạy, không cần khởi động lại; nếu cần, vui lòng chọn khởi động lại${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node start
        else
            systemctl start v2node
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node khởi động thành công, vui lòng dùng v2node log để xem log vận hành${plain}"
        else
            echo -e "${red}v2node có thể khởi động thất bại, vui lòng dùng v2node log để xem log sau${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node stop
    else
        systemctl stop v2node
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}v2node đã dừng thành công${plain}"
    else
        echo -e "${red}Dừng v2node thất bại, có thể do thời gian dừng vượt quá hai giây. Vui lòng xem log sau${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node restart
    else
        systemctl restart v2node
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}v2node khởi động lại thành công, vui lòng dùng v2node log để xem log vận hành${plain}"
    else
        echo -e "${red}v2node có thể khởi động thất bại, vui lòng dùng v2node log để xem log sau${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node status
    else
        systemctl status v2node --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add v2node
    else
        systemctl enable v2node
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Đã bật tự khởi động v2node thành công${plain}"
    else
        echo -e "${red}Bật tự khởi động v2node thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del v2node
    else
        systemctl disable v2node
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Đã tắt tự khởi động v2node thành công${plain}"
    else
        echo -e "${red}Tắt tự khởi động v2node thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}Hệ thống Alpine tạm thời chưa hỗ trợ xem log${plain}\n" && exit 1
    else
        journalctl -u v2node.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/v2node -N --no-check-certificate https://raw.githubusercontent.com/wyx2685/v2node/master/script/v2node.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}Tải script thất bại, vui lòng kiểm tra máy có thể kết nối GitHub không${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2node
        echo -e "${green}Nâng cấp script thành công, vui lòng chạy lại script${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2node status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status v2node | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep v2node)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled v2node)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}v2node đã được cài đặt, vui lòng không cài lại${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}Vui lòng cài đặt v2node trước${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Trạng thái v2node: ${green}đang chạy${plain}"
            show_enable_status
            ;;
        1)
            echo -e "Trạng thái v2node: ${yellow}chưa chạy${plain}"
            show_enable_status
            ;;
        2)
            echo -e "Trạng thái v2node: ${red}chưa cài đặt${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Tự khởi động khi boot: ${green}có${plain}"
    else
        echo -e "Tự khởi động khi boot: ${red}không${plain}"
    fi
}

show_v2node_version() {
    echo -n "Phiên bản v2node: "
    /usr/local/v2node/v2node version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

generate_v2node_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"

        mkdir -p /etc/v2node >/dev/null 2>&1
        cat > /etc/v2node/config.json <<EOF
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${node_id},
            "ApiKey": "${api_key}",
            "Timeout": 15
        }
    ]
}
EOF
        echo -e "${green}Đã tạo xong file cấu hình V2node, đang khởi động lại dịch vụ${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node restart
        else
            systemctl restart v2node
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node khởi động lại thành công${plain}"
        else
            echo -e "${red}v2node có thể khởi động thất bại, vui lòng dùng v2node log để xem log${plain}"
        fi
}


generate_config_file() {
    # Thu thập tham số tương tác, cung cấp giá trị mặc định ví dụ
    read -rp "Địa chỉ API panel [định dạng: https://example.com/]: " api_host
    api_host=${api_host:-https://example.com/}
    read -rp "ID node: " node_id
    node_id=${node_id:-1}
    read -rp "Khóa giao tiếp node: " api_key

    # Tạo file cấu hình (ghi đè template có thể đã được copy từ gói)
    generate_v2node_config "$api_host" "$node_id" "$api_key"
}

# Mở cổng tường lửa
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}Mở cổng tường lửa thành công!${plain}"
}

show_usage() {
    echo "Cách dùng script quản lý v2node: "
    echo "------------------------------------------"
    echo "v2node              - Hiển thị menu quản lý (nhiều chức năng hơn)"
    echo "v2node start        - Khởi động v2node"
    echo "v2node stop         - Dừng v2node"
    echo "v2node restart      - Khởi động lại v2node"
    echo "v2node status       - Xem trạng thái v2node"
    echo "v2node enable       - Bật tự khởi động v2node"
    echo "v2node disable      - Tắt tự khởi động v2node"
    echo "v2node log          - Xem log v2node"
    echo "v2node x25519       - Tạo khóa x25519"
    echo "v2node generate     - Tạo file cấu hình v2node"
    echo "v2node update       - Cập nhật v2node"
    echo "v2node update x.x.x - Cài đặt v2node phiên bản chỉ định"
    echo "v2node install      - Cài đặt v2node"
    echo "v2node uninstall    - Gỡ cài đặt v2node"
    echo "v2node version      - Xem phiên bản v2node"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}Script quản lý backend v2node,${plain} ${red}không áp dụng cho Docker${plain}
--- https://github.com/wyx2685/v2node ---
  ${green}0.${plain} Sửa cấu hình
————————————————
  ${green}1.${plain} Cài đặt v2node
  ${green}2.${plain} Cập nhật v2node
  ${green}3.${plain} Gỡ cài đặt v2node
————————————————
  ${green}4.${plain} Khởi động v2node
  ${green}5.${plain} Dừng v2node
  ${green}6.${plain} Khởi động lại v2node
  ${green}7.${plain} Xem trạng thái v2node
  ${green}8.${plain} Xem log v2node
————————————————
  ${green}9.${plain} Bật tự khởi động v2node
  ${green}10.${plain} Tắt tự khởi động v2node
————————————————
  ${green}11.${plain} Xem phiên bản v2node
  ${green}12.${plain} Nâng cấp script bảo trì v2node
  ${green}13.${plain} Tạo file cấu hình v2node
  ${green}14.${plain} Mở tất cả cổng mạng của VPS
  ${green}15.${plain} Thoát script
 "
 # Có thể thêm các cập nhật sau vào chuỗi ở trên
    show_status
    echo && read -rp "Vui lòng nhập lựa chọn [0-15]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) check_install && show_v2node_version ;;
        12) update_shell ;;
        13) generate_config_file ;;
        14) open_ports ;;
        15) exit ;;
        *) echo -e "${red}Vui lòng nhập số hợp lệ [0-15]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "version") check_install 0 && show_v2node_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi