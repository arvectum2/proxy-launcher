// Explicit macOS-only CLI probe for the same native packet bridge used by
// the isolated NE. Test-only synthetic packets, no real profile or routes.
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/netip"
	"os"
	"runtime"
	"time"
)

func udpFixture(src, dst netip.Addr, nonce []byte) []byte {
	h := 20
	if src.Is6() {
		h = 40
	}
	p := make([]byte, h+8+len(nonce))
	udp := p[h:]
	binary.BigEndian.PutUint16(udp[0:2], 39894)
	binary.BigEndian.PutUint16(udp[2:4], 39892)
	binary.BigEndian.PutUint16(udp[4:6], uint16(len(udp)))
	copy(udp[8:], nonce)
	if h == 20 {
		p[0] = 0x45
		binary.BigEndian.PutUint16(p[2:4], uint16(len(p)))
		p[8] = 64
		p[9] = 17
		copy(p[12:16], src.AsSlice())
		copy(p[16:20], dst.AsSlice())
		binary.BigEndian.PutUint16(p[10:12], checksum(p[:20]))
		return p
	}
	p[0] = 0x60
	binary.BigEndian.PutUint16(p[4:6], uint16(len(udp)))
	p[6] = 17
	p[7] = 64
	copy(p[8:24], src.AsSlice())
	copy(p[24:40], dst.AsSlice())
	pseudo := append([]byte{}, p[8:40]...)
	pseudo = append(pseudo, 0, 0, 0, byte(len(udp)), 0, 0, 0, 17)
	pseudo = append(pseudo, udp...)
	sum := checksum(pseudo)
	if sum == 0 {
		sum = 0xffff
	}
	binary.BigEndian.PutUint16(udp[6:8], sum)
	return p
}
func exactUDPResponse(p []byte, client, server netip.Addr, nonce string) bool {
	if !validBridgePacket(p) {
		return false
	}
	h := 20
	if client.Is4() {
		if p[0] != 0x45 || p[9] != 17 || !bytes.Equal(p[12:16], server.AsSlice()) || !bytes.Equal(p[16:20], client.AsSlice()) {
			return false
		}
	} else {
		h = 40
		if p[0]>>4 != 6 || p[6] != 17 || !bytes.Equal(p[8:24], server.AsSlice()) || !bytes.Equal(p[24:40], client.AsSlice()) {
			return false
		}
	}
	u := p[h:]
	return len(u) == 60 && binary.BigEndian.Uint16(u[:2]) == 39892 && binary.BigEndian.Uint16(u[2:4]) == 39894 && binary.BigEndian.Uint16(u[4:6]) == 60 && string(u[8:]) == "APL:"+nonce
}
func runLANBridgeProbe(path string) int {
	if runtime.GOOS != "darwin" {
		return 1
	}
	f, e := os.Open(path)
	if e != nil {
		return 2
	}
	defer f.Close()
	raw, e := io.ReadAll(io.LimitReader(f, 4097))
	defer clear(raw)
	if e != nil || len(raw) > 4096 {
		return 2
	}
	var c struct{ Private, Peer, PSK, Nonce, ClientIP string }
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(&c) != nil || d.Decode(new(any)) != io.EOF || c.ClientIP != "192.168.1.80" {
		return 2
	}
	nonce, e := hex.DecodeString(c.Nonce)
	if e != nil || len(nonce) != 24 {
		return 2
	}
	keys, e := hex.DecodeString(c.Private + c.Peer + c.PSK)
	if e != nil || len(keys) != 96 || len(c.Private) != 64 || len(c.Peer) != 64 || len(c.PSK) != 64 {
		return 2
	}
	defer clear(keys)
	b := &packetBridge{}
	token := b.startLAN(awgLabServerIP, keys)
	if token == 0 {
		return 3
	}
	defer b.stop(token)
	for _, pair := range [][2]string{{"192.0.2.1", "192.0.2.2"}, {"2001:db8::1", "2001:db8::2"}} {
		client, server := netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1])
		p := udpFixture(client, server, []byte(c.Nonce))
		if b.push(token, p) != len(p) {
			return 4
		}
		buf := make([]byte, bridgeMTU)
		deadline := time.Now().Add(4 * time.Second)
		got := false
		for time.Now().Before(deadline) {
			n := b.pull(token, buf)
			if n < 0 {
				return 5
			}
			if n > 0 && exactUDPResponse(buf[:n], client, server, c.Nonce) {
				got = true
				break
			}
			time.Sleep(5 * time.Millisecond)
		}
		fmt.Printf("AWG_BRIDGE_UDP v%d receipt=%t\n", map[bool]int{true: 4, false: 6}[client.Is4()], got)
		if !got {
			return 6
		}
	}
	if !b.stop(token) || b.push(token, make([]byte, 20)) != bridgeFailure {
		return 7
	}
	return 0
}
