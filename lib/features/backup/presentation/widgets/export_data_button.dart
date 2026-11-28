import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:ludo_rank/features/backup/data/data_export_service.dart';

/// Opens the system share sheet with the given export files.
typedef ShareExport =
    Future<void> Function(DataExport export, Rect? sharePositionOrigin);

Future<void> shareExportWithSystemSheet(
  DataExport export,
  Rect? sharePositionOrigin,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(export.databaseFile.path, mimeType: 'application/vnd.sqlite3'),
        XFile(export.jsonFile.path, mimeType: 'application/json'),
      ],
      subject: 'نسخة بيانات LudoRank',
      text: 'نسخة من بيانات LudoRank: ملف قاعدة البيانات (.db) وملف JSON.',
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

/// App-bar action "تصدير البيانات": writes the export files, then opens
/// the share sheet so the user can keep them in Files, Drive, WhatsApp...
class ExportDataButton extends StatefulWidget {
  final DataExportService Function() service;
  final ShareExport share;

  const ExportDataButton({
    super.key,
    required this.service,
    this.share = shareExportWithSystemSheet,
  });

  @override
  State<ExportDataButton> createState() => _ExportDataButtonState();
}

class _ExportDataButtonState extends State<ExportDataButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    try {
      final export = await widget.service().export();
      await widget.share(export, origin);
    } catch (e) {
      debugPrint('Data export failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر تصدير البيانات، حاول مرة أخرى')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'تصدير البيانات',
      onPressed: _busy ? null : _export,
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share),
    );
  }
}
