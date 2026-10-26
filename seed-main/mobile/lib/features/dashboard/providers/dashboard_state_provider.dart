import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../grain/services/grain_analysis_api.dart';

class DashboardState {
  final Uint8List? selectedBytes;
  final Size? selectedImageSize;
  final Offset? referenceStart;
  final Offset? referenceEnd;
  final String fileName;
  final GrainAnalysisResult? result;
  final String? error;
  final String previewMode;
  final bool qcEditMode;
  final bool busy;
  final double progress;
  final String progressPhase;
  final String referenceMmInput;
  final bool pixelOnlyConfirmed;
  final bool manualCalibrationRequested;

  const DashboardState({
    this.selectedBytes,
    this.selectedImageSize,
    this.referenceStart,
    this.referenceEnd,
    this.fileName = 'camera-frame.png',
    this.result,
    this.error,
    this.previewMode = 'overlay',
    this.qcEditMode = false,
    this.busy = false,
    this.progress = 0,
    this.progressPhase = '',
    this.referenceMmInput = '',
    this.pixelOnlyConfirmed = false,
    this.manualCalibrationRequested = false,
  });

  DashboardState copyWith({
    Uint8List? Function()? selectedBytes,
    Size? Function()? selectedImageSize,
    Offset? Function()? referenceStart,
    Offset? Function()? referenceEnd,
    String? fileName,
    GrainAnalysisResult? Function()? result,
    String? Function()? error,
    String? previewMode,
    bool? qcEditMode,
    bool? busy,
    double? progress,
    String? progressPhase,
    String? referenceMmInput,
    bool? pixelOnlyConfirmed,
    bool? manualCalibrationRequested,
  }) {
    return DashboardState(
      selectedBytes:
          selectedBytes != null ? selectedBytes() : this.selectedBytes,
      selectedImageSize: selectedImageSize != null
          ? selectedImageSize()
          : this.selectedImageSize,
      referenceStart:
          referenceStart != null ? referenceStart() : this.referenceStart,
      referenceEnd: referenceEnd != null ? referenceEnd() : this.referenceEnd,
      fileName: fileName ?? this.fileName,
      result: result != null ? result() : this.result,
      error: error != null ? error() : this.error,
      previewMode: previewMode ?? this.previewMode,
      qcEditMode: qcEditMode ?? this.qcEditMode,
      busy: busy ?? this.busy,
      progress: progress ?? this.progress,
      progressPhase: progressPhase ?? this.progressPhase,
      referenceMmInput: referenceMmInput ?? this.referenceMmInput,
      pixelOnlyConfirmed: pixelOnlyConfirmed ?? this.pixelOnlyConfirmed,
      manualCalibrationRequested:
          manualCalibrationRequested ?? this.manualCalibrationRequested,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier() : super(const DashboardState());

  void setSelectedImage(Uint8List bytes, Size? size, String fileName) {
    state = state.copyWith(
      selectedBytes: () => bytes,
      selectedImageSize: () => size,
      fileName: fileName,
      referenceStart: () => null,
      referenceEnd: () => null,
      result: () => null,
      error: () => null,
      previewMode: 'overlay',
      qcEditMode: false,
      referenceMmInput: '',
      pixelOnlyConfirmed: false,
      manualCalibrationRequested: false,
    );
  }

  void setReferenceLine(Offset? start, Offset? end) {
    state = state.copyWith(
      referenceStart: () => start,
      referenceEnd: () => end,
    );
  }

  void clearReference() {
    state = state.copyWith(
      referenceStart: () => null,
      referenceEnd: () => null,
      referenceMmInput: '',
    );
  }

  void setReferenceMmInput(String val) {
    state = state.copyWith(referenceMmInput: val);
  }

  void confirmPixelOnly() {
    state = state.copyWith(
      pixelOnlyConfirmed: true,
      manualCalibrationRequested: false,
      error: () => null,
    );
  }

  void requestManualCalibration() {
    state = state.copyWith(
      pixelOnlyConfirmed: false,
      manualCalibrationRequested: true,
      error: () => null,
    );
  }

  void markCalibrationApplied() {
    state = state.copyWith(
      pixelOnlyConfirmed: false,
      manualCalibrationRequested: false,
      error: () => null,
    );
  }

  void resetCalibrationDecision() {
    state = state.copyWith(
      pixelOnlyConfirmed: false,
      manualCalibrationRequested: false,
    );
  }

  void setBusy(bool busy) {
    state = state.copyWith(busy: busy);
  }

  void setProgress(double progress, String phase) {
    state = state.copyWith(
      progress: progress,
      progressPhase: phase,
    );
  }

  void setResult(GrainAnalysisResult? result) {
    state = state.copyWith(
      result: () => result,
      error: () => null,
    );
  }

  void setError(String? error) {
    state = state.copyWith(
      error: () => error,
    );
  }

  void setPreviewMode(String mode) {
    state = state.copyWith(previewMode: mode);
  }

  void setQcEditMode(bool editMode) {
    state = state.copyWith(qcEditMode: editMode);
  }

  void reset() {
    state = const DashboardState();
  }
}

final dashboardStateProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier();
});
