"""Generate only the standalone WG QA DNS reference variant."""
from pathlib import Path
import sys
d=Path(sys.argv[1]);shared=Path(__file__).resolve().parents[1]/"AWGPeerLab"
for name in ("dns_witness.go","dns_witness_test.go"):
    s=(shared/(name+".txt")).read_text()
    s=s.replace("github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack","golang.zx2c4.com/wireguard/tun/netstack").replace("c config,","c Config,").replace("clientAddresses[0]",'netip.MustParseAddr("10.77.0.2")').replace("[4]byte{192,0,2,2}","[4]byte{198,51,100,77}").replace('strings.Repeat("a",48)','strings.Repeat("a",40)')
    (d/name).write_text(s)
def edit(name,changes):
    p=d/name;s=p.read_text()
    for a,b in changes:
        assert s.count(a)==1,(name,a)
        s=s.replace(a,b)
    p.write_text(s)
edit("main.go",[
    ('Measure bool   `json:"measure"`','Measure bool   `json:"measure"`\n DNS bool `json:"dns,omitempty"`'),
    ('tunnel, stack, err := netstack.CreateNetTUN(addresses, nil, 1280)','if cfg.DNS && (!cfg.Dual || !validNonce(cfg.Nonce)) {return 2}\n tunAddresses:=append([]netip.Addr{},addresses...)\n if cfg.DNS {tunAddresses=append(tunAddresses,witnessDNS)}\n tunnel, stack, err := netstack.CreateNetTUN(tunAddresses, nil, 1280)'),
    ('fmt.Println("PEER_QA_READY_server")', '''var dnsCount atomic.Uint64
 if cfg.DNS {
  u,e:=stack.ListenUDPAddrPort(netip.AddrPortFrom(witnessDNS,53))
  if e!=nil{return 7}
  udpListeners=append(udpListeners,u);udpWorkers.Add(1)
  go func(){defer udpWorkers.Done();serveDNS(u,cfg.Nonce,&dnsCount)}()
 }
 fmt.Println("PEER_QA_READY_server")'''),
    ('75 * time.Second','120 * time.Second'),
    ('sent, received := bind.stats()','if cfg.DNS {fmt.Printf("WG_DNS_A_WITNESS %d\\n",dnsCount.Load())}\n sent, received := bind.stats()')
])
edit("client.go",[
    ('if d.IpcSet(cfg) != nil || d.Up() != nil {','if c.DNS {cfg+="allowed_ip=192.0.2.53/32\\n"}\n if d.IpcSet(cfg) != nil || d.Up() != nil {'),
    ('if !positive {','if c.DNS {if !positive || !requestDNS(c,stack){return 8};kinds=[]string{"tcp4"}}\n if !positive {')
])
