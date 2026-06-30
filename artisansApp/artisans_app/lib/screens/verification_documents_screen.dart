// lib/screens/verification_documents_screen.dart

import 'dart:io';
import 'package:artisans_app/services/api_client.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class VerificationDocumentsScreen extends StatefulWidget {
  const VerificationDocumentsScreen({super.key});

  @override
  State<VerificationDocumentsScreen> createState() =>
      _VerificationDocumentsScreenState();
}

class _VerificationDocumentsScreenState
    extends State<VerificationDocumentsScreen> {
  final ApiClient _apiClient = ApiClient();

  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  String? _error;
  bool _isUploading = false;

  // Allowed file extensions for verification documents
  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'pdf'};
  static const _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiClient.getList('/api/auth/me/verification-documents/');
      if (!mounted) return;
      setState(() {
        _documents = result.cast<Map<String, dynamic>>();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  bool _isValidFile(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid file type. Allowed: ${_allowedExtensions.join(', ')}'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    if (file.lengthSync() > _maxFileSizeBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File too large. Maximum size is 5 MB.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions.toList(),
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.first;
      if (platformFile.path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access the selected file.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final file = File(platformFile.path!);
      if (!_isValidFile(file)) return;

      setState(() => _isUploading = true);

      await _apiClient.uploadFile(
        '/api/auth/me/verification-documents/',
        file: file,
        fieldName: 'document',
        fields: {
          'document_type': _inferDocumentType(platformFile.name),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document uploaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadDocuments();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _inferDocumentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('id') || lower.contains('national')) return 'ID_CARD';
    if (lower.contains('passport')) return 'PASSPORT';
    if (lower.contains('license') || lower.contains('licence')) return 'LICENSE';
    if (lower.contains('certificate') || lower.contains('cert')) return 'CERTIFICATE';
    return 'OTHER';
  }

  Future<void> _deleteDocument(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this verification document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiClient.delete('/api/auth/me/verification-documents/$index/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document deleted.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadDocuments();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _iconForDocType(String? docType) {
    switch (docType?.toUpperCase()) {
      case 'ID_CARD':
        return Icons.badge;
      case 'PASSPORT':
        return Icons.bookmark;
      case 'LICENSE':
        return Icons.card_travel;
      case 'CERTIFICATE':
        return Icons.verified;
      default:
        return Icons.description;
    }
  }

  Color _colorForStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      case 'PENDING':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Documents'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDocuments,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Info banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xFF00897B).withValues(alpha: 0.1),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF00897B)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Upload verification documents (ID, certificate, etc.) to verify your artisan account. Accepted formats: JPG, PNG, PDF (max 5 MB).',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Document list
                    Expanded(
                      child: _documents.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.upload_file,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No documents uploaded yet.',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: _isUploading ? null : _pickAndUploadFile,
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Upload Document'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadDocuments,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _documents.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == _documents.length) {
                                    // Upload button at the bottom of list
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: ElevatedButton.icon(
                                        onPressed: _isUploading ? null : _pickAndUploadFile,
                                        icon: _isUploading
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.upload),
                                        label: Text(_isUploading ? 'Uploading...' : 'Upload Document'),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final doc = _documents[index];
                                  final docType = doc['document_type'] as String?;
                                  final status = doc['status'] as String?;
                                  final fileName = doc['file'] as String? ?? 'Document ${index + 1}';
                                  final uploadedAt = doc['uploaded_at'] as String?;
                                  final docIndex = doc['id'] as int? ?? index;

                                  return _buildDocumentCard(
                                    docType: docType,
                                    fileName: fileName,
                                    status: status,
                                    uploadedAt: uploadedAt,
                                    docIndex: docIndex,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDocumentCard({
    required String? docType,
    required String fileName,
    required String? status,
    required String? uploadedAt,
    required int docIndex,
  }) {
    final icon = _iconForDocType(docType);
    final statusColor = _colorForStatus(status);
    final displayType = docType?.replaceAll('_', ' ') ?? 'Document';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF00897B), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayType,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileName.split('/').last,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (uploadedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Uploaded ${_formatDate(uploadedAt)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                (status ?? 'PENDING').replaceAll('_', ' '),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _deleteDocument(docIndex),
              tooltip: 'Delete document',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}