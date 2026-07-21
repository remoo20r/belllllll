import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/preset_servers.dart';
import '../../../data/models/xtream_profile.dart';
import '../../../data/services/device_mode_service.dart';
import '../../../data/services/xtream_api_service.dart';
import '../../../state/profile_providers.dart';
import '../../common/app_logo.dart';
import '../../common/support_contact_bar.dart';
import '../../common/tv_focusable.dart';
import '../../common/tv_text_field.dart';

/// Login / add-playlist screen.
///
/// The user picks a server *by name* (the real host URL is hidden, see
/// [kPresetServers]), types a username + password, and chooses the device
/// type (phone / TV). Everything Xtream — M3U is no longer offered here.
class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key, this.existingProfile});

  final XtreamProfile? existingProfile;

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  final _deviceService = DeviceModeService();

  /// Currently selected preset server (by index into [kPresetServers]).
  int _serverIndex = 0;

  /// Currently selected device mode (phone / TV).
  DeviceMode _deviceMode = DeviceMode.touch;

  bool _obscurePassword = true;
  bool _saving = false;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _usernameController = TextEditingController(text: p?.username ?? '');
    _passwordController = TextEditingController();

    // Pre-select the saved device mode (falls back to phone/touch).
    _deviceMode = _deviceService.getSaved() ?? DeviceMode.touch;

    // When editing, try to match the profile's host back to a preset so the
    // right server stays selected; otherwise keep the first one.
    if (p != null) {
      final normalized = XtreamApiService.normalizeHost(p.host);
      final match = kPresetServers.indexWhere(
        (s) => XtreamApiService.normalizeHost(s.host) == normalized,
      );
      if (match != -1) _serverIndex = match;

      if (p.kind == PlaylistKind.xtream) {
        ref.read(profileRepositoryProvider).getPassword(p.id).then((pw) {
          if (pw != null && mounted) _passwordController.text = pw;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Persist the chosen device mode so the whole app adapts (TV vs touch).
    await _deviceService.save(_deviceMode);

    final repo = ref.read(profileRepositoryProvider);
    final id = widget.existingProfile?.id ?? repo.newId();
    final server = kPresetServers[_serverIndex];

    final profile = XtreamProfile(
      id: id,
      // Name the profile after the server so it's recognisable in the list.
      name: server.name,
      host: XtreamApiService.normalizeHost(server.host),
      username: _usernameController.text.trim(),
      kind: PlaylistKind.xtream,
    );
    final password = _passwordController.text;

    await ref.read(profilesProvider.notifier).upsert(profile, password: password);

    if (!mounted) return;
    setState(() => _saving = false);

    // Make the just-saved server the active one.
    ref.read(selectedProfileIdProvider.notifier).select(profile.id);

    if (_isEditing && context.canPop()) {
      // Reached from Settings: go back where we came from.
      context.pop();
    } else {
      // Fresh sign-in: enter the app.
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: compact ? 16 : 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ---- Brand header -------------------------------
                        Center(
                          child: Column(
                            children: [
                              const AppLogo(size: 56),
                              SizedBox(height: compact ? 10 : 16),
                              Text(
                                _isEditing ? 'Edit Playlist' : 'Sign In',
                                style: Theme.of(context).textTheme.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Choose your server and enter your credentials',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 20 : 32),

                        // ---- Server selector ----------------------------
                        _FieldLabel('Server'),
                        const SizedBox(height: 8),
                        _ServerSelector(
                          servers: kPresetServers,
                          selectedIndex: _serverIndex,
                          onSelected: (i) => setState(() => _serverIndex = i),
                        ),
                        const SizedBox(height: 18),

                        // ---- Username -----------------------------------
                        _FieldLabel('Username'),
                        const SizedBox(height: 8),
                        TvTextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_outline),
                            hintText: 'Enter your username',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 18),

                        // ---- Password -----------------------------------
                        _FieldLabel('Password'),
                        const SizedBox(height: 8),
                        TvTextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline),
                            hintText: 'Enter your password',
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 18),

                        // ---- Device selector ----------------------------
                        _FieldLabel('Device'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _DeviceChip(
                                icon: Icons.smartphone,
                                label: 'Phone / Tablet',
                                selected: _deviceMode == DeviceMode.touch,
                                onTap: () => setState(
                                    () => _deviceMode = DeviceMode.touch),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DeviceChip(
                                icon: Icons.tv,
                                label: 'TV / Remote',
                                selected: _deviceMode == DeviceMode.tv,
                                onTap: () => setState(
                                    () => _deviceMode = DeviceMode.tv),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 22 : 30),

                        // ---- Sign-in button -----------------------------
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black),
                                  )
                                : Text(_isEditing ? 'Save' : 'Sign In'),
                          ),
                        ),
                        SizedBox(height: compact ? 20 : 28),

                        // ---- Support contact ----------------------------
                        const SupportContactBar(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small uppercase label above a field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// Dropdown-style server picker that shows names only. Opens a themed bottom
/// sheet so it works with both touch and a TV remote (via [TvFocusable]).
class _ServerSelector extends StatelessWidget {
  const _ServerSelector({
    required this.servers,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<PresetServer> servers;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Select Server',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (int i = 0; i < servers.length; i++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: TvFocusable(
                    autofocus: i == selectedIndex,
                    borderRadius: 14,
                    onTap: () => Navigator.of(context).pop(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: i == selectedIndex
                            ? AppColors.gold.withValues(alpha: 0.14)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: i == selectedIndex
                              ? AppColors.gold
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.dns_outlined,
                              color: AppColors.gold, size: 20),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              servers[i].name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (i == selectedIndex)
                            const Icon(Icons.check_circle,
                                color: AppColors.gold, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 14,
      onTap: () => _openPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, color: AppColors.gold, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                servers[selectedIndex].name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// A selectable device-type chip (phone / TV).
class _DeviceChip extends StatelessWidget {
  const _DeviceChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 14,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.glassBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? AppColors.gold : AppColors.textSecondary,
                size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
