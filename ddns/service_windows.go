//go:build windows

package main

import (
	"log"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

type ddnsService struct{}

func (s *ddnsService) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (bool, uint32) {
	changes <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}

	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	RunUpdate()

	for {
		select {
		case <-ticker.C:
			RunUpdate()
		case c := <-r:
			switch c.Cmd {
			case svc.Interrogate:
				changes <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending}
				return false, 0
			}
		}
	}
}

func RunService(name string) {
	if err := svc.Run(name, &ddnsService{}); err != nil {
		log.Fatalf("服务运行失败: %v", err)
	}
}

func InstallService() {
	exe, err := os.Executable()
	if err != nil {
		log.Fatalf("获取程序路径失败: %v", err)
	}
	exe, _ = filepath.Abs(exe)

	m, err := mgr.Connect()
	if err != nil {
		log.Fatalf("连接服务管理器失败: %v", err)
	}
	defer m.Disconnect()

	s, err := m.CreateService("CloudflareDDNS", exe, mgr.Config{
		DisplayName: "Cloudflare DDNS",
		Description: "自动更新 Cloudflare DNS 记录的动态域名解析服务",
		StartType:   mgr.StartAutomatic,
	}, "service")
	if err != nil {
		log.Fatalf("创建服务失败: %v", err)
	}
	defer s.Close()

	if err := s.Start(); err != nil {
		log.Printf("启动服务失败: %v", err)
	}

	log.Println("服务 CloudflareDDNS 已安装并启动")
}

func UninstallService() {
	m, err := mgr.Connect()
	if err != nil {
		log.Fatalf("连接服务管理器失败: %v", err)
	}
	defer m.Disconnect()

	s, err := m.OpenService("CloudflareDDNS")
	if err != nil {
		log.Fatalf("打开服务失败: %v", err)
	}
	defer s.Close()

	s.Control(svc.Stop)
	if err := s.Delete(); err != nil {
		log.Fatalf("删除服务失败: %v", err)
	}

	log.Println("服务 CloudflareDDNS 已卸载")
}
