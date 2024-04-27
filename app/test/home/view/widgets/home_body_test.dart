// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:health_car_demo_app/src/presentation/home/home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeBody', () {
    testWidgets('renders Text', (tester) async {
      await tester.pumpWidget(
        BlocProvider(
          create: (context) => BackgroundProcessBloc(),
          child: MaterialApp(home: HomeBody()),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
    });
  });
}