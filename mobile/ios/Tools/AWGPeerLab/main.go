// Standalone application witness: exact synthetic TCP/UDP exchanges, no proxy,
// Internet forwarding, kernel routes, plaintext logs or owner credentials.
package main

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
	"io"
	"net"
	"net/netip"
	"os"
	"sync/atomic"
	"time"
)

const legacyFixture = "jc=0\njmin=0\njmax=0\ns1=15\ns2=18\nh1=123456\nh2=67543\nh3=123123\nh4=32345\n"
const witnessPort = 39892

var clientAddresses = []netip.Addr{netip.MustParseAddr("192.0.2.1"), netip.MustParseAddr("2001:db8::1")}
var serverAddresses = []netip.Addr{netip.MustParseAddr("192.0.2.2"), netip.MustParseAddr("2001:db8::2")}

type config struct{ Private, Peer, PSK, Nonce, ClientIP string }

func key(s string) bool {
	p, e := hex.DecodeString(s)
	if e != nil || len(p) != 32 {
		return false
	}
	defer clear(p)
	var z byte
	for _, v := range p {
		z |= v
	}
	return z != 0
}
func readConfig(path string) (config, bool) {
	var c config
	f, e := os.Open(path)
	if e != nil {
		return c, false
	}
	defer f.Close()
	raw, e := io.ReadAll(io.LimitReader(f, 4097))
	defer clear(raw)
	if e != nil || len(raw) > 4096 {
		return c, false
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(&c) != nil || d.Decode(new(any)) != io.EOF {
		return c, false
	}
	n, e := hex.DecodeString(c.Nonce)
	ip, iperr := netip.ParseAddr(c.ClientIP)
	return c, e == nil && len(n) == 24 && iperr == nil && validLabClient(ip) && key(c.Private) && key(c.Peer) && key(c.PSK)
}
func initPeer(c config, server bool) (*device.Device, *netstack.Net, *scopedBind, error) {
	ip, _ := netip.ParseAddr(c.ClientIP)
	b, e := newScopedBind(server, ip)
	if e != nil {
		return nil, nil, nil, e
	}
	local, remote := clientAddresses, serverAddresses
	if server {
		local, remote = remote, local
	}
	tun, stack, e := netstack.CreateNetTUN(local, nil, 1280)
	if e != nil {
		return nil, nil, nil, e
	}
	d := device.NewDevice(tun, b, device.NewLogger(device.LogLevelSilent, ""))
	cfg := legacyFixture + fmt.Sprintf("private_key=%s\nlisten_port=%d\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=%s/32\nallowed_ip=%s/128\nendpoint=%s\n", c.Private, b.local.Port(), c.Peer, c.PSK, remote[0], remote[1], b.remote)
	if d.IpcSet(cfg) != nil || d.Up() != nil {
		d.Close()
		return nil, nil, nil, fmt.Errorf("native peer start failed")
	}
	return d, stack, b, nil
}
func response(n string) []byte { return []byte("APL:" + n) }
func serve(c config, stack *netstack.Net, b *scopedBind, path string) int {
	var count [4]atomic.Uint64
	var closers []io.Closer
	defer func() {
		for _, l := range closers {
			l.Close()
		}
	}()
	for i, addr := range serverAddresses {
		a := netip.AddrPortFrom(addr, witnessPort)
		l, e := stack.ListenTCPAddrPort(a)
		if e != nil {
			return 3
		}
		closers = append(closers, l)
		go func(idx int, l net.Listener) {
			for {
				p, e := l.Accept()
				if e != nil {
					return
				}
				p.SetDeadline(time.Now().Add(2 * time.Second))
				buf := make([]byte, 48)
				_, e = io.ReadFull(p, buf)
				if e == nil && string(buf) == c.Nonce {
					if n, e := p.Write(response(c.Nonce)); e == nil && n == 52 {
						count[idx].Add(1)
					}
				}
				p.Close()
			}
		}(i, l)
		u, e := stack.ListenUDPAddrPort(a)
		if e != nil {
			return 4
		}
		closers = append(closers, u)
		go func(idx int, u net.PacketConn) {
			buf := make([]byte, 128)
			for {
				n, from, e := u.ReadFrom(buf)
				if e != nil {
					return
				}
				if n == 48 && string(buf[:n]) == c.Nonce {
					if n, e := u.WriteTo(response(c.Nonce), from); e == nil && n == 52 {
						count[idx].Add(1)
					}
				}
			}
		}(i+2, u)
	}
	fmt.Println("AWG_PEER_READY")
	until := time.Now().Add(45 * time.Second)
	for time.Now().Before(until) {
		if _, e := os.Stat(path + ".stop"); e == nil {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	for _, l := range closers {
		l.Close()
	}
	sent, recv, rejected := b.stats()
	fmt.Printf("AWG_WITNESS tcp4=%d tcp6=%d udp4=%d udp6=%d sent=%d received=%d rejected=%d\n", count[0].Load(), count[1].Load(), count[2].Load(), count[3].Load(), sent, recv, rejected)
	return 0
}
func request(c config, stack *netstack.Net, kind string) bool {
	i := 0
	if kind == "tcp6" || kind == "udp6" {
		i = 1
	}
	target := netip.AddrPortFrom(serverAddresses[i], witnessPort)
	var p net.Conn
	var e error
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if kind == "tcp4" || kind == "tcp6" {
		p, e = stack.DialContextTCPAddrPort(ctx, target)
	} else {
		p, e = stack.DialUDPAddrPort(netip.AddrPortFrom(clientAddresses[i], 0), target)
	}
	if e != nil {
		return false
	}
	defer p.Close()
	p.SetDeadline(time.Now().Add(3 * time.Second))
	n, e := p.Write([]byte(c.Nonce))
	if e != nil || n != 48 {
		return false
	}
	buf := make([]byte, 53)
	if kind == "tcp4" || kind == "tcp6" {
		n, e = io.ReadFull(p, buf[:52])
	} else {
		n, e = p.Read(buf)
	}
	return e == nil && n == 52 && bytes.Equal(buf[:n], response(c.Nonce))
}
func run() int {
	if len(os.Args) != 3 {
		return 1
	}
	mode, path := os.Args[1], os.Args[2]
	if mode != "server" && mode != "positive" && mode != "negative" {
		return 1
	}
	c, ok := readConfig(path)
	if !ok {
		return 2
	}
	d, stack, b, e := initPeer(c, mode == "server")
	if e != nil {
		return 3
	}
	defer d.Close()
	if mode == "server" {
		return serve(c, stack, b, path)
	}
	kinds := []string{"tcp4", "tcp6", "udp4", "udp6"}
	if mode == "negative" {
		kinds = []string{"tcp4", "udp4"}
	}
	for _, k := range kinds {
		got := request(c, stack, k)
		fmt.Printf("AWG_CLIENT %s receipt=%t\n", k, got)
		if got != (mode == "positive") {
			return 5
		}
	}
	sent, recv, _ := b.stats()
	fmt.Printf("AWG_CLIENT_TRANSPORT sent=%d received=%d\n", sent, recv)
	if sent == 0 || (mode == "positive" && recv == 0) {
		return 6
	}
	return 0
}
func main() { os.Exit(run()) }
