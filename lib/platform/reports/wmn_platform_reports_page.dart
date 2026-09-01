import 'package:flutter/material.dart';

import '../../features/reports/report_builder_view.dart';
import '../../modules/reporting/application/report_builder_service.dart';

class WmnPlatformReportsPage extends StatelessWidget {
  const WmnPlatformReportsPage({super.key, required this.reportBuilder});

  final ReportBuilderService reportBuilder;

  @override
  Widget build(BuildContext context) {
    return ReportBuilderView(service: reportBuilder);
  }
}
