# v2node
Backend V2board dựa trên xray-core đã chỉnh sửa.
Dịch vụ node V2board dựa trên nhân xray đã chỉnh sửa.

**Lưu ý: Dự án này cần chạy cùng [V2board bản chỉnh sửa](https://github.com/wyx2685/v2board)**

## Cài đặt

### Cài đặt một lệnh

```
wget -N https://raw.githubusercontent.com/wyx2685/v2node/master/script/install.sh && bash install.sh
```

## Build
``` bash
GOEXPERIMENT=jsonv2 go build -v -o build_assets/v2node -trimpath -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=$version' -s -w -buildid="
```

## Lịch sử tăng sao

[![Stargazers over time](https://starchart.cc/wyx2685/v2node.svg?variant=adaptive)](https://starchart.cc/wyx2685/v2node)
