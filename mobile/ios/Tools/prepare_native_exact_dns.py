#!/usr/bin/env python3
"""New isolated Rust candidate; preserve captured DNS destinations, not a DIRECT bypass."""
import hashlib,json,pathlib,sys,subprocess
from prepare_ios_rust_without_tproxy import prepare,replace,sha
from verify_ios_no_tproxy_receipt import RECEIPT,ARCHIVE
T=pathlib.Path(__file__).resolve().parent

def prepare_exact(source,work):
    prepare(source,work)
    src=work/'src/src'
    a=src/'args.rs'
    replace(a,'    pub dns: ArgDns,','''    pub dns: ArgDns,

    /// Native review: do not rewrite intercepted DNS destinations.
    /// Restricted to the local Xray SOCKS5 transport, never direct egress.
    #[arg(long, default_value_t = false)]
    #[serde(default)]
    pub native_exact_dns: bool,''')
    replace(a,'            dns: ArgDns::default(),','            dns: ArgDns::default(),\n            native_exact_dns: false,')
    i=a.read_text().index('impl Args {')+len('impl Args {')
    text=a.read_text()
    a.write_text(text[:i]+'''
    pub(crate) fn validate_native_exact_dns(&self) -> Result<()> {
        if !self.native_exact_dns {return Ok(());}
        #[cfg(not(target_os = "ios"))]
        if !cfg!(test) {return Err(Error::from("native exact DNS requires iOS"));}
        if self.dns != ArgDns::Direct || self.proxy.proxy_type != ProxyType::Socks5
            || self.proxy.addr != "127.0.0.1:39879".parse::<SocketAddr>().unwrap()
            || self.proxy.credentials.is_some() || self.setup || !self.ipv6_enabled
            || !self.bypass.is_empty() || !self.dns_bypass.is_empty()
            || !self.flow_direct_candidate.is_empty() || self.experimental_scoped_direct {
            return Err(Error::from("invalid native exact DNS scope"));
        }
        #[cfg(unix)]
        if self.tun_fd.is_none() || self.close_fd_on_drop != Some(false) {
            return Err(Error::from("native exact DNS requires borrowed descriptor"));
        }
        #[cfg(feature = "udpgw")]
        if self.udpgw_server.is_some() {return Err(Error::from("native exact DNS requires SOCKS UDP"));}
        Ok(())
    }
'''+text[i:])
    l=src/'lib.rs'
    replace(l,'    log::info!("{} {} starting...", env!("CARGO_PKG_NAME"), version_info!());','    args.validate_native_exact_dns()?;\n    log::info!("{} {} starting...", env!("CARGO_PKG_NAME"), version_info!());')
    replace(l,'                    if is_private_ip(info.dst.ip()) {\n                        info.dst.set_ip(dns_addr); // !!! Here we change the destination address to remote DNS server!!!\n                    }','                    info.dst = dns_destination(info.dst, dns_addr, args.native_exact_dns);')
    replace(l,'const DNS_PORT: u16 = 53;','''const DNS_PORT: u16 = 53;
fn dns_destination(mut dst: SocketAddr, legacy_resolver: IpAddr, preserve: bool) -> SocketAddr {
    if !preserve && dst.port() == DNS_PORT && is_private_ip(dst.ip()) {
        dst.set_ip(legacy_resolver);
    }
    dst
}
#[cfg(test)]
mod native_exact_dns_tests {
    use super::*;
    #[test]
    fn native_exact_dns_keeps_resolvers_and_rejects_non_socks_scope() {
        let legacy="8.8.8.8".parse().unwrap();
        for raw in ["10.0.0.53:53","[fd00::53]:53","192.0.2.53:53","[2001:db8::53]:53","10.0.0.53:54"] {
            let addr:SocketAddr=raw.parse().unwrap();
            assert_eq!(dns_destination(addr,legacy,true),addr);
            let mut old=addr;
            if addr.port()==53 && is_private_ip(addr.ip()) {old.set_ip(legacy);}
            assert_eq!(dns_destination(addr,legacy,false),old);
        }
        let mut a=<Args as clap::Parser>::try_parse_from(["tun2proxy-bin","--proxy","socks5://127.0.0.1:39879","--tun-fd","3","--close-fd-on-drop","false","--dns","direct","--ipv6-enabled","--native-exact-dns"]).unwrap();
        assert!(a.validate_native_exact_dns().is_ok());
        a.dns=ArgDns::Virtual;assert!(a.validate_native_exact_dns().is_err());
        a.dns=ArgDns::Direct;a.experimental_scoped_direct=true;assert!(a.validate_native_exact_dns().is_err());
        a.experimental_scoped_direct=false;a.proxy.proxy_type=ProxyType::None;assert!(a.validate_native_exact_dns().is_err());
    }
}''')
    g=src/'general_api.rs'
    replace(g,'    let args = <Args as ::clap::Parser>::parse_from(args);','    let Ok(args) = <Args as ::clap::Parser>::try_parse_from(args) else {return -7;};\n    if args.validate_native_exact_dns().is_err() {return -7;}')
    replace(g,'    let mut tun_config = tun::Configuration::default();','    args.validate_native_exact_dns().map_err(std::io::Error::other)?;\n    let mut tun_config = tun::Configuration::default();')
    # Reuse the same dependencies and notices, not an old binary receipt.
    manifest={'schema':1,'base_receipt_sha256':RECEIPT,'base_archive_sha256':ARCHIVE,'preparation_sha256':sha(work/'preparation.json'),'script_sha256':sha(T/'prepare_native_exact_dns.py'),'source_sha256':{p.relative_to(work/'src').as_posix():sha(p) for p in sorted((work/'src').rglob('*')) if p.is_file() and not p.is_symlink()},'runtime_authorized':False,'release_authorized':False}
    (work/'exact-dns-source.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
if __name__=='__main__':prepare_exact(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
