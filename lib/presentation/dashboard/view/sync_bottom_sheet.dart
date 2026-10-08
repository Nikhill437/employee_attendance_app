import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';

/// One snapshot of a paginated download's progress, for the bottom
/// sheet's live percentage bar and Existing/Downloading/Remaining stats.
/// [existing] is the local row count *before* this sync started;
/// [downloading] is how many have been fetched so far this sync;
/// [remaining] is an estimate of how many are still to come (the server
/// only reports page counts, not an exact total, so this is a page-size
/// based estimate, not a guarantee).
class SyncProgress {
  final int existing;
  final int downloading;
  final int remaining;
  final double percent;

  const SyncProgress({
    required this.existing,
    required this.downloading,
    required this.remaining,
    required this.percent,
  });
}

/// What the user picked on [showResumeSyncDialog].
enum SyncResumeChoice { cancel, startOver, resume }

/// Shown before starting a full import when a previous one was
/// interrupted partway through (see
/// WorkerImportRepository.getInterruptedImport) — lets the user pick up
/// where it left off instead of silently re-fetching every page from the
/// start. Returns null (same as [SyncResumeChoice.cancel]) if dismissed.
Future<SyncResumeChoice?> showResumeSyncDialog(
  BuildContext context, {
  required String recordLabel,
  required int stoppedAtPage,
  required int totalPages,
  required int recordsSoFar,
}) {
  return showDialog<SyncResumeChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xFFF2F4F0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resume $recordLabel Sync?',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'A previous sync stopped at page $stoppedAtPage/$totalPages '
              'after $recordsSoFar records.',
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose how to continue.',
              style: TextStyle(fontSize: 15, color: AppColors.ink),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, SyncResumeChoice.cancel),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.deepGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, SyncResumeChoice.startOver),
                child: const Text(
                  'Start From Beginning',
                  style: TextStyle(
                    color: AppColors.deepGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pop(context, SyncResumeChoice.resume),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Resume',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the dashboard's "Check For New Data" bottom sheet and runs
/// [download]. If [availableCount] is known and positive, the sheet opens
/// on a "New Data Available!" confirmation naming it and
/// [recordLabel]; otherwise it starts downloading immediately (there
/// being nothing to preview). [download] receives a [SyncProgress]
/// reporter — call it for real, incremental progress (only the full first
/// Employee List import can; see WorkerListApi.fetchAll); leave it unused
/// and the sheet shows an indeterminate spinner instead of invented
/// numbers. Returns the fetched count, or null if the user cancelled
/// before downloading (or dismissed after a failure).
Future<int?> showSyncBottomSheet(
  BuildContext context, {
  required String recordLabel,
  int? availableCount,
  required Future<int> Function(void Function(SyncProgress) onProgress)
  download,
}) {
  return showModalBottomSheet<int?>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _SyncSheetBody(
      recordLabel: recordLabel,
      availableCount: availableCount,
      download: download,
    ),
  );
}

enum _SyncStep { confirm, downloading, success, error }

class _SyncSheetBody extends StatefulWidget {
  final String recordLabel;
  final int? availableCount;
  final Future<int> Function(void Function(SyncProgress) onProgress) download;

  const _SyncSheetBody({
    required this.recordLabel,
    required this.availableCount,
    required this.download,
  });

  @override
  State<_SyncSheetBody> createState() => _SyncSheetBodyState();
}

class _SyncSheetBodyState extends State<_SyncSheetBody> {
  late _SyncStep _step;
  SyncProgress? _progress;
  int _fetchedCount = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final available = widget.availableCount;
    if (available != null && available > 0) {
      _step = _SyncStep.confirm;
    } else {
      _step = _SyncStep.downloading;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _step = _SyncStep.downloading;
      _progress = null;
      _error = null;
    });
    try {
      final count = await widget.download((progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      });
      if (!mounted) return;
      setState(() {
        _fetchedCount = count;
        _step = _SyncStep.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _step = _SyncStep.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Syncing New Data...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (_step != _SyncStep.downloading)
                  GestureDetector(
                    onTap: () => Navigator.pop(
                      context,
                      _step == _SyncStep.success ? _fetchedCount : null,
                    ),
                    child: const Icon(Icons.close, color: AppColors.muted),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            switch (_step) {
              _SyncStep.confirm => _buildConfirm(context),
              _SyncStep.downloading => _buildDownloading(context),
              _SyncStep.success => _buildSuccess(context),
              _SyncStep.error => _buildError(context),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final count = widget.availableCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: Color(0xFFE9F7EF),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.download_outlined,
            color: AppColors.success,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'New Data Available!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$count new records available',
          style: const TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F7EF),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            '$count new ${widget.recordLabel} records',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: const Text(
              'Download',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepGreen,
              side: const BorderSide(color: AppColors.deepGreen),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloading(BuildContext context) {
    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Downloading data...',
              style: TextStyle(fontSize: 14, color: AppColors.slate),
            ),
            if (progress != null)
              Text(
                '${(progress.percent * 100).clamp(0, 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress?.percent.clamp(0, 1),
            minHeight: 8,
            backgroundColor: AppColors.cardBorder,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
          ),
        ),
        const SizedBox(height: 24),
        if (progress != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ProgressStat(
                icon: Icons.dns_outlined,
                label: 'Existing',
                value: progress.existing,
                color: AppColors.success,
                background: const Color(0xFFE9F7EF),
              ),
              _ProgressStat(
                icon: Icons.download_outlined,
                label: 'Downloading',
                value: progress.downloading,
                color: const Color(0xFF2563EB),
                background: const Color(0xFFE8F0FE),
              ),
              _ProgressStat(
                icon: Icons.schedule,
                label: 'Remaining',
                value: progress.remaining,
                color: AppColors.muted,
                background: const Color(0xFFF1F2F1),
              ),
            ],
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.deepGreen),
            ),
          ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 20),
        const Text(
          'All data Downloaded\nSuccessfully!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, _fetchedCount),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepGreen,
              side: const BorderSide(color: AppColors.deepGreen),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Back',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: Color(0xFFFCEAEA),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline,
            color: AppColors.danger,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sync failed',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _error == null ? '' : ApiException.messageFor(_error!),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.muted,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final Color background;

  const _ProgressStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
