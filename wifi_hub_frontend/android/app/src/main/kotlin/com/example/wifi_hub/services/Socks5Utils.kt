package com.example.wifi_hub.services

import java.io.InputStream
import java.io.OutputStream

class Socks5Utils {

    fun doGreeting(input: InputStream, output: OutputStream): Boolean{
        val version = input.read()
        if(version!=5) return false
        val nMethods = input.read()
        val methods = ByteArray(nMethods)
        input.read(methods)

        output.write(byteArrayOf(0x05, 0x00))
        output.flush()
        return true
    }

    // ── Stage 2: Parse connection request ────────────────────────────────────
    //
    // Client sends:  [0x05, cmd, 0x00, addrType, ...addr..., portHi, portLo]
    //   0x05       = SOCKS version
    //   cmd        = 0x01 (CONNECT) — we only support this
    //   0x00       = reserved byte
    //   addrType   = 0x01 (IPv4) | 0x03 (domain name) | 0x04 (IPv6)
    //
    // We reply:     [0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0]  (success)
    //   This is: version, success, reserved, IPv4 type, bound addr (zeros), bound port (zeros)
    //
    // Returns: Pair(host, port) or null on error
    fun parseRequest(input: InputStream, output: OutputStream): Pair<String, Int>?{
        val version = input.read()
        val command = input.read()
        input.read()

        if(version!=5 || command!=1){
            output.write(byteArrayOf(0x05, 0x07, 0x00, 0x01, 0,0,0,0, 0,0))
            return null
        }

        val addrType = input.read()
        val host: String = when(addrType){
            0x01->{   // IPv4: read 4 bytes
                val addr = ByteArray(4)
                input.read(addr)
                addr.joinToString(".") { (it.toInt() and 0xFF).toString() }
            }
            0x03->{// Domain name: first byte is length, then the name
                val len = input.read()
                val name = ByteArray(len)
                input.read(name)
                String(name)
            }
            0x04->{ // IPv6: read 16 bytes
                val addr = ByteArray(16)
                input.read(addr)
                java.net.Inet6Address.getByAddress(addr).hostAddress ?: run {
                    output.write(byteArrayOf(0x05, 0x08, 0x00, 0x01, 0,0,0,0, 0,0))
                    return null
                }
            }else ->{
                output.write(byteArrayOf(0x05, 0x08, 0x00, 0x01, 0,0,0,0, 0,0))
                return null
            }
        }

        val porthi = input.read()
        val portlow = input.read()
        val port = (porthi shl 8) or portlow

        output.write(byteArrayOf(0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0))
        output.flush()
        return Pair(host, port)
    }
}