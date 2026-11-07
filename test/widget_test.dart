import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_fingerprint/main.dart';

void main() {
  testWidgets('survey screen renders its controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WiFiFingerprintApp());
    expect(find.text('WiFi Fingerprint'), findsOneWidget);
    expect(find.text('Start survey'), findsOneWidget);
    expect(find.text('Scan Wi-Fi'), findsOneWidget);
    expect(find.text('No scan results.'), findsOneWidget);
  });
}
