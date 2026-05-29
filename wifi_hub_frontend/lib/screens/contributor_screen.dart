import 'dart:async';
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

class _ContributorScreenState extends State<ContributorScreen>
    with TickerProviderStateMixin {
  // --- State ---
  bool _isStarting = true;
  bool _isRunning = false;
  String _hotspotIp = '—';
  String _errorMessage = '';

  // Live data usage (bytes)
  int _totalBytesUp = 0;
  int _totalBytesDown = 0;
  double _currentSpeedMbps = 0.0;

  Timer? _statsTimer;

  // Animations
  late final AnimationController _pulseController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeIn;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _startProxy();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────

  Future<void> _startProxy() async {
    try {
      final ip = await ProxyChannel.startProxy();
      if (!mounted) return;
      setState(() {
        _hotspotIp = ip;
        _isRunning = true;
        _isStarting = false;
      });
      _fadeController.forward();
      _startStatsPolling();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Failed to start proxy.';
        _isStarting = false;
      });
    }
  }

  void _startStatsPolling() {
    // Poll ProxyChannel every second for byte counts.
    // ProxyChannel.getStats() should return a Map<String, int> with keys
    // 'bytesUp', 'bytesDown'. If your channel uses different keys, adjust below.
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final stats = await ProxyChannel.getStats(); // Map<String, int>
        if (!mounted) return;
        final newUp = stats['bytesUp'] ?? 0;
        final newDown = stats['bytesDown'] ?? 0;
        final delta = (newDown - _totalBytesDown) + (newUp - _totalBytesUp);
        setState(() {
          _currentSpeedMbps = (delta * 8) / 1e6; // bytes/s → Mbps
          _totalBytesUp = newUp;
          _totalBytesDown = newDown;
        });
      } catch (_) {
        // getStats not yet implemented — gracefully show 0
      }
    });
  }

  Future<void> _stopProxy() async {
    _statsTimer?.cancel();
    await ProxyChannel.stopProxy();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  // ── Helpers ────────────────────────────────────────────────

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Background radial glow
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B0057).withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF3D0099).withOpacity(0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isStarting) return _buildLoading();
    if (_errorMessage.isNotEmpty) return _buildError();
    return _buildRunning();
  }

  // ── Loading ────────────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Color(0xFFE040FB),
            strokeWidth: 2,
          ),
          SizedBox(height: 20),
          Text(
            'Starting proxy…',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4F6A), size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _glassButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: () {
              setState(() {
                _errorMessage = '';
                _isStarting = true;
              });
              _startProxy();
            },
            accent: const Color(0xFFE040FB),
          ),
        ],
      ),
    );
  }

  // ── Running ────────────────────────────────────────────────

  Widget _buildRunning() {
    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _buildHeader(),
          const SizedBox(height: 32),
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildSpeedCard(),
          const SizedBox(height: 16),
          _buildTransferRow(),
          const Spacer(),
          _buildStopButton(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Pulsing live dot
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(
                const Color(0xFF00E676),
                const Color(0xFF69F0AE),
                _pulseController.value,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(
                    0.4 + 0.4 * _pulseController.value,
                  ),
                  blurRadius: 8 + 6 * _pulseController.value,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'PROXY ACTIVE',
          style: GoogleFonts.sourceCodePro(
            fontSize: 11,
            color: const Color(0xFF00E676),
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
          ),
        ),
        const Spacer(),
        // IP badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Text(
            _hotspotIp,
            style: GoogleFonts.sourceCodePro(
              fontSize: 11,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOCKS5',
            style: GoogleFonts.sourceCodePro(
              fontSize: 10,
              color: const Color(0xFFE040FB),
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Port 1080',
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 36,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Proxy server is running and accepting connections',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white38,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedCard() {
    final speed = _currentSpeedMbps.toStringAsFixed(2);
    return _glassCard(
      accent: const Color(0xFF8B0057),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THROUGHPUT',
                style: GoogleFonts.sourceCodePro(
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    speed,
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 48,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Mbps',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Mini sparkle icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE040FB).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Color(0xFFE040FB),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferRow() {
    return Row(
      children: [
        Expanded(
          child: _glassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 14,
                      color: Color(0xFF40C4FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'UPLOAD',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 9,
                        color: Colors.white38,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatBytes(_totalBytesUp),
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _glassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: Color(0xFF69F0AE),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DOWNLOAD',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 9,
                        color: Colors.white38,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatBytes(_totalBytesDown),
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStopButton() {
    return SizedBox(
      width: double.infinity,
      child: _glassButton(
        label: 'Stop Proxy',
        icon: Icons.stop_circle_outlined,
        onTap: _stopProxy,
        accent: const Color(0xFFFF4F6A),
        fullWidth: true,
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────

  Widget _glassCard({
    required Widget child,
    Color accent = Colors.transparent,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: accent != Colors.transparent
            ? [
          BoxShadow(
            color: accent.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ]
            : null,
      ),
      child: child,
    );
  }

  Widget _glassButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color accent,
    bool fullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: fullWidth ? 0 : 20,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: accent,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}