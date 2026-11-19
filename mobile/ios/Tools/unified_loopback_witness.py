#!/usr/bin/env python3
"""Local-only witness exercise, never a LAN server or physical VPN proof."""
import hashlib,socket,time

class LoopbackWitness:
    def __init__(self,kind,probe,nonce,*,physical_qa_contract=False):
        if kind not in ('wireGuard','amneziaWG1','vlessReality') or probe not in ('tcp4','tcp6','udp4','udp6') or (kind=='vlessReality' and probe!='tcp4' and not physical_qa_contract):raise ValueError('unsupported witness')
        if len(nonce)!=(48 if kind=='amneziaWG1' else 40) or any(c not in '0123456789abcdef' for c in nonce):raise ValueError('invalid nonce')
        self.physical_qa_contract=physical_qa_contract
        self.probe=probe;self.awg=kind=='amneziaWG1';self.udp=probe.startswith('udp');self.nonce=nonce
        self.count=0;self.replies=0;self.closed=False
    @property
    def request(self):
        if self.awg:return self.nonce.encode()
        if self.udp:return ('APL_UDP:'+self.nonce).encode()
        # Matches the physical QA harness's literal HTTP authority, without
        # ever opening a non-loopback socket or asserting real peer reachability.
        authority='witness.invalid'
        if self.physical_qa_contract:
            authority='198.51.100.77:39883' if self.probe.endswith('4') else '[2001:db8:77::77]:39883'
        return ('GET /'+self.nonce+' HTTP/1.1\r\nHost: '+authority+'\r\nConnection: close\r\n\r\n').encode()
    @property
    def body(self):return (('APL:' if self.awg else 'APL_RECEIPT:')+self.nonce).encode()
    def payload(self,raw):
        if self.closed or raw!=self.request:return None
        self.count+=1
        if self.awg or self.udp:return self.body
        return b'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: '+str(len(self.body)).encode()+b'\r\n\r\n'+self.body
    def serve(self,s,maximum=3):
        # Caller can supply only a loopback-bound socket. No wildcard/public or
        # arbitrary relay, no externally controlled destination.
        if s.getsockname()[0] not in ('127.0.0.1','::1') or not 1<=maximum<=4:raise ValueError('local witness only')
        if s.family!=(socket.AF_INET if self.probe.endswith('4') else socket.AF_INET6) or s.type!=(socket.SOCK_DGRAM if self.udp else socket.SOCK_STREAM):raise ValueError('family/transport mismatch')
        end=time.monotonic()+2
        try:
            for _ in range(maximum):
                s.settimeout(max(.001,end-time.monotonic()))
                try:
                    if self.udp:
                        raw,peer=s.recvfrom(257);reply=self.payload(raw)
                        if reply is not None and s.sendto(reply,peer)==len(reply):self.replies+=1
                    else:
                        peer,_=s.accept()
                        with peer:
                            peer.settimeout(max(.001,end-time.monotonic()));raw=b''
                            while len(raw)<len(self.request):
                                part=peer.recv(257-len(raw))
                                if not part:break
                                raw+=part
                            reply=self.payload(raw)
                            if reply is not None:peer.sendall(reply);self.replies+=1
                except (TimeoutError,OSError):break
                if time.monotonic()>=end:break
        finally:self.closed=True
    def observation(self):
        if not self.closed:raise ValueError('observer still open')
        return {'scope':'local witness smoke only; not tunnel/peer transport evidence','matches':self.count,'responses':self.replies,'responseSHA256':hashlib.sha256(self.body).hexdigest() if self.replies else None,'runtime_authorized':False}
