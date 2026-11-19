// Appended only to a disposable host test translation unit. No TUN or external network.
#[cfg(test)]
#[path = "ios_dns_address_classification.rs"]
mod no_tproxy_test_classifier;
#[cfg(test)]
mod no_tproxy_host_regression {
    use super::*;
    use super::no_tproxy_test_classifier as replacement;
    #[test]
    fn compares_pinned_reference_boundary_classes() {
        use std::net::{Ipv4Addr,Ipv6Addr};
        let mut addresses=Vec::new();
        for a in 0..=255u8 {
            for b in [0,16,18,19,20,31,32,63,64,168,254,255] {
                let v=Ipv4Addr::new(a,b,23,45);
                addresses.push(IpAddr::V4(v));addresses.push(IpAddr::V6(v.to_ipv6_mapped()));
            }
        }
        for first in [0,1,0x2000,0x2001,0xfc00,0xfc01,0xfd00,0xfdff,0xfe00,0xfe7f,0xfe80,0xfe81,0xfebf,0xfec0,0xff00,0xffff] {
            addresses.push(IpAddr::V6(Ipv6Addr::new(first,0,0,0,0,0,0,1)));
            addresses.push(IpAddr::V6(Ipv6Addr::new(first,1,2,3,4,5,6,7)));
        }
        addresses.extend(["::".parse::<IpAddr>().unwrap(),"::1".parse().unwrap()]);
        for address in &addresses {assert_eq!(replacement::is_private_ip(*address),tproxy_config::is_private_ip(*address),"{address}");}
        println!("DNS_REFERENCE_CLASSIFIER_COMPARISON_PASS_{}",addresses.len());
    }
    #[tokio::test]
    async fn actual_connected_udp_helper_preserves_datagrams_and_local_family() {
        for host in ["127.0.0.1:0","[::1]:0"] {
            let relay=UdpSocket::bind(host).await.unwrap();let target=relay.local_addr().unwrap();
            let client=create_udp_stream(&None,target).await.unwrap();
            assert_eq!(client.peer_addr().unwrap(),target);assert!(client.local_addr().unwrap().ip().is_loopback());assert_eq!(client.local_addr().unwrap().is_ipv4(),target.is_ipv4());
            for payload in [vec![1],vec![2;257],vec![3;1200]] {
                assert_eq!(client.send(&payload).await.unwrap(),payload.len());
                let mut buffer=[0u8;1500];
                let (n,source)=tokio::time::timeout(std::time::Duration::from_secs(2),relay.recv_from(&mut buffer)).await.unwrap().unwrap();
                assert_eq!(&buffer[..n],&payload);assert_eq!(source,client.local_addr().unwrap());
                assert_eq!(relay.send_to(&payload,source).await.unwrap(),payload.len());
                let n=tokio::time::timeout(std::time::Duration::from_secs(2),client.recv(&mut buffer)).await.unwrap().unwrap();assert_eq!(&buffer[..n],&payload);
            }
        }
        println!("CONNECTED_UDP_LOOPBACK_PASS_6_OF_6");
    }
}
