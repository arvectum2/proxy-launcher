// Fixed synthetic lab endpoints only. Never a production or roaming bind.
package main

import (
	"fmt"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"net"
	"net/netip"
	"sync"
)

const awgLabClientPort = 39890
const awgLabServerPort = 39891

var awgLabServerIP = netip.MustParseAddr("192.168.1.80")
var awgLabLAN = netip.MustParsePrefix("192.168.1.0/24")

type scopedEndpoint struct{ netip.AddrPort }

func (e scopedEndpoint) ClearSrc()           {}
func (e scopedEndpoint) SrcToString() string { return "" }
func (e scopedEndpoint) DstToString() string { return e.String() }
func (e scopedEndpoint) DstToBytes() []byte  { b, _ := e.MarshalBinary(); return b }
func (e scopedEndpoint) DstIP() netip.Addr   { return e.Addr() }
func (e scopedEndpoint) SrcIP() netip.Addr   { return netip.Addr{} }

type scopedBind struct {
	mu                       sync.Mutex
	sock                     *net.UDPConn
	local, remote            netip.AddrPort
	sent, received, rejected uint64
}

func validLabClient(ip netip.Addr) bool {
	return ip.Is4() && awgLabLAN.Contains(ip) && ip != awgLabLAN.Addr() && ip != netip.MustParseAddr("192.168.1.255")
}
func newScopedBind(server bool, client netip.Addr) (*scopedBind, error) {
	if !validLabClient(client) {
		return nil, fmt.Errorf("invalid synthetic client address")
	}
	c := netip.AddrPortFrom(client, awgLabClientPort)
	s := netip.AddrPortFrom(awgLabServerIP, awgLabServerPort)
	if server {
		return &scopedBind{local: s, remote: c}, nil
	}
	return &scopedBind{local: c, remote: s}, nil
}
func (b *scopedBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}
	if port != b.local.Port() {
		return nil, 0, fmt.Errorf("invalid lab port")
	}
	s, e := net.ListenUDP("udp4", net.UDPAddrFromAddrPort(b.local))
	if e != nil {
		return nil, 0, e
	}
	b.sock = s
	return []conn.ReceiveFunc{func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		for {
			n, a, e := s.ReadFromUDPAddrPort(bufs[0])
			if e != nil {
				return 0, e
			}
			b.mu.Lock()
			if a != b.remote {
				b.rejected++
				b.mu.Unlock()
				continue
			}
			b.received++
			b.mu.Unlock()
			sizes[0] = n
			eps[0] = scopedEndpoint{a}
			return 1, nil
		}
	}}, port, nil
}
func (b *scopedBind) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock == nil {
		return nil
	}
	e := b.sock.Close()
	b.sock = nil
	return e
}
func (b *scopedBind) SetMark(mark uint32) error {
	if mark != 0 {
		return fmt.Errorf("invalid mark")
	}
	return nil
}
func (b *scopedBind) BatchSize() int { return 1 }
func (b *scopedBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	a, e := netip.ParseAddrPort(s)
	if e != nil || a != b.remote {
		return nil, fmt.Errorf("invalid fixed peer")
	}
	return scopedEndpoint{a}, nil
}
func (b *scopedBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	a, ok := ep.(scopedEndpoint)
	if !ok || a.AddrPort != b.remote {
		return conn.ErrWrongEndpointType
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock == nil {
		return net.ErrClosed
	}
	for _, p := range bufs {
		if _, e := b.sock.WriteToUDPAddrPort(p, b.remote); e != nil {
			return e
		}
		b.sent++
	}
	return nil
}
func (b *scopedBind) stats() (uint64, uint64, uint64) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.sent, b.received, b.rejected
}

var _ conn.Bind = (*scopedBind)(nil)
