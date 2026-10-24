// singfox-service runs the sing-box core as a Windows service so SingFox can
// use TUN without running elevated.
//
//	singfox-service install --user-sid <SID> --core <sing-box.exe>   (elevated)
//	singfox-service uninstall                                        (elevated)
//	singfox-service run                                              (by the SCM)
//
// The service listens on 127.0.0.1:47391. Every request needs the token in
// %ProgramData%\SingFox\service.token, which only the installing user,
// Administrators and SYSTEM can read. It only ever runs the core copy in its
// own install directory, which only Administrators can write.
package main

import (
	"fmt"
	"os"
)

const (
	serviceName = "SingFoxService"
	displayName = "SingFox Service"
	listenAddr  = "127.0.0.1:47391"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: singfox-service install|uninstall|run")
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "install":
		err = install(os.Args[2:])
	case "uninstall":
		err = uninstall()
	case "run":
		err = runService()
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
