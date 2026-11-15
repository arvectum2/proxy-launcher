package main

import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"net"
	"net/netip"
	"testing"
	"time"
)

func localUDP(t *testing.T, ip netip.Addr) *net.UDPConn {
	t.Helper()
	network := "udp4"
	if ip.Is6() {
		network = "udp6"
	}
	s, e := net.ListenUDP(network, net.UDPAddrFromAddrPort(netip.AddrPortFrom(ip, 0)))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	return s
}
func TestBoundPeerKernelSocket(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "::1"} {
		t.Run(host, func(t *testing.T) {
			ip := netip.MustParseAddr(host)
			srv := localUDP(t, ip)
			remote := srv.LocalAddr().(*net.UDPAddr).AddrPort()
			b, e := newBoundPeer(netip.AddrPortFrom(ip, 0), remote, "lo0")
			if e != nil {
				t.Fatal(e)
			}
			defer b.Close()
			receive, port, e := b.Open(0)
			if e != nil || port == 0 || len(receive) != 1 {
				t.Fatalf("open: %v", e)
			}
			if _, _, e = b.Open(0); e != conn.ErrBindAlreadyOpen {
				t.Fatal("double open")
			}
			ep, e := b.ParseEndpoint(remote.String())
			if e != nil {
				t.Fatal(e)
			}
			if _, e = b.ParseEndpoint(netip.AddrPortFrom(ip, port).String()); e == nil {
				t.Fatal("foreign endpoint")
			}
			payload := make([]byte, 32)
			if _, e = rand.Read(payload); e != nil {
				t.Fatal(e)
			}
			if e = b.Send([][]byte{payload}, ep); e != nil {
				t.Fatal(e)
			}
			srv.SetReadDeadline(time.Now().Add(time.Second))
			buf := make([]byte, 128)
			n, client, e := srv.ReadFromUDPAddrPort(buf)
			if e != nil || client != netip.AddrPortFrom(ip, port) || !bytes.Equal(buf[:n], payload) {
				t.Fatalf("wire witness: %v", e)
			}
			foreign := localUDP(t, ip)
			if _, e = foreign.WriteToUDPAddrPort([]byte("foreign"), client); e != nil {
				t.Fatal(e)
			}
			if _, e = srv.WriteToUDPAddrPort(payload, client); e != nil {
				t.Fatal(e)
			}
			b.sock.SetReadDeadline(time.Now().Add(time.Second))
			sizes := []int{0}
			eps := make([]conn.Endpoint, 1)
			n, e = receive[0]([][]byte{buf}, sizes, eps)
			if e != nil || n != 1 || !bytes.Equal(buf[:sizes[0]], payload) || eps[0].DstToString() != remote.String() {
				t.Fatalf("peer filter: %v", e)
			}
			b.sock.SetReadDeadline(time.Time{})
			done := make(chan error, 1)
			go func() { _, e := receive[0]([][]byte{make([]byte, 128)}, []int{0}, make([]conn.Endpoint, 1)); done <- e }()
			if e = b.Close(); e != nil {
				t.Fatal(e)
			}
			select {
			case e := <-done:
				if e == nil {
					t.Fatal("read survived close")
				}
			case <-time.After(time.Second):
				t.Fatal("close did not wake read")
			}
			if e = b.Send([][]byte{payload}, ep); e == nil {
				t.Fatal("send after close")
			}
		})
	}
}
func TestBoundPeerRejectsOutsideFixture(t *testing.T) {
	local := netip.MustParseAddrPort("127.0.0.1:0")
	remote := netip.MustParseAddrPort("127.0.0.1:12345")
	for _, bad := range []netip.AddrPort{netip.MustParseAddrPort("192.0.2.42:12345"), netip.MustParseAddrPort("[::1]:12345"), netip.MustParseAddrPort("127.0.0.1:0")} {
		if _, e := newBoundPeer(local, bad, "lo0"); e == nil {
			t.Fatal("outside fixture")
		}
	}
	if _, e := newBoundPeer(local, remote, "en0"); e == nil {
		t.Fatal("wrong interface")
	}
}
func TestBoundPeerNativeHandshake(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "::1"} {
		t.Run(host, func(t *testing.T) {
			ip := netip.MustParseAddr(host)
			a := localUDP(t, ip)
			b := localUDP(t, ip)
			ap := a.LocalAddr().(*net.UDPAddr).AddrPort()
			bp := b.LocalAddr().(*net.UDPAddr).AddrPort()
			a.Close()
			b.Close()
			ka, e := ecdh.X25519().GenerateKey(rand.Reader)
			if e != nil {
				t.Fatal(e)
			}
			kb, e := ecdh.X25519().GenerateKey(rand.Reader)
			if e != nil {
				t.Fatal(e)
			}
			psk := make([]byte, 32)
			if _, e = rand.Read(psk); e != nil {
				t.Fatal(e)
			}
			ba, e := newBoundPeer(ap, bp, "lo0")
			if e != nil {
				t.Fatal(e)
			}
			bb, e := newBoundPeer(bp, ap, "lo0")
			if e != nil {
				t.Fatal(e)
			}
			one, e := configuredBridgePeer(0, ap.Port(), bp.String(), append(append(ka.Bytes(), kb.PublicKey().Bytes()...), psk...), ba)
			if e != nil {
				t.Fatal("native first peer")
			}
			defer one.d.Close()
			two, e := configuredBridgePeer(1, bp.Port(), ap.String(), append(append(kb.Bytes(), ka.PublicKey().Bytes()...), psk...), bb)
			if e != nil {
				t.Fatal("native second peer")
			}
			defer two.d.Close()
			for _, pair := range [][2]string{{"192.0.2.1", "192.0.2.2"}, {"2001:db8::1", "2001:db8::2"}} {
				p, e := packet(netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1]))
				if e != nil {
					t.Fatal(e)
				}
				if one.t.push(p) != len(p) {
					t.Fatal("queue")
				}
				buf := make([]byte, bridgeMTU)
				deadline := time.Now().Add(4 * time.Second)
				matched := false
				for time.Now().Before(deadline) {
					n := two.t.pull(buf)
					if n > 0 {
						if !bytes.Equal(buf[:n], p) {
							t.Fatal("different frame")
						}
						matched = true
						break
					}
					time.Sleep(5 * time.Millisecond)
				}
				if !matched {
					t.Fatal("no native frame")
				}
			}
		})
	}
}
