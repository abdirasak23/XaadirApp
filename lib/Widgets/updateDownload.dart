// lib/update_download_popup.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Services/UpdateDownloadService.dart';

class _C {
  static const Color card = Color(0xFFF1F3F7);
  static const Color ink = Color(0xFF0F172A);
  static const Color dim = Color(0xFF6B7280);
  static const Color orange = Color(0xFFE09112);
  static const Color blue = Color(0xFF3B82F6);
}

const String _font = 'Poppins';

Color _tint(Color c, double opacity) => c.withAlpha((opacity * 255).round());

/// Shows the update popup. Closable until [UpdateInfo.locked]; then it cannot
/// be closed (no button, no back, no tap outside).
Future<void> showUpdateDownloadPopup(BuildContext context, UpdateInfo info) {
  HapticFeedback.mediumImpact();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDownloadPopup(info: info),
  );
}

class UpdateDownloadPopup extends StatefulWidget {
  const UpdateDownloadPopup({super.key, required this.info});
  final UpdateInfo info;

  @override
  State<UpdateDownloadPopup> createState() => _UpdateDownloadPopupState();
}

class _UpdateDownloadPopupState extends State<UpdateDownloadPopup> {
  bool _opening = false;

  UpdateInfo get _i => widget.info;

  Future<void> _update() async {
    if (_opening) return;
    setState(() => _opening = true);
    final ok = await UpdateDownloadService.instance.openStore(_i);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not open the store. Please try again.', style: TextStyle(fontFamily: _font)),
        ));
    }
  }

  Future<void> _close() async {
    await UpdateDownloadService.instance.registerClose(_i);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _i.locked;
    final tone = locked ? _C.orange : _C.blue;
    final storeName = _i.isIos ? 'TestFlight' : 'Google Play';

    return PopScope(
      canPop: false, // back button never closes it; "Later" does (when allowed)
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _tint(tone, 0.14), shape: BoxShape.circle),
                    child: Icon(
                      locked ? Icons.lock_rounded : Icons.system_update_rounded,
                      size: 42,
                      color: tone,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  locked ? 'Update required' : 'Update available',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: _font, fontSize: 24, fontWeight: FontWeight.w700, color: _C.ink, height: 1.25),
                ),
                if (_i.version.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _tint(tone, 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text('Version ${_i.version}',
                          style: TextStyle(
                              fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600, color: tone)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  locked
                      ? 'You closed this ${_i.maxCloses} times. Please update the app to continue. '
                      '${_i.message}'
                      : _i.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w400, color: _C.dim, height: 1.5),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _opening ? null : _update,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.ink,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _C.ink.withAlpha(150),
                      disabledForegroundColor: Colors.white70,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _opening
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text('Update on $storeName',
                        style: const TextStyle(
                            fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
                if (!locked) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: _opening ? null : _close,
                      style: TextButton.styleFrom(foregroundColor: _C.ink),
                      child: Text(
                        _i.closesLeft == 1 ? 'Later · last time you can close this' : 'Later',
                        style: const TextStyle(
                            fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w700, color: _C.ink),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}