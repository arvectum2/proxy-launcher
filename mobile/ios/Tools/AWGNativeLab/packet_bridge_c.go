package main

/*
#include <stdint.h>
*/
import "C"
import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/netip"
	"time"
	"unsafe"
)

var isolatedBridge packetBridge

// Keys: exactly 96 bytes (private, remote public, PSK). Loopback lab only.
//
//export aplAWGBridgeStart
func aplAWGBridgeStart(role C.int, listen, remote C.uint16_t, keys unsafe.Pointer, size C.int) C.uint64_t {
	if keys == nil || size != 96 {
		return 0
	}
	copyKeys := C.GoBytes(keys, size)
	defer clear(copyKeys)
	return C.uint64_t(isolatedBridge.start(int(role), uint16(listen), uint16(remote), copyKeys))
}

// Explicit LAN-only fixture, local address encoded as network-order octets.
//
//export aplAWGBridgeStartLAN
func aplAWGBridgeStartLAN(local C.uint32_t, keys unsafe.Pointer, size C.int) C.uint64_t {
	if keys == nil || size != 96 {
		return 0
	}
	ip := uint32(local)
	addr := netip.AddrFrom4([4]byte{byte(ip >> 24), byte(ip >> 16), byte(ip >> 8), byte(ip)})
	copyKeys := C.GoBytes(keys, size)
	defer clear(copyKeys)
	return C.uint64_t(isolatedBridge.startLAN(addr, copyKeys))
}

//export aplAWGBridgePush
func aplAWGBridgePush(token C.uint64_t, input unsafe.Pointer, size C.int) C.int {
	if input == nil || size < 20 || size > bridgeMTU {
		return bridgeFailure
	}
	return C.int(isolatedBridge.push(uint64(token), C.GoBytes(input, size)))
}

//export aplAWGBridgePull
func aplAWGBridgePull(token C.uint64_t, output unsafe.Pointer, size C.int) C.int {
	if output == nil || size != bridgeMTU {
		return bridgeFailure
	}
	return C.int(isolatedBridge.pull(uint64(token), unsafe.Slice((*byte)(output), bridgeMTU)))
}

//export aplAWGBridgeStop
func aplAWGBridgeStop(token C.uint64_t) C.int {
	if !isolatedBridge.stop(uint64(token)) {
		return bridgeFailure
	}
	return 0
}

// Exact compiled UAPI validation, never opens a socket or starts a device.
//
//export aplAWGBridgeValidateConfig
func aplAWGBridgeValidateConfig(input unsafe.Pointer, size C.int) C.int {
	if input == nil || size <= 0 || size > 4096 {
		return bridgeFailure
	}
	raw := C.GoBytes(input, size)
	defer clear(raw)
	if !validateProductUAPI(raw) {
		return bridgeFailure
	}
	return 0
}

// Authentic encrypted packet roundtrip through the public C ABI and a
// second native engine, bounded to loopback. No owner data or OS tunnel.
//
//export aplAWGBridgeSelfTest
func aplAWGBridgeSelfTest() C.int {
	a, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		return 1
	}
	b, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		return 1
	}
	psk := make([]byte, 32)
	if _, e = rand.Read(psk); e != nil {
		return 1
	}
	ka := append(append(a.Bytes(), b.PublicKey().Bytes()...), psk...)
	kb := append(append(b.Bytes(), a.PublicKey().Bytes()...), psk...)
	defer clear(ka)
	defer clear(kb)
	defer clear(psk)
	peer, e := makeBridgePeer(1, 0, 1, kb)
	if e != nil {
		return 2
	}
	defer peer.d.Close()
	token := aplAWGBridgeStart(0, 0, C.uint16_t(peer.bind.port()), unsafe.Pointer(&ka[0]), 96)
	if token == 0 {
		return 3
	}
	defer aplAWGBridgeStop(token)
	if aplAWGBridgeStart(0, 0, C.uint16_t(peer.bind.port()), unsafe.Pointer(&ka[0]), 96) != 0 {
		return 4
	}
	if e = peer.d.IpcSet(fmt.Sprintf("public_key=%s\nendpoint=127.0.0.1:%d\n", hex.EncodeToString(a.PublicKey().Bytes()), isolatedBridge.port(uint64(token)))); e != nil {
		return 5
	}
	wait := func(pull func([]byte) int, want []byte) bool {
		buf := make([]byte, bridgeMTU)
		deadline := time.Now().Add(4 * time.Second)
		for time.Now().Before(deadline) {
			n := pull(buf)
			if n < 0 {
				return false
			}
			if n > 0 {
				return bytes.Equal(buf[:n], want)
			}
			time.Sleep(time.Millisecond * 5)
		}
		return false
	}
	for _, pair := range [][2]string{{"192.0.2.1", "192.0.2.2"}, {"2001:db8::1", "2001:db8::2"}} {
		src, dst := netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1])
		forward, e := packet(src, dst)
		if e != nil {
			return 6
		}
		if aplAWGBridgePush(token, unsafe.Pointer(&forward[0]), C.int(len(forward))) != C.int(len(forward)) || !wait(peer.t.pull, forward) {
			return 7
		}
		reverse, e := packet(dst, src)
		if e != nil {
			return 6
		}
		if peer.t.push(reverse) != len(reverse) || !wait(func(p []byte) int { return int(aplAWGBridgePull(token, unsafe.Pointer(&p[0]), bridgeMTU)) }, reverse) {
			return 8
		}
	}
	if aplAWGBridgeStop(token) != 0 {
		return 9
	}
	staleBuf := make([]byte, bridgeMTU)
	if aplAWGBridgePull(token, unsafe.Pointer(&staleBuf[0]), bridgeMTU) != bridgeFailure {
		return 10
	}
	next := aplAWGBridgeStart(0, 0, C.uint16_t(peer.bind.port()), unsafe.Pointer(&ka[0]), 96)
	if next == 0 || next == token {
		return 11
	}
	defer aplAWGBridgeStop(next)
	if aplAWGBridgeStop(token) != bridgeFailure {
		return 12
	}
	if aplAWGBridgeStop(next) != 0 {
		return 13
	}
	return 0
}
