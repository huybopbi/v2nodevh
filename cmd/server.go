package cmd

import (
	"fmt"
	"net/http"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/wyx2685/v2node/conf"
	"github.com/wyx2685/v2node/core"
	"github.com/wyx2685/v2node/limiter"
	"github.com/wyx2685/v2node/node"
)

var (
	config string
	watch  bool
)

var serverCommand = cobra.Command{
	Use:   "server",
	Short: "Chạy server v2node",
	Run:   serverHandle,
	Args:  cobra.NoArgs,
}

func init() {
	serverCommand.PersistentFlags().
		StringVarP(&config, "config", "c",
			"/etc/v2node/config.json", "đường dẫn file cấu hình")
	serverCommand.PersistentFlags().
		BoolVarP(&watch, "watch", "w",
			true, "theo dõi thay đổi file cấu hình")
	command.AddCommand(&serverCommand)
}

func serverHandle(_ *cobra.Command, _ []string) {
	showVersion()
	c := conf.New()
	err := c.LoadFromPath(config)
	log.SetFormatter(&log.TextFormatter{
		DisableTimestamp: true,
		DisableQuote:     true,
		PadLevelText:     false,
	})
	if err != nil {
		log.WithField("err", err).Error("Tải file cấu hình thất bại")
		return
	}
	switch c.LogConfig.Level {
	case "debug":
		log.SetLevel(log.DebugLevel)
	case "info":
		log.SetLevel(log.InfoLevel)
	case "warn", "warning":
		log.SetLevel(log.WarnLevel)
	case "error":
		log.SetLevel(log.ErrorLevel)
	}
	if c.LogConfig.Output != "" {
		f, err := os.OpenFile(c.LogConfig.Output, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.WithField("err", err).Error("Mở file log thất bại, chuyển sang dùng stdout")
		}
		log.SetOutput(f)
	}
	// Enable pprof if configured
	if c.PprofPort != 0 {
		go func() {
			log.Infof("Đang khởi động server pprof trên :%d", c.PprofPort)
			if err := http.ListenAndServe(fmt.Sprintf("127.0.0.1:%d", c.PprofPort), nil); err != nil {
				log.WithField("err", err).Error("Server pprof thất bại")
			}
		}()
	}
	//init limiter
	limiter.Init()
	//get node info
	nodes, err := node.New(c.NodeConfigs)
	if err != nil {
		log.WithField("err", err).Error("Lấy thông tin node thất bại")
		return
	}
	log.Info("Đã lấy thông tin node từ server")
	//core
	var reloadCh = make(chan struct{}, 1)
	v2core := core.New(c)
	v2core.ReloadCh = reloadCh
	err = v2core.Start(nodes.NodeInfos)
	if err != nil {
		log.WithField("err", err).Error("Khởi động core thất bại")
		return
	}
	defer v2core.Close()
	//node
	err = nodes.Start(c.NodeConfigs, v2core)
	if err != nil {
		log.WithField("err", err).Error("Chạy node thất bại")
		return
	}
	log.Info("Các node đã khởi động")
	if watch {
		// On file change, just signal reload; do not run reload concurrently here
		err = c.Watch(config, func() {
			select {
			case reloadCh <- struct{}{}:
			default: // drop if a reload is already queued
			}
		})
		if err != nil {
			log.WithField("err", err).Error("Bắt đầu theo dõi file thất bại")
			return
		}
	}
	// clear memory
	runtime.GC()

	osSignals := make(chan os.Signal, 1)
	signal.Notify(osSignals, syscall.SIGINT, syscall.SIGTERM)

	for {
		select {
		case <-osSignals:
			log.Info("Đã nhận tín hiệu thoát, đang tắt chương trình...")
			os.Exit(0)
		case <-reloadCh:
			log.Info("Đã nhận tín hiệu khởi động lại, đang tải lại cấu hình...")
			if err := reload(config, &nodes, &v2core); err != nil {
				log.WithField("err", err).Panic("Khởi động lại thất bại")
			}
			log.Info("Khởi động lại thành công")
		}
	}
}

func reload(config string, nodes **node.Node, v2core **core.V2Core) error {
	// Preserve old reload channel so new core continues to receive signals
	var oldReloadCh chan struct{}
	if *v2core != nil {
		oldReloadCh = (*v2core).ReloadCh
	}

	if err := (*nodes).Close(); err != nil {
		return err
	}

	if err := (*v2core).Close(); err != nil {
		return err
	}

	newConf := conf.New()
	if err := newConf.LoadFromPath(config); err != nil {
		return err
	}

	switch newConf.LogConfig.Level {
	case "debug":
		log.SetLevel(log.DebugLevel)
	case "info":
		log.SetLevel(log.InfoLevel)
	case "warn", "warning":
		log.SetLevel(log.WarnLevel)
	case "error":
		log.SetLevel(log.ErrorLevel)
	}
	if newConf.LogConfig.Output != "" {
		f, err := os.OpenFile(newConf.LogConfig.Output, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.WithField("err", err).Error("Mở file log thất bại, chuyển sang dùng stdout")
		} else {
			// Đóng file log cũ nếu output hiện tại là file.
			if oldWriter, ok := log.StandardLogger().Out.(*os.File); ok && oldWriter != os.Stdout && oldWriter != os.Stderr {
				oldWriter.Close()
			}
			log.SetOutput(f)
		}
	}

	newNodes, err := node.New(newConf.NodeConfigs)
	if err != nil {
		return err
	}

	newCore := core.New(newConf)
	// Reattach reload channel
	newCore.ReloadCh = oldReloadCh
	if err := newCore.Start(newNodes.NodeInfos); err != nil {
		return err
	}

	if err := newNodes.Start(newConf.NodeConfigs, newCore); err != nil {
		return err
	}

	*nodes = newNodes
	*v2core = newCore

	runtime.GC()
	return nil
}
