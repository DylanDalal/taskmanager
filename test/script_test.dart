import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taskmanager/main.dart';

void main() {
  group('Script Tests', () {
    test('Script creation and serialization', () {
      final argument = ScriptArgument(
        name: 'environment',
        defaultValue: 'production',
        description: 'The environment to deploy to',
      );

      final script = Script(
        id: 'test-script-1',
        name: 'Deploy App',
        runCommand: 'npm',
        filePath: 'deploy.js',
        arguments: [argument],
        description: 'Deploy the application to the specified environment',
        cronSchedule: '0 9 * * 1-5',
        createdAt: DateTime.now(),
      );

      // Test JSON serialization
      final json = script.toJson();
      final deserializedScript = Script.fromJson(json);

      expect(deserializedScript.id, equals(script.id));
      expect(deserializedScript.name, equals(script.name));
      expect(deserializedScript.runCommand, equals(script.runCommand));
      expect(deserializedScript.filePath, equals(script.filePath));
      expect(deserializedScript.description, equals(script.description));
      expect(deserializedScript.cronSchedule, equals(script.cronSchedule));
      expect(deserializedScript.arguments.length, equals(1));
      expect(deserializedScript.arguments.first.name, equals('environment'));
      expect(deserializedScript.arguments.first.defaultValue, equals('production'));
    });

    test('Script argument creation and serialization', () {
      final argument = ScriptArgument(
        name: 'version',
        defaultValue: '1.0.0',
        description: 'The version to deploy',
      );

      final json = argument.toJson();
      final deserializedArgument = ScriptArgument.fromJson(json);

      expect(deserializedArgument.name, equals(argument.name));
      expect(deserializedArgument.defaultValue, equals(argument.defaultValue));
      expect(deserializedArgument.description, equals(argument.description));
    });

    test('Project with scripts serialization', () {
      final script = Script(
        id: 'test-script-1',
        name: 'Build Project',
        runCommand: 'npm',
        filePath: 'build.js',
        arguments: [],
        createdAt: DateTime.now(),
      );

      final project = Project(
        id: 'test-project-1',
        name: 'Test Project',
        description: 'A test project',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        scripts: [script],
        createdAt: DateTime.now(),
      );

      // Test JSON serialization
      final json = project.toJson();
      final deserializedProject = Project.fromJson(json);

      expect(deserializedProject.scripts.length, equals(1));
      expect(deserializedProject.scripts.first.name, equals('Build Project'));
      expect(deserializedProject.scripts.first.runCommand, equals('npm'));
    });
  });
} 