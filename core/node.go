package core

import (
	"fmt"

	panel "github.com/wyx2685/v2node/api/v2board"
)

func (v *V2Core) AddNode(tag string, info *panel.NodeInfo) error {
	inBoundConfig, err := buildInbound(info, tag)
	if err != nil {
		return fmt.Errorf("lỗi build inbound: %s", err)
	}
	err = v.addInbound(inBoundConfig)
	if err != nil {
		return fmt.Errorf("lỗi thêm inbound: %s", err)
	}
	return nil
}

func (v *V2Core) DelNode(tag string) error {
	err := v.removeInbound(tag)
	if err != nil {
		return fmt.Errorf("lỗi xóa inbound: %s", err)
	}
	return nil
}
