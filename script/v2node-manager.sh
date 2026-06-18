#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${V2NODE_CONFIG_FILE:-/etc/v2node/config.json}"
BACKUP_DIR="${V2NODE_BACKUP_DIR:-/etc/v2node/backups}"
V2NODE_BIN="${V2NODE_BIN:-/usr/local/v2node/v2node}"
INSTALL_URL="${V2NODE_INSTALL_URL:-https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install.sh}"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
GRAY='\033[90m'
BOLD='\033[1m'
RESET='\033[0m'

check_root() {
	if [[ ${EUID} -ne 0 ]]; then
		echo -e "${RED}Lỗi: Script này cần quyền root để chạy!${RESET}"
		echo -e "${YELLOW}Vui lòng chạy với: sudo $0${RESET}"
		exit 1
	fi
}

install_jq() {
	echo -e "${YELLOW}jq chưa được cài đặt, đang tự động cài đặt...${RESET}"
	if command -v apt-get >/dev/null 2>&1; then
		apt-get update -qq >/dev/null 2>&1
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq >/dev/null 2>&1
	elif command -v yum >/dev/null 2>&1; then
		yum install -y -q jq >/dev/null 2>&1
	elif command -v apk >/dev/null 2>&1; then
		apk add --no-cache jq >/dev/null 2>&1
	elif command -v pacman >/dev/null 2>&1; then
		pacman -Sy --noconfirm --needed jq >/dev/null 2>&1
	else
		echo -e "${RED}Không thể tự động cài đặt jq.${RESET}"
		echo -e "${YELLOW}Vui lòng cài jq thủ công rồi chạy lại script.${RESET}"
		exit 1
	fi

	if ! command -v jq >/dev/null 2>&1; then
		echo -e "${RED}Cài đặt jq thất bại.${RESET}"
		exit 1
	fi
	echo -e "${GREEN}Đã cài đặt jq thành công.${RESET}"
}

check_jq() {
	if ! command -v jq >/dev/null 2>&1; then
		install_jq
	fi
}

check_v2node() {
	[[ -x "${V2NODE_BIN}" ]]
}

ensure_config() {
	if [[ -f "${CONFIG_FILE}" ]]; then
		return
	fi

	echo -e "${YELLOW}Không tìm thấy file cấu hình: ${CONFIG_FILE}${RESET}"
	echo -e "${YELLOW}Đang tạo file cấu hình mặc định...${RESET}"
	mkdir -p "$(dirname "${CONFIG_FILE}")"
	jq -n '{
		Log: {
			Level: "warning",
			Output: "",
			Access: "none"
		},
		Nodes: []
	}' >"${CONFIG_FILE}"
	chmod 644 "${CONFIG_FILE}"
	echo -e "${GREEN}Đã tạo file cấu hình mặc định.${RESET}"
}

validate_config() {
	if ! jq -e '.Nodes and (.Nodes | type == "array")' "${CONFIG_FILE}" >/dev/null; then
		echo -e "${RED}File cấu hình không hợp lệ: cần có trường Nodes dạng mảng.${RESET}"
		return 1
	fi
}

