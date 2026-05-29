package com.example.wifi_hub.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import android.os.Build
import android.util.Log

/**
 * ProxyService — Android foreground service that runs a SOCKS5 proxy server.
 *
 * Lifecycle:
 *   startForegroundService() → onStartCommand() → startForeground() [<5s]
 *   → coroutine loop: accept() → handle each connection → repeat
 *   stopService() → onDestroy() → serverSocket.close() → loop exits cleanly
 *
 * The SOCKS5 protocol has 3 stages per connection:
 *   1. Greeting  — client says hello, we say "no auth needed"
 *   2. Request   — client says "connect me to host:port"
 *   3. Pipe      — we open that connection and copy bytes both ways
 */

class ProxyService: Service(){
    companion object{
        const val PORT = 1080
        const val CHANNEL_ID = "proxy_channel"
        const val NOTIF_ID = 1
        const val COORDINATOR_URL = "coordinator_url"
    }
    private val coroutine1 = CoroutineScope(Dispatchers.IO+SupervisorJob())
    private var serverSocket : ServerSocket?=null
    private var wsClient: ContributorWebSocket?=null
    private var utils= Socks5Utils()

    //lifecycle
    override fun onBind(intent: Intent?): IBinder?= null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())

        coroutine1.launch{
            runeProxyServer()
        }

        val coordinatorUrl = intent?.getStringExtra(COORDINATOR_URL)
        if (coordinatorUrl!=null){
            wsClient = ContributorWebSocket(coordinatorUrl, coroutine1)
            wsClient?.connect()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        serverSocket?.close()
        wsClient?.disconnect()
        coroutine1.cancel()
    }

    //proxy server function, basically the socks5 running code

    private fun runeProxyServer(){
        try{
            serverSocket = ServerSocket(PORT)
            while(true){
                val clientSocket = serverSocket!!.accept()
                coroutine1.launch{
                    handleConnection(clientSocket)
                }
            }
        }catch(e: SocketException){

        }catch(e: Exception){
            e.printStackTrace()
        }
    }

    private suspend fun handleConnection(client: Socket){
        try{
            client.use{
                val input = client.getInputStream()
                val output = client.getOutputStream()

                if (!utils.doGreeting(input, output)) return
                //right now setup connection with just one device, later on this part will be expanded and the contributor screen will come into play
                val contributor = utils.parseRequest(input, output)?: return
                connectAndPipe(client, input, output, contributor.first, contributor.second)

            }
        }catch(e:Exception){

        }
    }

    // ── Stage 1: SOCKS5 Greeting ──────────────────────────────────────────────
    //
    // Client sends:  [0x05, nMethods, method1, method2, ...]
    //   0x05       = SOCKS version 5
    //   nMethods   = how many auth methods the client supports
    //   methods    = list of method IDs (0x00 = no auth)
    //
    // We reply:     [0x05, 0x00]
    //   0x05       = SOCKS version 5
    //   0x00       = we chose "no authentication"


    // ── Stage 3: Connect to target and pipe bytes both ways ───────────────────
    //
    // We open a TCP socket to (host, port) using the phone's cellular data.
    // Then we launch two coroutines:
    //   client → target : copies bytes from Chrome to google.com
    //   target → client : copies bytes from google.com back to Chrome
    // When either side closes, both coroutines stop.
    private suspend fun connectAndPipe(client: Socket, clientIn: InputStream, clientOut: OutputStream, host:String, port:Int){
        try{
            Socket(host, port).use{ target->
                val targetIn = target.getInputStream()
                val targetOut = target.getOutputStream()

                coroutineScope {
                    val clientToTarget = launch (Dispatchers.IO){
//                            try{clientIn.copyTo(targetOut)}catch(e: Exception){}
                        relay(clientIn, targetOut, "CLIENT -> TARGET")
                    }
                    val targetToClient = launch(Dispatchers.IO ){
//                            try{targetIn.copyTo(clientOut)}catch(e: Exception){}
                        relay(targetIn, clientOut, "TARGET -> CLIENT")
                    }
                    clientToTarget.join()
                    targetToClient.join()
                }

            }
        }catch(e: Exception){
            //target unreachable connection will silently fail
        }
    }


    // ── Notification helpers

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Proxy Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Community Hotspot proxy is running"
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("You are now a contributor")
            .setContentText("SOCKS5 proxy active on port $PORT")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)           // can't be swiped away
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    private fun ByteArray.toHexString(length: Int): String {
        return (0 until length).joinToString(" ") {
            "%02X".format(this[it])
        }
    }
    suspend fun relay(
        input: InputStream,
        output: OutputStream,
        tag: String
    ) {
        val buffer = ByteArray(8192)

        while (true) {
            val bytesRead = input.read(buffer)

            if (bytesRead == -1) {
                Log.d("SOCKS", "$tag CLOSED")
                break
            }

            Log.d(
                "SOCKS",
                "$tag RECEIVED ($bytesRead bytes): ${
                    buffer.toHexString(bytesRead)
                }"
            )

            Log.d(
                "SOCKS",
                "$tag TEXT: ${
                    String(buffer, 0, bytesRead)
                }"
            )

            output.write(buffer, 0, bytesRead)
            output.flush()

            Log.d("SOCKS", "$tag FORWARDED")
        }
    }
}


