// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskmanager/main.dart';

void main() {
  group('Project URL Parsing Tests', () {
    test('should extract base URL from Jira project URL', () {
      final project = Project(
        id: 'test-1',
        name: 'Test Project',
        description: 'Test Description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        jiraProjectUrl: 'https://company.atlassian.net/jira/software/projects/MOBILE/boards/1',
        createdAt: DateTime.now(),
      );

      expect(project.jiraBaseUrl, equals('https://company.atlassian.net'));
    });

    test('should extract project key from Jira project URL', () {
      final project = Project(
        id: 'test-1',
        name: 'Test Project',
        description: 'Test Description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        jiraProjectUrl: 'https://company.atlassian.net/jira/software/projects/MOBILE/boards/1',
        createdAt: DateTime.now(),
      );

      expect(project.extractedJiraProjectKey, equals('MOBILE'));
    });

    test('should extract project key from browse URL', () {
      final project = Project(
        id: 'test-1',
        name: 'Test Project',
        description: 'Test Description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        jiraProjectUrl: 'https://company.atlassian.net/browse/API-123',
        createdAt: DateTime.now(),
      );

      expect(project.extractedJiraProjectKey, equals('API'));
    });

    test('should return null for invalid URL', () {
      final project = Project(
        id: 'test-1',
        name: 'Test Project',
        description: 'Test Description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        jiraProjectUrl: 'invalid-url',
        createdAt: DateTime.now(),
      );

      expect(project.jiraBaseUrl, isNull);
    });

    test('should use manual project key when URL parsing fails', () {
      final project = Project(
        id: 'test-1',
        name: 'Test Project',
        description: 'Test Description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        jiraProjectUrl: 'https://company.atlassian.net/some/other/path',
        jiraProjectKey: 'MANUAL',
        createdAt: DateTime.now(),
      );

      expect(project.extractedJiraProjectKey, equals('MANUAL'));
    });
  });

  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TaskManagerApp());

    // Wait for the app to fully load and avoid layout issues
    await tester.pumpAndSettle();

    // Verify that the dashboard is displayed
    expect(find.text('DASHBOARD'), findsOneWidget);
  });
}
