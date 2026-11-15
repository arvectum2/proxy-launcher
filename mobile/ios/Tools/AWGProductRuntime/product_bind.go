// Exact connected UDP peer, no forced interface or bypass routes.
package main

import (
	"errors"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"net"
	"net/netip"
	"sync"
	"time"
)

type productBind struct {
	mu                             sync.Mutex
	remote                         netip.AddrPort
	sock                           *net.UDPConn
	enabled, attemptedBeforeEnable bool
}

var _ conn.Bind = (*productBind)(nil)

func validProductEndpoint(a netip.AddrPort) bool {
	ip := a.Addr()
	return a.Port() != 0 && ip.Zone() == "" && !ip.Is4In6() && ip.IsGlobalUnicast()
}
func (b *productBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.enabled {
		b.attemptedBeforeEnable = true
		return nil, 0, errors.New("socket admission disabled")
	}
	if b.sock != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}
	network := "udp4"
	local := net.IPv4zero
	if b.remote.Addr().Is6() {
		network = "udp6"
		local = net.IPv6zero
	}
	dialer := net.Dialer{Timeout: time.Second, LocalAddr: &net.UDPAddr{IP: local, Port: int(port)}}
	c, err := dialer.Dial(network, b.remote.String())
	if err != nil {
		return nil, 0, err
	}
	s, ok := c.(*net.UDPConn)
	if !ok {
		c.Close()
		return nil, 0, errors.New("invalid udp socket")
	}
	actual := s.LocalAddr().(*net.UDPAddr).AddrPort()
	remote := s.RemoteAddr().(*net.UDPAddr).AddrPort()
	if !actual.Addr().IsValid() || actual.Addr().IsUnspecified() || actual.Port() == 0 || (port != 0 && actual.Port() != port) || netip.AddrPortFrom(remote.Addr().Unmap(), remote.Port()) != b.remote {
		s.Close()
		return nil, 0, errors.New("socket identity mismatch")
	}
	b.sock = s
	return []conn.ReceiveFunc{func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		if len(bufs) == 0 || len(sizes) == 0 || len(eps) == 0 {
			return 0, errors.New("invalid receive batch")
		}
		n, e := s.Read(bufs[0])
		if e != nil {
			return 0, e
		}
		sizes[0] = n
		eps[0] = scopedEndpoint{b.remote}
		return 1, nil
	}}, actual.Port(), nil
}
func (b *productBind) permitStart() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.enabled || b.attemptedBeforeEnable || b.sock != nil {
		return false
	}
	b.enabled = true
	return true
}
func (b *productBind) preparedWithoutSockets() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return !b.enabled && !b.attemptedBeforeEnable && b.sock == nil
}
func (b *productBind) revoke() { b.mu.Lock(); b.enabled = false; b.mu.Unlock() }
func (b *productBind) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sock == nil {
		return nil
	}
	s := b.sock
	b.sock = nil
	return s.Close()
}
func (b *productBind) SetMark(mark uint32) error {
	if mark != 0 {
		return errors.New("mark unsupported")
	}
	return nil
}
func (b *productBind) BatchSize() int { return 1 }
func (b *productBind) ParseEndpoint(raw string) (conn.Endpoint, error) {
	a, e := netip.ParseAddrPort(raw)
	if e != nil || a != b.remote {
		return nil, errors.New("unexpected peer")
	}
	return scopedEndpoint{a}, nil
}
func (b *productBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	e, ok := ep.(scopedEndpoint)
	if !ok || e.AddrPort != b.remote {
		return conn.ErrWrongEndpointType
	}
	b.mu.Lock()
	s := b.sock
	if !b.enabled {
		s = nil
	}
	b.mu.Unlock()
	if s == nil {
		return net.ErrClosed
	}
	if err := s.SetWriteDeadline(time.Now().Add(time.Second)); err != nil {
		return err
	}
	for _, p := range bufs {
		n, err := s.Write(p)
		if err != nil {
			return err
		}
		if n != len(p) {
			return errors.New("short send")
		}
	}
	return nil
}
