// Localhost-only independent reference client, not an application backend.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
	"io"
	"net"
	"net/netip"
	"os"
	"time"
)

func runClient(path string, positive bool) int {
	raw, e := os.ReadFile(path)
	var c Config
	if e != nil || len(raw) > 4096 || json.Unmarshal(raw, &c) != nil || !validNonce(c.Nonce) || !validKey(c.Private) || !validKey(c.Peer) || !validKey(c.PSK) || !c.Dual {
		return 2
	}
	t, stack, e := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.77.0.2"), netip.MustParseAddr("2001:db8:77::2")}, nil, 1280)
	if e != nil {
		return 3
	}
	b := &loop{remotePort: 39882}
	d := device.NewDevice(t, b, device.NewLogger(device.LogLevelSilent, ""))
	defer d.Close()
	cfg := fmt.Sprintf("private_key=%s\nlisten_port=39881\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=198.51.100.77/32\nallowed_ip=2001:db8:77::77/128\nendpoint=127.0.0.1:39882\n", c.Private, c.Peer, c.PSK)
	if d.IpcSet(cfg) != nil || d.Up() != nil {
		return 4
	}
	kinds := []string{"tcp4", "tcp6", "udp4", "udp6"}
	if !positive {
		kinds = []string{"tcp4", "udp4"}
	}
	for _, k := range kinds {
		target := "198.51.100.77:39883"
		if k[3] == '6' {
			target = "[2001:db8:77::77]:39883"
		}
		var conn net.Conn
		var err error
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		conn, err = stack.DialContext(ctx, k, target)
		cancel()
		ok := false
		if err == nil {
			_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
			req := "APL_UDP:" + c.Nonce
			if k[:3] == "tcp" {
				req = "GET /" + c.Nonce + " HTTP/1.1\r\nHost: witness.invalid\r\nConnection: close\r\n\r\n"
			}
			if _, err = io.WriteString(conn, req); err == nil {
				if k[:3] == "tcp" {
					raw, err := io.ReadAll(io.LimitReader(conn, 512))
					ok = err == nil && string(raw) == fmt.Sprintf("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s", len("APL_RECEIPT:"+c.Nonce), "APL_RECEIPT:"+c.Nonce)
				} else {
					buf := make([]byte, 128)
					n, err := conn.Read(buf)
					ok = err == nil && string(buf[:n]) == "APL_RECEIPT:"+c.Nonce
				}
			}
			conn.Close()
		}
		fmt.Printf("WG_CLIENT %s receipt=%t\n", k, ok)
		if ok != positive {
			return 5
		}
	}
	return 0
}
