import 'package:flutter_test/flutter_test.dart';
import 'package:seed_mobile/features/grain/services/grain_analysis_api.dart';

void main() {
  test('applies post-analysis calibration using image scale', () {
    const result = GrainAnalysisResult(
      run: {'id': 'local-test'},
      image: {'width': 100, 'height': 100, 'scale': 2.0},
      summary: {
        'count': 1,
        'qc': {
          'suspect_count': 0,
          'inlier_count': 1,
          'suspect_ids': [],
          'robust_used_for_reporting': true,
        },
      },
      segmentation: {'segment_count': 1},
      calibration: {'enabled': false},
      measurements: [
        {
          'id': 1,
          'area_px': 200,
          'length_px': 20,
          'width_px': 10,
          'qc_outlier': false,
        },
      ],
      csv: 'id,area_px,length_px,width_px,area_mm2,length_mm,width_mm\n'
          '1,200,20,10,,,',
      previews: {},
    );

    final calibrated = result.withAppliedCalibration(
      referencePixels: 50,
      referenceMm: 10,
      referencePixelSpace: 'original',
    );

    expect(calibrated.calibrated, isTrue);
    expect(calibrated.calibration['processedReferencePixels'], 100);
    expect(calibrated.calibration['mm_per_pixel'], 0.1);
    expect(calibrated.measurements.single['length_mm'], 2);
    expect(calibrated.measurements.single['width_mm'], 1);
    expect(calibrated.measurements.single['area_mm2'], 2);
    expect(calibrated.meanLengthMm, 2);
    expect(calibrated.meanWidthMm, 1);
    expect(calibrated.meanAreaMm2, 2);
    expect(calibrated.csv, contains('1,200,20,10,2.0,2.0,1.0'));
  });
}
