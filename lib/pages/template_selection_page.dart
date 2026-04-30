import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/resume_model.dart';
import '../services/template_access.dart';
import '../services/template_entitlements_store.dart';
import '../widgets/template_paywall_sheet.dart';
import '../widgets/uniform_app_bar.dart';
import 'resume_preview_page.dart';

class TemplateSelectionPage extends StatefulWidget {
  final ResumeData data;

  const TemplateSelectionPage({super.key, required this.data});

  @override
  State<TemplateSelectionPage> createState() =>
      _TemplateSelectionPageState();
}

class _TemplateSelectionPageState
    extends State<TemplateSelectionPage> {
  static const String _industryAll = 'all';
  static const String _industryIt = 'it';
  static const String _industryFinance = 'finance';
  static const String _industryTeacher = 'teacher';
  static const String _industryInfluencer = 'influencer';
  static const String _industryCreative = 'creative';

  String _selectedIndustry = _industryAll;

  final List<Map<String, dynamic>> templates = [
    {
      "id": "1",
      "name": "Minimal Classic",
      "colors": [Color(0xFF2563EB), Color(0xFF111827)],
      "premium": false,
      "thumb": "assets/templates/template1.png",
      "industries": [_industryAll, _industryIt, _industryFinance, _industryTeacher],
    },
    {
      "id": "2",
      "name": "Navy Classic",
      "colors": [Color(0xFF2F3A4A), Color(0xFF252D3A)],
      "premium": false,
      "thumb": "assets/templates/template2.png",
      "industries": [_industryAll, _industryIt, _industryFinance],
    },
    {
      "id": "3",
      "name": "Teal & Gold",
      "colors": [Color(0xFF0E3A43), Color(0xFFB38A3B)],
      "premium": true,
      "thumb": "assets/templates/template3.png",
      "industries": [_industryAll, _industryIt, _industryCreative, _industryInfluencer],
    },
    {
      "id": "4",
      "name": "Black & Yellow",
      "colors": [Color(0xFF222222), Color(0xFFF3C300)],
      "premium": true,
      "thumb": "assets/templates/template4.png",
      "industries": [_industryAll, _industryCreative, _industryInfluencer],
    },
    {
      "id": "5",
      "name": "Minimal Grey",
      "colors": [Color(0xFFE7E7E7), Color(0xFF9CA3AF)],
      "premium": true,
      "thumb": "assets/templates/template5.png",
      "industries": [_industryAll, _industryTeacher, _industryFinance],
    },
    {
      "id": "6",
      "name": "Teal Pro",
      "colors": [Color(0xFF163C52), Color(0xFF0E2B3A)],
      "premium": true,
      "thumb": "assets/templates/template6.png",
      "industries": [_industryAll, _industryIt, _industryFinance],
    },
    {
      "id": "7",
      "name": "Slate Icons",
      "colors": [Color(0xFF2F3840), Color(0xFF20272D)],
      "premium": true,
      "thumb": "assets/templates/template_7.png",
      "industries": [_industryAll, _industryIt, _industryTeacher],
    },
    {
      "id": "8",
      "name": "Modern Cards",
      "colors": [Color(0xFFF3F4F6), Color(0xFF3A9CA5)],
      "premium": false,
      "thumb": "assets/templates/template_8.png",
      "industries": [_industryAll, _industryCreative, _industryInfluencer],
    },
    {
      "id": "9",
      "name": "Gold Header",
      "colors": [Color(0xFF0F2E3C), Color(0xFFC7A24B)],
      "premium": true,
      "thumb": "",
      "industries": [_industryAll, _industryFinance, _industryIt],
    },
    {
      "id": "10",
      "name": "Mobile Neutral",
      "colors": [Color(0xFFE5E7EB), Color(0xFF6B7280)],
      "premium": true,
      "thumb": "",
      "industries": [_industryAll, _industryTeacher, _industryIt],
    },
    {
      "id": "11",
      "name": "ATS Pro",
      "colors": [Color(0xFF111827), Color(0xFF334155)],
      "premium": true,
      "thumb": "",
      "industries": [_industryAll, _industryIt, _industryFinance, _industryTeacher],
    },
    {
      "id": "12",
      "name": "Executive Mono",
      "colors": [Color(0xFF0B1220), Color(0xFF1F2A44)],
      "premium": true,
      "thumb": "",
      "industries": [_industryAll, _industryFinance, _industryIt],
    },
    {
      "id": "13",
      "name": "Compact Modern",
      "colors": [Color(0xFF052E2B), Color(0xFF0E7490)],
      "premium": true,
      "thumb": "",
      "industries": [_industryAll, _industryIt, _industryCreative],
    },
  ];

  String _industryLabel(AppLocalizations t, String industryId) {
    switch (industryId) {
      case _industryAll:
        return t.industryAll;
      case _industryIt:
        return t.industryIT;
      case _industryFinance:
        return t.industryFinance;
      case _industryTeacher:
        return t.industryTeacher;
      case _industryInfluencer:
        return t.industryInfluencer;
      case _industryCreative:
        return t.industryCreative;
      default:
        return industryId;
    }
  }

  List<Map<String, dynamic>> _filteredTemplates() {
    if (_selectedIndustry == _industryAll) return templates;
    return templates.where((tpl) {
      final inds = (tpl["industries"] as List?)?.cast<String>() ?? const <String>[];
      return inds.contains(_selectedIndustry) || inds.contains(_industryAll);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final filtered = _filteredTemplates();
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: UniformAppBar.material(t.chooseTemplate),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.templatesTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.templatesCountLine(filtered.length),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      // Wrap on small screens; scroll on very tight widths.
                      final chips = [
                        _industryPill(t, _industryAll),
                        _industryPill(t, _industryIt),
                        _industryPill(t, _industryFinance),
                        _industryPill(t, _industryTeacher),
                        _industryPill(t, _industryInfluencer),
                        _industryPill(t, _industryCreative),
                      ];
                      if (c.maxWidth < 330) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(children: chips),
                        );
                      }
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: chips,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _templateCard(t, filtered[index]),
                childCount: filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _industryIcon(String industryId) {
    switch (industryId) {
      case _industryAll:
        return Icons.grid_view_rounded;
      case _industryIt:
        return Icons.memory_rounded;
      case _industryFinance:
        return Icons.account_balance_rounded;
      case _industryTeacher:
        return Icons.school_rounded;
      case _industryInfluencer:
        return Icons.campaign_rounded;
      case _industryCreative:
        return Icons.brush_rounded;
      default:
        return Icons.work_rounded;
    }
  }

  Widget _industryPill(AppLocalizations t, String industryId) {
    final selected = _selectedIndustry == industryId;
    final label = _industryLabel(t, industryId);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFFFFE08A), Color(0xFFFDE68A)],
              )
            : const LinearGradient(
                colors: [Color(0x22FFFFFF), Color(0x10FFFFFF)],
              ),
        border: Border.all(
          color: selected
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.12),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFFFFE08A).withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _selectedIndustry = industryId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _industryIcon(industryId),
                  size: 16,
                  color: selected ? Colors.black : Colors.white.withOpacity(0.90),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white.withOpacity(0.90),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.1,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_rounded, size: 16, color: Colors.black),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNeedResumeContentDialog(AppLocalizations t) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          title: Text(
            t.templatePreviewNeedContentTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          content: Text(
            t.templatePreviewNeedContentMessage,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              height: 1.35,
              fontSize: 14,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop<ResumeData>(widget.data);
              },
              child: Text(t.templatePreviewNeedContentOk),
            ),
          ],
        );
      },
    );
  }

  // ================= TEMPLATE CARD =================

  Widget _templateCard(AppLocalizations l10n, Map<String, dynamic> template) {
    final List<Color> colors =
        (template["colors"] as List).cast<Color>();

    final name = (template["name"] ?? "").toString();
    final id = (template["id"] ?? "").toString();
    final thumb = (template["thumb"] ?? "").toString();
    final paid = TemplateAccess.isPaid(id);
    final unlocked = TemplateEntitlementsStore.instance.isUnlocked(id);
    final locked = paid && !unlocked;

    return GestureDetector(
      onTap: () {
        if (locked) {
          TemplatePaywallSheet.open(
            context,
            templateId: id,
            templateName: name,
          );
          return;
        }

        if (!widget.data.hasAnyResumeContentForPreview()) {
          _showNeedResumeContentDialog(l10n);
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResumePreviewPage(
              data: widget.data,
              templateId: template["id"],
            ),
          ),
        );
      },
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 240),
        tween: Tween(begin: 0.98, end: 1.0),
        curve: Curves.easeOut,
        builder: (context, t, child) => Transform.scale(scale: t, child: child),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                colors.first.withOpacity(0.92),
                colors.last.withOpacity(0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.28),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                ),
                              ),
                              child: Text(
                                "T$id",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (paid)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFE08A),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  locked ? 'PRO' : 'OWNED',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.94),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.35),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: thumb.isEmpty
                                      ? const SizedBox.shrink()
                                      : Image.asset(
                                          thumb,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              if (locked)
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      color: Colors.black.withOpacity(0.35),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.lock_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locked ? l10n.templatePaywallTitle : l10n.tapToPreview,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}