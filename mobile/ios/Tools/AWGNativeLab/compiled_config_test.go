package main

import (
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"os"
	"strings"
	"testing"
)

// Compiler test only, no device.Up or peer traffic. The loopback-only bind
// cannot resolve a non-local endpoint.
func TestSwiftCompiledConfiguration(t *testing.T) {
	path := os.Getenv("APL_AWG_COMPILED_CONFIG")
	if path == "" {
		t.Skip("standalone compiler acceptance only")
	}
	raw, e := os.ReadFile(path)
	if e != nil || len(raw) > 4096 {
		t.Fatal("fixture read failed")
	}
	defer clear(raw)
	if !strings.Contains(string(raw), "endpoint=127.0.0.1:39891\n") {
		t.Fatal("not a local fixture")
	}
	b := &loop{}
	d := device.NewDevice(newPacketBridgeTUN(), b, device.NewLogger(device.LogLevelSilent, ""))
	defer d.Close()
	if d.IpcSet(string(raw)) != nil {
		t.Fatal("native AWG config rejected")
	}
	if b.sent != 0 || b.received != 0 {
		t.Fatal("unexpected traffic")
	}
}
