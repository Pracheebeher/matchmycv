import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../models/resume_model.dart';
import '../widgets/region_language_sheet.dart';
import 'home_builder_page.dart';
import 'cover_letter_form_page.dart';
import 'ats_checker_page.dart';

class MainHomePage extends StatefulWidget {
  final ResumeData data;

  const MainHomePage({super.key, required this.data});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _parallaxPx = ValueNotifier(0.0);

  Future<void> _openRegionLanguageSheet() => RegionLanguageSheet.open(context);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final px = _scrollController.position.pixels;
      if (_parallaxPx.value != px) _parallaxPx.value = px;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _parallaxPx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      body: Stack(
        children: [
          _ParallaxBackdrop(scrollPixels: _parallaxPx),
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF7C3AED),
                                  Color(0xFF06B6D4),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF06B6D4)
                                      .withOpacity(0.18),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              header: true,
                              label:
                                  'CVentra AI - Resume builder and ATS optimizer',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t.appTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.fade,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: size.width < 360 ? 14 : 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.15,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    t.appSubtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.fade,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.66),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.12,
                                      height: 1.12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.center,
                            children: [
                              Icon(
                                Icons.trending_up_rounded,
                                size: 20,
                                color: Colors.white.withOpacity(0.92),
                              ),
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                                color: Colors.white.withOpacity(0.88),
                              ),
                              Icon(
                                Icons.timer_rounded,
                                size: 18,
                                color: Colors.white.withOpacity(0.88),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.heroTitle,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: size.width < 380 ? 24 : 28,
                              fontWeight: FontWeight.w900,
                              height: 1.12,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        12 + MediaQuery.paddingOf(context).bottom,
                      ),
                      // Do not use LayoutBuilder here: SliverFillRemaining probes intrinsic
                      // dimensions of its child, which LayoutBuilder does not support.
                      child: Align(
                        alignment: Alignment(
                          0,
                          MediaQuery.sizeOf(context).height < 720
                              ? -0.12
                              : -0.20,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 10),
                              _HeroActionCard(
                                title: t.ctaResumeTitle,
                                subtitle: t.ctaResumeSubtitle,
                                icon: Icons.description_rounded,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4facfe),
                                    Color(0xFF00f2fe),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HomeBuilderPage(
                                        data: widget.data,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              _HeroActionCard(
                                title: t.ctaAtsTitle,
                                subtitle: t.ctaAtsSubtitle,
                                icon: Icons.analytics_rounded,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF11998e),
                                    Color(0xFF38ef7d),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ATSCheckerPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              _HeroActionCard(
                                title: t.ctaCoverTitle,
                                subtitle: t.ctaCoverSubtitle,
                                icon: Icons.mail_rounded,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFfa709a),
                                    Color(0xFFfee140),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CoverLetterFormPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              InkWell(
                                onTap: _openRegionLanguageSheet,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.public_rounded,
                                        size: 20,
                                        color: Colors.white.withOpacity(0.92),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              t.countryLanguageTitle,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.92),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            ListenableBuilder(
                                              listenable: Listenable.merge(
                                                [appLocale, appCountryCode],
                                              ),
                                              builder: (context, _) {
                                                final cc = appCountryCode.value;
                                                final lk = RegionLanguageSheet
                                                    .languageKeyForLocale(
                                                  appLocale.value,
                                                );
                                                final cName =
                                                    RegionLanguageSheet
                                                            .countryNames[cc] ??
                                                        cc;
                                                final lName =
                                                    RegionLanguageSheet
                                                            .languageNames[lk] ??
                                                        lk;
                                                return Text(
                                                  "$cName · $lName  (${cc.toUpperCase()}/${lk.toUpperCase()})",
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.70),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white.withOpacity(0.85),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParallaxBackdrop extends StatefulWidget {
  final ValueListenable<double> scrollPixels;

  const _ParallaxBackdrop({required this.scrollPixels});

  @override
  State<_ParallaxBackdrop> createState() => _ParallaxBackdropState();
}

class _ParallaxBackdropState extends State<_ParallaxBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.scrollPixels, _ambient]),
      builder: (context, _) {
        final px = widget.scrollPixels.value;
        final wave = math.sin(_ambient.value * math.pi * 2);
        final driftY = wave * 22.0;
        final driftX = wave * 14.0;

        final gradDy = px * 0.14;
        final gradDx = px * 0.06;
        final cx = (-0.65 + (px * 0.00035).clamp(-0.12, 0.12)).clamp(-1.0, 1.0);
        final cy = (-0.75 + (px * 0.00022).clamp(-0.08, 0.08)).clamp(-1.0, 1.0);
        final meshScale = 1.0 + (px * 0.00035).clamp(0.0, 0.09);

        final orbTopDy = px * 0.62 + driftY;
        final orbTopDx = px * 0.18 + driftX;
        final orbBotDy = -px * 0.48 - driftY * 0.75;
        final orbBotDx = -px * 0.14 - driftX * 0.5;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(gradDx, gradDy),
                child: Transform.scale(
                  scale: meshScale,
                  alignment: Alignment.topLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(cx, cy),
                        radius: 1.25,
                        colors: const [
                          Color(0xFF1B2A4A),
                          Color(0xFF070A12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _ParallaxHomeIconLayer(
                  scrollPixels: px,
                  driftX: driftX,
                  driftY: driftY,
                ),
              ),
            ),
            Positioned(
              left: -140 + orbTopDx,
              top: -160 + orbTopDy,
              child: const _GlowOrb(color: Color(0xFF7C3AED), size: 340),
            ),
            Positioned(
              right: -160 + orbBotDx,
              bottom: -170 + orbBotDy,
              child: const _GlowOrb(color: Color(0xFF06B6D4), size: 380),
            ),
          ],
        );
      },
    );
  }
}

