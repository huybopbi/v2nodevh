package cmd

import (
	log "github.com/sirupsen/logrus"

	"github.com/spf13/cobra"
)

var command = &cobra.Command{
	Use: "v2node",
}

func Run() {
	err := command.Execute()
	if err != nil {
		log.WithField("err", err).Error("Thực thi lệnh thất bại")
	}
}
