import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taskmanager/main.dart';

void main() {
  group('Script Sharing Tests', () {
    test('AppSettings should store and retrieve shared scripts', () {
      final script1 = Script(
        id: '1',
        name: 'Build Script',
        runCommand: 'npm',
        filePath: 'build.js',
        arguments: [
          ScriptArgument(name: 'environment', defaultValue: 'production'),
        ],
        description: 'Builds the project',
        createdAt: DateTime.now(),
      );

      final script2 = Script(
        id: '2',
        name: 'Test Script',
        runCommand: 'npm',
        filePath: 'test.js',
        arguments: [],
        description: 'Runs tests',
        createdAt: DateTime.now(),
      );

      final settings = AppSettings(
        chatGptToken: 'test-token',
        sharedScripts: [script1, script2],
      );

      // Test serialization
      final json = settings.toJson();
      final deserializedSettings = AppSettings.fromJson(json);

      expect(deserializedSettings.sharedScripts.length, equals(2));
      expect(deserializedSettings.sharedScripts[0].name, equals('Build Script'));
      expect(deserializedSettings.sharedScripts[1].name, equals('Test Script'));
      expect(deserializedSettings.sharedScripts[0].arguments.length, equals(1));
      expect(deserializedSettings.sharedScripts[0].arguments[0].name, equals('environment'));
    });

    test('Script should be copyable with new ID for project use', () {
      final originalScript = Script(
        id: 'original-id',
        name: 'Original Script',
        runCommand: 'python',
        filePath: 'script.py',
        arguments: [
          ScriptArgument(name: 'input', defaultValue: 'default.txt'),
        ],
        description: 'Original script description',
        createdAt: DateTime.now(),
      );

      // Create a copy for project use
      final projectScript = Script(
        id: 'new-project-id',
        name: originalScript.name,
        runCommand: originalScript.runCommand,
        filePath: originalScript.filePath,
        arguments: originalScript.arguments,
        description: originalScript.description,
        cronSchedule: originalScript.cronSchedule,
        createdAt: DateTime.now(),
      );

      expect(projectScript.id, equals('new-project-id'));
      expect(projectScript.name, equals(originalScript.name));
      expect(projectScript.runCommand, equals(originalScript.runCommand));
      expect(projectScript.arguments.length, equals(originalScript.arguments.length));
    });

    test('Project should store scripts separately from shared scripts', () {
      final sharedScript = Script(
        id: 'shared-1',
        name: 'Shared Build Script',
        runCommand: 'npm',
        filePath: 'build.js',
        arguments: [],
        createdAt: DateTime.now(),
      );

      final projectScript = Script(
        id: 'project-1',
        name: 'Project Specific Script',
        runCommand: 'python',
        filePath: 'project.py',
        arguments: [],
        createdAt: DateTime.now(),
      );

      final project = Project(
        id: 'test-project',
        name: 'Test Project',
        description: 'Test project description',
        type: ProjectType.development,
        color: Colors.blue,
        icon: Icons.code,
        scripts: [projectScript],
        createdAt: DateTime.now(),
      );

      expect(project.scripts.length, equals(1));
      expect(project.scripts[0].name, equals('Project Specific Script'));
      expect(project.scripts[0].id, equals('project-1'));
    });

    test('ScriptArgument should serialize and deserialize correctly', () {
      final argument = ScriptArgument(
        name: 'environment',
        defaultValue: 'production',
        description: 'Target environment for deployment',
      );

      final json = argument.toJson();
      final deserialized = ScriptArgument.fromJson(json);

      expect(deserialized.name, equals('environment'));
      expect(deserialized.defaultValue, equals('production'));
      expect(deserialized.description, equals('Target environment for deployment'));
    });
  });
} 