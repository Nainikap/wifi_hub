package com.example.wifi_hub.services

import android.util.Log
import kotlinx.coroutines.*
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket

/**
 * One active tunnel between a remote client (via coordinator WebSocket)
 * and the local SOCKS5 proxy server.
 *
 * Data flow:
 *   Coordinator → onRemoteData() → localSocket(127.0.0.1:1080) → SOCKS5 → Internet
 *   Internet → SOCKS5 → localSocket → onLocalData callback → Coordinator
 */

class TunnelSession(
    val tunnelId: Int,
    private val host: String,
    private val port: Int,
    private val scope: CoroutineScope,
    private val onLocalData: (tunnelId: Int, data: ByteArray)->Unit,
    private val onClosed: (tunnelId: Int) -> Unit
){
    companion object{
        private const val TAG= "tunnel session"
    }
    private var localSocket: Socket? = null
    private var localOut: OutputStream?= null
    private var utils= Socks5Utils()
    @Volatile private var isOpen = false
    @Volatile private var isReady = false

    private val pendingData = mutableListOf<ByteArray>()
    private val pendingLock = Any()

    fun open(){
        scope.launch(Dispatchers.IO){
            try{
                val socket = Socket("127.0.0.1", ProxyService.PORT)
                localSocket=socket
                localOut = socket.getOutputStream()
                isOpen=true

                if (utils.doGreeting(socket.getInputStream(), socket.getOutputStream())){
                    sendConnect(socket.getInputStream(), socket.getOutputStream())
                }else {
                    Log.e(TAG, "Errr doing socks5 handshake at tunnel $tunnelId")
                    close()
                }

                synchronized(pendingLock){
                    isReady=true
                    for(chunk in pendingData){
                        localOut?.write(chunk)
                        localOut?.flush()
                    }
                    pendingData.clear()
                }
                Log.d(TAG, "Tunnel $tunnelId ready → $host:$port")
                //read loop
                val  buf = ByteArray(8192)
                val input: InputStream = socket.getInputStream()
                while(true){
                    val n = input.read(buf)
                    if (n==-1) break
                    onLocalData(tunnelId, buf.copyOf(n))
                }
            }catch(e: Exception){

            }finally{
                close()
                onClosed(tunnelId)
            }
        }
    }
    /** Called when the coordinator pushes bytes from the remote client. */
    @Synchronized
    fun onRemoteData(data: ByteArray){
        if(!isOpen) return

        synchronized(pendingLock){
            if(!isReady){
                pendingData.add(data)
                return
            }
        }
        scope.launch(Dispatchers.IO){
            try{
                localOut?.write(data)
                localOut?.flush()
            }catch(e: Exception){
                close()
            }
        }
    }

    fun sendConnect(input: InputStream, output: OutputStream){
        val hostBytes = host.toByteArray(Charsets.UTF_8)
        val request = ByteArray(4 + 1 + hostBytes.size +2)
        request[0] = 0x05       // SOCKS version
        request[1] = 0x01       // CONNECT command
        request[2] = 0x00       // reserved
        request[3] = 0x03       // address type: domain name
        request[4] = hostBytes.size.toByte()
        hostBytes.copyInto(request, 5)
        request[5+hostBytes.size] = ((port shr 8) and 0xFF).toByte()
        request[5+hostBytes.size+1] = (port  and 0xFF).toByte()

        output.write(request)
        output.flush()

        val connectReply = ByteArray(10)
        readReply(input, connectReply)
        if(connectReply[1] != 0x00.toByte()){
            throw IllegalStateException(
                "SOCKS5 CONNECT failed, status=0x${"%02X".format(connectReply[1])}"
            )
        }
    }

    private fun readReply(input: InputStream, connectReply: ByteArray){
        var offset = 0
        while(offset<connectReply.size){
            val n = input.read(connectReply, offset, connectReply.size-offset)
            if (n == -1) throw IllegalStateException("Stream closed during SOCKS5 handshake")
            offset += n
        }
    }
    fun close(){
        isOpen=false
        try{
            localSocket?.close()
        }catch(e: Exception){

        }
    }
}