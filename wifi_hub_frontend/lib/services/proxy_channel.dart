import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

//poc for dart files and kotlin code files
//establishes socks5, makes the calls to socks5 etc
class ProxyChannel{
static const _channel = MethodChannel('com.example.wifi_hub/proxy');
  static Future<String> startProxy() async{
    final ip = await _channel.invokeMethod('startProxy', {
      'coordinatorUrl': 'ws://coordinator-ip:8080/pool',
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
}