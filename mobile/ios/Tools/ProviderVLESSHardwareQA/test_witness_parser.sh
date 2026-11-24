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
print("SCOPED_TCP_WITNESS_PARSER_9_PASS")
SWIFT
xcrun swiftc "$root/ScopedTCPWitness.swift" "$temp/main.swift" -o "$temp/check"
"$temp/check"
