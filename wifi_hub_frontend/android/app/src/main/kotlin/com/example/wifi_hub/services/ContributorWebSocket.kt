package com.example.wifi_hub.services

import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Manages the contributor's outbound WebSocket connection to the coordinator.
 *
 * Responsibilities:
 *  - Connect to coordinator and register as available
 *  - Receive multiplexed tunnel frames and dispatch to TunnelSession instances
 *  - Forward local proxy replies back to the coordinator
 *  - Reconnect automatically on disconnect (with backoff)
 *
 * Frame format (binary WebSocket messages):
 *   [4 bytes big-endian: tunnelId][1 byte: type][remaining bytes: payload]
 *
 *   Types:
 *     0x01 DATA     payload = raw bytes
 *     0x02 OPEN     parses host:port from payload, creates a TunnelSession
 *     0x03 CLOSE    either side closing tunnel
 *     0x04 REGISTER contributor → coordinator (payload = optional metadata JSON)
 *     0x05 ACK      coordinator confirms registration
 */

class ContributorWebSocket(
    private val coordinatorUrl: String,
    private val scope: CoroutineScope
){
    companion object{
        private const val TAG = "ContribWS"

        const val TYPE_DATA = 0X01.toByte()
        const val TYPE_OPEN = 0X02.toByte()
        const val TYPE_CLOSE = 0X03.toByte()
        const val TYPE_REGISTER = 0X04.toByte()
        const val TYPE_ACK = 0X05.toByte()

    }

    private val client = OkHttpClient.Builder()
        .readTimeout(0,TimeUnit.MILLISECONDS)
        .build()
    private var webSocket: WebSocket?= null
    private var activeTunnels = ConcurrentHashMap<Int, TunnelSession>()
    private var isRunning =  false

    //public apis
    fun connect(){
        isRunning = true
        attemptConnect()
    }
    fun disconnect(){
        isRunning = false
        webSocket?.close(1000, "Contributor stopping")
        activeTunnels.values.forEach{it.close()}
        activeTunnels.clear()
    }
    //internal
    private fun attemptConnect(delayMs: Long=0){
        scope.launch(Dispatchers.IO){
            if(delayMs>0) delay(delayMs)
            if (!isRunning) return@launch
            Log.d(TAG, "connection to coordinator at $coordinatorUrl")
            val request = Request.Builder().url(coordinatorUrl).build()
            webSocket = client.newWebSocket(request, wsListener)
        }
    }

    private val wsListener = object : WebSocketListener(){
        override fun onOpen(ws: WebSocket, response: Response){
            Log.d(TAG, "Connected to coordinator — registering")
            ws.send(buildFrame(tunnelId=0, type=TYPE_REGISTER, payload = ByteArray(0)).toByteString())
        }
        override fun onMessage(ws: WebSocket, text: String){
            Log.w(TAG, "Unexpected text frame: $text")
        }
        override fun onMessage(ws: WebSocket, bytes: ByteString){
            handleFrame(bytes.toByteArray())
        }
        override fun onClosing(ws: WebSocket, code: Int, reason: String){
            Log.d(TAG, "Coordinator closing: $reason")
            ws.close(1000, null)
        }
        override fun onFailure(ws: WebSocket, t: Throwable, response: Response){
            Log.e(TAG, "WebSocket failure: ${t.message}")
            activeTunnels.values.forEach{it.close()}
            activeTunnels.clear()
            if (isRunning) attemptConnect(delayMs = 5000)

        }
    }

    private fun handleFrame(raw: ByteArray){
        if(raw.size<5){
            Log.d(TAG, "received array size is less than required. hence connection closed")
            return
        }
        val buf = ByteBuffer.wrap(raw)
        val tunnelId = buf.int  // reads 4 bytes
        val type = buf.get()    // reads 1 byte
        val payload = raw.copyOfRange(5,raw.size)

        when(type) {
            TYPE_ACK -> {
                Log.d(TAG, "contributor registered with coordinator successfully")
            }

            TYPE_OPEN -> {
                // Payload: [1 byte hostLen][hostLen bytes host][2 bytes port]
                val hostAndPort = parseOpenPayload(payload)
                if(hostAndPort==null){
                    Log.e( TAG, "TYPE_OPEN for tunnel $tunnelId has malformed payload")
                    return
                }
                val (host, port)= hostAndPort

                Log.d(TAG, "new tunnel requested with id: $tunnelId")
                openTunnel(tunnelId, host, port)
            }

            TYPE_DATA -> {
                activeTunnels[tunnelId]?.onRemoteData(payload)
                    ?: Log.w(TAG, "data from unknown tunnel with id: $tunnelId")
            }

            TYPE_CLOSE -> {
                Log.d(TAG, "closed tunnel with id: $tunnelId")
                activeTunnels.remove(tunnelId)?.close()
            }

            else -> {
                Log.w(TAG, "unknown frame type: $type")
            }
        }
    }
    /**
     * Parses the TYPE_OPEN payload produced by coordinator.js buildOpenPayload().
     *
     * Layout:
     *   [1 byte : host length N]
     *   [N bytes: host string UTF-8]
     *   [2 bytes: port big-endian]
     *
     * Returns Pair(host, port) or null if the payload is too short / malformed.
     */
    private fun parseOpenPayload(payload: ByteArray): Pair<String, Int>?{
        if(payload.isEmpty()) return null
        val hostlen = payload[0].toInt() and 0xFF
        if(payload.size< 3+hostlen) return null
        val host = String(payload, 1, hostlen, Charsets.UTF_8)
        val port = ((payload[1+hostlen].toInt() and 0xFF) shl 8) or (payload[1+hostlen+1].toInt() and 0xFF)
        return Pair(host, port)
    }

    private fun openTunnel(tunnelId: Int, host: String, port: Int){
        val session = TunnelSession(
            tunnelId = tunnelId,
            host = host,
            port = port,
            scope=scope,
            onLocalData = {
                id, data->
                val frame = buildFrame(tunnelId = id, type = TYPE_DATA, payload = data)
                webSocket?.send(frame.toByteString())
            },
            onClosed = {id->
                activeTunnels.remove(id)
                val frame = buildFrame(tunnelId = id, type = TYPE_CLOSE, payload = ByteArray(0))
                webSocket?.send(frame.toByteString())
                Log.d(TAG, "Tunnel $id closed")
            }
        )
        activeTunnels[tunnelId] = session
        session.open()
    }

    /**
     * Builds a binary frame:
     * [4 bytes: tunnelId big-endian][1 byte: type][payload bytes]
     */
    private fun buildFrame(tunnelId: Int, type: Byte, payload: ByteArray): ByteArray {
        val frame = ByteBuffer.allocate(4 + 1 + payload.size)
        frame.putInt(tunnelId)
        frame.put(type)
        frame.put(payload)
        return frame.array()
    }

}

