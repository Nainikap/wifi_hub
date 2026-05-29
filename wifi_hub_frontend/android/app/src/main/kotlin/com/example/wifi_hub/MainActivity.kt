package com.example.wifi_hub
import com.example.wifi_hub.services.ProxyService

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.net.wifi.WifiManager
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.Proxy
import android.os.Build


class MainActivity : FlutterActivity(){
    private val CHANNEL = "com.example.wifi_hub/proxy";
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                1001
            )
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when(call.method){
                "startProxy" ->{
                    android.util.Log.d("PROXY", "startProxy received")

                    try{
                        val coordinatorUrl = call.argument<String>("coordinatorUrl")
                        val intent = Intent(this, ProxyService::class.java)
                        if(coordinatorUrl!=null){
                            intent.putExtra(ProxyService.COORDINATOR_URL, coordinatorUrl)
                        }
                        startForegroundService(intent)
                        val ip = getHotspotIP()
                        result.success(ip)
                    }catch(e: Exception){
                        result.error(
                            "STRT FAILED",
                            e.message,
                            null
                        )
                    }
                }
                "stopProxy" -> {
                    android.util.Log.d("ProxyService", "stopProxy called from Flutter")
                    try{
                        val intent = Intent(this, ProxyService::class.java)
                        stopService(intent)
                        result.success(null)
                    }catch(e: Exception){
                        result.error(
                            "STRT FAILED",
                            e.message,
                            null
                        )
                    }
                }
                "getHotspotIP" ->{
                    result.success(getHotspotIP())
                }
                else -> result.notImplemented()
            }
        }
    }
    /**
     * Returns the phone's hotspot gateway IP.
     *
     * When you enable hotspot, Android typically assigns itself
     * 192.168.43.1 as the gateway. We read it via WifiManager
     * and convert from the int representation Android uses.
     *
     * Falls back to "192.168.43.1" if the IP can't be determined —
     * this is correct on ~95% of Android devices.
     */
    private fun getHotspotIP(): String{
        return try{
            val WifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val dhcp = WifiManager.dhcpInfo
            val ip = dhcp.gateway
            InetAddress.getByAddress(
                byteArrayOf(
                    (ip and 0xFF).toByte(),
                    (ip shr 8 and 0xFF).toByte(),
                    (ip shr 16 and 0xFF).toByte(),
                    (ip shr 24 and 0xFF).toByte(),
                )
            ).hostAddress ?: "192.168.43.1"
        } catch(e: Exception){
            "192.168.43.1"
        }
    }
}
