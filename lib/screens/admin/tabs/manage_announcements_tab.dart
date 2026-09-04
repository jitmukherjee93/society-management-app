import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageAnnouncementsTab extends StatelessWidget {
  const ManageAnnouncementsTab({super.key});

  void _showAddAnnouncementDialog(BuildContext context) {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    bool isPinned = false;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('New Announcement'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageController,
                      decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
                      maxLines: 5,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Pin to top'),
                      value: isPinned,
                      onChanged: (val) => setState(() => isPinned = val),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (titleController.text.trim().isEmpty || messageController.text.trim().isEmpty) return;
                    setState(() => isLoading = true);
                    
                    try {
                      await FirebaseFirestore.instance.collection('announcements').add({
                        'title': titleController.text.trim(),
                        'message': messageController.text.trim(),
                        'isPinned': isPinned,
                        'authorName': 'Admin', 
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                      setState(() => isLoading = false);
                    }
                  },
                  child: isLoading ? const CircularProgressIndicator() : const Text('Post'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('announcements')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No announcements yet.'));
          }

          // Sort pinned to top locally
          docs.sort((a, b) {
            final aPinned = (a.data() as Map<String, dynamic>)['isPinned'] ?? false;
            final bPinned = (b.data() as Map<String, dynamic>)['isPinned'] ?? false;
            if (aPinned && !bPinned) return -1;
            if (!aPinned && bPinned) return 1;
            return 0; // retain createdAt sort order
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final isPinned = data['isPinned'] ?? false;
              
              return Card(
                elevation: isPinned ? 4 : 1,
                color: isPinned ? Colors.deepPurple.shade50 : null,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isPinned) const Icon(Icons.push_pin, color: Colors.deepPurple, size: 20),
                                if (isPinned) const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    data['title'] ?? '',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Announcement?'),
                                  content: const Text('This will remove it from all resident dashboards.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () {
                                        FirebaseFirestore.instance.collection('announcements').doc(docs[index].id).delete();
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                )
                              );
                            },
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(data['message'] ?? '', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAnnouncementDialog(context),
        icon: const Icon(Icons.campaign),
        label: const Text('New Announcement'),
      ),
    );
  }
}
