import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/task_status_viewmodel.dart';

/// Checkout-time screen, shared by the worker's own entry and the
/// supervisor's review of it — for both the supervisor-initiated flow
/// (checking a worker out from worker_list_screen.dart) and the worker's
/// own self-service checkout (public kiosk flow,
/// mark_attendance_screen.dart with no supervisor involved).
///
/// Each task card starts in the worker's entry form (numeric value + photo
/// + that task's own Save) and, once saved, switches to the supervisor's
/// read-only view of what the worker entered plus a Yes/No decision, a
/// remark, and that review's own Save — see [TaskStatusViewModel] for which
/// of these actually reach the database today.
class TaskStatusScreen extends StatefulWidget {
  final int workerId;
  final String workerName;
  final int attendanceId;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final TaskStatusViewModel? viewModel;

  const TaskStatusScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.attendanceId,
    this.viewModel,
  });

  @override
  State<TaskStatusScreen> createState() => _TaskStatusScreenState();
}

class _TaskStatusScreenState extends State<TaskStatusScreen> {
  late final TaskStatusViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        TaskStatusViewModel(
          workerId: widget.workerId,
          attendanceId: widget.attendanceId,
        );
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto(TaskSubmission submission) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    _viewModel.setPhoto(submission, File(picked.path));
  }

  void _submitEntry(TaskSubmission submission) {
    if (submission.numericValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a numeric value before saving')),
      );
      return;
    }
    if (submission.photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a photo before saving')),
      );
      return;
    }
    _viewModel.submitEntry(submission);
  }

  Future<void> _saveReview(TaskSubmission submission) async {
    if (submission.supervisorApproved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick Yes or No before saving')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await _viewModel.saveReview(submission);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Task review saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Task Status',
            subtitle: '${widget.workerName} — Checkout',
            showBack: true,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.submissions.isEmpty) {
      return const Center(
        child: Text(
          'No tasks assigned yet',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final submission in _viewModel.submissions) ...[
          submission.isSubmitted
              ? _SupervisorReviewCard(
                  submission: submission,
                  onDecisionChanged: (approved) =>
                      _viewModel.setSupervisorDecision(submission, approved),
                  onRemarkChanged: (remark) =>
                      _viewModel.setRemark(submission, remark),
                  onSaveReview: () => _saveReview(submission),
                )
              : _WorkerEntryCard(
                  submission: submission,
                  onNumericChanged: (value) =>
                      _viewModel.setNumericValue(submission, value),
                  onCapturePhoto: () => _capturePhoto(submission),
                  onSave: () => _submitEntry(submission),
                ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Phase 1: the worker's own entry form for one task.
class _WorkerEntryCard extends StatefulWidget {
  final TaskSubmission submission;
  final ValueChanged<double?> onNumericChanged;
  final VoidCallback onCapturePhoto;
  final VoidCallback onSave;

  const _WorkerEntryCard({
    required this.submission,
    required this.onNumericChanged,
    required this.onCapturePhoto,
    required this.onSave,
  });

  @override
  State<_WorkerEntryCard> createState() => _WorkerEntryCardState();
}

class _WorkerEntryCardState extends State<_WorkerEntryCard> {
  late final TextEditingController _numericController;

  @override
  void initState() {
    super.initState();
    _numericController = TextEditingController(
      text: widget.submission.numericValue?.toString() ?? '',
    )..addListener(_onNumericTextChanged);
  }

  void _onNumericTextChanged() {
    widget.onNumericChanged(double.tryParse(_numericController.text.trim()));
  }

  @override
  void dispose() {
    _numericController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completion = widget.submission.completion;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            completion.taskName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          AppFormField(
            label: 'Quantity',
            hint: 'Enter a numeric value',
            icon: Icons.numbers,
            controller: _numericController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),
          AppImageCaptureField(
            label: 'Task Photo',
            hint: 'Tap to capture a photo for this task',
            image: widget.submission.photo,
            onCapture: widget.onCapturePhoto,
          ),
          const SizedBox(height: 14),
          AppSecondaryButton(label: 'Save', onPressed: widget.onSave),
        ],
      ),
    );
  }
}

/// Phase 2: the supervisor's read-only view of what the worker entered,
/// plus their own Yes/No decision and remark.
class _SupervisorReviewCard extends StatefulWidget {
  final TaskSubmission submission;
  final ValueChanged<bool> onDecisionChanged;
  final ValueChanged<String> onRemarkChanged;
  final VoidCallback onSaveReview;

  const _SupervisorReviewCard({
    required this.submission,
    required this.onDecisionChanged,
    required this.onRemarkChanged,
    required this.onSaveReview,
  });

  @override
  State<_SupervisorReviewCard> createState() => _SupervisorReviewCardState();
}

class _SupervisorReviewCardState extends State<_SupervisorReviewCard> {
  late final TextEditingController _remarkController;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController(text: widget.submission.remark)
      ..addListener(() => widget.onRemarkChanged(_remarkController.text));
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    final completion = submission.completion;
    final photo = submission.photo;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            completion.taskName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.numbers, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(
                'Quantity: ${submission.numericValue ?? '—'}',
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Task Photo',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: photo == null
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Center(
                      child: Text(
                        'No photo captured',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(photo, fit: BoxFit.cover, width: double.infinity),
                  ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Supervisor Decision',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DecisionButton(
                  label: 'Yes',
                  isSelected: submission.supervisorApproved == true,
                  onTap: () => widget.onDecisionChanged(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DecisionButton(
                  label: 'No',
                  isSelected: submission.supervisorApproved == false,
                  onTap: () => widget.onDecisionChanged(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppFormField(
            label: 'Remark',
            hint: 'Add a remark for this task',
            controller: _remarkController,
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          AppSecondaryButton(
            label: submission.reviewSaved ? 'Saved' : 'Save Review',
            onPressed: submission.reviewSaved ? null : widget.onSaveReview,
            color: submission.reviewSaved ? AppColors.success : AppColors.deepGreen,
          ),
        ],
      ),
    );
  }
}

class _DecisionButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = label == 'Yes' ? AppColors.deepGreen : AppColors.danger;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : AppColors.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
