// iOS candidate DNS destination classification. Does not install routes or
// authorize direct egress. Preserve the old classifier's exact boundary,
// including its narrower fe80: prefix and IPv4-mapped address treatment.
use std::net::IpAddr;
pub(crate) fn is_private_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => v.is_private() || v.is_loopback() || v.is_link_local() || (u32::from(v) >> 17 == 0x6309),
        IpAddr::V6(v) => {
            if let Some(m) = v.to_ipv4_mapped() {
                return m.is_private() || m.is_loopback() || m.is_link_local();
            }
            v.is_unique_local() || v.segments()[0] == 0xfe80 || v.is_loopback() || v.is_unspecified()
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn boundary_vectors() {
        for (s,expected) in [("10.0.0.0",true),("11.0.0.0",false),("172.15.255.255",false),("172.16.0.0",true),("172.31.255.255",true),("172.32.0.0",false),("192.168.0.1",true),("127.0.0.1",true),("169.254.1.1",true),("198.17.255.255",false),("198.18.0.0",true),("198.19.255.255",true),("198.20.0.0",false),("0.0.0.0",false),("100.64.0.1",false),("224.0.0.1",false),("::",true),("::1",true),("fc00::1",true),("fdff::1",true),("fe80::1",true),("fe81::1",false),("febf::1",false),("2001:db8::1",false),("::ffff:10.0.0.1",true),("::ffff:198.18.0.1",false),("::ffff:127.0.0.1",true),("::ffff:8.8.8.8",false)] {
            assert_eq!(is_private_ip(s.parse().unwrap()),expected,"{s}");
        }
    }
}
