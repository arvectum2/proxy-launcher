#!/bin/bash
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")" && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cat > "$temp/main.swift" <<'SWIFT'
import Foundation
let nonce=String(repeating:"a",count:40)
let body="APL_RECEIPT:"+nonce
func response(_ status:String="200 OK",_ length:Int=52,_ content:String,_ extra:String="")->Data {
    Data(("HTTP/1.0 "+status+"\r\nContent-Length: "+String(length)+"\r\n"+extra+"\r\n"+content).utf8)
}
precondition(ScopedTCPWitness.matches(response("200 OK",body.utf8.count,body),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("404 Not Found",body.utf8.count,body),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("200 OK",body.utf8.count,body+"x"),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("200 OK",1,body),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("200 OK",body.utf8.count,body,"Content-Length: 52\r\n"),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("200 OK",body.utf8.count,body,"Transfer-Encoding: chunked\r\n"),nonce:nonce))
precondition(!ScopedTCPWitness.matches(response("200 OK",body.utf8.count,body),nonce:String(repeating:"b",count:40)))
precondition(!ScopedTCPWitness.matches(Data(body.utf8),nonce:nonce))
precondition(ScopedTCPWitness.run("invalid").counters.isEmpty)
precondition(FixedUDPWitness.matches(Data(body.utf8),nonce:nonce))
precondition(!FixedUDPWitness.matches(Data((body+"x").utf8),nonce:nonce))
precondition(!FixedUDPWitness.matches(Data(body.utf8),nonce:String(repeating:"b",count:40)))
precondition(FixedUDPWitness.run(nonce,kind:.tcp6).counters.isEmpty)
precondition(FixedUDPWitness.run("invalid",kind:.udp6).counters.isEmpty)
precondition(ScopedTCPWitness.run(nonce,kind:.udp4).counters.isEmpty)
let dns=FixedDNSWire.expected(nonce)
precondition(FixedDNSWire.query(nonce).count==70)
precondition(dns.count==86)
precondition(FixedDNSWire.matches(dns,nonce:nonce))
precondition(!FixedDNSWire.matches(dns,nonce:String(repeating:"b",count:40)))
precondition(!FixedDNSWire.matches(dns+Data([0]),nonce:nonce))
precondition(!FixedDNSWire.matches(Data(),nonce:"invalid"))
print("TCP_UDP_DNS_WITNESS_21_PASS")
SWIFT
xcrun swiftc "$root/FixedWitnessKind.swift" "$root/ScopedTCPWitness.swift" "$root/FixedUDPWitness.swift" "$root/FixedDNSWire.swift" "$temp/main.swift" -o "$temp/check"
"$temp/check"
