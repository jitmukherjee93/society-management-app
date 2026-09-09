import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/notice_model.dart';
import '../../utils/storage_utils.dart';
import 'notice_rich_formatter.dart';

class NoticeEditorDialog extends StatefulWidget {
  final NoticeModel? initialNotice;

  const NoticeEditorDialog({super.key, this.initialNotice});

  static Future<bool?> show(BuildContext context, {NoticeModel? notice}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => NoticeEditorDialog(initialNotice: notice),
    );
  }

  @override
  State<NoticeEditorDialog> createState() => _NoticeEditorDialogState();
}

class _NoticeEditorDialogState extends State<NoticeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late UndoHistoryController _undoController;

  NoticeCategory _category = NoticeCategory.general;
  NoticePriority _priority = NoticePriority.medium;
  bool _isPinned = false;
  String _targetAudience = 'All Residents';
  DateTime? _validUntil;

  bool _isLoading = false;
  String _loadingStatus = '';
  int _tabIndex = 0; // 0 = Compose, 1 = Live Preview

  @override
  void initState() {
    super.initState();
    final n = widget.initialNotice;
    _titleController = TextEditingController(text: n?.title ?? '');
    _contentController = TextEditingController(text: n?.content ?? '');
    _undoController = UndoHistoryController();

    if (n != null) {
      _category = n.category;
      _priority = n.priority;
      _isPinned = n.isPinned;
      _targetAudience = n.targetAudience;
      _validUntil = n.validUntil;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  /// Inserts or wraps text around current cursor selection
  void _applyFormat(String prefix, String suffix, {String defaultText = 'text'}) {
    final text = _contentController.text;
    final selection = _contentController.selection;

    if (!selection.isValid || selection.isCollapsed) {
      final cursor = selection.isValid ? selection.start : text.length;
      final newText = text.replaceRange(cursor, cursor, '$prefix$defaultText$suffix');
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: cursor + prefix.length,
          extentOffset: cursor + prefix.length + defaultText.length,
        ),
      );
    } else {
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '$prefix$selectedText$suffix',
      );
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + prefix.length + selectedText.length + suffix.length,
        ),
      );
    }
    setState(() {});
  }

  void _insertLinePrefix(String linePrefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursor = selection.isValid ? selection.start : text.length;

    int lineStart = cursor > 0 ? text.lastIndexOf('\n', cursor - 1) + 1 : 0;
    if (lineStart < 0) lineStart = 0;

    final newText = text.replaceRange(lineStart, lineStart, linePrefix);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor + linePrefix.length),
    );
    setState(() {});
  }

  void _insertAtCursor(String insertion) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursor = selection.isValid ? selection.start : text.length;

    final newText = text.replaceRange(cursor, cursor, insertion);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor + insertion.length),
    );
    setState(() {});
  }

  /// Cut selected text to clipboard
  Future<void> _cutText() async {
    final selection = _contentController.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selectedText = _contentController.text.substring(selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: selectedText));

    final newText = _contentController.text.replaceRange(selection.start, selection.end, '');
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cut to clipboard'), duration: Duration(seconds: 1)),
      );
    }
    setState(() {});
  }

  /// Copy selected text to clipboard
  Future<void> _copyText() async {
    final selection = _contentController.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selectedText = _contentController.text.substring(selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: selectedText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// Paste text from clipboard at cursor
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasteContent = data?.text;
    if (pasteContent == null || pasteContent.isEmpty) return;

    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    final newText = text.replaceRange(start, end, pasteContent);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + pasteContent.length),
    );
    setState(() {});
  }

  /// Uploads image and inserts inline tag `![filename](url)`
  Future<void> _insertInlineImage() async {
    try {
      final file = await pickFile(
        context: context,
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
        performReadabilityCheck: true,
      );
      if (file == null) return;

      setState(() {
        _isLoading = true;
        _loadingStatus = 'Uploading inline photo ${file.name}...';
      });

      final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storagePath = 'notices/inline/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final downloadUrl = await uploadFile(file, storagePath);

      if (downloadUrl != null) {
        _insertAtCursor('\n\n![]($downloadUrl)\n\n');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2E7D32),
              content: Text('Inserted inline image "${file.name}" at cursor!'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Uploads document/PDF and inserts inline tag `[doc:url|filename]`
  Future<void> _insertInlineDocument() async {
    try {
      final file = await pickFile(
        context: context,
        extensions: ['pdf', 'docx', 'xlsx', 'xls', 'csv'],
        performReadabilityCheck: true,
      );
      if (file == null) return;

      setState(() {
        _isLoading = true;
        _loadingStatus = 'Uploading inline document ${file.name}...';
      });

      final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storagePath = 'notices/inline/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final downloadUrl = await uploadFile(file, storagePath);

      if (downloadUrl != null) {
        _insertAtCursor('\n\n[doc:$downloadUrl|${file.name}]\n\n');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2E7D32),
              content: Text('Inserted inline document "${file.name}" at cursor!'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Text Color',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: NoticeColorPresets.textColors.map((color) {
                  final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFormat('[color=$hex]', '[/color]', defaultText: 'Colored text');
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Background Highlight',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: NoticeColorPresets.bgColors.map((color) {
                  final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFormat('[bg=$hex]', '[/bg]', defaultText: 'Highlighted text');
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black26, width: 1),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showCalloutPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Insert Callout / Alert Box',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                title: const Text('Urgent Alert Box'),
                onTap: () {
                  Navigator.pop(ctx);
                  _insertLinePrefix('> [!ALERT] Emergency water outage from 2 PM to 5 PM.\n');
                },
              ),
              ListTile(
                leading: const Icon(Icons.error_outline_rounded, color: Colors.orange),
                title: const Text('Warning / Action Box'),
                onTap: () {
                  Navigator.pop(ctx);
                  _insertLinePrefix('> [!WARNING] Please park vehicles strictly in allotted slots.\n');
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: Colors.blue),
                title: const Text('Information Box'),
                onTap: () {
                  Navigator.pop(ctx);
                  _insertLinePrefix('> [!INFO] Clubhouse maintenance will occur this Sunday.\n');
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                title: const Text('Success / Resolved Box'),
                onTap: () {
                  Navigator.pop(ctx);
                  _insertLinePrefix('> [!SUCCESS] Lift repair work completed successfully.\n');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveNotice() async {
    if (!_formKey.currentState!.validate()) {
      if (_tabIndex != 0) setState(() => _tabIndex = 0);
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = 'Publishing notice...';
    });

    try {
      final noticeId = widget.initialNotice?.id ?? FirebaseFirestore.instance.collection('announcements').doc().id;

      final noticeData = {
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'message': _contentController.text.trim(), // legacy sync
        'category': _category.name,
        'priority': _priority.name,
        'isPinned': _isPinned,
        'targetAudience': _targetAudience,
        'authorName': 'Admin',
        'authorRole': 'RWA Management',
        'createdAt': widget.initialNotice?.createdAt != null
            ? Timestamp.fromDate(widget.initialNotice!.createdAt)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'validUntil': _validUntil != null ? Timestamp.fromDate(_validUntil!) : null,
      };

      if (widget.initialNotice != null) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(widget.initialNotice!.id)
            .update(noticeData);
      } else {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(noticeId)
            .set(noticeData);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text(widget.initialNotice != null ? 'Notice updated successfully.' : 'Notice published successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLargeScreen = size.width > 700;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_undoController.value.canUndo) _undoController.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          if (_undoController.value.canUndo) _undoController.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (_undoController.value.canRedo) _undoController.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () {
          if (_undoController.value.canRedo) _undoController.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () {
          if (_undoController.value.canRedo) _undoController.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () {
          if (_undoController.value.canRedo) _undoController.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _applyFormat('**', '**', defaultText: 'Bold Text'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _applyFormat('*', '*', defaultText: 'Italic Text'),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _applyFormat('<u>', '</u>', defaultText: 'Underlined Text'),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: isLargeScreen ? 680 : double.infinity,
          constraints: BoxConstraints(maxHeight: size.height * 0.88),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: Colors.amber, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialNotice != null ? 'Edit Notice / Announcement' : 'Issue New Society Notice',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Inline photos & documents, rich formatting & colors',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Tab Switcher (Compose vs Live Preview)
                Container(
                  color: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 0,
                              icon: Icon(Icons.edit_note_rounded, size: 18),
                              label: Text('Compose Notice'),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              icon: Icon(Icons.visibility_outlined, size: 18),
                              label: Text('Live Preview'),
                            ),
                          ],
                          selected: {_tabIndex},
                          onSelectionChanged: (set) {
                            setState(() => _tabIndex = set.first);
                          },
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Body
                Expanded(
                  child: _tabIndex == 0 ? _buildComposeTab() : _buildLivePreviewTab(),
                ),

                // Bottom Actions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isLoading)
                        Expanded(
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _loadingStatus,
                                  style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancel'),
                        ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveNotice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: Text(widget.initialNotice != null ? 'Update Notice' : 'Publish Notice'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Notice Headline / Title *',
              hintText: 'e.g. Annual General Meeting (AGM) Notice',
              prefixIcon: const Icon(Icons.title_rounded, color: Color(0xFF475569)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
          ),
          const SizedBox(height: 16),

          // Category & Priority Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<NoticeCategory>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: NoticeCategory.values.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(c.icon, size: 18, color: c.color),
                          const SizedBox(width: 8),
                          Text(c.label, style: const TextStyle(fontSize: 13.5)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _category = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<NoticePriority>(
                  initialValue: _priority,
                  decoration: InputDecoration(
                    labelText: 'Priority Level',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: NoticePriority.values.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(p.label, style: const TextStyle(fontSize: 13.5)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _priority = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Audience & Pin to Top Switch Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _targetAudience,
                  decoration: InputDecoration(
                    labelText: 'Audience',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All Residents', child: Text('All Residents', style: TextStyle(fontSize: 13.5))),
                    DropdownMenuItem(value: 'Owners Only', child: Text('Owners Only', style: TextStyle(fontSize: 13.5))),
                    DropdownMenuItem(value: 'Tenants Only', child: Text('Tenants Only', style: TextStyle(fontSize: 13.5))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _targetAudience = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.push_pin_outlined, size: 18, color: Color(0xFF64748B)),
                          SizedBox(width: 6),
                          Text('Pin on top', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      Switch(
                        value: _isPinned,
                        activeThumbColor: const Color(0xFF3F51B5),
                        onChanged: (val) => setState(() => _isPinned = val),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rich Formatting Toolbar with Inline Media buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Undo / Redo
                ListenableBuilder(
                  listenable: _undoController,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolbarBtn(
                          icon: Icons.undo_rounded,
                          tooltip: 'Undo (Ctrl+Z)',
                          onTap: _undoController.value.canUndo ? () => _undoController.undo() : null,
                          color: _undoController.value.canUndo ? const Color(0xFF1E293B) : Colors.black26,
                        ),
                        _buildToolbarBtn(
                          icon: Icons.redo_rounded,
                          tooltip: 'Redo (Ctrl+Y)',
                          onTap: _undoController.value.canRedo ? () => _undoController.redo() : null,
                          color: _undoController.value.canRedo ? const Color(0xFF1E293B) : Colors.black26,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: 10, thickness: 1)),

                // Cut / Copy / Paste
                _buildToolbarBtn(
                  icon: Icons.content_cut_rounded,
                  tooltip: 'Cut (Ctrl+X)',
                  onTap: _cutText,
                ),
                _buildToolbarBtn(
                  icon: Icons.content_copy_rounded,
                  tooltip: 'Copy (Ctrl+C)',
                  onTap: _copyText,
                ),
                _buildToolbarBtn(
                  icon: Icons.content_paste_rounded,
                  tooltip: 'Paste (Ctrl+V)',
                  onTap: _pasteText,
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: 10, thickness: 1)),

                // Inline Media Upload Buttons
                _buildToolbarBtn(
                  icon: Icons.add_photo_alternate_rounded,
                  tooltip: 'Upload & Insert Inline Photo at Cursor',
                  color: const Color(0xFF0284C7),
                  onTap: _isLoading ? null : _insertInlineImage,
                ),
                _buildToolbarBtn(
                  icon: Icons.picture_as_pdf_rounded,
                  tooltip: 'Upload & Insert Inline PDF / Doc at Cursor',
                  color: const Color(0xFFDC2626),
                  onTap: _isLoading ? null : _insertInlineDocument,
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: 10, thickness: 1)),

                // Headings
                _buildToolbarBtn(
                  icon: Icons.title_rounded,
                  tooltip: 'Heading 1 (# )',
                  onTap: () => _insertLinePrefix('# '),
                ),
                _buildToolbarBtn(
                  icon: Icons.format_size_rounded,
                  tooltip: 'Heading 2 (## )',
                  onTap: () => _insertLinePrefix('## '),
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: 10, thickness: 1)),

                // Styles
                _buildToolbarBtn(
                  icon: Icons.format_bold_rounded,
                  tooltip: 'Bold (**text** / Ctrl+B)',
                  onTap: () => _applyFormat('**', '**', defaultText: 'Bold Text'),
                ),
                _buildToolbarBtn(
                  icon: Icons.format_italic_rounded,
                  tooltip: 'Italic (*text* / Ctrl+I)',
                  onTap: () => _applyFormat('*', '*', defaultText: 'Italic Text'),
                ),
                _buildToolbarBtn(
                  icon: Icons.format_underlined_rounded,
                  tooltip: 'Underline (<u>text</u> / Ctrl+U)',
                  onTap: () => _applyFormat('<u>', '</u>', defaultText: 'Underlined Text'),
                ),
                _buildToolbarBtn(
                  icon: Icons.format_strikethrough_rounded,
                  tooltip: 'Strikethrough (~~text~~)',
                  onTap: () => _applyFormat('~~', '~~', defaultText: 'Strikethrough Text'),
                ),
                const SizedBox(height: 20, child: VerticalDivider(width: 10, thickness: 1)),

                // Colors & Helpers
                _buildToolbarBtn(
                  icon: Icons.palette_outlined,
                  tooltip: 'Text Color & Highlight',
                  color: Colors.indigo,
                  onTap: _showColorPicker,
                ),
                _buildToolbarBtn(
                  icon: Icons.format_list_bulleted_rounded,
                  tooltip: 'Bullet list (• )',
                  onTap: () => _insertLinePrefix('• '),
                ),
                _buildToolbarBtn(
                  icon: Icons.format_list_numbered_rounded,
                  tooltip: 'Numbered list (1. )',
                  onTap: () => _insertLinePrefix('1. '),
                ),
                _buildToolbarBtn(
                  icon: Icons.warning_amber_rounded,
                  tooltip: 'Callout Box (> [!ALERT])',
                  color: Colors.orange.shade800,
                  onTap: _showCalloutPicker,
                ),
                _buildToolbarBtn(
                  icon: Icons.horizontal_rule_rounded,
                  tooltip: 'Divider line (---)',
                  onTap: () => _insertLinePrefix('---\n'),
                ),
              ],
            ),
          ),

          // Message Body Field with native undo/redo & context menu
          TextFormField(
            controller: _contentController,
            undoController: _undoController,
            maxLines: 12,
            style: const TextStyle(fontSize: 14.5, height: 1.4, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Type notice content here...\n\nClick the 📷 Photo or 📄 PDF icon in the toolbar above to upload and insert photos/documents directly inline with your text at the cursor position!',
              border: OutlineInputBorder(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Please enter notice content' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 19, color: color ?? const Color(0xFF334155)),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }

  Widget _buildLivePreviewTab() {
    final title = _titleController.text.trim().isEmpty ? 'Notice Title Preview' : _titleController.text.trim();
    final content = _contentController.text.trim().isEmpty ? '*No content written yet. Switch back to Compose to write formatted notice text.*' : _contentController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.preview_rounded, size: 18, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Text(
                'How this Notice will appear to residents (with inline photos/docs):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preview Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _isPinned ? _category.color.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                width: _isPinned ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _category.backgroundColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(_category.icon, size: 14, color: _category.color),
                            const SizedBox(width: 5),
                            Text(
                              _category.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _category.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _priority.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _priority.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _priority.color,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_isPinned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.push_pin, size: 13, color: Colors.deepOrange),
                              SizedBox(width: 3),
                              Text('Pinned', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Author & Date
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: Color(0xFF1E293B),
                        child: Text('A', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Admin • RWA Management',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                      ),
                      SizedBox(width: 8),
                      Text('• Just now', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),

                  // Formatted Rich Text Body with inline media
                  NoticeRichText(content: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
