// Standalone non-Xray reference peer. Local-only synthetic traffic.
package main

import (
	"encoding/hex"
 "encoding/binary"
	"encoding/json"
	"fmt"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
 "golang.zx2c4.com/wireguard/tun"
	"io"
	"net"
	"net/netip"
	"os"
	"sync"
	"time"
)

type endpoint struct{ netip.AddrPort }

func (e endpoint) ClearSrc()           {}
func (e endpoint) SrcToString() string { return "" }
func (e endpoint) DstToString() string { return e.String() }
func (e endpoint) DstToBytes() []byte  { b, _ := e.MarshalBinary(); return b }
func (e endpoint) DstIP() netip.Addr   { return e.Addr() }
func (e endpoint) SrcIP() netip.Addr   { return netip.Addr{} }

// Private bind implementing upstream conn.Bind on actual localhost UDP.
// Reject every endpoint except 127.0.0.1; no external route.
type loop struct {
	mu             sync.Mutex
	sock           *net.UDPConn
	sent, received int
}

func (l *loop) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}
	s, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: int(port)})
	if err != nil {
		return nil, 0, err
	}
	l.sock = s
	return []conn.ReceiveFunc{func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		n, a, err := s.ReadFromUDPAddrPort(bufs[0])
		if err != nil {
			return 0, err
		}
		if a.Addr() != netip.MustParseAddr("127.0.0.1") || a.Port() != 39881 {
			return 0, net.ErrClosed
		}
		sizes[0] = n
		eps[0] = endpoint{a}
		l.mu.Lock()
		l.received++
		l.mu.Unlock()
		return 1, nil
	}}, uint16(s.LocalAddr().(*net.UDPAddr).Port), nil
}
func (l *loop) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return nil
	}
	err := l.sock.Close()
	l.sock = nil
	return err
}
func (l *loop) SetMark(mark uint32) error {
	if mark != 0 {
		return fmt.Errorf("not a lab mark")
	}
	return nil
}
func (l *loop) BatchSize() int { return 1 }
func (l *loop) ParseEndpoint(s string) (conn.Endpoint, error) {
	a, err := netip.ParseAddrPort(s)
	if err != nil || a.Addr() != netip.MustParseAddr("127.0.0.1") || a.Port() != 39881 {
		return nil, fmt.Errorf("not loopback")
	}
	return endpoint{a}, nil
}
func (l *loop) Send(bufs [][]byte, ep conn.Endpoint) error {
	e, ok := ep.(endpoint)
	if !ok || e.Addr() != netip.MustParseAddr("127.0.0.1") || e.Port() != 39881 {
		return conn.ErrWrongEndpointType
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return net.ErrClosed
	}
	for _, b := range bufs {
		if _, err := l.sock.WriteToUDPAddrPort(b, e.AddrPort); err != nil {
			return err
		}
		l.sent++
	}
	return nil
}
func (l *loop) port() uint16 {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.sock == nil {
		return 0
	}
	return uint16(l.sock.LocalAddr().(*net.UDPAddr).Port)
}
func (l *loop) stats() (int, int) { l.mu.Lock(); defer l.mu.Unlock(); return l.sent, l.received }

var _ conn.Bind = (*loop)(nil)

// Only aggregate packet metadata for synthetic local QA; never store payload.
type measuredTUN struct {tun.Device}
func measurePacket(direction string, b []byte) {
 if len(b)<20 {return}
 version:=b[0]>>4
 var proto byte
 var off int
 var src,dst netip.Addr
 if version==4 {
  off=int(b[0]&15)*4;proto=b[9]
  src,_=netip.AddrFromSlice(b[12:16]);dst,_=netip.AddrFromSlice(b[16:20])
 } else if version==6 && len(b)>=40 {
  off=40;proto=b[6];src,_=netip.AddrFromSlice(b[8:24]);dst,_=netip.AddrFromSlice(b[24:40])
 } else {return}
 if off<20 || len(b)<off+8{return}
 if proto==17 {
  fmt.Printf("WG_PACKET_%s_V%d_UDP_SRC_LAB_%t_DST_LAB_%t_PORT_OK_%t_LEN_%d_CHECKSUM_ZERO_%t\n",direction,version,src==netip.MustParseAddr("10.77.0.2")||src==netip.MustParseAddr("2001:db8:77::2"),dst==netip.MustParseAddr("198.51.100.77")||dst==netip.MustParseAddr("2001:db8:77::77"),binary.BigEndian.Uint16(b[off+2:off+4])==39883,binary.BigEndian.Uint16(b[off+4:off+6]),binary.BigEndian.Uint16(b[off+6:off+8])==0)
 } else if proto==1 || proto==58 {
  fmt.Printf("WG_PACKET_%s_V%d_ICMP_TYPE_%d_CODE_%d\n",direction,version,b[off],b[off+1])
 }
}
func(t *measuredTUN) Write(bufs [][]byte,off int)(int,error){
 for _,b:=range bufs {if off>=0 && off<len(b){measurePacket("RX",b[off:])}}
 return t.Device.Write(bufs,off)
}
func(t *measuredTUN) Read(bufs [][]byte,sizes []int,off int)(int,error){
 n,e:=t.Device.Read(bufs,sizes,off)
 for i:=0;i<n;i++{if off>=0&&off+sizes[i]<=len(bufs[i]){measurePacket("TX",bufs[i][off:off+sizes[i]])}}
 return n,e
}

