import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Available preset text colors for rich notices
class NoticeColorPresets {
  static const Color darkCharcoal = Color(0xFF263238);
  static const Color crimsonRed = Color(0xFFD32F2F);
  static const Color sapphireBlue = Color(0xFF1976D2);
  static const Color emeraldGreen = Color(0xFF2E7D32);
  static const Color royalPurple = Color(0xFF7B1FA2);
  static const Color amberOrange = Color(0xFFE65100);
  static const Color teal = Color(0xFF00796B);
  static const Color slateGrey = Color(0xFF546E7A);

  static const List<Color> textColors = [
    darkCharcoal,
    crimsonRed,
    sapphireBlue,
    emeraldGreen,
    royalPurple,
    amberOrange,
    teal,
    slateGrey,
  ];

  static const List<Color> bgColors = [
    Color(0xFFFFF9C4), // Light Yellow
    Color(0xFFFFEBEE), // Light Pink/Red
    Color(0xFFE3F2FD), // Light Blue
    Color(0xFFE8F5E9), // Light Green
    Color(0xFFF3E5F5), // Light Purple
    Color(0xFFFFF3E0), // Light Orange
  ];

  static Color? parseColor(String str) {
    str = str.trim().toLowerCase();
    if (str.startsWith('#')) {
      final hex = str.replaceFirst('#', '');
      if (hex.length == 6) {
        final val = int.tryParse('FF$hex', radix: 16);
        if (val != null) return Color(val);
      } else if (hex.length == 8) {
        final val = int.tryParse(hex, radix: 16);
        if (val != null) return Color(val);
      }
    }
    switch (str) {
      case 'red':
      case 'crimson':
        return crimsonRed;
      case 'blue':
      case 'sapphire':
        return sapphireBlue;
      case 'green':
      case 'emerald':
        return emeraldGreen;
      case 'purple':
      case 'royalpurple':
        return royalPurple;
      case 'orange':
      case 'amber':
        return amberOrange;
      case 'teal':
        return teal;
      case 'grey':
      case 'gray':
      case 'slate':
        return slateGrey;
      case 'yellow':
        return const Color(0xFFFBC02D);
      case 'black':
      case 'charcoal':
        return darkCharcoal;
    }
    return null;
  }
}

/// Rich Text rendering widget for formatted notice content with inline media & docs
class NoticeRichText extends StatelessWidget {
  final String content;
  final TextStyle? baseStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const NoticeRichText({
    super.key,
    required this.content,
    this.baseStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  void _openUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  void _showImageLightbox(BuildContext context, String imageUrl, String caption) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 300,
                        height: 300,
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 250,
                      height: 200,
                      color: Colors.black87,
                      child: const Center(
                        child: Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
                      tooltip: 'Open / Download Original',
                      onPressed: () => _openUrl(context, imageUrl),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final defaultStyle = baseStyle ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              height: 1.4,
              color: const Color(0xFF2C3E50),
            ) ??
        const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF2C3E50));

    final lines = content.split('\n');
    final List<Widget> blockWidgets = [];

