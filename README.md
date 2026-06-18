# v2node
Backend V2board dựa trên xray-core đã chỉnh sửa.
Dịch vụ node V2board dựa trên nhân xray đã chỉnh sửa.

**Lưu ý: Dự án này cần chạy cùng [V2board bản chỉnh sửa](https://github.com/wyx2685/v2board)**

## Cài đặt

### Cài đặt một lệnh

```
wget -N https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install.sh && bash install.sh
```

## Các script hỗ trợ

### Script quản lý cơ bản

Sau khi cài đặt, có thể dùng lệnh `v2node` để mở menu quản lý cơ bản:

```bash
v2node
```

Các lệnh thường dùng:

```bash
v2node start
v2node stop
v2node restart
v2node status
v2node log
v2node generate
v2node update
v2node uninstall
```

### Script quản lý nâng cao

`script/v2node-manager.sh` hỗ trợ quản lý node trong `/etc/v2node/config.json`:

- Tự kiểm tra/cài `jq`
- Tự tạo config mặc định nếu chưa có
- Backup config trước khi sửa
- Liệt kê, thêm, xóa, sửa node
- Hỗ trợ NodeID dạng `1`, `1,3,5` hoặc `1-5`
- Xem config, khôi phục backup, kiểm tra trạng thái, restart, install/update v2node

Chạy menu tương tác:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/v2node-manager.sh)
```

Hoặc chạy lệnh trực tiếp:

```bash
bash script/v2node-manager.sh list
bash script/v2node-manager.sh add
bash script/v2node-manager.sh delete
bash script/v2node-manager.sh edit
bash script/v2node-manager.sh status
```

### Script cài đặt preset VPNFast

`script/install-vpnfast.sh` là script cài đặt nhanh với thông số cài sẵn:

- `ApiHost`: `https://my.vpnfast.org/`
- `ApiKey`: `huydzvclhahahaha`

Sau khi cài xong, script sẽ tự cài kèm command `v2node-manager` để dùng các chức năng quản lý nâng cao như thêm/xóa/sửa node, xem config và khôi phục backup.

Khi chạy chỉ cần truyền `NodeID`:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install-vpnfast.sh) --node-id 1
```

Có thể chỉ định phiên bản:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install-vpnfast.sh) v1.2.3 --node-id 1
```

Mở manager sau khi đã cài:

```bash
v2node-manager
```

Hoặc gọi manager thông qua script VPNFast:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install-vpnfast.sh) manager
bash <(curl -Ls https://raw.githubusercontent.com/huybopbi/v2nodevh/main/script/install-vpnfast.sh) manager add
```

## Build
``` bash
GOEXPERIMENT=jsonv2 go build -v -o build_assets/v2node -trimpath -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=$version' -s -w -buildid="
```

## Lịch sử tăng sao

[![Stargazers over time](https://starchart.cc/wyx2685/v2node.svg?variant=adaptive)](https://starchart.cc/wyx2685/v2node)