type Config struct {
	Private string `json:"private"`
	Peer    string `json:"peer"`
	PSK     string `json:"psk"`
	Dual    bool   `json:"dual"`
}

func validKey(s string) bool {
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 32 {
		return false
	}
	for _, v := range b {
		if v != 0 {
			return true
		}
	}
	return false
}

func run(path string) int {
	raw, err := os.ReadFile(path)
	var cfg Config
	if err != nil || len(raw) > 4096 || json.Unmarshal(raw, &cfg) != nil ||
		!validKey(cfg.Private) || !validKey(cfg.Peer) || !validKey(cfg.PSK) {
		return 2
	}
	addresses := []netip.Addr{netip.MustParseAddr("198.51.100.77")}
	if cfg.Dual {
		addresses = append(addresses, netip.MustParseAddr("2001:db8:77::77"))
	}
	tunnel, stack, err := netstack.CreateNetTUN(addresses, nil, 1280)
	if err != nil {
		return 3
	}
	bind := &loop{}
	dev := device.NewDevice(&measuredTUN{tunnel}, bind, device.NewLogger(device.LogLevelSilent, ""))
	defer dev.Close()
	settings := fmt.Sprintf("private_key=%s\nlisten_port=39882\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nreplace_allowed_ips=true\nallowed_ip=10.77.0.2/32\nendpoint=127.0.0.1:39881\n", cfg.Private, cfg.Peer, cfg.PSK)
	if cfg.Dual {
		settings += "allowed_ip=2001:db8:77::2/128\n"
	}
	if dev.IpcSet(settings) != nil || dev.Up() != nil || bind.port() != 39882 {
		return 4
	}
	listener, err := stack.ListenTCPAddrPort(netip.MustParseAddrPort("198.51.100.77:39883"))
	if err != nil {
		return 5
	}
	var listeners []net.Listener
	listeners = append(listeners, listener)
	if cfg.Dual {
		v6, err := stack.ListenTCPAddrPort(netip.MustParseAddrPort("[2001:db8:77::77]:39883"))
		if err != nil {
			listener.Close()
			return 5
		}
		listeners = append(listeners, v6)
	}
	var workers, acceptors, udpWorkers sync.WaitGroup
	var udpListeners []net.PacketConn
	if cfg.Dual {
		for _, addr := range addresses {
			udp, err := stack.ListenUDPAddrPort(netip.AddrPortFrom(addr, 39883))
			if err != nil {
				for _, l := range listeners {
					l.Close()
				}
				for _, u := range udpListeners {
					u.Close()
				}
				udpWorkers.Wait()
				return 5
			}
			udpListeners = append(udpListeners, udp)
			udpWorkers.Add(1)
			go func(u net.PacketConn) {
				defer udpWorkers.Done()
				buf := make([]byte, 128)
				for {
					n, from, err := u.ReadFrom(buf)
					if err != nil {
						return
					}
					if n != 48 {
						continue
					}
					// Fixed witness endpoint; no generic forwarding.
					w, err := net.DialTimeout("udp4", "127.0.0.1:39883", time.Second)
					if err != nil {
						continue
					}
					_ = w.SetDeadline(time.Now().Add(time.Second))
					_, err = w.Write(buf[:n])
					if err == nil {
						reply := make([]byte, 128)
						m, err := w.Read(reply)
						if err == nil {
							_, _ = u.WriteTo(reply[:m], from)
						}
					}
					w.Close()
				}
			}(udp)
		}
	}
	for _, l := range listeners {
		acceptors.Add(1)
		go func(l net.Listener) {
			defer acceptors.Done()
			for {
				c, err := l.Accept()
				if err != nil {
					return
				}
				workers.Add(1)
				go func() {
					defer workers.Done()
					defer c.Close()
					_ = c.SetDeadline(time.Now().Add(6 * time.Second))
					witness, err := net.DialTimeout("tcp4", "127.0.0.1:39883", time.Second)
					if err != nil {
						return
					}
					defer witness.Close()
					_ = witness.SetDeadline(time.Now().Add(6 * time.Second))
					done := make(chan struct{})
					go func() { _, _ = io.Copy(witness, c); close(done) }()
					_, _ = io.Copy(c, witness)
					_ = c.Close()
					_ = witness.Close()
					<-done
				}()
			}
		}(l)
	}
	fmt.Println("PEER_QA_READY_server")
	deadline := time.Now().Add(75 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path + ".stop"); err == nil {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	for _, l := range listeners {
		l.Close()
	}
	for _, u := range udpListeners {
		u.Close()
	}
	acceptors.Wait()
	udpWorkers.Wait()
	workers.Wait()
	dev.Close()
	if bind.port() != 0 {
		return 6
	}
	fmt.Println("PEER_QA_STOPPED_server")
	return 0
}
func main() {
	if len(os.Args) != 4 || os.Args[1] != "server" || os.Args[3] != "39882" {
		os.Exit(1)
	}
	os.Exit(run(os.Args[2]))
}
