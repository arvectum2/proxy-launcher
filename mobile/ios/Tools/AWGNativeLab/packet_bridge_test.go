package main

import (
	"bytes"
	"net/netip"
	"testing"
	"time"
)

func TestBoundedPacketQueueAndClose(t *testing.T) {
	q := newPacketBridgeTUN()
	p, err := packet(netip.MustParseAddr("192.0.2.1"), netip.MustParseAddr("192.0.2.2"))
	if err != nil {
		t.Fatal(err)
	}
	original := append([]byte(nil), p...)
	for i := 0; i < bridgeDepth; i++ {
		if q.push(p) != len(p) {
			t.Fatal("push")
		}
	}
	if q.push(p) != bridgeFull {
		t.Fatal("unbounded queue")
	}
	p[24] ^= 255
	buf := make([]byte, bridgeMTU+32)
	sizes := make([]int, 1)
	n, err := q.Read([][]byte{buf}, sizes, 32)
	if n != 1 || err != nil || !bytes.Equal(buf[32:32+sizes[0]], original) {
		t.Fatal("copy/offset")
	}
	malformed := append([]byte(nil), original...)
	malformed[2] = 255
	if q.push(malformed) != bridgeFailure {
		t.Fatal("invalid length")
	}
	for i := 0; i < bridgeDepth+2; i++ {
		if _, e := q.Write([][]byte{original}, 0); e != nil {
			t.Fatal(e)
		}
	}
	for i := 0; i < bridgeDepth; i++ {
		if q.pull(buf) != len(original) {
			t.Fatal("receive")
		}
	}
	if q.pull(buf) != 0 {
		t.Fatal("receive bound")
	}
	q.Close()
	q.Close()
	if q.push(original) != bridgeFailure || q.pull(buf) != bridgeFailure {
		t.Fatal("closed queue")
	}
	if _, err = q.Read([][]byte{buf}, sizes, 0); err == nil {
		t.Fatal("read after close")
	}
}
func TestBlockedReadReleasedByClose(t *testing.T) {
	q := newPacketBridgeTUN()
	done := make(chan error, 1)
	go func() { _, e := q.Read([][]byte{make([]byte, bridgeMTU)}, []int{0}, 0); done <- e }()
	q.Close()
	select {
	case e := <-done:
		if e == nil {
			t.Fatal("read not canceled")
		}
	case <-time.After(time.Second):
		t.Fatal("close blocked")
	}
}
func TestBridgeNativeRoundtrip(t *testing.T) {
	if rc := aplAWGBridgeSelfTest(); rc != 0 {
		t.Fatalf("native code %d", rc)
	}
}
