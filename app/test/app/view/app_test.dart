import 'package:flutter_test/flutter_test.dart';
import 'package:health_car_demo_app/app/app.dart';
import 'package:health_car_demo_app/counter/counter.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      await tester.pumpWidget(const App());
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}