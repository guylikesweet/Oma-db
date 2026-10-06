import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data/api_client.dart';
import 'core/network_errors.dart';
import 'data/app_session.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final username = TextEditingController();
  final currentPassword = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  Uint8List? photo;
  String? currentPhotoUrl;
  Uint8List? currentPhotoBytes;
  bool loading = true;
  bool saving = false;
  bool obscureCurrentPassword = true;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    username.dispose();
    currentPassword.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final profile = await widget.api.getProfile();
      if (!mounted) return;
      username.text = '${profile['username'] ?? AppSession.username}';
      currentPhotoUrl = profile['profile_photo_url']?.toString();
      if (currentPhotoUrl != null && currentPhotoUrl!.isNotEmpty) {
        try {
          currentPhotoBytes = await widget.api.downloadChatAttachment(currentPhotoUrl!);
        } catch (_) {
          // Keep the initials fallback if the protected avatar cannot be loaded.
        }
      }
      setState(() => loading = false);
    } catch (e) {
      if (mounted) setState(() { loading = false; error = userFacingError(e); });
    }
  }

  Future<void> pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1000,
      maxHeight: 1000,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => photo = bytes);
  }

  Future<void> save() async {
    if (password.text.isNotEmpty && password.text != confirm.text) {
      setState(() => error = 'Passwords do not match.');
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      Map<String, dynamic>? passwordResult;
      if (password.text.isNotEmpty) {
        if (currentPassword.text.isEmpty) {
          throw Exception('Enter your current password to set a new password.');
        }
        passwordResult = await widget.api.changePassword(
          currentPassword.text,
          password.text,
        );
        await widget.api.clearBiometricCredential();
      }

      final payload = <String, dynamic>{'username': username.text.trim()};
      if (photo != null) payload['profile_photo_base64'] = base64Encode(photo!);
      final result = await widget.api.updateProfile(payload);
      if (passwordResult != null && passwordResult['token'] != null) {
        await widget.api.saveToken('${passwordResult['token']}');
      }
      if (result['profile_photo_url'] != null) {
        currentPhotoUrl = result['profile_photo_url'].toString();
        try {
          currentPhotoBytes = await widget.api.downloadChatAttachment(currentPhotoUrl!);
        } catch (_) {}
      }
      currentPassword.clear();
      password.clear();
      confirm.clear();
      await AppSession.refresh(widget.api);
      if (mounted) {
        setState(() { saving = false; photo = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { saving = false; error = userFacingError(e); });
      if (classifyNetworkError(e) != null) {
        showNetworkError(context, e, onRetry: save);
      }
    }
  }

  Widget avatar() {
    final ImageProvider<Object>? image = photo != null
        ? MemoryImage(photo!)
        : (currentPhotoBytes == null ? null : MemoryImage(currentPhotoBytes!));
    return CircleAvatar(
      radius: 54,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: image,
      child: image == null
          ? Text(
              username.text.isEmpty ? '?' : username.text[0].toUpperCase(),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                avatar(),
                IconButton.filled(
                  onPressed: saving ? null : pickPhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('Profile photo is automatically compressed for team use.')),
          const SizedBox(height: 24),
          TextField(
            controller: username,
            enabled: !saving,
            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: currentPassword,
            enabled: !saving,
            obscureText: obscureCurrentPassword,
            decoration: InputDecoration(
              labelText: 'Current password (required when changing it)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscureCurrentPassword = !obscureCurrentPassword),
                icon: Icon(
                  obscureCurrentPassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: password,
            enabled: !saving,
            obscureText: obscurePassword,
            decoration: InputDecoration(
              labelText: 'New password (optional)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscurePassword = !obscurePassword),
                icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            enabled: !saving,
            obscureText: obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Saving…' : 'Save profile'),
          ),
        ],
      ),
    );
  }
}
