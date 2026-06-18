#!/usr/bin/env bash
set -euo pipefail

green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'
plain='\033[0m'

API_HOST="https://my.vpnfast.org/"
API_KEY="huydzvclhahahaha"
INSTALL_URL="https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install.sh"

VERSION_ARG=""
NODE_ID_ARG="${NODE_ID:-}"
DRY_RUN=false

usage() {
	echo "Cách dùng: $0 [phiên bản] --node-id ID"
	echo ""
	echo "Ví dụ:"
	echo "  bash $0 --node-id 1"
	echo "  bash $0 v1.2.3 --node-id 1"
	echo ""
	echo "Thông số cài sẵn:"
	echo "  ApiHost: ${API_HOST}"
	echo "  ApiKey:  ${API_KEY}"
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--node-id)
			NODE_ID_ARG="${2:-}"
			shift 2
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		--*)
			echo -e "${red}Tham số không xác định: $1${plain}" >&2
			exit 1
			;;
		*)
			if [[ -z "${VERSION_ARG}" ]]; then
				VERSION_ARG="$1"
			fi
			shift
			;;
		esac
	done
}

prompt_node_id() {
	if [[ -n "${NODE_ID_ARG}" ]]; then
		return
	fi

	read -r -p "Nhập NodeID cần cài đặt: " NODE_ID_ARG
}

validate_node_id() {
	if [[ -z "${NODE_ID_ARG}" ]]; then
		echo -e "${red}NodeID không được để trống.${plain}" >&2
		exit 1
	fi

	if ! [[ "${NODE_ID_ARG}" =~ ^[0-9]+$ ]]; then
		echo -e "${red}NodeID phải là số nguyên.${plain}" >&2
		exit 1
	fi
}

install_script_command() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

	if [[ -f "${script_dir}/install.sh" ]]; then
		INSTALL_CMD=(bash "${script_dir}/install.sh")
	else
		INSTALL_CMD=(bash -c "bash <(curl -Ls '${INSTALL_URL}') \"\$@\"" bash)
	fi

	if [[ -n "${VERSION_ARG}" ]]; then
		INSTALL_CMD+=("${VERSION_ARG}")
	fi
	INSTALL_CMD+=(--api-host "${API_HOST}" --node-id "${NODE_ID_ARG}" --api-key "${API_KEY}")
}

main() {
	parse_args "$@"
	prompt_node_id
	validate_node_id
	install_script_command

	echo -e "${green}Bắt đầu cài đặt v2node với thông số preset.${plain}"
	echo -e "${yellow}ApiHost:${plain} ${API_HOST}"
	echo -e "${yellow}NodeID:${plain} ${NODE_ID_ARG}"

	if [[ "${DRY_RUN}" == "true" ]]; then
		printf '%q ' "${INSTALL_CMD[@]}"
		echo
		return
	fi

	"${INSTALL_CMD[@]}"
}

main "$@"
