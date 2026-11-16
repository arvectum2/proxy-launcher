"""Extend only the disposable direct reference source, not product peer code."""
from pathlib import Path
import sys
d=Path(sys.argv[1]);root=Path(__file__).parent
for name in ("dns_witness.go","dns_witness_test.go"):
    (d/name).write_text((root/(name+".txt")).read_text())
p=d/"main.go";s=p.read_text()
def change(old,new):
    global s
    assert s.count(old)==1,old
    s=s.replace(old,new)
change("local, remote = remote, local","local, remote = remote, local\n local=append(append([]netip.Addr{},local...),witnessDNS)")
change("if d.IpcSet(cfg) != nil","if !server {cfg += \"allowed_ip=192.0.2.53/32\\n\"}\n if d.IpcSet(cfg) != nil")
change('fmt.Println("AWG_PEER_READY")','''var dnsCount atomic.Uint64
 dns,err:=stack.ListenUDPAddrPort(netip.AddrPortFrom(witnessDNS,53))
 if err!=nil{return 7}
 closers=append(closers,dns)
 workers.Add(1)
 go func(){defer workers.Done();serveDNS(dns,c.Nonce,&dnsCount)}()
 fmt.Println("AWG_PEER_READY")''')
change("sent, recv, rejected := b.stats()",'fmt.Printf("AWG_DNS_A_WITNESS %d\\n",dnsCount.Load())\n sent, recv, rejected := b.stats()')
change('mode != "negative" {','mode != "negative" && mode != "dns-positive" {')
change('kinds := []string{"tcp4", "tcp6", "udp4", "udp6"}','''if mode=="dns-positive" {
 if requestDNS(c,stack) && request(c,stack,"tcp4"){return 0};return 8
 }
 kinds := []string{"tcp4", "tcp6", "udp4", "udp6"}''')
p.write_text(s)
