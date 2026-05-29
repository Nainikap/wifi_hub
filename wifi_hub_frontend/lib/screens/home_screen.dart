import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wifi_hub/screens/contributor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 16.0,
                horizontal: 16,
              ),
              child: Text(
                "Welcome to WifiHub!",
                textAlign: TextAlign.center,
                style: GoogleFonts.gupter(
                  fontSize: 50,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
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
                  child: InkWell(
                    onTap: (){
                      try{
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ContributorScreen())
                        );
                      }
                      catch(e){
                        debugPrint('Navigation error: $e');
                      }
                    },
                    child: const Text(
                      "Be a contributor",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color.fromARGB(255, 243, 6, 184),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )

                ),

                const SizedBox(width: 15),
              ],
            ),
          ],
        ),
      ),
    );
  }
}