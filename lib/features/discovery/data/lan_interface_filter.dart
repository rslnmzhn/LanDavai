final RegExp _nonLanInterfaceTokenPattern = RegExp(
  r'(?:^|[-_.\s])(?:tun|utun|tap|wg|ppp|pptp|l2tp|ipsec|xfrm|rmnet|ccmni|pdp_ip|wwan|clat|dummy|ifb|sit|gre|vti|ip6tnl|ovpn|warp|lo)(?:[-_.\d]|$)',
);

const List<String> _nonLanInterfaceProductHints = <String>[
  'wireguard',
  'tailscale',
  'zerotier',
  'hamachi',
  'clash',
  'sing-box',
  'singbox',
  'nekobox',
  'v2ray',
  'xray',
  'amnezia',
  'openvpn',
  'proton',
  'mullvad',
  'nordlynx',
];

bool isNonLanInterfaceName(String interfaceName) {
  final lower = interfaceName.trim().toLowerCase();
  if (lower.isEmpty) {
    return false;
  }
  if (_nonLanInterfaceTokenPattern.hasMatch(lower)) {
    return true;
  }
  return _nonLanInterfaceProductHints.any(lower.contains);
}
