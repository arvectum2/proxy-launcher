#!/bin/bash
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")" && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cat > "$temp/main.swift" <<'SWIFT'
import Foundation
let inbound:[String:Any]=["tag":"apl-local","listen":"127.0.0.1","port":39879,"protocol":"socks"]
let outbound:[String:Any]=["tag":"apl-vless","protocol":"vless","settings":["address":"192.168.1.80","port":39882],"streamSettings":["sockopt":["interface":"en0"]]]
let input:[String:Any]=["inbounds":[inbound],"outbounds":[outbound],"routing":["rules":[]],"log":["loglevel":"none"]]
func encode(_ v:[String:Any])->Data {try! JSONSerialization.data(withJSONObject:v,options:.sortedKeys)}
let guarded=try FullRouteGuard.restrict(encode(input))
let root=try JSONSerialization.jsonObject(with:guarded) as! [String:Any]
let exits=root["outbounds"] as! [[String:Any]]
precondition(exits.count==2 && exits[0]["protocol"] as? String=="blackhole" && exits[1]["tag"] as? String=="apl-vless")
precondition(encode(exits[1])==encode(outbound))
let rules=(root["routing"] as! [String:Any])["rules"] as! [[String:Any]]
precondition(rules.count==2 && rules[0]["ip"] as? [String]==["198.51.100.77/32"] && rules[0]["port"] as? String=="39883" && rules[0]["network"] as? String=="tcp" && rules[0]["outboundTag"] as? String=="apl-vless")
precondition(rules[1]["outboundTag"] as? String=="qa-drop" && rules[1]["network"] as? String=="tcp,udp")
func rejected(_ v:[String:Any])->Bool {(try? FullRouteGuard.restrict(encode(v)))==nil}
var changed=input
changed["outbounds"]=[outbound,outbound];precondition(rejected(changed))
changed=input;changed["inbounds"]=[inbound,inbound];precondition(rejected(changed))
var altered=outbound;altered["settings"]=["address":"203.0.113.9","port":39882]
changed=input;changed["outbounds"]=[altered];precondition(rejected(changed))
altered=outbound;altered["streamSettings"]=["sockopt":["interface":"pdp_ip0"]]
changed=input;changed["outbounds"]=[altered];precondition(rejected(changed))
changed=input;changed["api"]=[:];precondition(rejected(changed))
let tuples:[(FixedWitnessKind,String,String)]=[(.tcp4,"198.51.100.77/32","tcp"),(.tcp6,"2001:db8:77::77/128","tcp"),(.udp4,"198.51.100.77/32","udp"),(.udp6,"2001:db8:77::77/128","udp")]
for (kind,cidr,network) in tuples {
    let root=try JSONSerialization.jsonObject(with:FullRouteGuard.restrict(encode(input),kind:kind)) as! [String:Any]
    let rules=(root["routing"] as! [String:Any])["rules"] as! [[String:Any]]
    precondition(rules.count==2 && rules[0]["ip"] as? [String]==[cidr] && rules[0]["network"] as? String==network && rules[0]["port"] as? String=="39883" && rules[1]["outboundTag"] as? String=="qa-drop")
}
precondition(FixedWitnessKind(rawValue:"dns4")==nil)
print("FULL_ROUTE_GUARD_14_PASS")
SWIFT
xcrun swiftc "$root/FixedWitnessKind.swift" "$root/FullRouteGuard.swift" "$temp/main.swift" -o "$temp/check"
"$temp/check"
