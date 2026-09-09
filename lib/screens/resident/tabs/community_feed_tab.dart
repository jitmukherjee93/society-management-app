import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CommunityFeedTab extends StatefulWidget {
  const CommunityFeedTab({super.key});

  @override
  State<CommunityFeedTab> createState() => _CommunityFeedTabState();
}

class _CommunityFeedTabState extends State<CommunityFeedTab> {
  final _postController = TextEditingController();
  bool _isPosting = false;

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _createPost() async {
    final text = _postController.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to post.')));
      return;
    }

    setState(() => _isPosting = true);
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final authorName = userDoc.data()?['name'] ?? 'Unknown Resident';

      await FirebaseFirestore.instance.collection('posts').add({
        'content': text,
        'authorUid': user.uid,
        'authorName': authorName,
        'likes': [], // Array of UIDs
        'createdAt': FieldValue.serverTimestamp(),
      });

      _postController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _toggleLike(String postId, List<dynamic> currentLikes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final isLiked = currentLikes.contains(uid);

    try {
      if (isLiked) {
        await FirebaseFirestore.instance.collection('posts').doc(postId).update({
          'likes': FieldValue.arrayRemove([uid])
        });
      } else {
        await FirebaseFirestore.instance.collection('posts').doc(postId).update({
          'likes': FieldValue.arrayUnion([uid])
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating like: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          // Create Post Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _postController,
                    decoration: InputDecoration(
                      hintText: "What's happening in the society?",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isPosting 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.send, color: Colors.teal),
                  onPressed: _isPosting ? null : _createPost,
                )
              ],
            ),
          ),
          const Divider(height: 1),
          // Feed
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("It's quiet here. Be the first to post!"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final authorName = data['authorName'] ?? 'Unknown';
                    final content = data['content'] ?? '';
                    final List<dynamic> likes = data['likes'] ?? [];
                    final isLiked = likes.contains(currentUid);
                    final isMyPost = data['authorUid'] == currentUid;
                    
                    String timeAgo = 'Just now';
                    if (data['createdAt'] != null) {
                      final dt = (data['createdAt'] as Timestamp).toDate();
                      timeAgo = DateFormat('MMM d, h:mm a').format(dt);
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.teal.shade100,
                                      child: Text(
                                        authorName.isNotEmpty ? authorName[0].toUpperCase() : '?', 
                                        style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold)
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Text(timeAgo, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                                if (isMyPost)
                                  IconButton(
                                    icon: const Icon(Icons.more_vert),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        builder: (ctx) => SafeArea(
                                          child: Wrap(
                                            children: [
                                              ListTile(
                                                leading: const Icon(Icons.delete, color: Colors.red),
                                                title: const Text('Delete Post', style: TextStyle(color: Colors.red)),
                                                onTap: () {
                                                  FirebaseFirestore.instance.collection('posts').doc(doc.id).delete();
                                                  Navigator.pop(ctx);
                                                },
                                              )
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(content, style: const TextStyle(fontSize: 15)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _toggleLike(doc.id, likes),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isLiked ? Icons.favorite : Icons.favorite_border,
                                          color: isLiked ? Colors.red : Colors.grey,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${likes.length}',
                                          style: TextStyle(
                                            color: isLiked ? Colors.red : Colors.grey,
                                            fontWeight: isLiked ? FontWeight.bold : FontWeight.normal
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comments coming soon!')));
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline, color: Colors.grey.shade600, size: 20),
                                        const SizedBox(width: 6),
                                        Text('Comment', style: TextStyle(color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

