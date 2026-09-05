import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_network_core_example/main.dart';

void main() {
  testWidgets('example app loads', (tester) async {
    await tester.pumpWidget(const NetworkCoreExampleApp());
    expect(find.text('flutter_network_core'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
