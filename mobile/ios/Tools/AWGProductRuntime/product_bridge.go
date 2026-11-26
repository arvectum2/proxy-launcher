package main

/*
#include <stdint.h>
*/
import "C"
import (
	"encoding/hex"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"math"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"unsafe"
)

// Exact single-peer full-tunnel UAPI emitted by NativeWireGuardRuntimeConfig.
func inspectProductConfig(raw []byte, mtu int) (netip.AddrPort, bool) {
	var invalid netip.AddrPort
	if mtu < 1280 || mtu > 1500 || len(raw) == 0 || len(raw) > 4096 || raw[len(raw)-1] != '\n' {
		return invalid, false
	}
	fields := map[string]string{}
	routes := map[string]bool{}
	for _, line := range strings.Split(string(raw[:len(raw)-1]), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok || v == "" {
			return invalid, false
		}
		if k == "allowed_ip" {
			if routes[v] {
				return invalid, false
			}
			routes[v] = true
			continue
		}
		if _, exists := fields[k]; exists {
			return invalid, false
		}
		switch k {
		case "private_key", "public_key", "preshared_key":
			data, e := hex.DecodeString(v)
			if e != nil || len(data) != 32 || hex.EncodeToString(data) != v {
				return invalid, false
			}
			nonzero := false
			for _, b := range data {
				nonzero = nonzero || b != 0
			}
			clear(data)
			if !nonzero {
				return invalid, false
			}
		case "listen_port":
			if v != "0" {
				return invalid, false
			}
		case "replace_peers", "replace_allowed_ips":
			if v != "true" {
				return invalid, false
			}
		case "jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4", "persistent_keepalive_interval":
			bits := 32
			if k == "persistent_keepalive_interval" {
				bits = 16
			}
			n, e := strconv.ParseUint(v, 10, bits)
			if e != nil || strconv.FormatUint(n, 10) != v {
				return invalid, false
			}
		case "endpoint":
		default:
			return invalid, false
		}
		fields[k] = v
	}
	for _, key := range []string{"private_key", "public_key", "listen_port", "replace_peers", "replace_allowed_ips", "jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4", "persistent_keepalive_interval", "endpoint"} {
		if fields[key] == "" {
			return invalid, false
		}
	}
	if len(routes) != 2 || !routes["0.0.0.0/0"] || !routes["::/0"] {
		return invalid, false
	}
	remote, e := netip.ParseAddrPort(fields["endpoint"])
	if e != nil || !validProductEndpoint(remote) {
		return invalid, false
	}
	return remote, true
}

type productBridgeState struct {
	mu                 sync.Mutex
	generation         uint64
	dev                *device.Device
	tun                *productPacketTUN
	bind               *productBind
	attempted, started bool
}

var productBridge productBridgeState

func (b *productBridgeState) prepare(raw []byte, mtu int, expected netip.AddrPort) uint64 {
	remote, ok := inspectProductConfig(raw, mtu)
	if !ok || remote != expected || !validateProductUAPI(raw) {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.dev != nil || b.generation == math.MaxUint64 {
		return 0
	}
	t := newProductPacketTUN(mtu)
	binding := &productBind{remote: remote}
	d := device.NewDevice(t, binding, device.NewLogger(device.LogLevelSilent, ""))
	if d.IpcSet(string(raw)) != nil || !binding.preparedWithoutSockets() {
		d.Close()
		return 0
	}
	b.generation++
	b.dev = d
	b.tun = t
	b.bind = binding
	b.attempted = false
	b.started = false
	return b.generation
}
func (b *productBridgeState) start(token uint64) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if token == 0 || token != b.generation || b.dev == nil || b.attempted {
		return false
	}
	b.attempted = true
	if !b.bind.permitStart() {
		return false
	}
	if b.dev.Up() != nil {
		b.bind.revoke()
		return false
	}
	b.started = true
	return true
}
func (b *productBridgeState) push(token uint64, raw []byte) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	if token == 0 || token != b.generation || b.dev == nil || !b.started {
		return bridgeFailure
	}
	return b.tun.push(raw)
}
func (b *productBridgeState) pull(token uint64, raw []byte) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	if token == 0 || token != b.generation || b.dev == nil || !b.started || len(raw) != b.tun.mtu {
		return bridgeFailure
	}
	return b.tun.pull(raw)
}
func (b *productBridgeState) stop(token uint64) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if token == 0 || token != b.generation || b.dev == nil {
		return false
	}
	b.started = false
	b.bind.revoke()
	b.dev.Close()
	b.dev = nil
	b.tun = nil
	b.bind = nil
	return true
}

//export aplAWGProductPrepare
func aplAWGProductPrepare(input unsafe.Pointer, size C.int, mtu C.int, host unsafe.Pointer, hostSize C.int, port C.uint16_t) C.uint64_t {
	if input == nil || size <= 0 || size > 4096 || host == nil || hostSize <= 0 || hostSize > 45 || port == 0 {
		return 0
	}
	raw := C.GoBytes(input, size)
	defer clear(raw)
	ip, err := netip.ParseAddr(string(C.GoBytes(host, hostSize)))
	if err != nil {
		return 0
	}
	return C.uint64_t(productBridge.prepare(raw, int(mtu), netip.AddrPortFrom(ip, uint16(port))))
}

//export aplAWGProductStart
func aplAWGProductStart(token C.uint64_t) C.int {
	if productBridge.start(uint64(token)) {
		return 0
	}
	return bridgeFailure
}

//export aplAWGProductPush
func aplAWGProductPush(token C.uint64_t, input unsafe.Pointer, size C.int) C.int {
	if input == nil || size < 20 || size > 1500 {
		return bridgeFailure
	}
	return C.int(productBridge.push(uint64(token), C.GoBytes(input, size)))
}

//export aplAWGProductPull
func aplAWGProductPull(token C.uint64_t, output unsafe.Pointer, size C.int) C.int {
	if output == nil || size < 1280 || size > 1500 {
		return bridgeFailure
	}
	return C.int(productBridge.pull(uint64(token), unsafe.Slice((*byte)(output), int(size))))
}

//export aplAWGProductStop
func aplAWGProductStop(token C.uint64_t) C.int {
	if productBridge.stop(uint64(token)) {
		return 0
	}
	return bridgeFailure
}
