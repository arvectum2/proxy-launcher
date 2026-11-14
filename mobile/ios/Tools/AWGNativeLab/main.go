// Isolated synthetic transport QA. No OS tunnel, routing, owner credentials,
// production link, or non-loopback listener. Upstream engine owns crypto.
package main

import "C"
import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/tuntest"
	"net"
	"net/netip"
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
		if a.Addr() != netip.MustParseAddr("127.0.0.1") {
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
	if err != nil || a.Addr() != netip.MustParseAddr("127.0.0.1") || a.Port() == 0 {
		return nil, fmt.Errorf("not loopback")
	}
	return endpoint{a}, nil
}
func (l *loop) Send(bufs [][]byte, ep conn.Endpoint) error {
	e, ok := ep.(endpoint)
	if !ok || e.Addr() != netip.MustParseAddr("127.0.0.1") {
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

func checksum(b []byte) uint16 {
	var sum uint32
	for i := 0; i < len(b); i += 2 {
		sum += uint32(b[i]) << 8
		if i+1 < len(b) {
			sum += uint32(b[i+1])
		}
	}
	for sum > 65535 {
		sum = (sum & 65535) + (sum >> 16)
	}
	return ^uint16(sum)
}
func packet(src, dst netip.Addr) ([]byte, error) {
	// Unique per-probe ICMP data; exact complete IP frame compared at peer.
	if src.Is6() && dst.Is6() {
		p := make([]byte, 68)
		p[0] = 0x60
		binary.BigEndian.PutUint16(p[4:], uint16(len(p)-40))
		p[6] = 58
		p[7] = 64
		copy(p[8:24], src.AsSlice())
		copy(p[24:40], dst.AsSlice())
		p[40] = 128
		if _, err := rand.Read(p[48:]); err != nil {
			return nil, err
		}
		pseudo := append([]byte{}, p[8:40]...)
		pseudo = append(pseudo, 0, 0, 0, byte(len(p)-40), 0, 0, 0, 58)
		pseudo = append(pseudo, p[40:]...)
		binary.BigEndian.PutUint16(p[42:], checksum(pseudo))
		return p, nil
	}
	if !src.Is4() || !dst.Is4() {
		return nil, fmt.Errorf("mixed address families")
	}
	p := make([]byte, 48)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(len(p)))
	p[8] = 64
	p[9] = 1
	copy(p[12:16], src.AsSlice())
	copy(p[16:20], dst.AsSlice())
	p[20] = 8
	if _, err := rand.Read(p[24:]); err != nil {
		return nil, err
	}
	binary.BigEndian.PutUint16(p[22:], checksum(p[20:]))
	binary.BigEndian.PutUint16(p[10:], checksum(p[:20]))
	return p, nil
}
func exchange(from, to *tuntest.ChannelTUN, src, dst netip.Addr, expect bool) bool {
	p, err := packet(src, dst)
	if err != nil {
		return false
	}
	timer := time.NewTimer(4 * time.Second)
	defer timer.Stop()
	select {
	case from.Outbound <- p:
	case <-timer.C:
		return false
	}
	select {
	case got, open := <-to.Inbound:
		return expect && open && bytes.Equal(p, got)
	case <-timer.C:
		return !expect
	}
}

// One fixed synthetic legacy-format fixture; no tuning or production import.
// Both peers intentionally share this upstream-compatible test fixture.
const fixture = "jc=0\njmin=0\njmax=0\ns1=15\ns2=18\nh1=123456\nh2=67543\nh3=123123\nh4=32345\n"

//export aplAWGSelfTest
func aplAWGSelfTest(mode C.int) C.int {
	if mode < 0 || mode > 2 {
		return 7
	}
	a, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return 1
	}
	b, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return 1
	}
	wrong, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return 1
	}
	psk := make([]byte, 32)
	badPSK := make([]byte, 32)
	if _, err = rand.Read(psk); err != nil {
		return 1
	}
	if _, err = rand.Read(badPSK); err != nil {
		return 1
	}
	keys := []*ecdh.PrivateKey{a, b}
	publics := []string{hex.EncodeToString(b.PublicKey().Bytes()), hex.EncodeToString(a.PublicKey().Bytes())}
	if mode == 1 {
		publics[0] = hex.EncodeToString(wrong.PublicKey().Bytes())
	}
	ips := []netip.Addr{netip.MustParseAddr("192.0.2.1"), netip.MustParseAddr("192.0.2.2")}
	ips6 := []netip.Addr{netip.MustParseAddr("2001:db8::1"), netip.MustParseAddr("2001:db8::2")}
	ts := []*tuntest.ChannelTUN{tuntest.NewChannelTUN(), tuntest.NewChannelTUN()}
	binds := []*loop{{}, {}}
	ds := make([]*device.Device, 2)
	for i := range ds {
		ds[i] = device.NewDevice(ts[i].TUN(), binds[i], device.NewLogger(device.LogLevelSilent, ""))
		defer ds[i].Close()
		secret := psk
		if mode == 2 && i == 0 {
			secret = badPSK
		}
		cfg := fixture + fmt.Sprintf("private_key=%s\nlisten_port=0\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=%s/32\nallowed_ip=%s/128\n", hex.EncodeToString(keys[i].Bytes()), publics[i], hex.EncodeToString(secret), ips[i^1], ips6[i^1])
		if ds[i].IpcSet(cfg) != nil || ds[i].Up() != nil {
			return 2
		}
	}
	for i := range ds {
		port := binds[i^1].port()
		if port == 0 {
			return 3
		}
		cfg := fmt.Sprintf("public_key=%s\nendpoint=127.0.0.1:%d\n", publics[i], port)
		if ds[i].IpcSet(cfg) != nil {
			return 3
		}
	}
	if mode == 0 {
		for _, pair := range [][]netip.Addr{ips, ips6} {
			if !exchange(ts[0], ts[1], pair[0], pair[1], true) || !exchange(ts[1], ts[0], pair[1], pair[0], true) {
				return 4
			}
		}
		for _, l := range binds {
			sent, recv := l.stats()
			if sent < 2 || recv < 2 {
				return 5
			}
		}
	} else {
		if !exchange(ts[0], ts[1], ips[0], ips[1], false) {
			return 4
		}
		sent, _ := binds[0].stats()
		_, recv := binds[1].stats()
		if sent < 1 || recv < 1 {
			return 5
		}
	}
	for _, d := range ds {
		d.Close()
	}
	for _, l := range binds {
		if l.port() != 0 {
			return 6
		}
	}
	return 0
}
func main() {}