/// Resume / AI / ATS themed icons — scattered full screen, moves with parallax.
class _ParallaxHomeIconLayer extends StatelessWidget {
  final double scrollPixels;
  final double driftX;
  final double driftY;

  const _ParallaxHomeIconLayer({
    required this.scrollPixels,
    required this.driftX,
    required this.driftY,
  });

  static const List<IconData> _icons = [
    Icons.description_rounded,
    Icons.analytics_rounded,
    Icons.auto_awesome_rounded,
    Icons.psychology_rounded,
    Icons.work_outline_rounded,
    Icons.article_rounded,
    Icons.assessment_rounded,
    Icons.check_circle_outline_rounded,
    Icons.school_rounded,
    Icons.trending_up_rounded,
    Icons.mail_outline_rounded,
    Icons.speed_rounded,
    Icons.verified_rounded,
    Icons.insert_drive_file_rounded,
    Icons.folder_special_rounded,
  ];

  static double _frac(int salt) {
    final x = math.sin(salt.toDouble() * 12.9898) * 43758.5453123;
    return x - x.floorToDouble();
  }

  static const int _count = 28;

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final w = sz.width;
    final h = sz.height;
    final px = scrollPixels;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: List.generate(_count, (i) {
        final icon = _icons[i % _icons.length];
        // Different seeds than HomeBuilder so layout isn’t identical.
        final uX = _frac(i * 6829 + 211);
        final uY = _frac(i * 6833 + 617);
        final uD = _frac(i * 5849 + 419);
        final uS = _frac(i * 4999 + 823);
        final uO = _frac(i * 4273 + 131);

        final baseX = w * (0.02 + 0.96 * uX);
        final baseY = h * (0.02 + 0.98 * uY);
        final depth = 0.5 + 0.8 * uD;
        final ox = driftX * depth * 1.2 + px * 0.05 * depth;
        final oy = driftY * depth * 0.9 + px * 0.07 * depth;
        final size = 16.0 + uS * 24.0;
        final opacity = 0.04 + uO * 0.06;

        return Positioned(
          left: baseX + ox - size * 0.5,
          top: baseY + oy - size * 0.5,
          child: Icon(
            icon,
            size: size,
            color: Colors.white.withOpacity(opacity.clamp(0.032, 0.10)),
          ),
        );
      }),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.48),
            color.withOpacity(0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
      ),
    );
  }
}

class _HeroActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _HeroActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              right: -26,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.22),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

