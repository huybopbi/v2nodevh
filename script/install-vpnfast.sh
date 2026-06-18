#!/usr/bin/env bash
set -euo pipefail

green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'
plain='\033[0m'

API_HOST="https://my.vpnfast.org/"
API_KEY="huydzvclhahahaha"
INSTALL_URL="https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install.sh"
MANAGER_URL="https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/v2node-manager.sh"
MANAGER_TARGET="${V2NODE_MANAGER_TARGET:-/usr/bin/v2node-manager}"

VERSION_ARG=""
NODE_ID_ARG="${NODE_ID:-}"
DRY_RUN=false
INSTALL_MANAGER=true
RUN_MANAGER=false
MANAGER_ARGS=()

usage() {
	echo "Cách dùng: $0 [phiên bản] --node-id ID"
	echo "          $0 manager [lệnh manager]"
	echo ""
	echo "Ví dụ:"
	echo "  bash $0 --node-id 1"
	echo "  bash $0 v1.2.3 --node-id 1"
	echo "  bash $0 manager"
	echo "  bash $0 manager add"
	echo ""
	echo "Thông số cài sẵn:"
	echo "  ApiHost: ${API_HOST}"
	echo "  ApiKey:  ${API_KEY}"
	echo ""
	echo "Sau khi cài v2node, script sẽ tự cài kèm command: v2node-manager"
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		manager | --manager)
			RUN_MANAGER=true
			shift
			MANAGER_ARGS=("$@")
			break
			;;
		--node-id)
			NODE_ID_ARG="${2:-}"
			shift 2
			;;
		--no-manager)
			INSTALL_MANAGER=false
			shift
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

local_manager_path() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [[ -f "${script_dir}/v2node-manager.sh" ]]; then
		printf '%s' "${script_dir}/v2node-manager.sh"
	fi
	return 0
}

install_manager() {
	local local_manager
	local_manager="$(local_manager_path)"

	if [[ "${DRY_RUN}" == "true" ]]; then
		if [[ -n "${local_manager}" ]]; then
			printf 'cp %q %q && chmod +x %q\n' "${local_manager}" "${MANAGER_TARGET}" "${MANAGER_TARGET}"
		else
			printf 'curl -Ls %q -o %q && chmod +x %q\n' "${MANAGER_URL}" "${MANAGER_TARGET}" "${MANAGER_TARGET}"
		fi
		return
	fi

	echo -e "${yellow}Đang cài command v2node-manager...${plain}"
	if [[ -n "${local_manager}" ]]; then
		cp "${local_manager}" "${MANAGER_TARGET}"
	else
		curl -Ls "${MANAGER_URL}" -o "${MANAGER_TARGET}"
	fi
	chmod +x "${MANAGER_TARGET}"
	echo -e "${green}Đã cài v2node-manager tại ${MANAGER_TARGET}.${plain}"
}

run_manager() {
	if [[ ! -x "${MANAGER_TARGET}" ]]; then
		install_manager
	fi

	if [[ "${DRY_RUN}" == "true" ]]; then
		printf '%q ' "${MANAGER_TARGET}" "${MANAGER_ARGS[@]}"
		echo
		return
	fi

	exec "${MANAGER_TARGET}" "${MANAGER_ARGS[@]}"
}

main() {
	parse_args "$@"

	if [[ "${RUN_MANAGER}" == "true" ]]; then
		run_manager
		return
	fi

	prompt_node_id
	validate_node_id
	install_script_command

	echo -e "${green}Bắt đầu cài đặt v2node với thông số preset.${plain}"
	echo -e "${yellow}ApiHost:${plain} ${API_HOST}"
	echo -e "${yellow}NodeID:${plain} ${NODE_ID_ARG}"

	if [[ "${DRY_RUN}" == "true" ]]; then
		printf '%q ' "${INSTALL_CMD[@]}"
		echo
		if [[ "${INSTALL_MANAGER}" == "true" ]]; then
			install_manager
		fi
		return
	fi

	"${INSTALL_CMD[@]}"
	if [[ "${INSTALL_MANAGER}" == "true" ]]; then
		install_manager
		echo -e "${green}Bạn có thể chạy menu quản lý bằng lệnh: v2node-manager${plain}"
	fi
}

main "$@"