    int i = 0;
    while (i < lines.length) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      // Divider block
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        blockWidgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4.0),
            child: Divider(thickness: 1.0, height: 8, color: Color(0xFFE2E8F0)),
          ),
        );
        i++;
        continue;
      }

      // Inline Image block: ![caption](url)
      final imageMatch = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(trimmed);
      if (imageMatch != null) {
        final caption = imageMatch.group(1) ?? '';
        final imageUrl = imageMatch.group(2) ?? '';
        blockWidgets.add(_buildInlineImageWidget(context, imageUrl, caption));
        i++;
        continue;
      }

      // Inline Document block: [doc:url|name] or [pdf:url|name]
      final docMatch = RegExp(r'^\[(doc|pdf|file):\s*(.*?)\|(.*?)\]$').firstMatch(trimmed);
      if (docMatch != null) {
        final docUrl = docMatch.group(2) ?? '';
        final docName = docMatch.group(3) ?? 'Attached Document';
        blockWidgets.add(_buildInlineDocWidget(context, docUrl, docName));
        i++;
        continue;
      }

      // Callout alert box block: > [!ALERT], > [!INFO], > [!SUCCESS], > [!NOTE], or plain > quote
      if (trimmed.startsWith('>')) {
        final List<String> calloutLines = [];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          String l = lines[i].trim().substring(1).trim();
          calloutLines.add(l);
          i++;
        }

        final fullCalloutText = calloutLines.join('\n');
        blockWidgets.add(_buildCalloutBox(context, fullCalloutText, defaultStyle));
        continue;
      }

      // Heading 1 (#)
      if (trimmed.startsWith('# ')) {
        final headingText = trimmed.substring(2);
        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 2),
            child: Text(
              headingText,
              style: defaultStyle.copyWith(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A237E),
                letterSpacing: -0.2,
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // Heading 2 (##)
      if (trimmed.startsWith('## ')) {
        final headingText = trimmed.substring(3);
        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              headingText,
              style: defaultStyle.copyWith(
                fontSize: 15.0,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF283593),
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // Heading 3 (###)
      if (trimmed.startsWith('### ')) {
        final headingText = trimmed.substring(4);
        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 1),
            child: Text(
              headingText,
              style: defaultStyle.copyWith(
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF37474F),
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // Bullet Point (• or - or *)
      if (trimmed.startsWith('• ') ||
          (trimmed.startsWith('- ') && !trimmed.startsWith('---')) ||
          (trimmed.startsWith('* ') && !trimmed.endsWith('*'))) {
        final bulletText = trimmed.substring(2);
        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 7, right: 8),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3F51B5),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: _parseInlineSpans(context, bulletText, defaultStyle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        i++;
        continue;
      }

      // Numbered List (e.g. "1. ")
      final numMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (numMatch != null) {
        final numStr = numMatch.group(1)!;
        final restText = numMatch.group(2)!;
        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$numStr.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3F51B5),
                    ),
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: _parseInlineSpans(context, restText, defaultStyle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        i++;
        continue;
      }

      // Group consecutive regular paragraph lines together
      final List<String> paragraphLines = [];
      while (i < lines.length) {
        final curTrimmed = lines[i].trim();
        // Check if next line starts a new block
        if (curTrimmed.isEmpty ||
            curTrimmed.startsWith('![') ||
            curTrimmed.startsWith('[doc:') ||
            curTrimmed.startsWith('[pdf:') ||
            curTrimmed.startsWith('[file:') ||
            curTrimmed.startsWith('# ') ||
            curTrimmed.startsWith('## ') ||
            curTrimmed.startsWith('### ') ||
            curTrimmed.startsWith('• ') ||
            (curTrimmed.startsWith('- ') && !curTrimmed.startsWith('---')) ||
            (curTrimmed.startsWith('* ') && !curTrimmed.endsWith('*')) ||
            RegExp(r'^\d+\.\s+').hasMatch(curTrimmed) ||
            curTrimmed.startsWith('>') ||
            curTrimmed == '---' ||
            curTrimmed == '***' ||
            curTrimmed == '___') {
          if (paragraphLines.isEmpty && curTrimmed.isEmpty) {
            blockWidgets.add(const SizedBox(height: 6));
            i++;
          }
          break;
        }

        paragraphLines.add(lines[i]);
        i++;
      }

      if (paragraphLines.isNotEmpty) {
        final paragraphText = paragraphLines.join('\n');
        TextAlign align = TextAlign.start;
        String lineToParse = paragraphText;

        final pTrimmed = paragraphText.trim();
        if (pTrimmed.startsWith('[align=center]') && pTrimmed.endsWith('[/align]')) {
          align = TextAlign.center;
          lineToParse = pTrimmed.substring(14, pTrimmed.length - 8);
        } else if (pTrimmed.startsWith('[align=right]') && pTrimmed.endsWith('[/align]')) {
          align = TextAlign.end;
          lineToParse = pTrimmed.substring(13, pTrimmed.length - 8);
        }

        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: RichText(
              textAlign: align,
              text: TextSpan(
                children: _parseInlineSpans(context, lineToParse, defaultStyle),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blockWidgets,
    );
  }

  Widget _buildInlineImageWidget(BuildContext context, String imageUrl, String caption) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _showImageLightbox(context, imageUrl, caption),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220, minHeight: 80),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                color: const Color(0xFFF8FAFC),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Failed to load inline image', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text('Zoom', style: TextStyle(fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineDocWidget(BuildContext context, String docUrl, String docName) {
    final isPdf = docName.toLowerCase().endsWith('.pdf');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: const Color(0xFFF1F5F9),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        avatar: Icon(
          isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
          size: 15,
          color: isPdf ? Colors.red : const Color(0xFF1E293B),
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              docName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.download_rounded, size: 14, color: Color(0xFF64748B)),
          ],
        ),
        onPressed: () => _openUrl(context, docUrl),
      ),
    );
  }

  Widget _buildCalloutBox(BuildContext context, String rawText, TextStyle baseStyle) {
    Color borderColor = const Color(0xFF1976D2);
    Color bgColor = const Color(0xFFE3F2FD);
    IconData icon = Icons.info_outline_rounded;
    String title = 'Notice Note';
    String bodyText = rawText;

    if (rawText.startsWith('[!ALERT]') || rawText.startsWith('[!URGENT]') || rawText.startsWith('[!CRITICAL]')) {
      borderColor = const Color(0xFFD32F2F);
      bgColor = const Color(0xFFFFEBEE);
      icon = Icons.warning_amber_rounded;
      title = 'Important Alert';
      final tagMatch = RegExp(r'^\[\!(ALERT|URGENT|CRITICAL)\]\s*').firstMatch(rawText);
      if (tagMatch != null) {
        bodyText = rawText.substring(tagMatch.end).trim();
      }
    } else if (rawText.startsWith('[!WARNING]')) {
      borderColor = const Color(0xFFE65100);
      bgColor = const Color(0xFFFFF3E0);
      icon = Icons.error_outline_rounded;
      title = 'Attention Required';
      final tagMatch = RegExp(r'^\[\!WARNING\]\s*').firstMatch(rawText);
      if (tagMatch != null) {
        bodyText = rawText.substring(tagMatch.end).trim();
      }
    } else if (rawText.startsWith('[!SUCCESS]')) {
      borderColor = const Color(0xFF2E7D32);
      bgColor = const Color(0xFFE8F5E9);
      icon = Icons.check_circle_outline_rounded;
      title = 'Update / Resolved';
      final tagMatch = RegExp(r'^\[\!SUCCESS\]\s*').firstMatch(rawText);
      if (tagMatch != null) {
        bodyText = rawText.substring(tagMatch.end).trim();
      }
    } else if (rawText.startsWith('[!INFO]') || rawText.startsWith('[!NOTE]')) {
      borderColor = const Color(0xFF0288D1);
      bgColor = const Color(0xFFE1F5FE);
      icon = Icons.info_outline_rounded;
      title = 'Information';
      final tagMatch = RegExp(r'^\[\!(INFO|NOTE)\]\s*').firstMatch(rawText);
      if (tagMatch != null) {
        bodyText = rawText.substring(tagMatch.end).trim();
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: borderColor, width: 3.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: borderColor),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: borderColor,
                ),
              ),
            ],
          ),
          if (bodyText.isNotEmpty) const SizedBox(height: 4),
          if (bodyText.isNotEmpty)
            RichText(
              text: TextSpan(
                children: _parseInlineSpans(context, bodyText, baseStyle.copyWith(color: const Color(0xFF263238))),
              ),
            ),
        ],
      ),
    );
  }

  /// Parses inline formatting:
  /// - `**bold**`
  /// - `*italic*`
  /// - `<u>underline</u>` or `__underline__`
  /// - `~~strikethrough~~`
  /// - `[color=#HEX]...[/color]`
  /// - `[bg=#HEX]...[/bg]`
  /// - `[size=18]...[/size]`
  /// - `[Label](url)`
  static List<InlineSpan> _parseInlineSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    if (text.isEmpty) return [];

    final List<InlineSpan> spans = [];

    // Master Regex with dotAll: true so multi-line tags inside paragraphs match correctly
    final RegExp inlineRegex = RegExp(
      r'(\*\*([\s\S]*?)\*\*)|' // 1: **bold** (2)
      r'(\*([\s\S]*?)\*)|' // 3: *italic* (4)
      r'(<u>([\s\S]*?)<\/u>)|' // 5: <u>underline</u> (6)
      r'(__([^_]+)__)|' // 7: __underline__ (8)
      r'(~~([\s\S]*?)~~)|' // 9: ~~strikethrough~~ (10)
      r'(\[color=\s*([^\]]+)\s*\]([\s\S]*?)\[\/color\])|' // 11: [color=val] (12) (13)
      r'(\[bg=\s*([^\]]+)\s*\]([\s\S]*?)\[\/bg\])|' // 14: [bg=val] (15) (16)
      r'(\[size=\s*([^\]]+)\s*\]([\s\S]*?)\[\/size\])|' // 17: [size=val] (18) (19)
      r'(\[([^\]]+)\]\(([^)]+)\))', // 20: [link](url) (21) (22)
      caseSensitive: false,
      dotAll: true,
    );

    int lastMatchEnd = 0;
    for (final match in inlineRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      // Bold **...**
      if (match.group(1) != null) {
        final inner = match.group(2) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      }
      // Italic *...*
      else if (match.group(3) != null) {
        final inner = match.group(4) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      // Underline <u>...</u>
      else if (match.group(5) != null) {
        final inner = match.group(6) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(decoration: TextDecoration.underline),
        ));
      }
      // Underline __...__
      else if (match.group(7) != null) {
        final inner = match.group(8) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(decoration: TextDecoration.underline),
        ));
      }
      // Strikethrough ~~...~~
      else if (match.group(9) != null) {
        final inner = match.group(10) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      }
      // Color [color=val]...[/color]
      else if (match.group(11) != null) {
        final colorVal = match.group(12) ?? '';
        final inner = match.group(13) ?? '';
        final parsedColor = NoticeColorPresets.parseColor(colorVal);
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(color: parsedColor ?? baseStyle.color),
        ));
      }
      // Background highlight [bg=val]...[/bg]
      else if (match.group(14) != null) {
        final bgVal = match.group(15) ?? '';
        final inner = match.group(16) ?? '';
        final parsedBg = NoticeColorPresets.parseColor(bgVal) ?? const Color(0xFFFFF9C4);
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(
            backgroundColor: parsedBg,
            color: const Color(0xFF212121),
          ),
        ));
      }
      // Font size [size=val]...[/size]
      else if (match.group(17) != null) {
        final sizeVal = double.tryParse(match.group(18) ?? '');
        final inner = match.group(19) ?? '';
        spans.addAll(_parseInlineSpans(
          context,
          inner,
          baseStyle.copyWith(fontSize: sizeVal ?? baseStyle.fontSize),
        ));
      }
      // Link [label](url)
      else if (match.group(20) != null) {
        final linkText = match.group(21) ?? '';
        final url = match.group(22) ?? '';
        spans.add(TextSpan(
          text: linkText,
          style: baseStyle.copyWith(
            color: const Color(0xFF1976D2),
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              try {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                debugPrint('Link launch error: $e');
              }
            },
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
