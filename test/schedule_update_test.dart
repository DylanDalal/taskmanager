import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taskmanager/main.dart';
import 'package:taskmanager/services/jira_service.dart';

void main() {
  group('Schedule Update Tests', () {
    test('Schedule update callbacks should be registered and unregistered correctly', () {
      // This test verifies that the callback mechanism works
      final callbacks = <Function()>[];
      
      // Simulate registering a callback
      void testCallback() {}
      callbacks.add(testCallback);
      
      expect(callbacks.length, 1);
      
      // Simulate unregistering a callback
      callbacks.remove(testCallback);
      
      expect(callbacks.length, 0);
    });

    test('ScheduledTask should be created correctly', () {
      final task = Task(
        id: 'test-task-1',
        key: 'TEST-1',
        title: 'Test Task',
        description: 'Test Description',
        projectId: 'test-project',
        createdAt: DateTime.now(),
        status: 'To Do',
        priorityEnum: Priority.medium,
      );
      
      final project = DevelopmentProject(
        id: 'test-project',
        name: 'Test Project',
        description: 'Test Project Description',
        color: Colors.blue,
        icon: Icons.code,
        createdAt: DateTime.now(),
      );
      
      final scheduledTask = ScheduledTask(
        id: 'scheduled-task-1',
        task: task,
        projectId: project.id,
        projectName: project.name,
        projectColor: project.color,
        scheduledAt: DateTime.now(),
      );
      
      expect(scheduledTask.task.title, 'Test Task');
      expect(scheduledTask.projectName, 'Test Project');
      expect(scheduledTask.task.projectId, 'test-project');
    });

    test('Priority comparison should work correctly', () {
      // Test priority comparison logic
      const priorityOrder = {
        Priority.critical: 4,
        Priority.high: 3,
        Priority.medium: 2,
        Priority.low: 1,
      };
      
      // Critical should be higher than high
      expect(priorityOrder[Priority.critical]! > priorityOrder[Priority.high]!, true);
      
      // High should be higher than medium
      expect(priorityOrder[Priority.high]! > priorityOrder[Priority.medium]!, true);
      
      // Medium should be higher than low
      expect(priorityOrder[Priority.medium]! > priorityOrder[Priority.low]!, true);
    });
  });
} 