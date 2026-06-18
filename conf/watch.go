package conf

import (
	"fmt"
	"log"
	"time"

	"github.com/fsnotify/fsnotify"
)

func (p *Conf) Watch(filePath string, reload func()) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return fmt.Errorf("lỗi tạo watcher: %s", err)
	}
	go func() {
		var pre time.Time
		defer watcher.Close()
		for {
			select {
			case e := <-watcher.Events:
				if e.Has(fsnotify.Chmod) {
					continue
				}
				if pre.Add(10 * time.Second).After(time.Now()) {
					continue
				}
				pre = time.Now()
				go func() {
					time.Sleep(5 * time.Second)
					log.Println("File cấu hình đã thay đổi, đang tải lại...")
					*p = *New()
					err := p.LoadFromPath(filePath)
					if err != nil {
						log.Printf("Lỗi tải lại cấu hình: %s", err)
					}
					reload()
					log.Println("Tải lại cấu hình thành công")
				}()
			case err := <-watcher.Errors:
				if err != nil {
					log.Printf("Lỗi watcher file: %s", err)
				}
			}
		}
	}()
	err = watcher.Add(filePath)
	if err != nil {
		return fmt.Errorf("lỗi theo dõi file: %s", err)
	}
	return nil
}
