"""Isolated QA reference source preparation. Never compiled into the product."""
import sys
from pathlib import Path

def replace(s,old,new):
    assert s.count(old)==1,old
    return s.replace(old,new)

src,dst=map(Path,sys.argv[1:])
s=src.read_text()
s=replace(s,'"fmt"','"fmt"\n "encoding/binary"')
s=replace(s,'sent, received, rejected uint64','sent, received, rejected uint64\n directPhone, learned bool')
s=replace(s,'ip.Is4() && awgLabLAN.Contains(ip) && ip != awgLabLAN.Addr() && ip != netip.MustParseAddr("192.168.1.255")','ip == awgLabServerIP || ip == netip.MustParseAddr("192.168.1.90")')
s=replace(s,'local: s, remote: c','local: s, remote: c, directPhone: client == netip.MustParseAddr("192.168.1.90")')
s=replace(s,'func (b *scopedBind) Open(','''// Called under b.mu. Only a single known phone and first synthetic
// initiation may select a source port; never grant cryptographic authority.
func (b *scopedBind) acceptsSource(a netip.AddrPort, packet []byte) bool {
 if !b.directPhone || b.learned { return a == b.remote }
 if a.Addr()!=b.remote.Addr() || a.Port()==0 || len(packet)!=163 ||
     binary.LittleEndian.Uint32(packet[15:19])!=123456 { return false }
 b.remote=a
 b.learned=true
 return true
}
func (b *scopedBind) Open(''')
s=replace(s,'if a != b.remote {','if !b.acceptsSource(a, bufs[0][:n]) {')
s=replace(s,'a, e := netip.ParseAddrPort(s)\n\tif e != nil','a, e := netip.ParseAddrPort(s)\n b.mu.Lock(); defer b.mu.Unlock()\n\tif e != nil')
s=replace(s,'a, ok := ep.(scopedEndpoint)\n\tif !ok','b.mu.Lock(); defer b.mu.Unlock()\n a, ok := ep.(scopedEndpoint)\n\tif !ok')
s=replace(s,'\t}\n\tb.mu.Lock()\n\tdefer b.mu.Unlock()\n\tif b.sock == nil {\n\t\treturn net.ErrClosed','\t}\n\tif b.sock == nil {\n\t\treturn net.ErrClosed')
(dst/'scoped_bind.go').write_text(s)
(dst/'scoped_bind_direct_test.go').write_text('''package main
import ("testing"; "net/netip"; "encoding/binary")
func TestExactSyntheticSource(t *testing.T) {
 a:=netip.MustParseAddr("192.168.1.90")
 b,e:=newScopedBind(true,a); if e!=nil{t.Fatal(e)}
 p:=make([]byte,163);binary.LittleEndian.PutUint32(p[15:],123456)
 other:=netip.MustParseAddrPort("192.168.1.91:41234")
 first:=netip.AddrPortFrom(a,41234);second:=netip.AddrPortFrom(a,41235)
 if b.acceptsSource(other,p)||b.acceptsSource(first,[]byte{1})||b.learned {t.Fatal("invalid source accepted")}
 if !b.acceptsSource(first,p)||!b.learned||b.remote!=first{t.Fatal("first source not pinned")}
 if b.acceptsSource(second,p)||!b.acceptsSource(first,p){t.Fatal("port changed")}
 local,e:=newScopedBind(true,awgLabServerIP);if e!=nil{t.Fatal(e)}
 if local.acceptsSource(netip.AddrPortFrom(awgLabServerIP,41234),p){t.Fatal("local fixed source relaxed")}
}
''')
