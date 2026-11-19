package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/netip"
	"testing"
)

func TestProductPreparationOwnsExactPeerAndDrainsWithoutSockets(t *testing.T) {
	a, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	b, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	raw := []byte(fmt.Sprintf("private_key=%s\nlisten_port=0\nreplace_peers=true\n"+fixture+"public_key=%s\nendpoint=192.0.2.42:51820\npersistent_keepalive_interval=0\nreplace_allowed_ips=true\nallowed_ip=0.0.0.0/0\nallowed_ip=::/0\n", hex.EncodeToString(a.Bytes()), hex.EncodeToString(b.PublicKey().Bytes())))
	defer clear(raw)
	peer := netip.MustParseAddrPort("192.0.2.42:51820")
	var engine productBridgeState
	if engine.prepare(raw, 1500, netip.MustParseAddrPort("192.0.2.43:51820")) != 0 {
		t.Fatal("wrong peer admitted")
	}
	token := engine.prepare(raw, 1500, peer)
	if token == 0 {
		t.Fatal("prepare failed")
	}
	defer func() {
		if engine.dev != nil {
			engine.stop(token)
		}
	}()
	if !engine.bind.preparedWithoutSockets() {
		t.Fatal("socket opened during prepare")
	}
	if engine.prepare(raw, 1280, peer) != 0 || engine.stop(token+1) || engine.push(token, make([]byte, 40)) != bridgeFailure {
		t.Fatal("ownership or down-state violated")
	}
	if mtu, _ := engine.tun.MTU(); mtu != 1500 {
		t.Fatal("mtu mismatch")
	}
	if !engine.stop(token) || engine.stop(token) {
		t.Fatal("drain mismatch")
	}
	next := engine.prepare(raw, 1280, peer)
	if next <= token || !engine.stop(next) {
		t.Fatal("generation not retired")
	}
}
