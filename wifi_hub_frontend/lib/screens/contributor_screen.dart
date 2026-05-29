import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wifi_hub/screens/home_screen.dart';
import 'package:wifi_hub/services/proxy_channel.dart';

class ContributorScreen extends StatefulWidget {
  const ContributorScreen({super.key});

  @override
  State<ContributorScreen> createState() => _ContributorScreenState();
}


class _ContributorScreenState extends State<ContributorScreen> {
  @override
  void initState(){

    super.initState();
    _startProxy();
  }

  @override
  void dispose(){
    super.dispose();
  }

  bool _isStarting = true;   // true while we wait for startProxy() to return
  bool _isRunning  = false;
  String _hotspotIp = '—';
  String _errorMessage = '';

// --actions--
  Future<void> _startProxy() async{
    debugPrint('>>> _startProxy called???!?!?!?!');
    try{
      debugPrint('>>> ABOUT TO CALL???!!!@#');
      final ip = await ProxyChannel.startProxy();
      debugPrint('>>> CALL KHATAM HO GAYI??!!!?!?!');
      if (!mounted) return;
      setState(() {
        _hotspotIp=ip;
        _isRunning=true;
        _isStarting=false;
      });
    }
    on PlatformException catch(e){
      if(!mounted) return;

      setState(() {
        _errorMessage = e.message ?? 'Failed to start proxy.';
        _isStarting = false;
      });  }
  }

  Future<void> _stopProxy(BuildContext context) async {
    await ProxyChannel.stopProxy();
    if(!mounted) return;
    setState(() {
      _isRunning=false;
    });
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));

  }

  //--build--
@override
  Widget build(BuildContext context) {
    return Scaffold(

      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black38,
              Color.fromRGBO(120, 12, 86, 1.0),
            ],
          ),
        ),
        padding: const EdgeInsets.all(15),
        child: Center(
          child: ListView(
          children: [
            if(_isStarting)
              Center(
                child: CircularProgressIndicator(),
              )
            else if(_errorMessage.isNotEmpty)
              Text(
                _errorMessage,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              )
            else ...[
            Text(
              'Proxy Active!\n SOCKS5 server running on port 1080',
              style: GoogleFonts.gupter(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,

              ),
            ),
            Text(
              'Your data usage:',
              style: TextStyle(
                fontSize: 20,
              ),
            ),
            Text(
              '230Mbps',
              style: TextStyle(
                fontSize: 40,
              ),
            ),
            InkWell(

              onTap: () async{
                try{
                  await _stopProxy(context);
                  // Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                }
                catch(e){
                  debugPrint('Navigation error: $e');
                }
              },
              child: Container(
                width: 160,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(136, 33, 33, 33),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white,
                    width: 1,
                  ),
                ),
                child: const Text(
                  "Stop",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color.fromARGB(255, 243, 6, 184),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            )
          ],
            ],    ),
        ),),
    );
  }
}
