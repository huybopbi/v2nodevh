package core

import (
	"encoding/json"
	"strconv"
)

type panelFallback struct {
	Alpn string          `json:"alpn,omitempty"`
	Path string          `json:"path,omitempty"`
	Dest json.RawMessage `json:"dest,omitempty"`
	Xver json.RawMessage `json:"xver,omitempty"`
}

func extractPanelFallbacksToBytes(raw json.RawMessage) []byte {
	if len(raw) == 0 {
		return nil
	}
	var panelFBs []panelFallback
	if err := json.Unmarshal(raw, &panelFBs); err != nil {
		return nil
	}

	var parsedFBs []map[string]interface{}
	for _, fb := range panelFBs {
		m := make(map[string]interface{})
		if fb.Alpn != "" {
			m["alpn"] = fb.Alpn
		}
		if fb.Path != "" {
			m["path"] = fb.Path
		}
		
		dest := ""
		if len(fb.Dest) > 0 {
			var dstr string
			if err := json.Unmarshal(fb.Dest, &dstr); err == nil {
				dest = dstr
			} else {
				var dint int
				if err := json.Unmarshal(fb.Dest, &dint); err == nil {
					dest = strconv.Itoa(dint)
				}
			}
		}
		if dest != "" {
			m["dest"] = dest
		}

		xver := uint64(0)
		if len(fb.Xver) > 0 {
			var xv interface{}
			json.Unmarshal(fb.Xver, &xv)
			switch v := xv.(type) {
			case float64:
				xver = uint64(v)
			case string:
				xverInt, _ := strconv.ParseUint(v, 10, 64)
				xver = xverInt
			}
		}
		if xver > 0 {
			m["xver"] = xver
		}

		parsedFBs = append(parsedFBs, m)
	}
	out, _ := json.Marshal(parsedFBs)
	return out
}
