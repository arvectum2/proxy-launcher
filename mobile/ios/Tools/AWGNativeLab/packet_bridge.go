// Isolated packetFlow-shaped queue. No OS routes, production credentials,
// arbitrary endpoints or shared Xray runtime. Fixed synthetic loopback only.
package main

import (
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"math"
	"net/netip"
	"os"
	"sync"
)

const bridgeMTU = 1280
const bridgeDepth = 32
const bridgeFailure = -1
const bridgeFull = -2

type packetBridgeTUN struct {
	send, receive chan []byte
	done          chan struct{}
	events        chan tun.Event
	mu            sync.Mutex
	closed        bool
}

var _ tun.Device = (*packetBridgeTUN)(nil)

func newPacketBridgeTUN() *packetBridgeTUN {
	t := &packetBridgeTUN{send: make(chan []byte, bridgeDepth), receive: make(chan []byte, bridgeDepth), done: make(chan struct{}), events: make(chan tun.Event, 1)}
	// Explicit device.Up controls lifecycle; no implicit asynchronous start.
	return t
}
func validBridgePacket(p []byte) bool {
	if len(p) < 20 || len(p) > bridgeMTU {
		return false
	}
	switch p[0] >> 4 {
	case 4:
		h := int(p[0]&15) * 4
		return h >= 20 && h <= len(p) && int(binary.BigEndian.Uint16(p[2:4])) == len(p)
	case 6:
		return len(p) >= 40 && int(binary.BigEndian.Uint16(p[4:6]))+40 == len(p)
	default:
		return false
	}
}
func (t *packetBridgeTUN) File() *os.File           { return nil }
func (t *packetBridgeTUN) MTU() (int, error)        { return bridgeMTU, nil }
func (t *packetBridgeTUN) Name() (string, error)    { return "apl-awg-packet-bridge", nil }
func (t *packetBridgeTUN) Events() <-chan tun.Event { return t.events }
func (t *packetBridgeTUN) BatchSize() int           { return 1 }
func (t *packetBridgeTUN) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if !t.closed {
		t.closed = true
		close(t.done)
		close(t.events)
	}
	return nil
}
func (t *packetBridgeTUN) push(p []byte) int {
	if !validBridgePacket(p) {
		return bridgeFailure
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return bridgeFailure
	}
	select {
	case t.send <- append([]byte(nil), p...):
		return len(p)
	default:
		return bridgeFull
	}
}

// Nonblocking receive. Caller supplies MTU-sized buffer; no truncation.
func (t *packetBridgeTUN) pull(buf []byte) int {
	if len(buf) < bridgeMTU {
		return bridgeFailure
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return bridgeFailure
	}
	select {
	case p := <-t.receive:
		return copy(buf, p)
	default:
		return 0
	}
}
func (t *packetBridgeTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	if len(bufs) == 0 || len(sizes) == 0 || offset < 0 || offset > len(bufs[0]) {
		return 0, os.ErrInvalid
	}
	select {
	case <-t.done:
		return 0, os.ErrClosed
	case p := <-t.send:
		t.mu.Lock()
		defer t.mu.Unlock()
		if t.closed {
			return 0, os.ErrClosed
		}
		if len(bufs[0])-offset < len(p) {
			return 0, os.ErrInvalid
		}
		sizes[0] = copy(bufs[0][offset:], p)
		return 1, nil
	}
}
func (t *packetBridgeTUN) Write(bufs [][]byte, offset int) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return 0, os.ErrClosed
	}
	for i, b := range bufs {
		if offset < 0 || offset > len(b) || !validBridgePacket(b[offset:]) {
			return i, os.ErrInvalid
		}
		select {
		case t.receive <- append([]byte(nil), b[offset:]...):
		default: /* bounded drop, no fallback */
		}
	}
	return len(bufs), nil
}

type bridgePeer struct {
	t    *packetBridgeTUN
	d    *device.Device
	bind *loop
}

func configuredBridgePeer(role int, listen uint16, endpoint string, keys []byte, binding conn.Bind) (*bridgePeer, error) {
	if (role != 0 && role != 1) || len(keys) != 96 {
		return nil, os.ErrInvalid
	}
	for i := 0; i < 96; i += 32 {
		var sum byte
		for _, v := range keys[i : i+32] {
			sum |= v
		}
		if sum == 0 {
			return nil, os.ErrInvalid
		}
	}
	ip4 := []netip.Addr{netip.MustParseAddr("192.0.2.1"), netip.MustParseAddr("192.0.2.2")}
	ip6 := []netip.Addr{netip.MustParseAddr("2001:db8::1"), netip.MustParseAddr("2001:db8::2")}
	t := newPacketBridgeTUN()
	d := device.NewDevice(t, binding, device.NewLogger(device.LogLevelSilent, ""))
	cfg := fixture + fmt.Sprintf("private_key=%s\nlisten_port=%d\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=%s/32\nallowed_ip=%s/128\nendpoint=%s\n", hex.EncodeToString(keys[:32]), listen, hex.EncodeToString(keys[32:64]), hex.EncodeToString(keys[64:]), ip4[role^1], ip6[role^1], endpoint)
	if d.IpcSet(cfg) != nil || d.Up() != nil {
		d.Close()
		return nil, os.ErrInvalid
	}
	p := &bridgePeer{t: t, d: d}
	if b, ok := binding.(*loop); ok {
		p.bind = b
	}
	return p, nil
}
func makeBridgePeer(role int, listen, remote uint16, keys []byte) (*bridgePeer, error) {
	if remote == 0 || listen == remote {
		return nil, os.ErrInvalid
	}
	return configuredBridgePeer(role, listen, fmt.Sprintf("127.0.0.1:%d", remote), keys, &loop{})
}
func (b *packetBridge) startLAN(local netip.Addr, keys []byte) uint64 {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer != nil || b.generation == math.MaxUint64 {
		return 0
	}
	binding, e := newScopedBind(false, local)
	if e != nil {
		return 0
	}
	p, e := configuredBridgePeer(0, awgLabClientPort, binding.remote.String(), keys, binding)
	if e != nil {
		return 0
	}
	b.generation++
	b.peer = p
	return b.generation
}

type packetBridge struct {
	mu         sync.Mutex
	generation uint64
	peer       *bridgePeer
}

func (b *packetBridge) start(role int, listen, remote uint16, keys []byte) uint64 {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer != nil || b.generation == math.MaxUint64 {
		return 0
	}
	p, err := makeBridgePeer(role, listen, remote, keys)
	if err != nil {
		return 0
	}
	b.generation++
	b.peer = p
	return b.generation
}
func (b *packetBridge) push(token uint64, p []byte) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer == nil || token != b.generation {
		return bridgeFailure
	}
	return b.peer.t.push(p)
}
func (b *packetBridge) pull(token uint64, p []byte) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer == nil || token != b.generation {
		return bridgeFailure
	}
	return b.peer.t.pull(p)
}
func (b *packetBridge) stop(token uint64) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer == nil || token != b.generation {
		return false
	}
	b.peer.d.Close()
	b.peer = nil
	return true
}

func (b *packetBridge) port(token uint64) uint16 {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.peer == nil || token != b.generation {
		return 0
	}
	if b.peer.bind == nil {
		return 0
	}
	return b.peer.bind.port()
}
