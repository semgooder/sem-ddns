//go:build !windows

package main

import "fmt"

func InstallService() {
	fmt.Println("Windows 服务仅在 Windows 系统上可用")
}

func UninstallService() {
	fmt.Println("Windows 服务仅在 Windows 系统上可用")
}
