import 'dart:io';

InternetAddress? lanBroadcastAddressFor(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) {
    return null;
  }
  return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
}
