import 'package:flutter/material.dart';

import 'app/wmn_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = _buildWmnErrorWidget;
  runApp(const _WmnBootstrapHost());
}

Widget _buildWmnErrorWidget(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          elevation: 2,
          color: const Color(0xfffff3f2),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xffba1a1a)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      'WMN UI error\n$message',
                      style: const TextStyle(color: Color(0xff93000a)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WmnBootstrapHost extends StatefulWidget {
  const _WmnBootstrapHost();

  @override
  State<_WmnBootstrapHost> createState() => _WmnBootstrapHostState();
}

class _WmnBootstrapHostState extends State<_WmnBootstrapHost> {
  late final Future<Widget> _appFuture = WmnBootstrap.create();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _appFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'WMN startup failed.\n\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting WMN Application Platform…'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
