// Standalone non-Xray reference peer. Local-only synthetic traffic.
package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
	"io"
	"net"
	"net/netip"
	"os"
	"sync"
	"time"
)

type endpoint struct{ netip.AddrPort }

func (e endpoint) ClearSrc()           {}
func (e endpoint) SrcToString() string { return "" }
func (e endpoint) DstToString() string { return e.String() }
func (e endpoint) DstToBytes() []byte  { b, _ := e.MarshalBinary(); return b }
func (e endpoint) DstIP() netip.Addr   { return e.Addr() }
func (e endpoint) SrcIP() netip.Addr   { return netip.Addr{} }

// Private bind implementing upstream conn.Bind on actual localhost UDP.
// Reject every endpoint except 127.0.0.1; no external route.
type loop struct {
	mu             sync.Mutex
	sock           *net.UDPConn
	sent, received int
}

func (l *loop) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}
	s, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: int(port)})
	if err != nil {
		return nil, 0, err
	}
	l.sock = s
	return []conn.ReceiveFunc{func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		n, a, err := s.ReadFromUDPAddrPort(bufs[0])
		if err != nil {
			return 0, err
		}
		if a.Addr() != netip.MustParseAddr("127.0.0.1") || a.Port() != 39881 {
			return 0, net.ErrClosed
		}
		sizes[0] = n
		eps[0] = endpoint{a}
		l.mu.Lock()
		l.received++
		l.mu.Unlock()
		return 1, nil
	}}, uint16(s.LocalAddr().(*net.UDPAddr).Port), nil
}
func (l *loop) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return nil
	}
	err := l.sock.Close()
	l.sock = nil
	return err
}
func (l *loop) SetMark(mark uint32) error {
	if mark != 0 {
		return fmt.Errorf("not a lab mark")
	}
	return nil
}
func (l *loop) BatchSize() int { return 1 }
func (l *loop) ParseEndpoint(s string) (conn.Endpoint, error) {
	a, err := netip.ParseAddrPort(s)
	if err != nil || a.Addr() != netip.MustParseAddr("127.0.0.1") || a.Port() != 39881 {
		return nil, fmt.Errorf("not loopback")
	}
	return endpoint{a}, nil
}
func (l *loop) Send(bufs [][]byte, ep conn.Endpoint) error {
	e, ok := ep.(endpoint)
	if !ok || e.Addr() != netip.MustParseAddr("127.0.0.1") || e.Port() != 39881 {
		return conn.ErrWrongEndpointType
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return net.ErrClosed
	}
	for _, b := range bufs {
		if _, err := l.sock.WriteToUDPAddrPort(b, e.AddrPort); err != nil {
			return err
		}
		l.sent++
	}
	return nil
}
func (l *loop) port() uint16 {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return 0
	}
	return uint16(l.sock.LocalAddr().(*net.UDPAddr).Port)
}
func (l *loop) stats() (int, int) { l.mu.Lock(); defer l.mu.Unlock(); return l.sent, l.received }

var _ conn.Bind = (*loop)(nil)

type Config struct {
	Private string `json:"private"`
	Peer    string `json:"peer"`
	PSK     string `json:"psk"`
}

func validKey(s string) bool {
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 32 {
		return false
	}
	for _, v := range b {
		if v != 0 {
			return true
		}
	}
	return false
}

func run(path string) int {
	raw, err := os.ReadFile(path)
	var cfg Config
	if err != nil || len(raw) > 4096 || json.Unmarshal(raw, &cfg) != nil ||
		!validKey(cfg.Private) || !validKey(cfg.Peer) || !validKey(cfg.PSK) {
		return 2
	}
	tunnel, stack, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("198.51.100.77")}, nil, 1280)
	if err != nil {
		return 3
	}
	bind := &loop{}
	dev := device.NewDevice(tunnel, bind, device.NewLogger(device.LogLevelSilent, ""))
	defer dev.Close()
	settings := fmt.Sprintf("private_key=%s\nlisten_port=39882\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=10.77.0.2/32\nendpoint=127.0.0.1:39881\n", cfg.Private, cfg.Peer, cfg.PSK)
	if dev.IpcSet(settings) != nil || dev.Up() != nil || bind.port() != 39882 {
		return 4
	}
	listener, err := stack.ListenTCPAddrPort(netip.MustParseAddrPort("198.51.100.77:39883"))
	if err != nil {
		return 5
	}
	var workers sync.WaitGroup
	acceptDone := make(chan struct{})
	go func() {
		defer close(acceptDone)
		for {
			c, err := listener.Accept()
			if err != nil {
				return
			}
			workers.Add(1)
			go func() {
				defer workers.Done()
				defer c.Close()
				_ = c.SetDeadline(time.Now().Add(6 * time.Second))
				witness, err := net.DialTimeout("tcp4", "127.0.0.1:39883", time.Second)
				if err != nil {
					return
				}
				defer witness.Close()
				_ = witness.SetDeadline(time.Now().Add(6 * time.Second))
				done := make(chan struct{})
				go func() { _, _ = io.Copy(witness, c); close(done) }()
				_, _ = io.Copy(c, witness)
				_ = c.Close()
				_ = witness.Close()
				<-done
			}()
		}
	}()
	fmt.Println("PEER_QA_READY_server")
	deadline := time.Now().Add(75 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path + ".stop"); err == nil {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	listener.Close()
	<-acceptDone
	workers.Wait()
	dev.Close()
	if bind.port() != 0 {
		return 6
	}
	fmt.Println("PEER_QA_STOPPED_server")
	return 0
}
func main() {
	if len(os.Args) != 4 || os.Args[1] != "server" || os.Args[3] != "39882" {
		os.Exit(1)
	}
	os.Exit(run(os.Args[2]))
}
