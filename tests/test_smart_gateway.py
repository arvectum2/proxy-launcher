"""Real TLS CONNECT E2E: two virtual names at same IP, different egress."""
import asyncio
import base64
import hashlib
import json
import shutil
import socket
import ssl
import subprocess
import tempfile
import unittest
from pathlib import Path
from free_gateway.config import UpstreamProxy
from free_gateway.smart import SmartAccount, SmartGateway, connect_authority, exact_host

def basic(user, password):
    return 'Basic '+base64.b64encode(f'{user}:{password}'.encode()).decode()

async def origin(reader, writer, label):
    try:
        await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'),timeout=5)
        writer.write(b'HTTP/1.1 200 OK\r\nX-APL-Egress: '+label.encode()+b'\r\nContent-Length: 2\r\n\r\nOK')
        await writer.drain()
    finally:
        writer.close()

class SmartGatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        if not shutil.which('openssl'):
            self.skipTest('openssl needed for a temporary test-only TLS certificate')
        self.temp=tempfile.TemporaryDirectory()
        cert,key=Path(self.temp.name)/'cert.pem',Path(self.temp.name)/'key.pem'
        subprocess.run(['openssl','req','-x509','-nodes','-newkey','rsa:2048',
            '-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=site.test',
            '-addext','subjectAltName=DNS:site.test,DNS:api.site.test,DNS:static.site.test,DNS:tracker.other.test'],
            check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        self.cert=str(cert)
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert),str(key))
        self.direct=await asyncio.start_server(lambda r,w:origin(r,w,'DIRECT'),'127.0.0.1',0,ssl=context)
        self.proxied=await asyncio.start_server(lambda r,w:origin(r,w,'SUPPLIER'),'127.0.0.1',0,ssl=context)
        self.direct_port=self.direct.sockets[0].getsockname()[1]
        self.proxy_port=self.proxied.sockets[0].getsockname()[1]
        self.proxied_targets=[]
        self.supplier=await asyncio.start_server(self.supplier_connect,'127.0.0.1',0)
        upstream=UpstreamProxy('lab','Lab','ZZ','127.0.0.1',self.supplier.sockets[0].getsockname()[1])
        account=SmartAccount('lab-user',hashlib.sha256(b'a-secret-test-token').hexdigest(),'lab')
        self.smart=SmartGateway({'lab':upstream},[account],test_connector=self.open_test_origin)
        self.listener=await asyncio.start_server(self.smart.handle,'127.0.0.1',0)
        self.port=self.listener.sockets[0].getsockname()[1]

    async def open_test_origin(self,host,port):
        self.assertEqual(port,443)
        return await asyncio.open_connection('127.0.0.1',self.direct_port)

    async def supplier_connect(self,reader,writer):
        remote=None
        try:
            head=await reader.readuntil(b'\r\n\r\n')
            authority=head.split(b' ',2)[1].decode()
            self.proxied_targets.append(authority)
            source,remote=await asyncio.open_connection('127.0.0.1',self.proxy_port)
            writer.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            await writer.drain()
            async def pump(src,dst):
                while data:=await src.read(8192):
                    dst.write(data)
                    await dst.drain()
            tasks=[asyncio.create_task(pump(reader,remote)),asyncio.create_task(pump(source,writer))]
            done,pending=await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
            for task in pending:task.cancel()
            await asyncio.gather(*tasks,return_exceptions=True)
        except (OSError,asyncio.IncompleteReadError):pass
        finally:
            if remote:remote.close()
            writer.close()

    async def asyncTearDown(self):
        for server in (self.listener,self.supplier,self.direct,self.proxied):
            server.close()
            await server.wait_closed()
        self.temp.cleanup()
    async def put_policy(self,domains,password='a-secret-test-token'):
        payload=json.dumps({'domains':domains}).encode()
        req=(f'PUT /v1/smart/policy HTTP/1.1\r\nHost: gateway.test\r\n'
            f'Authorization: {basic("lab-user",password)}\r\nContent-Length: {len(payload)}\r\n\r\n').encode()+payload
        reader,writer=await asyncio.open_connection('127.0.0.1',self.port)
        writer.write(req)
        await writer.drain()
        answer=await asyncio.wait_for(reader.read(),timeout=4)
        writer.close()
        await writer.wait_closed()
        return answer

    def client_tls_sync(self,host,password='a-secret-test-token'):
        with socket.create_connection(('127.0.0.1',self.port),timeout=4) as raw:
            req=(f'CONNECT {host}:443 HTTP/1.1\r\nHost: {host}:443\r\n'
                 f'Proxy-Authorization: {basic("lab-user",password)}\r\n\r\n').encode()
            raw.sendall(req)
            reply=b''
            while b'\r\n\r\n' not in reply:
                more=raw.recv(4096)
                if not more:break
                reply+=more
            if b'200 Connection Established' not in reply:
                return reply
            context=ssl.create_default_context(cafile=self.cert)
            with context.wrap_socket(raw,server_hostname=host) as client:
                client.sendall(f'GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n'.encode())
                data=b''
                while more:=client.recv(4096):data+=more
                return data

    async def test_real_tls_same_ip_precise_direct_and_upstream(self):
        self.assertIn(b'SUPPLIER',await asyncio.to_thread(self.client_tls_sync,'site.test'))
        self.assertIn(b'200 OK',await self.put_policy(['site.test','api.site.test','static.site.test']))
        for host in ('site.test','api.site.test','static.site.test'):
            data=await asyncio.to_thread(self.client_tls_sync,host)
            self.assertIn(b'X-APL-Egress: DIRECT',data)
        other=await asyncio.to_thread(self.client_tls_sync,'tracker.other.test')
        self.assertIn(b'X-APL-Egress: SUPPLIER',other)
        self.assertEqual(self.proxied_targets,['site.test:443','tracker.other.test:443'])
        self.assertEqual(len(self.smart.policy['lab-user']),3)
        print('REAL_TLS_SHARED_IP: site/API/CSS DIRECT, unrelated SUPPLIER')

    async def test_auth_policy_revoke_and_fail_closed(self):
        self.assertIn(b'401 Unauthorized',await self.put_policy(['site.test'],password='wrong'))
        self.assertIn(b'400 Bad Request',await self.put_policy(['*.site.test']))
        self.assertIn(b'200 OK',await self.put_policy(['site.test']))
        self.assertIn(b'DIRECT',await asyncio.to_thread(self.client_tls_sync,'site.test'))
        self.assertIn(b'200 OK',await self.put_policy([]))
        self.assertIn(b'SUPPLIER',await asyncio.to_thread(self.client_tls_sync,'site.test'))
        self.assertIn(b'407 Proxy Authentication Required',
                      await asyncio.to_thread(self.client_tls_sync,'site.test',password='wrong'))
        self.supplier.close()
        await self.supplier.wait_closed()
        result=await asyncio.to_thread(self.client_tls_sync,'tracker.other.test')
        self.assertNotIn(b'200 Connection Established',result)

    async def test_policy_expiration_revokes_remote_direct_without_client_reconnect(self):
        clock = [1000.0]
        self.smart.clock = lambda: clock[0]
        self.assertIn(b'200 OK',await self.put_policy(['site.test']))
        self.assertIn(b'DIRECT',await asyncio.to_thread(self.client_tls_sync,'site.test'))
        clock[0] += 181
        self.assertIn(b'SUPPLIER',await asyncio.to_thread(self.client_tls_sync,'site.test'))

    def test_hostname_validation(self):
        for invalid in ('*.site.test','site.test.evil/','site..test','localhost','192.0.2.1'):
            with self.assertRaises(ValueError):exact_host(invalid)
        self.assertEqual(exact_host('SITE.TEST.'),'site.test')
        self.assertEqual(connect_authority('site.test:443'),('site.test',443,True))
        self.assertEqual(connect_authority('192.0.2.1:443'),('192.0.2.1',443,False))
        self.assertEqual(connect_authority('site.test:22'),('site.test',22,True))
        with self.assertRaises(ValueError):connect_authority('site.test:0')
