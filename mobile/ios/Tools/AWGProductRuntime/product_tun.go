// Opt-in product queue; no route installation or implicit start.
package main

import (
	"encoding/binary"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"os"
	"sync"
)

type productPacketTUN struct {
	mtu           int
	send, receive chan []byte
	done          chan struct{}
	events        chan tun.Event
	mu            sync.Mutex
	closed        bool
}

var _ tun.Device = (*productPacketTUN)(nil)

func newProductPacketTUN(mtu int) *productPacketTUN {
	t := &productPacketTUN{mtu: mtu, send: make(chan []byte, bridgeDepth), receive: make(chan []byte, bridgeDepth), done: make(chan struct{}), events: make(chan tun.Event, 1)}
	// Explicit device.Up controls lifecycle; no implicit asynchronous start.
	return t
}
func validProductPacket(p []byte, mtu int) bool {
	if len(p) < 20 || len(p) > mtu {
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
func (t *productPacketTUN) File() *os.File           { return nil }
func (t *productPacketTUN) MTU() (int, error)        { return t.mtu, nil }
func (t *productPacketTUN) Name() (string, error)    { return "apl-awg-product", nil }
func (t *productPacketTUN) Events() <-chan tun.Event { return t.events }
func (t *productPacketTUN) BatchSize() int           { return 1 }
func (t *productPacketTUN) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if !t.closed {
		t.closed = true
		close(t.done)
		close(t.events)
	}
	return nil
}
func (t *productPacketTUN) push(p []byte) int {
	if !validProductPacket(p, t.mtu) {
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
func (t *productPacketTUN) pull(buf []byte) int {
	if len(buf) < t.mtu {
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
func (t *productPacketTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
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
func (t *productPacketTUN) Write(bufs [][]byte, offset int) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return 0, os.ErrClosed
	}
	for i, b := range bufs {
		if offset < 0 || offset > len(b) || !validProductPacket(b[offset:], t.mtu) {
			return i, os.ErrInvalid
		}
		select {
		case t.receive <- append([]byte(nil), b[offset:]...):
		default: /* bounded drop, no fallback */
		}
	}
	return len(bufs), nil
}
