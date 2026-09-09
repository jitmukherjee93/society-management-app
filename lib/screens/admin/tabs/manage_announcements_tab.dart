import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../models/notice_model.dart';
import '../../../widgets/notices/notice_card_widget.dart';
import '../../../widgets/notices/notice_editor_dialog.dart';

class ManageAnnouncementsTab extends StatefulWidget {
  const ManageAnnouncementsTab({super.key});

  @override
  State<ManageAnnouncementsTab> createState() => _ManageAnnouncementsTabState();
}

class _ManageAnnouncementsTabState extends State<ManageAnnouncementsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool? _isTwoColumnView;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTwoColumn = _isTwoColumnView ?? (constraints.maxWidth >= 600);

          return Column(
            children: [
              // Top Header & Search Bar
              _buildHeader(context, isTwoColumn),

              // Notices List Stream
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('announcements')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text('Error loading notices: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final allNotices = docs.map((d) => NoticeModel.fromFirestore(d)).toList();

                    // Stats count
                    final totalNotices = allNotices.length;
                    final pinnedCount = allNotices.where((n) => n.isPinned).length;
                    final urgentCount = allNotices.where((n) => n.priority == NoticePriority.urgent).length;

                    // Filter by category and search query
                    final filteredNotices = allNotices.where((notice) {
                      final matchesCategory = _selectedCategory == 'All' ||
                          notice.category.name.toLowerCase() == _selectedCategory.toLowerCase() ||
                          notice.category.label.toLowerCase() == _selectedCategory.toLowerCase();

                      final query = _searchQuery.toLowerCase().trim();
                      final matchesSearch = query.isEmpty ||
                          notice.title.toLowerCase().contains(query) ||
                          notice.content.toLowerCase().contains(query);

                      return matchesCategory && matchesSearch;
                    }).toList();

                    // Sort: Pinned notices first, then newest
                    filteredNotices.sort((a, b) {
                      if (a.isPinned && !b.isPinned) return -1;
                      if (!a.isPinned && b.isPinned) return 1;
                      return b.createdAt.compareTo(a.createdAt);
                    });

                    // Distribute into 2 columns if 2-column view is active
                    final col1 = <NoticeModel>[];
                    final col2 = <NoticeModel>[];
                    if (isTwoColumn) {
                      for (int i = 0; i < filteredNotices.length; i++) {
                        if (i % 2 == 0) {
                          col1.add(filteredNotices[i]);
                        } else {
                          col2.add(filteredNotices[i]);
                        }
                      }
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1140),
                        child: CustomScrollView(
                          slivers: [
                            // Compact Stats Strip
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                                child: _buildStatsStrip(totalNotices, pinnedCount, urgentCount),
                              ),
                            ),

                            // Empty State
                            if (filteredNotices.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.campaign_outlined, size: 36, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _searchQuery.isNotEmpty || _selectedCategory != 'All'
                                            ? 'No notices match your filter.'
                                            : 'No society notices issued yet.',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Create announcements to broadcast updates to all residents.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: () => NoticeEditorDialog.show(context),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E293B),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        icon: const Icon(Icons.add, size: 16),
                                        label: const Text('Create First Notice', style: TextStyle(fontSize: 12.5)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (isTwoColumn)
                              // Two Column Side-by-Side View
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                                sliver: SliverToBoxAdapter(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: col1.map((notice) => NoticeCardWidget(
                                            key: ValueKey(notice.id),
                                            notice: notice,
                                            isAdmin: true,
                                          )).toList(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: col2.map((notice) => NoticeCardWidget(
                                            key: ValueKey(notice.id),
                                            notice: notice,
                                            isAdmin: true,
                                          )).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              // Single Column List View
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final notice = filteredNotices[index];
                                      return NoticeCardWidget(
                                        key: ValueKey(notice.id),
                                        notice: notice,
                                        isAdmin: true,
                                      );
                                    },
                                    childCount: filteredNotices.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTwoColumn) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search notices, circulars, meetings...',
                          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Column Layout Toggle
                  Tooltip(
                    message: isTwoColumn ? 'Switch to Single Column List' : 'Switch to 2-Column Side by Side',
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isTwoColumnView = !isTwoColumn;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isTwoColumn ? Icons.view_column_rounded : Icons.view_agenda_outlined,
                              size: 18,
                              color: const Color(0xFF334155),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isTwoColumn ? '2 Columns' : '1 Column',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    onPressed: () => NoticeEditorDialog.show(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0.5,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('New Notice', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Category Chips Filter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCategoryChip('All', null),
                    ...NoticeCategory.values.map((c) => _buildCategoryChip(c.label, c)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, NoticeCategory? cat) {
    final isSelected = _selectedCategory == label || (cat != null && _selectedCategory == cat.name);
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: FilterChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selected: isSelected,
        avatar: cat != null
            ? Icon(cat.icon, size: 12, color: isSelected ? Colors.white : cat.color)
            : null,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF1E293B),
        checkmarkColor: Colors.white,
        showCheckmark: false,
        side: BorderSide(
          color: isSelected ? Colors.transparent : const Color(0xFFCBD5E1),
          width: 0.8,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        onSelected: (selected) {
          setState(() {
            _selectedCategory = selected ? label : 'All';
          });
        },
      ),
    );
  }

  Widget _buildStatsStrip(int total, int pinned, int urgent) {
    return Row(
      children: [
        _buildMiniBadge(
          icon: Icons.campaign_rounded,
          label: '$total Total',
          color: const Color(0xFF3F51B5),
        ),
        const SizedBox(width: 8),
        if (pinned > 0) ...[
          _buildMiniBadge(
            icon: Icons.push_pin_rounded,
            label: '$pinned Pinned',
            color: const Color(0xFFE65100),
          ),
          const SizedBox(width: 8),
        ],
        if (urgent > 0) ...[
          _buildMiniBadge(
            icon: Icons.warning_amber_rounded,
            label: '$urgent Urgent',
            color: const Color(0xFFD32F2F),
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        Text(
          _selectedCategory == 'All' ? 'Showing all notices' : 'Filtered by $_selectedCategory',
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildMiniBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