backup_config() {
	if [[ ! -f "${CONFIG_FILE}" ]]; then
		return
	fi

	mkdir -p "${BACKUP_DIR}"
	local backup_file="${BACKUP_DIR}/config_$(date +%Y%m%d_%H%M%S).json"
	cp "${CONFIG_FILE}" "${backup_file}"
	chmod 600 "${backup_file}"
	echo -e "${GRAY}Đã backup config: $(basename "${backup_file}")${RESET}"

	# Giữ tối đa 10 bản backup mới nhất.
	mapfile -t old_backups < <(ls -t "${BACKUP_DIR}"/config_*.json 2>/dev/null | tail -n +11 || true)
	if [[ ${#old_backups[@]} -gt 0 ]]; then
		rm -f "${old_backups[@]}"
	fi
}

restart_v2node() {
	echo -e "${YELLOW}Đang khởi động lại v2node...${RESET}"
	if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^v2node\.service'; then
		if systemctl restart v2node >/dev/null 2>&1; then
			echo -e "${GREEN}Dịch vụ v2node đã khởi động lại.${RESET}"
			return 0
		fi
	fi

	if command -v service >/dev/null 2>&1; then
		if service v2node restart >/dev/null 2>&1; then
			echo -e "${GREEN}Dịch vụ v2node đã khởi động lại.${RESET}"
			return 0
		fi
	fi

	echo -e "${YELLOW}Không thể tự động khởi động lại v2node.${RESET}"
	echo -e "${GRAY}Bạn có thể thử: systemctl restart v2node hoặc service v2node restart${RESET}"
	return 1
}

start_v2node() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl start v2node 2>/dev/null && return 0
	fi
	command -v service >/dev/null 2>&1 && service v2node start
}

stop_v2node() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl stop v2node 2>/dev/null && return 0
	fi
	command -v service >/dev/null 2>&1 && service v2node stop
}

pause() {
	echo ""
	read -r -p "Nhấn Enter để tiếp tục..."
}

node_count() {
	jq '.Nodes | length' "${CONFIG_FILE}"
}

list_nodes() {
	ensure_config
	validate_config

	local count
	count=$(node_count)
	echo -e "${BOLD}${CYAN}Danh sách node hiện tại:${RESET}"
	echo ""

	if [[ "${count}" -eq 0 ]]; then
		echo -e "${YELLOW}Chưa có node nào.${RESET}"
		return
	fi

	echo -e "${GRAY}Tổng ${count} node${RESET}"
	echo ""
	jq -r '.Nodes | to_entries[] |
		"Node #\(.key + 1)\n" +
		"  NodeID: \(.value.NodeID)\n" +
		"  ApiHost: \(.value.ApiHost)\n" +
		"  ApiKey: \(.value.ApiKey)\n" +
		"  Timeout: \(.value.Timeout // 15)\n"' "${CONFIG_FILE}"
}

parse_range_list() {
	local input="$1"
	local result=()
	local part start end i

	IFS=',' read -ra parts <<<"${input}"
	for part in "${parts[@]}"; do
		part="${part//[[:space:]]/}"
		[[ -z "${part}" ]] && continue

		if [[ "${part}" =~ ^[0-9]+$ ]]; then
			result+=("${part}")
		elif [[ "${part}" =~ ^[0-9]+-[0-9]+$ ]]; then
			start="${part%-*}"
			end="${part#*-}"
			if ((start > end)); then
				echo -e "${RED}Lỗi phạm vi: ${part}${RESET}" >&2
				return 1
			fi
			for ((i = start; i <= end; i++)); do
				result+=("${i}")
			done
		else
			echo -e "${RED}Định dạng không hợp lệ: ${part}${RESET}" >&2
			return 1
		fi
	done

	if [[ ${#result[@]} -eq 0 ]]; then
		echo -e "${RED}Không có giá trị hợp lệ.${RESET}" >&2
		return 1
	fi

	printf '%s\n' "${result[@]}"
}

prompt_required() {
	local prompt="$1"
	local value
	read -r -p "${prompt}" value
	if [[ -z "${value}" ]]; then
		echo -e "${RED}Giá trị không được để trống.${RESET}" >&2
		return 1
	fi
	printf '%s' "${value}"
}

prompt_timeout() {
	local default_value="$1"
	local value
	read -r -p "Timeout (mặc định: ${default_value}): " value
	value="${value:-${default_value}}"
	if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
		echo -e "${RED}Timeout phải là số nguyên.${RESET}" >&2
		return 1
	fi
	printf '%s' "${value}"
}

choose_existing_node_config() {
	local count="$1"
	local selected_index array_index

	echo -e "${BOLD}Chọn node để dùng lại ApiHost/ApiKey:${RESET}" >&2
	jq -r '.Nodes | to_entries[] |
		"\(.key + 1)\t\(.value.NodeID)\t\(.value.ApiHost)\t\(.value.Timeout // 15)"' "${CONFIG_FILE}" |
		while IFS=$'\t' read -r idx node_id api_host timeout; do
			echo -e " ${YELLOW}${idx})${RESET} NodeID: ${node_id}, ApiHost: ${api_host}, Timeout: ${timeout}" >&2
		done

	echo "" >&2
	read -r -p "Nhập số thứ tự node (1-${count}): " selected_index
	if ! [[ "${selected_index}" =~ ^[0-9]+$ ]] || ((selected_index < 1 || selected_index > count)); then
		echo -e "${RED}Số thứ tự node không hợp lệ.${RESET}" >&2
		return 1
	fi

	array_index=$((selected_index - 1))
	jq -r ".Nodes[${array_index}] | [.ApiHost, .ApiKey, (.Timeout // 15)] | @tsv" "${CONFIG_FILE}"
}

add_node() {
	ensure_config
	validate_config
	backup_config

	local count api_host api_key timeout use_existing nodeid_input nodeids existing nodes_to_add
	count=$(node_count)

	echo -e "${BOLD}${CYAN}Thêm node mới${RESET}"
	echo ""

	if [[ "${count}" -gt 0 ]]; then
		echo -e "${BOLD}Bạn có muốn dùng lại ApiHost và ApiKey từ node hiện có không?${RESET}"
		echo -e " ${YELLOW}1)${RESET} Có"
		echo -e " ${YELLOW}2)${RESET} Không, nhập thủ công"
		read -r -p "Lựa chọn (mặc định: 2): " use_existing
	else
		use_existing="2"
	fi

	if [[ "${use_existing}" == "1" ]]; then
		IFS=$'\t' read -r api_host api_key timeout < <(choose_existing_node_config "${count}")
	else
		api_host=$(prompt_required "API Host: ") || return
		api_key=$(prompt_required "API Key: ") || return
		timeout=$(prompt_timeout "15") || return
	fi

	echo ""
	read -r -p "NodeID (ví dụ 95, hoặc phạm vi 1-5, hoặc 1,3,5): " nodeid_input
	mapfile -t nodeids < <(parse_range_list "${nodeid_input}") || return

	mapfile -t existing < <(jq -r '.Nodes[].NodeID' "${CONFIG_FILE}")
	nodes_to_add=()
	local nodeid exists
	for nodeid in "${nodeids[@]}"; do
		exists=false
		local current
		for current in "${existing[@]}"; do
			if [[ "${nodeid}" == "${current}" ]]; then
				exists=true
				break
			fi
		done
		if [[ "${exists}" == "true" ]]; then
			echo -e "${YELLOW}NodeID ${nodeid} đã tồn tại, bỏ qua.${RESET}"
		else
			nodes_to_add+=("${nodeid}")
		fi
	done

	if [[ ${#nodes_to_add[@]} -eq 0 ]]; then
		echo -e "${RED}Không có node mới để thêm.${RESET}"
		return
	fi

	local tmp
	tmp=$(mktemp)
	cp "${CONFIG_FILE}" "${tmp}"
	for nodeid in "${nodes_to_add[@]}"; do
		jq \
			--arg api_host "${api_host}" \
			--arg api_key "${api_key}" \
			--argjson node_id "${nodeid}" \
			--argjson timeout "${timeout}" \
			'.Nodes += [{
				ApiHost: $api_host,
				NodeID: $node_id,
				ApiKey: $api_key,
				Timeout: $timeout
			}]' "${tmp}" >"${tmp}.new"
		mv "${tmp}.new" "${tmp}"
	done
	mv "${tmp}" "${CONFIG_FILE}"
	chmod 644 "${CONFIG_FILE}"

	echo -e "${GREEN}Đã thêm ${#nodes_to_add[@]} node.${RESET}"
	echo -e "${GRAY}NodeID: ${nodes_to_add[*]}${RESET}"
	restart_v2node || true
}

resolve_node_indices() {
	local input="$1"
	local count number idx found
	local -a values nodeids indices
	local -A seen=()

	count=$(node_count)
	mapfile -t values < <(parse_range_list "${input}") || return
	mapfile -t nodeids < <(jq -r '.Nodes[].NodeID' "${CONFIG_FILE}")

	for number in "${values[@]}"; do
		found=false
		if ((number >= 1 && number <= count)); then
			idx=$((number - 1))
			if [[ -z "${seen[${idx}]:-}" ]]; then
				seen["${idx}"]=1
				indices+=("${idx}")
			fi
			continue
		fi

		for idx in "${!nodeids[@]}"; do
			if [[ "${nodeids[${idx}]}" == "${number}" ]]; then
				found=true
				if [[ -z "${seen[${idx}]:-}" ]]; then
					seen["${idx}"]=1
					indices+=("${idx}")
				fi
				break
			fi
		done

		if [[ "${found}" == "false" ]]; then
			echo -e "${YELLOW}Không tìm thấy số thứ tự hoặc NodeID ${number}, bỏ qua.${RESET}" >&2
		fi
	done

	if [[ ${#indices[@]} -eq 0 ]]; then
		echo -e "${RED}Không tìm thấy node cần xử lý.${RESET}" >&2
		return 1
	fi

	printf '%s\n' "${indices[@]}" | sort -rn
}

delete_node() {
	ensure_config
	validate_config

	local count input indices tmp idx
	count=$(node_count)
	if [[ "${count}" -eq 0 ]]; then
		echo -e "${YELLOW}Không có node nào để xóa.${RESET}"
		return
	fi

	list_nodes
	echo ""
	read -r -p "Nhập số thứ tự hoặc NodeID cần xóa (hỗ trợ 1,3,5 hoặc 1-5): " input
	[[ -z "${input}" ]] && echo -e "${YELLOW}Đã hủy thao tác.${RESET}" && return
	mapfile -t indices < <(resolve_node_indices "${input}") || return

	echo -e "${YELLOW}Sẽ xóa ${#indices[@]} node. Tiếp tục? [y/N]: ${RESET}\c"
	read -r confirm
	if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
		echo -e "${YELLOW}Đã hủy thao tác.${RESET}"
		return
	fi

	backup_config
	tmp=$(mktemp)
	cp "${CONFIG_FILE}" "${tmp}"
	for idx in "${indices[@]}"; do
		jq "del(.Nodes[${idx}])" "${tmp}" >"${tmp}.new"
		mv "${tmp}.new" "${tmp}"
	done
	mv "${tmp}" "${CONFIG_FILE}"
	chmod 644 "${CONFIG_FILE}"

	echo -e "${GREEN}Đã xóa ${#indices[@]} node.${RESET}"
	restart_v2node || true
}

edit_node() {
	ensure_config
	validate_config

	local count node_index array_index current_node current_nodeid current_api_host current_api_key current_timeout
	local new_nodeid new_api_host new_api_key new_timeout conflict tmp

	count=$(node_count)
	if [[ "${count}" -eq 0 ]]; then
		echo -e "${YELLOW}Không có node nào để sửa.${RESET}"
		return
	fi

	list_nodes
	echo ""
	read -r -p "Nhập số thứ tự node cần sửa (1-${count}): " node_index
	if ! [[ "${node_index}" =~ ^[0-9]+$ ]] || ((node_index < 1 || node_index > count)); then
		echo -e "${RED}Số thứ tự node không hợp lệ.${RESET}"
		return
	fi

	array_index=$((node_index - 1))
	current_node=$(jq ".Nodes[${array_index}]" "${CONFIG_FILE}")
	current_nodeid=$(jq -r '.NodeID' <<<"${current_node}")
	current_api_host=$(jq -r '.ApiHost' <<<"${current_node}")
	current_api_key=$(jq -r '.ApiKey' <<<"${current_node}")
	current_timeout=$(jq -r '.Timeout // 15' <<<"${current_node}")

	echo ""
	echo -e "${GRAY}Cấu hình hiện tại:${RESET}"
	echo "  NodeID: ${current_nodeid}"
	echo "  ApiHost: ${current_api_host}"
	echo "  ApiKey: ${current_api_key}"
	echo "  Timeout: ${current_timeout}"
	echo ""

	read -r -p "NodeID (mặc định: ${current_nodeid}): " new_nodeid
	new_nodeid="${new_nodeid:-${current_nodeid}}"
	read -r -p "API Host (mặc định: ${current_api_host}): " new_api_host
	new_api_host="${new_api_host:-${current_api_host}}"
	read -r -p "API Key (mặc định: ${current_api_key}): " new_api_key
	new_api_key="${new_api_key:-${current_api_key}}"
	read -r -p "Timeout (mặc định: ${current_timeout}): " new_timeout
	new_timeout="${new_timeout:-${current_timeout}}"

	if ! [[ "${new_nodeid}" =~ ^[0-9]+$ ]] || ! [[ "${new_timeout}" =~ ^[0-9]+$ ]]; then
		echo -e "${RED}NodeID và Timeout phải là số nguyên.${RESET}"
		return
	fi

	conflict=$(jq --argjson node_id "${new_nodeid}" --argjson idx "${array_index}" \
		'any(.Nodes | to_entries[]; .key != $idx and .value.NodeID == $node_id)' "${CONFIG_FILE}")
	if [[ "${conflict}" == "true" ]]; then
		echo -e "${RED}NodeID ${new_nodeid} đã được node khác sử dụng.${RESET}"
		return
	fi

	backup_config
	tmp=$(mktemp)
	jq \
		--argjson idx "${array_index}" \
		--argjson node_id "${new_nodeid}" \
		--arg api_host "${new_api_host}" \
		--arg api_key "${new_api_key}" \
		--argjson timeout "${new_timeout}" \
		'.Nodes[$idx] = {
			ApiHost: $api_host,
			NodeID: $node_id,
			ApiKey: $api_key,
			Timeout: $timeout
		}' "${CONFIG_FILE}" >"${tmp}"
	mv "${tmp}" "${CONFIG_FILE}"
	chmod 644 "${CONFIG_FILE}"

	echo -e "${GREEN}Node đã được cập nhật.${RESET}"
	restart_v2node || true
}

show_config() {
	ensure_config
	validate_config
	echo -e "${BOLD}${CYAN}Nội dung file cấu hình:${RESET}"
	echo ""
	jq . "${CONFIG_FILE}"
}

restore_backup() {
	if [[ ! -d "${BACKUP_DIR}" ]]; then
		echo -e "${YELLOW}Không tìm thấy thư mục backup.${RESET}"
		return
	fi

	local backups=()
	mapfile -t backups < <(ls -t "${BACKUP_DIR}"/config_*.json 2>/dev/null || true)
	if [[ ${#backups[@]} -eq 0 ]]; then
		echo -e "${YELLOW}Không có file backup nào.${RESET}"
		return
	fi

	echo -e "${BOLD}${CYAN}Danh sách backup:${RESET}"
	local i backup size stamp
	for i in "${!backups[@]}"; do
		backup="${backups[${i}]}"
		size=$(du -h "${backup}" 2>/dev/null | cut -f1)
		stamp=$(basename "${backup}" | sed 's/config_\(.*\)\.json/\1/' | sed 's/_/ /')
		echo -e " ${YELLOW}$((i + 1)))${RESET} ${stamp} ${GRAY}(${size})${RESET}"
	done

	echo ""
	read -r -p "Chọn backup để khôi phục (1-${#backups[@]}) hoặc 0 để hủy: " choice
	if [[ "${choice}" == "0" || -z "${choice}" ]]; then
		echo -e "${YELLOW}Đã hủy khôi phục.${RESET}"
		return
	fi
	if ! [[ "${choice}" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#backups[@]})); then
		echo -e "${RED}Lựa chọn không hợp lệ.${RESET}"
		return
	fi

	if [[ -f "${CONFIG_FILE}" ]]; then
		cp "${CONFIG_FILE}" "${CONFIG_FILE}.before_restore"
	fi
	cp "${backups[$((choice - 1))]}" "${CONFIG_FILE}"
	chmod 644 "${CONFIG_FILE}"
	echo -e "${GREEN}Khôi phục cấu hình thành công.${RESET}"
	restart_v2node || true
}

install_v2node() {
	echo -e "${BOLD}${CYAN}Cài đặt/Cài lại v2node${RESET}"
	echo ""

	if check_v2node; then
		echo -e "${YELLOW}v2node đã được cài đặt tại: ${V2NODE_BIN}${RESET}"
		read -r -p "Bạn có muốn cài đặt lại không? [y/N]: " confirm
		if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
			echo -e "${YELLOW}Đã hủy cài đặt.${RESET}"
			return
		fi
	fi

	bash <(curl -Ls "${INSTALL_URL}")
}

update_v2node() {
	echo -e "${BOLD}${CYAN}Cập nhật v2node${RESET}"
	echo ""
	echo -e "${GRAY}Phiên bản hiện tại:${RESET}"
	"${V2NODE_BIN}" version 2>/dev/null || echo "Không xác định được"
	echo ""
	bash <(curl -Ls "${INSTALL_URL}")
	echo ""
	echo -e "${GREEN}Cập nhật hoàn tất.${RESET}"
}

show_status() {
	echo -e "${BOLD}${CYAN}Trạng thái v2node${RESET}"
	echo ""

	if check_v2node; then
		echo -e "${GREEN}v2node đã cài đặt.${RESET}"
		echo -e "${GRAY}Binary: ${V2NODE_BIN}${RESET}"
	else
		echo -e "${RED}v2node chưa được cài đặt.${RESET}"
	fi

	if command -v systemctl >/dev/null 2>&1; then
		if systemctl is-active --quiet v2node; then
			echo -e "${GREEN}Dịch vụ đang chạy.${RESET}"
		else
			echo -e "${YELLOW}Dịch vụ chưa chạy.${RESET}"
		fi

		if systemctl is-enabled --quiet v2node 2>/dev/null; then
			echo -e "${GREEN}Tự khởi động: bật.${RESET}"
		else
			echo -e "${GRAY}Tự khởi động: tắt.${RESET}"
		fi
	fi

	echo ""
	echo -e "${GRAY}Phiên bản:${RESET}"
	"${V2NODE_BIN}" version 2>/dev/null || echo "Không xác định được"
}

show_menu() {
	while true; do
		clear
		echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
		echo -e "${BOLD}${CYAN} v2node Manager Pro${RESET}"
		echo -e "${GRAY} Config: ${CONFIG_FILE}${RESET}"
		echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
		if check_v2node; then
			echo -e "${GREEN}● v2node: đã cài${RESET}"
		else
			echo -e "${RED}○ v2node: chưa cài${RESET}"
		fi
		echo ""
		echo -e "${BOLD}Quản lý cài đặt${RESET}"
		echo -e " ${YELLOW}i${RESET}) Cài đặt/Cài lại v2node"
		echo -e " ${YELLOW}u${RESET}) Cập nhật v2node"
		echo -e " ${YELLOW}s${RESET}) Xem trạng thái v2node"
		echo -e " ${YELLOW}r${RESET}) Khởi động lại v2node"
		echo ""
		echo -e "${BOLD}Quản lý node${RESET}"
		echo -e " ${YELLOW}1${RESET}) Liệt kê node"
		echo -e " ${YELLOW}2${RESET}) Thêm node (hỗ trợ 1-5, 1,3,5)"
		echo -e " ${YELLOW}3${RESET}) Xóa node (hỗ trợ số thứ tự hoặc NodeID)"
		echo -e " ${YELLOW}4${RESET}) Sửa node"
		echo ""
		echo -e "${BOLD}Tiện ích${RESET}"
		echo -e " ${YELLOW}5${RESET}) Xem nội dung config"
		echo -e " ${YELLOW}b${RESET}) Khôi phục config từ backup"
		echo -e " ${YELLOW}0${RESET}) Thoát"
		echo ""
		read -r -p "Lựa chọn ➜ " choice

		case "${choice}" in
		i | I) install_v2node && pause ;;
		u | U) update_v2node && pause ;;
		s | S) show_status && pause ;;
		r | R) restart_v2node || true; pause ;;
		1) list_nodes && pause ;;
		2) add_node && pause ;;
		3) delete_node && pause ;;
		4) edit_node && pause ;;
		5) show_config && pause ;;
		b | B) restore_backup && pause ;;
		0)
			echo -e "${GREEN}Tạm biệt!${RESET}"
			return
			;;
		*)
			echo -e "${RED}Lựa chọn không hợp lệ.${RESET}"
			sleep 1
			;;
		esac
	done
}

usage() {
	echo "Cách dùng: $0 [command]"
	echo ""
	echo "Commands:"
	echo "  menu      Mở menu tương tác (mặc định)"
	echo "  list      Liệt kê node"
	echo "  add       Thêm node"
	echo "  delete    Xóa node"
	echo "  edit      Sửa node"
	echo "  config    Xem config"
	echo "  restore   Khôi phục config từ backup"
	echo "  status    Xem trạng thái v2node"
	echo "  restart   Khởi động lại v2node"
	echo "  install   Cài đặt/Cài lại v2node"
	echo "  update    Cập nhật v2node"
}

main() {
	check_root
	check_jq
	ensure_config
	validate_config

	case "${1:-menu}" in
	menu) show_menu ;;
	list) list_nodes ;;
	add) add_node ;;
	delete | del | remove) delete_node ;;
	edit) edit_node ;;
	config | show-config) show_config ;;
	restore | backup) restore_backup ;;
	status) show_status ;;
	restart) restart_v2node ;;
	install) install_v2node ;;
	update) update_v2node ;;
	-h | --help | help) usage ;;
	*)
		usage
		return 1
		;;
	esac
}

main "$@"
