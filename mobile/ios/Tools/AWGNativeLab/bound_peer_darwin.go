// Isolated, inactive fixed-peer bind. Loopback only until real OS underlay
// and route policy are independently accepted. No roaming or fallback.
package main

import (
	"context"
	"errors"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"golang.org/x/sys/unix"
	"net"
	"net/netip"
	"sync"
	"syscall"
	"time"
)

type boundPeer struct {
	mu            sync.Mutex
	local, remote netip.AddrPort
	iface         string
	sock          *net.UDPConn
}

func newBoundPeer(local, remote netip.AddrPort, iface string) (*boundPeer, error) {
	if !local.Addr().IsLoopback() || !remote.Addr().IsLoopback() || local.Addr().Is4() != remote.Addr().Is4() || local.Addr().Is4In6() || remote.Addr().Is4In6() || remote.Port() == 0 || iface != "lo0" || local == remote {
		return nil, errors.New("not a fixed local fixture")
	}
	return &boundPeer{local: local, remote: remote, iface: iface}, nil
}
func (b *boundPeer) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}
	if b.local.Port() != 0 && port != b.local.Port() {
		return nil, 0, errors.New("wrong local port")
	}
	iface, e := net.InterfaceByName(b.iface)
	if e != nil || iface.Index <= 0 || iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback == 0 {
		return nil, 0, errors.New("interface unavailable")
	}
	addrs, e := iface.Addrs()
	if e != nil {
		return nil, 0, e
	}
	found := false
	for _, a := range addrs {
		p, e := netip.ParsePrefix(a.String())
		if e == nil && p.Addr() == b.local.Addr() {
			found = true
		}
	}
	if !found {
		return nil, 0, errors.New("source is not on interface")
	}
	network := "udp4"
	level, opt := unix.IPPROTO_IP, unix.IP_BOUND_IF
	if b.local.Addr().Is6() {
		network = "udp6"
		level, opt = unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF
	}
	d := net.Dialer{LocalAddr: net.UDPAddrFromAddrPort(netip.AddrPortFrom(b.local.Addr(), port)), Timeout: time.Second, Control: func(_, _ string, c syscall.RawConn) error {
		var inner error
		e := c.Control(func(fd uintptr) {
			inner = unix.SetsockoptInt(int(fd), level, opt, iface.Index)
			if inner == nil {
				var got int
				got, inner = unix.GetsockoptInt(int(fd), level, opt)
				if inner == nil && got != iface.Index {
					inner = errors.New("kernel binding mismatch")
				}
			}
		})
		if e != nil {
			return e
		}
		return inner
	}}
	c, e := d.DialContext(context.Background(), network, b.remote.String())
	if e != nil {
		return nil, 0, e
	}
	s, ok := c.(*net.UDPConn)
	if !ok {
		c.Close()
		return nil, 0, errors.New("not UDP")
	}
	actual := s.LocalAddr().(*net.UDPAddr).AddrPort()
	if actual.Addr() != b.local.Addr() || (port != 0 && actual.Port() != port) || s.RemoteAddr().(*net.UDPAddr).AddrPort() != b.remote {
		s.Close()
		return nil, 0, errors.New("socket identity mismatch")
	}
	b.sock = s
	receive := func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		n, e := s.Read(bufs[0])
		if e != nil {
			return 0, e
		}
		sizes[0] = n
		eps[0] = scopedEndpoint{b.remote}
		return 1, nil
	}
	return []conn.ReceiveFunc{receive}, actual.Port(), nil
}
func (b *boundPeer) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock == nil {
		return nil
	}
	e := b.sock.Close()
	b.sock = nil
	return e
}
func (b *boundPeer) SetMark(mark uint32) error {
	if mark != 0 {
		return errors.New("unsupported mark")
	}
	return nil
}
func (b *boundPeer) BatchSize() int { return 1 }
func (b *boundPeer) ParseEndpoint(raw string) (conn.Endpoint, error) {
	a, e := netip.ParseAddrPort(raw)
	if e != nil || a != b.remote {
		return nil, errors.New("wrong fixed peer")
	}
	return scopedEndpoint{a}, nil
}
func (b *boundPeer) Send(bufs [][]byte, ep conn.Endpoint) error {
	e, ok := ep.(scopedEndpoint)
	if !ok || e.AddrPort != b.remote {
		return conn.ErrWrongEndpointType
	}
	b.mu.Lock()
	s := b.sock
	b.mu.Unlock()
	if s == nil {
		return net.ErrClosed
	}
	if err := s.SetWriteDeadline(time.Now().Add(time.Second)); err != nil {
		return err
	}
	for _, p := range bufs {
		n, e := s.Write(p)
		if e != nil {
			return e
		}
		if n != len(p) {
			return errors.New("short UDP send")
		}
	}
	return nil
}

var _ conn.Bind = (*boundPeer)(nil)
