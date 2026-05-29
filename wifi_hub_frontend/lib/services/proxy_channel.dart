import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

//poc for dart files and kotlin code files
//establishes socks5, makes the calls to socks5 etc
class ProxyChannel{
static const _channel = MethodChannel('com.example.wifi_hub/proxy');
  static Future<String> startProxy() async{
    final ip = await _channel.invokeMethod('startProxy', {
      'coordinatorUrl': 'ws://10.192.81.60:8080/pool',
    });
    return ip;
  }
  static Future<void> stopProxy() async{
    await _channel.invokeMethod('stopProxy');
  }
  static Future<String> getHotspotIP() async{
    final ip = await _channel.invokeMethod('getHotspotIP');
    return ip;
  }
static Future<Map<String, int>> getStats() async {
  final result = await _channel.invokeMapMethod<String, int>('getStats');
  return result ?? {'bytesUp': 0, 'bytesDown': 0};
}
}