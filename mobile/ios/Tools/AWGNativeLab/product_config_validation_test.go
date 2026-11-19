package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"
	"testing"
)

func TestProductUAPIValidationWithoutSockets(t *testing.T) {
	a, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	b, e := ecdh.X25519().GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	config := fixture + fmt.Sprintf("private_key=%s\nlisten_port=0\nreplace_peers=true\npublic_key=%s\nreplace_allowed_ips=true\nallowed_ip=0.0.0.0/0\nallowed_ip=::/0\nendpoint=192.0.2.42:39891\n", hex.EncodeToString(a.Bytes()), hex.EncodeToString(b.PublicKey().Bytes()))
	if !validateProductUAPI([]byte(config)) {
		t.Fatal("valid literal config rejected")
	}
	for _, bad := range []string{strings.Replace(config, "192.0.2.42:39891", "example.invalid:39891", 1), strings.Replace(config, "192.0.2.42:39891", "[::ffff:192.0.2.42]:39891", 1), config + "unexpected=1\n", strings.Repeat("x", 4097)} {
		if validateProductUAPI([]byte(bad)) {
			t.Fatal("invalid configuration accepted")
		}
	}
	bind := &validationOnlyBind{}
	if _, _, e := bind.Open(0); e == nil || !bind.attempted.Load() {
		t.Fatal("bind unexpectedly opened")
	}
}
