import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math; 
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'services/jira_service.dart';
import 'services/ai_expand_service.dart';
import 'services/youtube_service.dart';
import 'services/youtube_analytics_service.dart';
import 'ui_dashboard.dart';
import 'ui_project_details.dart';
import 'ui_task_details.dart';
import 'ui_youtube_project_details.dart';

void main() {
  runApp(const TaskManagerApp());
}

// Data Models
enum ProjectType { development, general, youtube }
enum TaskType { general, email, video }

// Script model for custom project scripts
class ScriptArgument {
  final String name;
  final String? defaultValue;
  final String? description;

  ScriptArgument({
    required this.name,
    this.defaultValue,
    this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'defaultValue': defaultValue,
      'description': description,
    };
  }

  factory ScriptArgument.fromJson(Map<String, dynamic> json) {
    return ScriptArgument(
      name: json['name'] as String,
      defaultValue: json['defaultValue'] as String?,
      description: json['description'] as String?,
    );
  }

  ScriptArgument copyWith({
    String? name,
    String? defaultValue,
    String? description,
  }) {
    return ScriptArgument(
      name: name ?? this.name,
      defaultValue: defaultValue ?? this.defaultValue,
      description: description ?? this.description,
    );
  }
}

class Script {
  final String id;
  final String name;
  final String runCommand;
  final String filePath;
  final List<ScriptArgument> arguments;
  final String? description;
  final String? cronSchedule;
  final DateTime createdAt;

  Script({
    required this.id,
    required this.name,
    required this.runCommand,
    required this.filePath,
    this.arguments = const [],
    this.description,
    this.cronSchedule,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'runCommand': runCommand,
      'filePath': filePath,
      'arguments': arguments.map((arg) => arg.toJson()).toList(),
      'description': description,
      'cronSchedule': cronSchedule,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Script.fromJson(Map<String, dynamic> json) {
    return Script(
      id: json['id'] as String,
      name: json['name'] as String,
      runCommand: json['runCommand'] as String,
      filePath: json['filePath'] as String,
      arguments: (json['arguments'] as List<dynamic>?)
          ?.map((argJson) => ScriptArgument.fromJson(argJson))
          .toList() ?? [],
      description: json['description'] as String?,
      cronSchedule: json['cronSchedule'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  Script copyWith({
    String? name,
    String? runCommand,
    String? filePath,
    List<ScriptArgument>? arguments,
    String? description,
    String? cronSchedule,
  }) {
    return Script(
      id: id,
      name: name ?? this.name,
      runCommand: runCommand ?? this.runCommand,
      filePath: filePath ?? this.filePath,
      arguments: arguments ?? this.arguments,
      description: description ?? this.description,
      cronSchedule: cronSchedule ?? this.cronSchedule,
      createdAt: createdAt,
    );
  }

  // Helper method to run the script with provided arguments
  Future<void> runScript(Map<String, String> argumentValues) async {
    try {
      // Build the command with arguments
      List<String> command = [runCommand, filePath];
      
      // Add arguments in order
      for (final argument in arguments) {
        final value = argumentValues[argument.name] ?? argument.defaultValue ?? '';
        if (value.isNotEmpty) {
          command.add(value);
        }
      }
      
      // Run the command
      final result = await Process.run(command.first, command.skip(1).toList());
      
      if (result.exitCode != 0) {
        throw Exception('Script failed with exit code ${result.exitCode}: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to run script: $e');
    }
  }
}

class Project {
  final String id;
  final String name;
  final String description;
  final String? projectSummary;
  final String? techStack;
  final ProjectType type;
  final Color color;
  final IconData icon;
  final List<Task> tasks;
  final String? jiraProjectUrl;
  final String? jiraProjectKey;
  final List<Script> scripts;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    required this.description,
    this.projectSummary,
    this.techStack,
    required this.type,
    required this.color,
    required this.icon,
    this.tasks = const [],
    this.jiraProjectUrl,
    this.jiraProjectKey,
    this.scripts = const [],
    required this.createdAt,
  });

  Project copyWith({
    String? name,
    String? description,
    String? projectSummary,
    String? techStack,
    List<Task>? tasks,
    String? jiraProjectUrl,
    String? jiraProjectKey,
    List<Script>? scripts,
    ProjectType? type,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      projectSummary: projectSummary ?? this.projectSummary,
      techStack: techStack ?? this.techStack,
      type: type ?? this.type,
      color: type != null 
        ? (type == ProjectType.development 
            ? Colors.grey[600]! 
            : type == ProjectType.youtube 
              ? Colors.red[600]! 
              : Colors.orange[600]!)
        : color,
      icon: type != null 
        ? (type == ProjectType.development 
            ? Icons.code 
            : type == ProjectType.youtube 
              ? Icons.video_library 
              : Icons.task)
        : icon,
      tasks: tasks ?? this.tasks,
      jiraProjectUrl: jiraProjectUrl ?? this.jiraProjectUrl,
      jiraProjectKey: jiraProjectKey ?? this.jiraProjectKey,
      scripts: scripts ?? this.scripts,
      createdAt: createdAt,
    );
  }

  // Helper to extract base URL and project key from the project URL
  String? get jiraBaseUrl {
    if (jiraProjectUrl == null) return null;
    try {
      final uri = Uri.parse(jiraProjectUrl!);
      // Check if we have a valid scheme and host
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        return null;
      }
      return '${uri.scheme}://${uri.host}';
    } catch (e) {
      return null;
    }
  }

  String? get extractedJiraProjectKey {
    if (jiraProjectUrl == null) return null;
    try {
      // Extract project key from URL patterns like:
      // https://domain.atlassian.net/jira/software/projects/PROJ/boards/1
      // https://domain.atlassian.net/browse/PROJ-123
      final uri = Uri.parse(jiraProjectUrl!);
      final segments = uri.pathSegments;
      
      // Look for project key in various URL patterns
      for (int i = 0; i < segments.length; i++) {
        if (segments[i] == 'projects' && i + 1 < segments.length) {
          final extractedKey = segments[i + 1];
          print('Extracted project key from projects URL: $extractedKey');
          return extractedKey;
        }
        if (segments[i] == 'browse' && i + 1 < segments.length) {
          final issueKey = segments[i + 1];
          // Extract project key from issue key (e.g., "PROJ-123" -> "PROJ")
          final dashIndex = issueKey.indexOf('-');
          if (dashIndex > 0) {
            final extractedKey = issueKey.substring(0, dashIndex);
            print('Extracted project key from browse URL: $extractedKey');
            return extractedKey;
          }
        }
      }
      
      // If no pattern matches, return the manually set project key
      print('No URL pattern matched, using manually set project key: $jiraProjectKey');
      return jiraProjectKey;
    } catch (e) {
      print('Error extracting project key: $e');
      return jiraProjectKey;
    }
  }

  int get completedTasks => tasks.where((task) => task.isCompleted && !task.isSubtask).length;
  
  // Calculate progress based on Jira issues if available, otherwise local tasks
  double getProgressPercentage(List<Task> jiraIssues) {
    if (jiraIssues.isNotEmpty) {
      // Exclude subtasks from progress calculation
      final mainIssues = jiraIssues.where((issue) => !issue.isSubtask).toList();
      final doneIssues = mainIssues.where((issue) => issue.isCompleted).length;
      return mainIssues.isEmpty ? 0.0 : (doneIssues / mainIssues.length) * 100;
    } else {
      return tasks.isEmpty ? 0.0 : (completedTasks / tasks.length) * 100;
    }
  }
  
  // Calculate sprint progress based on current sprint issues
  double getSprintProgressPercentage(List<Task> jiraIssues) {
    if (jiraIssues.isEmpty) return 0.0;
    
    // Exclude subtasks from sprint progress calculation
    final sprintIssues = jiraIssues.where((issue) => issue.isInActiveSprint && !issue.isSubtask).toList();
    if (sprintIssues.isEmpty) return 0.0;
    
    final doneSprintIssues = sprintIssues.where((issue) => issue.isCompleted).length;
    
    return (doneSprintIssues / sprintIssues.length) * 100;
  }
  
  // Get current sprint name
  String? getCurrentSprintName(List<Task> jiraIssues) {
    final sprintIssues = jiraIssues.where((issue) => issue.isInActiveSprint && !issue.isSubtask).toList();
    return sprintIssues.isNotEmpty ? sprintIssues.first.sprintName : null;
  }
  
  // Get count of sprint issues (excluding subtasks)
  int getSprintIssueCount(List<Task> jiraIssues) {
    return jiraIssues.where((issue) => issue.isInActiveSprint && !issue.isSubtask).length;
  }
  
  // Get count of completed sprint issues (excluding subtasks)
  int getCompletedSprintIssueCount(List<Task> jiraIssues) {
    return jiraIssues.where((issue) => 
      issue.isInActiveSprint && !issue.isSubtask && issue.isCompleted
    ).length;
  }
  
  double get progressPercentage {
    final mainTasks = tasks.where((task) => !task.isSubtask).length;
    return mainTasks == 0 ? 0.0 : (completedTasks / mainTasks) * 100;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'projectSummary': projectSummary,
      'techStack': techStack,
      'type': type == ProjectType.development 
          ? 'development' 
          : type == ProjectType.youtube 
            ? 'youtube' 
            : 'general',
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'jiraProjectUrl': jiraProjectUrl,
      'jiraProjectKey': jiraProjectKey,
      'scripts': scripts.map((script) => script.toJson()).toList(),
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    final typeString = json['type'] as String?;
    final type = typeString == 'development' 
        ? ProjectType.development 
        : typeString == 'youtube' 
            ? ProjectType.youtube 
            : ProjectType.general;
    
    // Return YouTubeProject if type is youtube
    if (type == ProjectType.youtube) {
      return YouTubeProject.fromJson(json);
    }
    
    // Return DevelopmentProject if type is development
    if (type == ProjectType.development) {
      return DevelopmentProject.fromJson(json);
    }
    
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      projectSummary: json['projectSummary'] as String?,
      techStack: json['techStack'] as String?,
      type: type,
              color: type == ProjectType.development ? Colors.grey[600]! : Colors.orange[600]!,
      icon: type == ProjectType.development ? Icons.code : Icons.task,
      tasks: (json['tasks'] as List<dynamic>?)
          ?.map((taskJson) => Task.fromJson(taskJson))
          .toList() ?? [],
      jiraProjectUrl: json['jiraProjectUrl'] as String?,
      jiraProjectKey: json['jiraProjectKey'] as String?,
      scripts: (json['scripts'] as List<dynamic>?)
          ?.map((scriptJson) => Script.fromJson(scriptJson))
          .toList() ?? [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }
}

// Stub class for YouTube Analytics snapshots
class AnalyticsSnap {
  final DateTime timestamp;
  final Map<String, dynamic> data;

  AnalyticsSnap({
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'data': data,
    };
  }

  factory AnalyticsSnap.fromJson(Map<String, dynamic> json) {
    return AnalyticsSnap(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

class YouTubeProject extends Project {
  final String channelLink;
  final String? pipelinePath;
  final String? uploadSchedule;
  final List<AnalyticsSnap> analyticsSnapshots;

  YouTubeProject({
    required super.id,
    required super.name,
    required super.description,
    super.projectSummary,
    super.techStack,
    required super.color,
    required super.icon,
    super.tasks = const [],
    super.jiraProjectUrl,
    super.jiraProjectKey,
    super.scripts = const [],
    required super.createdAt,
    required this.channelLink,
    this.pipelinePath,
    this.uploadSchedule,
    this.analyticsSnapshots = const [],
  }) : super(type: ProjectType.youtube);

  // Get Google credentials from api_keys.txt
  Map<String, String?> get googleCredentials {
    try {
      final file = File('api_keys.txt');
      if (!file.existsSync()) return {'client_id': null, 'client_secret': null};
      
      final contents = file.readAsStringSync();
      final lines = contents.split('\n');
      final clientIdKey = '${name}_Google_Client_ID';
      final clientSecretKey = '${name}_Google_Client_Secret';
      
      String? clientId;
      String? clientSecret;
      
      for (final line in lines) {
        if (line.startsWith('$clientIdKey=')) {
          clientId = line.substring(clientIdKey.length + 1);
        } else if (line.startsWith('$clientSecretKey=')) {
          clientSecret = line.substring(clientSecretKey.length + 1);
        }
      }
      
      return {'client_id': clientId, 'client_secret': clientSecret};
    } catch (e) {
      return {'client_id': null, 'client_secret': null};
    }
  }

  // Set Google credentials in api_keys.txt from credentials.json
  void setGoogleCredentials(String clientId, String clientSecret) {
    try {
      final file = File('api_keys.txt');
      final clientIdKey = '${name}_Google_Client_ID';
      final clientSecretKey = '${name}_Google_Client_Secret';
      
      List<String> lines = [];
      if (file.existsSync()) {
        lines = file.readAsStringSync().split('\n');
      }
      
      // Remove existing credentials if they exist
      lines.removeWhere((line) => 
        line.startsWith('$clientIdKey=') || 
        line.startsWith('$clientSecretKey=')
      );
      
      // Add new credentials
      lines.add('$clientIdKey=$clientId');
      lines.add('$clientSecretKey=$clientSecret');
      
      // Write back to file
      file.writeAsStringSync(lines.join('\n'));
    } catch (e) {
      print('Error saving Google credentials: $e');
    }
  }

  // Parse and store credentials from credentials.json content
  void processCredentialsJson(String jsonContent) {
    try {
      final Map<String, dynamic> credentials = jsonDecode(jsonContent);
      
      // Extract client credentials (for installed app)
      if (credentials.containsKey('installed')) {
        final installed = credentials['installed'] as Map<String, dynamic>;
        final clientId = installed['client_id'] as String;
        final clientSecret = installed['client_secret'] as String;
        
        setGoogleCredentials(clientId, clientSecret);
      }
      // Extract client credentials (for web app)
      else if (credentials.containsKey('web')) {
        final web = credentials['web'] as Map<String, dynamic>;
        final clientId = web['client_id'] as String;
        final clientSecret = web['client_secret'] as String;
        
        setGoogleCredentials(clientId, clientSecret);
      } else {
        throw Exception('Invalid credentials.json format: missing "installed" or "web" section');
      }
    } catch (e) {
      print('Error processing credentials.json: $e');
      rethrow;
    }
  }

  @override
  YouTubeProject copyWith({
    String? name,
    String? description,
    String? projectSummary,
    String? techStack,
    List<Task>? tasks,
    String? jiraProjectUrl,
    String? jiraProjectKey,
    List<Script>? scripts,
    ProjectType? type,
    String? channelLink,
    String? pipelinePath,
    String? uploadSchedule,
    List<AnalyticsSnap>? analyticsSnapshots,
  }) {
    return YouTubeProject(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      projectSummary: projectSummary ?? this.projectSummary,
      techStack: techStack ?? this.techStack,
      color: Colors.red[600]!,
      icon: Icons.video_library,
      tasks: tasks ?? this.tasks,
      jiraProjectUrl: jiraProjectUrl ?? this.jiraProjectUrl,
      jiraProjectKey: jiraProjectKey ?? this.jiraProjectKey,
      scripts: scripts ?? this.scripts,
      createdAt: createdAt,
      channelLink: channelLink ?? this.channelLink,
      pipelinePath: pipelinePath ?? this.pipelinePath,
      uploadSchedule: uploadSchedule ?? this.uploadSchedule,
      analyticsSnapshots: analyticsSnapshots ?? this.analyticsSnapshots,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    baseJson.addAll({
      'channelLink': channelLink,
      'pipelinePath': pipelinePath,
      'uploadSchedule': uploadSchedule,
      'analyticsSnapshots': analyticsSnapshots.map((snap) => snap.toJson()).toList(),
    });
    return baseJson;
  }

  factory YouTubeProject.fromJson(Map<String, dynamic> json) {
    return YouTubeProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      projectSummary: json['projectSummary'] as String?,
      techStack: json['techStack'] as String?,
      color: Colors.red[600]!,
      icon: Icons.video_library,
      tasks: (json['tasks'] as List<dynamic>?)
          ?.map((taskJson) => Task.fromJson(taskJson))
          .toList() ?? [],
      jiraProjectUrl: json['jiraProjectUrl'] as String?,
      jiraProjectKey: json['jiraProjectKey'] as String?,
      scripts: (json['scripts'] as List<dynamic>?)
          ?.map((scriptJson) => Script.fromJson(scriptJson))
          .toList() ?? [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      channelLink: json['channelLink'] as String,
      pipelinePath: json['pipelinePath'] as String?,
      uploadSchedule: json['uploadSchedule'] as String?,
      analyticsSnapshots: (json['analyticsSnapshots'] as List<dynamic>?)
          ?.map((snapJson) => AnalyticsSnap.fromJson(snapJson))
          .toList() ?? [],
    );
  }
}

class DevelopmentProject extends Project {
  final String? githubRepoPath;
  final String? setupScriptPath;
  final String? setupScriptContent;

  DevelopmentProject({
    required super.id,
    required super.name,
    required super.description,
    super.projectSummary,
    super.techStack,
    required super.color,
    required super.icon,
    super.tasks = const [],
    super.jiraProjectUrl,
    super.jiraProjectKey,
    super.scripts = const [],
    required super.createdAt,
    this.githubRepoPath,
    this.setupScriptPath,
    this.setupScriptContent,
  }) : super(type: ProjectType.development);

  @override
  DevelopmentProject copyWith({
    String? name,
    String? description,
    String? projectSummary,
    String? techStack,
    List<Task>? tasks,
    String? jiraProjectUrl,
    String? jiraProjectKey,
    List<Script>? scripts,
    ProjectType? type,
    String? githubRepoPath,
    String? setupScriptPath,
    String? setupScriptContent,
  }) {
    return DevelopmentProject(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      projectSummary: projectSummary ?? this.projectSummary,
      techStack: techStack ?? this.techStack,
      color: Colors.grey[600]!,
      icon: Icons.code,
      tasks: tasks ?? this.tasks,
      jiraProjectUrl: jiraProjectUrl ?? this.jiraProjectUrl,
      jiraProjectKey: jiraProjectKey ?? this.jiraProjectKey,
      scripts: scripts ?? this.scripts,
      createdAt: createdAt,
      githubRepoPath: githubRepoPath ?? this.githubRepoPath,
      setupScriptPath: setupScriptPath ?? this.setupScriptPath,
      setupScriptContent: setupScriptContent ?? this.setupScriptContent,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    baseJson.addAll({
      'githubRepoPath': githubRepoPath,
      'setupScriptPath': setupScriptPath,
      'setupScriptContent': setupScriptContent,
    });
    return baseJson;
  }

  factory DevelopmentProject.fromJson(Map<String, dynamic> json) {
    return DevelopmentProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      projectSummary: json['projectSummary'] as String?,
      techStack: json['techStack'] as String?,
      color: Colors.grey[600]!,
      icon: Icons.code,
      tasks: (json['tasks'] as List<dynamic>?)
          ?.map((taskJson) => Task.fromJson(taskJson))
          .toList() ?? [],
      jiraProjectUrl: json['jiraProjectUrl'] as String?,
      jiraProjectKey: json['jiraProjectKey'] as String?,
      scripts: (json['scripts'] as List<dynamic>?)
          ?.map((scriptJson) => Script.fromJson(scriptJson))
          .toList() ?? [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      githubRepoPath: json['githubRepoPath'] as String?,
      setupScriptPath: json['setupScriptPath'] as String?,
      setupScriptContent: json['setupScriptContent'] as String?,
    );
  }

  // Helper method to run the setup script
  Future<void> runSetupScript() async {
    if (setupScriptContent != null && setupScriptContent!.isNotEmpty) {
      try {
        // Create a temporary script file
        final directory = await getApplicationDocumentsDirectory();
        final scriptFile = File('${directory.path}/temp_setup_${id}.sh');
        await scriptFile.writeAsString(setupScriptContent!);
        
        // Make the script executable
        await Process.run('chmod', ['+x', scriptFile.path]);
        
        // Run the script in the GitHub repo directory if available
        final workingDirectory = githubRepoPath ?? directory.path;
        final result = await Process.run('bash', [scriptFile.path], 
          workingDirectory: workingDirectory);
        
        // Clean up the temporary script file
        await scriptFile.delete();
        
        if (result.exitCode != 0) {
          throw Exception('Setup script failed with exit code ${result.exitCode}: ${result.stderr}');
        }
      } catch (e) {
        throw Exception('Failed to run setup script: $e');
      }
    }
  }
}

// Task class and Priority enum are now defined in services/jira_service.dart

// Model for scheduled tasks/subtasks
class ScheduledTask {
  final String id;
  final Task task;
  final String projectId;
  final String projectName;
  final Color projectColor;
  final DateTime scheduledAt;
  final DateTime? dueDate;

  ScheduledTask({
    required this.id,
    required this.task,
    required this.projectId,
    required this.projectName,
    required this.projectColor,
    required this.scheduledAt,
    this.dueDate,
  });

  ScheduledTask copyWith({
    DateTime? dueDate,
  }) {
    return ScheduledTask(
      id: id,
      task: task,
      projectId: projectId,
      projectName: projectName,
      projectColor: projectColor,
      scheduledAt: scheduledAt,
      dueDate: dueDate ?? this.dueDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task': task.toJson(),
      'projectId': projectId,
      'projectName': projectName,
      'projectColor': projectColor.value,
      'scheduledAt': scheduledAt.millisecondsSinceEpoch,
      'dueDate': dueDate?.millisecondsSinceEpoch,
    };
  }

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    return ScheduledTask(
      id: json['id'] as String,
      task: Task.fromJson(json['task'] as Map<String, dynamic>),
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      projectColor: Color(json['projectColor'] as int),
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(json['scheduledAt'] as int),
      dueDate: json['dueDate'] != null ? DateTime.fromMillisecondsSinceEpoch(json['dueDate'] as int) : null,
    );
  }
}

class AppSettings {
  final String? chatGptToken;
  final String? jiraToken;
  final String? jiraUsername;
  final List<Script> sharedScripts;

  AppSettings({
    this.chatGptToken,
    this.jiraToken,
    this.jiraUsername,
    this.sharedScripts = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'chatGptToken': chatGptToken,
      'jiraToken': jiraToken,
      'jiraUsername': jiraUsername,
      'sharedScripts': sharedScripts.map((script) => script.toJson()).toList(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      chatGptToken: json['chatGptToken'],
      jiraToken: json['jiraToken'],
      jiraUsername: json['jiraUsername'],
      sharedScripts: (json['sharedScripts'] as List<dynamic>?)
          ?.map((scriptJson) => Script.fromJson(scriptJson))
          .toList() ?? [],
    );
  }

  AppSettings copyWith({
    String? chatGptToken,
    String? jiraToken,
    String? jiraUsername,
    List<Script>? sharedScripts,
  }) {
    return AppSettings(
      chatGptToken: chatGptToken ?? this.chatGptToken,
      jiraToken: jiraToken ?? this.jiraToken,
      jiraUsername: jiraUsername ?? this.jiraUsername,
      sharedScripts: sharedScripts ?? this.sharedScripts,
    );
  }
}

class TaskManagerApp extends StatefulWidget {
  const TaskManagerApp({super.key});

  @override
  State<TaskManagerApp> createState() => _TaskManagerAppState();
}

class _TaskManagerAppState extends State<TaskManagerApp> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppSettings _settings = AppSettings();
  List<Project> _professionalProjects = [];
  List<Project> _personalProjects = [];
  Map<String, List<Task>> _projectJiraIssues = {}; // Store Jira issues by project ID
  List<ScheduledTask> _scheduledTasks = []; // Store scheduled tasks
  List<Function()> _scheduleUpdateCallbacks = []; // Callbacks to notify schedule updates

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
    _initializeProjects();
    _initializeYouTubeServices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initializeProjects() async {
    // Load projects from storage
    await _loadProjects();
    await _loadScheduledTasks();
    // Automatically fetch and schedule assigned Jira issues
    _fetchAndScheduleAssignedIssues();
  }

  void _initializeYouTubeServices() async {
    try {
      await YouTubeAnalyticsService().initialize();
      print('YouTube services initialized successfully');
    } catch (e) {
      print('Error initializing YouTube services: $e');
    }
  }

  Future<void> _loadProjects() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_projects.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents);
        
        setState(() {
          _professionalProjects = (json['professional'] as List<dynamic>?)
              ?.map((projectJson) => Project.fromJson(projectJson))
              .toList() ?? [];
          _personalProjects = (json['personal'] as List<dynamic>?)
              ?.map((projectJson) => Project.fromJson(projectJson))
              .toList() ?? [];
        });
        
        print('Loaded ${_professionalProjects.length} professional projects');
        print('Loaded ${_personalProjects.length} personal projects');
        
        // Fetch Jira issues for any existing Jira projects
        _refreshAllJiraIssues();
      } else {
        print('No saved projects file found, initializing empty lists');
        // Initialize with empty project lists if no saved data
        setState(() {
          _professionalProjects = [];
          _personalProjects = [];
        });
      }
    } catch (e) {
      print('Error loading projects: $e');
      // Fallback to empty lists
      setState(() {
        _professionalProjects = [];
        _personalProjects = [];
      });
    }
  }

  Future<void> _saveProjects() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_projects.json');
      
      final json = {
        'professional': _professionalProjects.map((project) => project.toJson()).toList(),
        'personal': _personalProjects.map((project) => project.toJson()).toList(),
      };
      
      await file.writeAsString(jsonEncode(json));
      print('Saved ${_professionalProjects.length} professional and ${_personalProjects.length} personal projects');
    } catch (e) {
      print('Error saving projects: $e');
    }
  }

  void _refreshAllJiraIssues() {
    for (final project in [..._professionalProjects, ..._personalProjects]) {
      if (project.jiraProjectUrl != null && 
          project.jiraProjectUrl!.isNotEmpty && 
          project.extractedJiraProjectKey != null) {
        _fetchJiraIssuesForProject(project);
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_settings.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents);
        setState(() {
          _settings = AppSettings.fromJson(json);
        });
      }
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_settings.json');
      await file.writeAsString(jsonEncode(_settings.toJson()));
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    _saveSettings();
  }

  void _addSharedScript(Script script) {
    setState(() {
      _settings = _settings.copyWith(
        sharedScripts: [..._settings.sharedScripts, script],
      );
    });
    _saveSettings();
  }

  void _updateSharedScript(Script updatedScript) {
    setState(() {
      final updatedScripts = _settings.sharedScripts.map((script) {
        if (script.id == updatedScript.id) {
          return updatedScript;
        }
        return script;
      }).toList();
      _settings = _settings.copyWith(sharedScripts: updatedScripts);
    });
    _saveSettings();
  }

  void _removeSharedScript(String scriptId) {
    setState(() {
      final updatedScripts = _settings.sharedScripts.where((script) => script.id != scriptId).toList();
      _settings = _settings.copyWith(sharedScripts: updatedScripts);
    });
    _saveSettings();
  }

  Future<void> _loadScheduledTasks() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_scheduled_tasks.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as List<dynamic>;
        
        setState(() {
          _scheduledTasks = json
              .map((taskJson) => ScheduledTask.fromJson(taskJson))
              .toList();
        });
        
        print('Loaded ${_scheduledTasks.length} scheduled tasks');
      }
    } catch (e) {
      print('Error loading scheduled tasks: $e');
    }
  }

  Future<void> _saveScheduledTasks() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/taskmanager_scheduled_tasks.json');
      
      final json = _scheduledTasks.map((task) => task.toJson()).toList();
      
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print('Error saving scheduled tasks: $e');
    }
  }

  void _addTaskToSchedule(Task task, Project project) {
    // Check if task is already scheduled (prevent duplicates)
    final existingTask = _scheduledTasks.any((st) => 
      st.task.id == task.id || 
      (task.jiraTicketId != null && st.task.jiraTicketId == task.jiraTicketId)
    );
    
    if (existingTask) {
      // Don't show SnackBar during initialization
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${task.title}" is already in the schedule'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final scheduledTask = ScheduledTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      task: task,
      projectId: project.id,
      projectName: project.name,
      projectColor: project.color,
      scheduledAt: DateTime.now(),
    );

    setState(() {
      _scheduledTasks.add(scheduledTask);
    });
    
    _saveScheduledTasks();
    _notifyScheduleUpdate();
    
    // Don't show SnackBar during initialization
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${task.title}" to schedule'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _removeTaskFromSchedule(ScheduledTask scheduledTask) {
    setState(() {
      _scheduledTasks.removeWhere((st) => st.id == scheduledTask.id);
    });
    
    _saveScheduledTasks();
    _notifyScheduleUpdate();
    
    // Don't show SnackBar during initialization
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${scheduledTask.task.title}" from schedule'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _reorderScheduledTasks(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _scheduledTasks.removeAt(oldIndex);
      _scheduledTasks.insert(newIndex, item);
    });

    _saveScheduledTasks();
    _notifyScheduleUpdate();
  }

  Future<void> _expandScheduledTaskWithAI(
      BuildContext context, ScheduledTask scheduledTask) async {
    final project = [..._professionalProjects, ..._personalProjects]
        .firstWhere((p) => p.id == scheduledTask.projectId);

    if (project.projectSummary == null || project.projectSummary!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Project summary is required for AI Expand. Please add a project summary in project settings.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final aiService = AIExpandService();
      final taskDescription = scheduledTask.task.description?.isNotEmpty == true
          ? scheduledTask.task.description!
          : scheduledTask.task.title;

      final subtaskItems = await aiService.expandTask(
        taskDescription: taskDescription,
        projectSummary: project.projectSummary!,
        isDevelopmentProject: project.type == ProjectType.development,
        techStack: project.techStack,
      );

      final List<Task> newSubtasks = [];
      final parentIndex =
          _scheduledTasks.indexWhere((st) => st.id == scheduledTask.id);
      int insertIndex = parentIndex + 1;

      for (final item in subtaskItems) {
        final uniqueId =
            DateTime.now().millisecondsSinceEpoch.toString() + '_${item.id}';
        final subtask = Task(
          id: uniqueId,
          key: uniqueId,
          title: item.title,
          description: item.prompt,
          projectId: project.id,
          createdAt: DateTime.now(),
          status: 'To Do',
          priorityEnum: Priority.medium,
          parentKey: scheduledTask.task.key,
          isSubtask: true,
        );
        newSubtasks.add(subtask);

        final scheduledSubtask = ScheduledTask(
          id: uniqueId,
          task: subtask,
          projectId: project.id,
          projectName: project.name,
          projectColor: project.color,
          scheduledAt: DateTime.now(),
        );
        _scheduledTasks.insert(insertIndex, scheduledSubtask);
        insertIndex++;
      }

      setState(() {});
      await _saveScheduledTasks();
      _notifyScheduleUpdate();

      _showScheduleSubtasksDialog(context, newSubtasks);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error expanding task: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showScheduleSubtasksDialog(
      BuildContext context, List<Task> subtasks) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.purple),
            const SizedBox(width: 8),
            const Text('AI Expanded Subtasks'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created ${subtasks.length} subtasks:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: subtasks.length,
                  itemBuilder: (context, index) {
                    final subtask = subtasks[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subtask.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtask.description ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _registerScheduleUpdate(Function() callback) {
    _scheduleUpdateCallbacks.add(callback);
  }

  void _unregisterScheduleUpdate(Function() callback) {
    _scheduleUpdateCallbacks.remove(callback);
  }

  void _notifyScheduleUpdate() {
    for (final callback in _scheduleUpdateCallbacks) {
      callback();
    }
  }

  void _updateProject(Project updatedProject) {
    setState(() {
      // Update in the appropriate list
      final allProjects = [..._professionalProjects, ..._personalProjects];
      final projectIndex = allProjects.indexWhere((p) => p.id == updatedProject.id);
      
      if (projectIndex != -1) {
        if (projectIndex < _professionalProjects.length) {
          _professionalProjects[projectIndex] = updatedProject;
        } else {
          final personalIndex = projectIndex - _professionalProjects.length;
          _personalProjects[personalIndex] = updatedProject;
        }
      }
    });
    
    _saveProjects();
  }

  void _addProject(Project project, bool isProfessional) {
    setState(() {
      if (isProfessional) {
        _professionalProjects.add(project);
      } else {
        _personalProjects.add(project);
      }
    });
    
    _saveProjects();
  }

  void _deleteProject(String projectId) {
    setState(() {
      _professionalProjects.removeWhere((p) => p.id == projectId);
      _personalProjects.removeWhere((p) => p.id == projectId);
    });
    
    _saveProjects();
  }

  Future<void> _fetchJiraIssuesForProject(Project project) async {
    if (project.jiraProjectUrl == null || project.jiraProjectUrl!.isEmpty) {
      return;
    }

    final baseUrl = project.jiraBaseUrl;
    final projectKey = project.extractedJiraProjectKey;

    if (baseUrl == null || projectKey == null) {
      return;
    }

    try {
      final jiraService = JiraService.instance;
      final issues = await jiraService.fetchProjectIssues(
        baseUrl,
        projectKey,
      );
      
      setState(() {
        _projectJiraIssues[project.id] = issues;
      });
    } catch (e) {
      print('Error fetching Jira issues for project ${project.name}: $e');
    }
  }

  Future<void> _fetchAndScheduleAssignedIssues() async {
    // Only fetch issues for projects that have Jira URLs configured
    for (final project in [..._professionalProjects, ..._personalProjects]) {
      if (project.jiraProjectUrl != null && 
          project.jiraProjectUrl!.isNotEmpty && 
          project.extractedJiraProjectKey != null) {
        await _fetchJiraIssuesForProject(project);
      }
    }
    
    // Schedule assigned issues - only if jiraUsername is set
    if (_settings.jiraUsername != null && _settings.jiraUsername!.isNotEmpty) {
      final List<ScheduledTask> newScheduledTasks = [];
      final now = DateTime.now();
      for (final project in [..._professionalProjects, ..._personalProjects]) {
        // Only process projects that are Jira-linked
        if (project.jiraProjectUrl != null && 
            project.jiraProjectUrl!.isNotEmpty && 
            project.extractedJiraProjectKey != null) {
          final issues = _projectJiraIssues[project.id] ?? [];
          for (final issue in issues) {
            if (issue.assigneeEmail != null && 
                issue.assigneeEmail!.toLowerCase() == _settings.jiraUsername!.toLowerCase() && 
                !issue.isCompleted && 
                !_scheduledTasks.any((st) => st.task.jiraTicketId == issue.jiraTicketId) &&
                !newScheduledTasks.any((st) => st.task.jiraTicketId == issue.jiraTicketId)) {
              newScheduledTasks.add(ScheduledTask(
                id: now.millisecondsSinceEpoch.toString() + '_' + issue.jiraTicketId!,
                task: issue,
                projectId: project.id,
                projectName: project.name,
                projectColor: project.color,
                scheduledAt: now,
              ));
            }
          }
        }
      }
      if (newScheduledTasks.isNotEmpty) {
        setState(() {
          _scheduledTasks.addAll(newScheduledTasks);
        });
        _saveScheduledTasks();
        _notifyScheduleUpdate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue,
          secondary: Colors.lightBlue,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
        ),
      ),
      home: MainLayout(
        tabController: _tabController,
        settings: _settings,
        professionalProjects: _professionalProjects,
        personalProjects: _personalProjects,
        projectJiraIssues: _projectJiraIssues,
        scheduledTasks: _scheduledTasks,
        onAddProject: _addProject,
        onUpdateProject: _updateProject,
        onDeleteProject: _deleteProject,
        onAddTaskToSchedule: _addTaskToSchedule,
        onRemoveTaskFromSchedule: _removeTaskFromSchedule,
        onExpandScheduledTask: _expandScheduledTaskWithAI,
        onReorderScheduledTasks: _reorderScheduledTasks,
        onRegisterScheduleUpdate: _registerScheduleUpdate,
        onUnregisterScheduleUpdate: _unregisterScheduleUpdate,
        onUpdateSettings: _updateSettings,
        onFetchJiraIssuesForProject: _fetchJiraIssuesForProject,
        onAddSharedScript: _addSharedScript,
        onUpdateSharedScript: _updateSharedScript,
        onRemoveSharedScript: _removeSharedScript,
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final TabController tabController;
  final AppSettings settings;
  final List<Project> professionalProjects;
  final List<Project> personalProjects;
  final Map<String, List<Task>> projectJiraIssues;
  final List<ScheduledTask> scheduledTasks;
  final Function(Project, bool) onAddProject;
  final Function(Project) onUpdateProject;
  final Function(String) onDeleteProject;
  final Function(Task, Project) onAddTaskToSchedule;
  final Function(ScheduledTask) onRemoveTaskFromSchedule;
  final Future<void> Function(BuildContext, ScheduledTask) onExpandScheduledTask;
  final Function(int, int) onReorderScheduledTasks;
  final Function(Function()) onRegisterScheduleUpdate;
  final Function(Function()) onUnregisterScheduleUpdate;
  final Function(AppSettings) onUpdateSettings;
  final Function(Project) onFetchJiraIssuesForProject;
  final Function(Script) onAddSharedScript;
  final Function(Script) onUpdateSharedScript;
  final Function(String) onRemoveSharedScript;

  const MainLayout({
    super.key,
    required this.tabController,
    required this.settings,
    required this.professionalProjects,
    required this.personalProjects,
    required this.projectJiraIssues,
    required this.scheduledTasks,
    required this.onAddProject,
    required this.onUpdateProject,
    required this.onDeleteProject,
    required this.onAddTaskToSchedule,
    required this.onRemoveTaskFromSchedule,
    required this.onExpandScheduledTask,
    required this.onReorderScheduledTasks,
    required this.onRegisterScheduleUpdate,
    required this.onUnregisterScheduleUpdate,
    required this.onUpdateSettings,
    required this.onFetchJiraIssuesForProject,
    required this.onAddSharedScript,
    required this.onUpdateSharedScript,
    required this.onRemoveSharedScript,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  Project? _selectedProject;
  List<Function()> _scheduleUpdateCallbacks = [];

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
      case Priority.critical:
        return Colors.purple;
  }
  }

  String _getPriorityText(Priority priority) {
    switch (priority) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
      case Priority.critical:
        return 'Critical';
    }
  }

  List<Task> _getSortedJiraIssuesForProject(List<Task> issues) {
    final sortedIssues = List<Task>.from(issues);
    sortedIssues.sort((a, b) {
      // Check if either task is "Done"
      final aIsDone = a.status.toLowerCase() == 'done' || 
                     a.status.toLowerCase() == 'closed' ||
                     a.status.toLowerCase() == 'resolved';
      final bIsDone = b.status.toLowerCase() == 'done' || 
                     b.status.toLowerCase() == 'closed' ||
                     b.status.toLowerCase() == 'resolved';
      
      // Done tasks go to bottom regardless of sprint status
      if (aIsDone && !bIsDone) return 1;
      if (!aIsDone && bIsDone) return -1;
      
      // For non-done tasks, prioritize sprint tasks first, then by priority
      if (!aIsDone && !bIsDone) {
        // Sprint tasks come first
        if (a.isInActiveSprint && !b.isInActiveSprint) return -1;
        if (!a.isInActiveSprint && b.isInActiveSprint) return 1;
        
        // Within same group (both sprint or both non-sprint), sort by priority (Critical to Low)
        final aPriority = _getPriorityValueFromString(a.priority);
        final bPriority = _getPriorityValueFromString(b.priority);
        return bPriority.compareTo(aPriority); // Highest to lowest
      }
      
      // For done tasks, also sort by priority but they're already at bottom
      final aPriority = _getPriorityValueFromString(a.priority);
      final bPriority = _getPriorityValueFromString(b.priority);
      return bPriority.compareTo(aPriority); // Highest to lowest
    });
    return sortedIssues;
  }

  List<Task> _getSortedLocalTasksForProject(List<Task> tasks) {
    final sortedTasks = List<Task>.from(tasks);
    sortedTasks.sort((a, b) {
      // Check if either task is completed
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      
      // For non-completed tasks, prioritize sprint tasks first, then by priority
      if (!a.isCompleted && !b.isCompleted) {
        // Sprint tasks come first (if local tasks can have sprint status)
        if (a.isInActiveSprint && !b.isInActiveSprint) return -1;
        if (!a.isInActiveSprint && b.isInActiveSprint) return 1;
        
        // Within same group (both sprint or both non-sprint), sort by priority (Critical to Low)
        final aPriority = _getPriorityValueFromEnum(a.priorityEnum);
        final bPriority = _getPriorityValueFromEnum(b.priorityEnum);
        return bPriority.compareTo(aPriority); // Highest to lowest
      }
      
      // For completed tasks, also sort by priority but they're already at bottom
      final aPriority = _getPriorityValueFromEnum(a.priorityEnum);
      final bPriority = _getPriorityValueFromEnum(b.priorityEnum);
      return bPriority.compareTo(aPriority); // Highest to lowest
    });
    return sortedTasks;
  }

  int _getPriorityValueFromString(String? priority) {
    if (priority == null) return 0;
    switch (priority.toLowerCase()) {
      case 'critical':
      case 'highest':
        return 4;
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
      case 'lowest':
        return 1;
      default:
        return 0;
    }
  }

  int _getPriorityValueFromEnum(Priority priority) {
    switch (priority) {
      case Priority.critical:
        return 4;
      case Priority.high:
        return 3;
      case Priority.medium:
        return 2;
      case Priority.low:
        return 1;
    }
  }

  @override
  void initState() {
    super.initState();
    // Register for schedule updates
    widget.onRegisterScheduleUpdate(_onScheduleUpdate);
  }

  @override
  void dispose() {
    // Unregister from schedule updates
    widget.onUnregisterScheduleUpdate(_onScheduleUpdate);
    super.dispose();
  }

  void _onScheduleUpdate() {
    // Force rebuild when schedule updates
    if (mounted) {
      setState(() {});
    }
  }

  void _showCreateProjectDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateProjectDialog(
        onProjectCreated: (project, isProfessional) {
          widget.onAddProject(project, isProfessional);
        },
        onAddSharedScript: widget.onAddSharedScript,
        onUpdateSharedScript: widget.onUpdateSharedScript,
        onRemoveSharedScript: widget.onRemoveSharedScript,
        sharedScripts: widget.settings.sharedScripts,
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        settings: widget.settings,
        onSettingsChanged: (newSettings) {
          // Update settings in main app
          widget.onUpdateSettings(newSettings);
        },
        onAddSharedScript: widget.onAddSharedScript,
        onUpdateSharedScript: widget.onUpdateSharedScript,
        onRemoveSharedScript: widget.onRemoveSharedScript,
      ),
    );
  }

  void _selectProject(Project project) {
    setState(() {
      _selectedProject = project;
    });
  }

  void _goBackToDashboard() {
    setState(() {
      _selectedProject = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Title area
            Padding(
              padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0, bottom: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (_selectedProject != null) ...[
                        IconButton(
                          onPressed: _goBackToDashboard,
                          icon: Icon(Icons.arrow_back, color: Colors.grey[300]),
                        ),
                        const SizedBox(width: 16),
                      ],
            Text(
                        _selectedProject?.name.toUpperCase() ?? 'TASK MANAGER',
              style: const TextStyle(
                          fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                          letterSpacing: 2.0,
              ),
            ),
                    ],
                  ),
                  Row(
                  children: [
                      IconButton(
                        onPressed: _showSettingsDialog,
                        icon: Icon(Icons.settings, color: Colors.grey[300]),
                        tooltip: 'Settings',
                      ),
                  ],
            ),
          ],
        ),
      ),
            
            // Three-column layout
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
        children: [
                    // Left Panel - Schedule (20%)
                    Expanded(
                      flex: 20,
                      child: _buildSchedulePanel(),
              ),
                    
                    const SizedBox(width: 20),
                    
                    // Center Panel - Content (60%)
                    Expanded(
                      flex: 60,
                      child: _selectedProject != null
                          ? _buildProjectDetailContent()
                          : _buildDashboardContent(),
                    ),
                    
                    const SizedBox(width: 20),
                    
                    // Right Panel - Updates (20%)
                    Expanded(
                      flex: 20,
                      child: _buildUpdatesPanel(),
              ),
            ],
          ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildSchedulePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
            children: [
                Icon(Icons.schedule, color: Colors.blue[400], size: 20),
              const SizedBox(width: 8),
                Expanded(
                  child: const Text(
                    'SCHEDULE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          ),
          
          // Schedule content using SharedSchedulePanel
          Expanded(
            child: SharedSchedulePanel(
              scheduledTasks: widget.scheduledTasks,
              onRemoveTask: widget.onRemoveTaskFromSchedule,
              onExpandTask: widget.onExpandScheduledTask,
              onReorder: widget.onReorderScheduledTasks,
              onOpenTaskDetail: (scheduledTask) {
                // Find the project for this task
                final project = [...widget.professionalProjects, ...widget.personalProjects]
                    .firstWhere((p) => p.id == scheduledTask.projectId);
                
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TaskDetailPage(
                      task: scheduledTask.task,
                      project: project,
                      projectName: project.name,
                      jiraBaseUrl: project.jiraBaseUrl,
                      projectKey: project.extractedJiraProjectKey,
                      onAddToSchedule: widget.onAddTaskToSchedule,
                    ),
                  ),
                );
              },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Container(
              decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
              ),
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // Header with tabs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.folder, color: Colors.blue[400], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'PROJECTS',
                          style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                FloatingActionButton(
                  onPressed: _showCreateProjectDialog,
                  backgroundColor: Colors.blue,
                  mini: true,
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ],
            ),
            ),
          
          // Tab bar
          Container(
            color: Colors.grey[800],
            child: TabBar(
              controller: widget.tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[400],
              indicatorColor: Colors.blue,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Professional'),
                Tab(text: 'Personal'),
              ],
            ),
          ),
          
          // Project content
          Expanded(
            child: TabBarView(
              controller: widget.tabController,
      children: [
                ProjectGrid(
                  projects: widget.professionalProjects,
                  isProfessional: true,
                  projectJiraIssues: widget.projectJiraIssues,
                  onUpdateProject: widget.onUpdateProject,
                  onDeleteProject: widget.onDeleteProject,
                  onAddTaskToSchedule: widget.onAddTaskToSchedule,
                  onFetchJiraIssues: widget.onFetchJiraIssuesForProject,
                  professionalProjects: widget.professionalProjects,
                  personalProjects: widget.personalProjects,
                  scheduledTasks: widget.scheduledTasks,
                  onRemoveTask: widget.onRemoveTaskFromSchedule,
                  onOpenTaskDetail: (scheduledTask) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TaskDetailPage(
                          task: scheduledTask.task,
                          project: widget.professionalProjects.firstWhere((p) => p.id == scheduledTask.projectId),
                          projectName: scheduledTask.projectName,
                          jiraBaseUrl: widget.professionalProjects.firstWhere((p) => p.id == scheduledTask.projectId).jiraBaseUrl,
                          projectKey: widget.professionalProjects.firstWhere((p) => p.id == scheduledTask.projectId).extractedJiraProjectKey,
                          onAddToSchedule: widget.onAddTaskToSchedule,
            ),
                      ),
                    );
                  },
                  onScheduleUpdated: null,
                  onRegisterScheduleUpdate: widget.onRegisterScheduleUpdate,
                  onUnregisterScheduleUpdate: widget.onUnregisterScheduleUpdate,
                  onProjectSelected: _selectProject,
                ),
                ProjectGrid(
                  projects: widget.personalProjects,
                  isProfessional: false,
                  projectJiraIssues: widget.projectJiraIssues,
                  onUpdateProject: widget.onUpdateProject,
                  onDeleteProject: widget.onDeleteProject,
                  onAddTaskToSchedule: widget.onAddTaskToSchedule,
                  onFetchJiraIssues: widget.onFetchJiraIssuesForProject,
                  professionalProjects: widget.professionalProjects,
                  personalProjects: widget.personalProjects,
                  scheduledTasks: widget.scheduledTasks,
                  onRemoveTask: widget.onRemoveTaskFromSchedule,
                  onOpenTaskDetail: (scheduledTask) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TaskDetailPage(
                          task: scheduledTask.task,
                          project: widget.personalProjects.firstWhere((p) => p.id == scheduledTask.projectId),
                          projectName: scheduledTask.projectName,
                          jiraBaseUrl: widget.personalProjects.firstWhere((p) => p.id == scheduledTask.projectId).jiraBaseUrl,
                          projectKey: widget.personalProjects.firstWhere((p) => p.id == scheduledTask.projectId).extractedJiraProjectKey,
                          onAddToSchedule: widget.onAddTaskToSchedule,
            ),
                      ),
                    );
                  },
                  onScheduleUpdated: null,
                  onRegisterScheduleUpdate: widget.onRegisterScheduleUpdate,
                  onUnregisterScheduleUpdate: widget.onUnregisterScheduleUpdate,
                  onProjectSelected: _selectProject,
                ),
              ],
          ),
        ),
      ],
      ),
    );
  }

    Widget _buildProjectDetailContent() {
    if (_selectedProject == null) return Container();
    
    // Handle YouTube projects with special detail page
    if (_selectedProject is YouTubeProject) {
      return YouTubeProjectDetailsPage(
        project: _selectedProject! as YouTubeProject,
        onProjectUpdated: (updatedProject) {
          widget.onUpdateProject(updatedProject);
          setState(() {
            _selectedProject = updatedProject;
          });
        },
        onAddToSchedule: widget.onAddTaskToSchedule,
      );
    }
    
    // Use the comprehensive ProjectDetailPage for other projects
    return ProjectDetailPage(
      project: _selectedProject!,
      onProjectUpdated: widget.onUpdateProject,
      onAddToSchedule: widget.onAddTaskToSchedule,
      professionalProjects: widget.professionalProjects,
      personalProjects: widget.personalProjects,
      scheduledTasks: widget.scheduledTasks,
      onRemoveTask: widget.onRemoveTaskFromSchedule,
      onOpenTaskDetail: (scheduledTask) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TaskDetailPage(
              task: scheduledTask.task,
              project: _selectedProject!,
              projectName: scheduledTask.projectName,
              jiraBaseUrl: _selectedProject!.jiraBaseUrl,
              projectKey: _selectedProject!.extractedJiraProjectKey,
              onAddToSchedule: widget.onAddTaskToSchedule,
            ),
          ),
        );
      },
      onRegisterScheduleUpdate: widget.onRegisterScheduleUpdate,
      onUnregisterScheduleUpdate: widget.onUnregisterScheduleUpdate,
      onAddSharedScript: widget.onAddSharedScript,
      onUpdateSharedScript: widget.onUpdateSharedScript,
      onRemoveSharedScript: widget.onRemoveSharedScript,
      sharedScripts: widget.settings.sharedScripts,
      onBack: () {
        setState(() {
          _selectedProject = null;
        });
      },
    );
  }



  Widget _buildUpdatesPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.update, color: Colors.blue[400], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedProject != null ? 'PROJECT DETAILS' : 'UPDATES',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedProject != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AddScriptDialog(
                          onScriptCreated: (script) {
                            final updatedProject = _selectedProject!.copyWith(
                              scripts: [..._selectedProject!.scripts, script],
                            );
                            widget.onUpdateProject(updatedProject);
                            setState(() {
                              _selectedProject = updatedProject;
                            });
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Script'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          
          // Updates content
          Expanded(
            child: _selectedProject != null
                ? _buildProjectUpdates()
                : _buildDashboardUpdates(),
                                              ),
                                            ],
                                          ),
    );
  }

  Widget _buildDashboardUpdates() {
    return Center(
                                            child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
          Icon(
            Icons.update_outlined,
            size: 48,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'No recent updates',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Project updates will appear here',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
                                            ),
                                          ),
        ],
                                        ),
    );
  }

  Widget _buildProjectUpdates() {
    if (_selectedProject == null) return Container();
    
    final project = _selectedProject!;
    final jiraIssues = widget.projectJiraIssues[project.id] ?? [];
    
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Project stats
        Card(
          color: const Color(0xFF2A2A2A),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project Stats',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total Tasks: ${project.tasks.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
                Text(
                  'Completed: ${project.completedTasks}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
                if (jiraIssues.isNotEmpty) ...[
                  Text(
                    'Jira Issues: ${jiraIssues.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                  Text(
                    'Sprint Issues: ${project.getSprintIssueCount(jiraIssues)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Project Summary
        if (project.projectSummary != null && project.projectSummary!.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, color: Colors.blue[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Project Summary',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    project.projectSummary!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[300],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Tech Stack
        if (project.techStack != null && project.techStack!.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.build, color: Colors.orange[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Tech Stack',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    project.techStack!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Jira Project URL
        if (project.jiraProjectUrl != null && project.jiraProjectUrl!.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.green[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Jira Project',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      // TODO: Open URL in browser
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Opening: ${project.jiraProjectUrl}')),
                      );
                    },
                    child: Text(
                      project.jiraProjectUrl!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[300],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // GitHub Repo Path (Development projects only)
        if (project is DevelopmentProject && 
            project.githubRepoPath != null && 
            project.githubRepoPath!.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder, color: Colors.purple[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'GitHub Repository',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    project.githubRepoPath!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Setup Script (Development projects only)
        if (project is DevelopmentProject && 
            project.setupScriptPath != null && 
            project.setupScriptPath!.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code, color: Colors.yellow[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Setup Script',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        project.setupScriptPath!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            await project.runSetupScript();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Setup script executed successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error running setup script: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        child: const Text('Run', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Custom Scripts
        if (project.scripts.isNotEmpty) ...[
          Card(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code, color: Colors.blue[400], size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Custom Scripts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${project.scripts.length} script(s) available',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...project.scripts.take(3).map((script) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_outline, color: Colors.green[400], size: 12),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            script.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[300],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                  if (project.scripts.length > 3) ...[
                    Text(
                      '... and ${project.scripts.length - 3} more',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Recent activity
        Card(
          color: const Color(0xFF2A2A2A),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Activity',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Project created: ${_formatDate(project.createdAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }



  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Add SharedSchedulePanel widget definition here (moved from ui_dashboard.dart)
class SharedSchedulePanel extends StatelessWidget {
  final List<ScheduledTask> scheduledTasks;
  final Function(ScheduledTask) onRemoveTask;
  final Function(ScheduledTask) onOpenTaskDetail;
  final Future<void> Function(BuildContext, ScheduledTask) onExpandTask;
  final Function(int, int)? onReorder;

  const SharedSchedulePanel({
    super.key,
    required this.scheduledTasks,
    required this.onRemoveTask,
    required this.onOpenTaskDetail,
    required this.onExpandTask,
    this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return scheduledTasks.isEmpty
        ? Center(
                                          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                  Icons.schedule_outlined,
                                                size: 48,
                  color: Colors.grey[600],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                  'No scheduled tasks',
                                                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                  'Add tasks from projects',
                                                style: TextStyle(
                                                  fontSize: 12,
                    color: Colors.grey[600],
                                                ),
                                              ),
              ],
            ),
          )
        : DragTarget<ScheduledTask>(
            onWillAccept: (data) => data != null,
            onAccept: (draggedTask) {
              // This will be handled by the individual drop targets
            },
            builder: (context, candidateData, rejectedData) {
              return ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: scheduledTasks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final scheduledTask = scheduledTasks[index];
                  final isSubtask = scheduledTask.task.isSubtask;

                  return DragTarget<ScheduledTask>(
                    onWillAccept: (data) => data != null && data.id != scheduledTask.id,
                    onAccept: (draggedTask) {
                      if (onReorder != null) {
                        final oldIndex = scheduledTasks.indexWhere((task) => task.id == draggedTask.id);
                        final newIndex = index;
                        if (oldIndex != -1) {
                          onReorder!(oldIndex, newIndex);
                        }
                      }
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Draggable<ScheduledTask>(
                        key: ValueKey(scheduledTask.id),
                        data: scheduledTask,
                        feedback: Material(
                          elevation: 8,
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.15, // 20% of screen width
                            padding: EdgeInsets.symmetric(
                              horizontal: isSubtask ? 8 : 12,
                              vertical: 10,
                                                  ),
                            decoration: BoxDecoration(
                              color: isSubtask
                                  ? const Color(0xFF262626)
                                  : const Color(0xFF2A2A2A),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                            child: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  child: isEmailTask(scheduledTask.task.description)
                                      ? Icon(
                                          Icons.email,
                                          size: isSubtask ? 10 : 12,
                                          color: scheduledTask.projectColor,
                                        )
                                      : isVideoTask(scheduledTask.task.description)
                                          ? Icon(
                                              Icons.play_circle,
                                              size: isSubtask ? 10 : 12,
                                              color: scheduledTask.projectColor,
                                            )
                                          : Container(
                                              width: isSubtask ? 6 : 8,
                                              height: isSubtask ? 6 : 8,
                                              decoration: BoxDecoration(
                                                color: scheduledTask.projectColor,
                                                borderRadius: BorderRadius.circular(isSubtask ? 3 : 4),
                                              ),
                                            ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    scheduledTask.task.title,
                                                  style: TextStyle(
                                      fontSize: isSubtask ? 10 : 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                                  ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                        ),
                        childWhenDragging: Container(
                          height: 60,
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: Colors.grey[800]!.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[600]!.withOpacity(0.3)),
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: candidateData.isNotEmpty
                                ? Border.all(color: Colors.blue, width: 2)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _HoverCard(
                            scheduledTask: scheduledTask,
                            isSubtask: isSubtask,
                            onRemoveTask: onRemoveTask,
                            onOpenTaskDetail: onOpenTaskDetail,
                            onExpandTask: onExpandTask,
                              ),
                            ),
                      );
                    },
                  );
                },
              );
            },
          );
  }
}

// Add this below SharedSchedulePanel
class _HoverCard extends StatefulWidget {
  final ScheduledTask scheduledTask;
  final bool isSubtask;
  final Function(ScheduledTask) onRemoveTask;
  final Function(ScheduledTask) onOpenTaskDetail;
  final Future<void> Function(BuildContext, ScheduledTask) onExpandTask;

  const _HoverCard({
    super.key,
    required this.scheduledTask,
    required this.isSubtask,
    required this.onRemoveTask,
    required this.onOpenTaskDetail,
    required this.onExpandTask,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool isHovered = false;

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
      case Priority.critical:
        return Colors.purple;
    }
  }

  String _getPriorityText(Priority priority) {
    switch (priority) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
      case Priority.critical:
        return 'Critical';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduledTask = widget.scheduledTask;
    final isSubtask = widget.isSubtask;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isHovered ? (Matrix4.identity()..translate(0.0, -1.0, 0.0)) : Matrix4.identity(),
        child: Card(
          color: isHovered
              ? (isSubtask ? const Color(0xFF1F1F1F) : const Color(0xFF232323))
              : (isSubtask ? const Color(0xFF262626) : const Color(0xFF2A2A2A)),
          margin: EdgeInsets.zero,
          elevation: isHovered ? 4 : 1,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSubtask ? 8 : 12,
              vertical: isSubtask ? 10 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
          children: [
                // Leading indicator - colored dot for regular tasks, colored email icon for email tasks
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  child: isEmailTask(scheduledTask.task.description)
                      ? Icon(
                          Icons.email,
                          size: isSubtask ? 10 : 12,
                          color: scheduledTask.projectColor,
                        )
                      : isVideoTask(scheduledTask.task.description)
                          ? Icon(
                              Icons.play_circle,
                              size: isSubtask ? 10 : 12,
                              color: scheduledTask.projectColor,
                            )
                          : Container(
                              width: isSubtask ? 6 : 8,
                              height: isSubtask ? 6 : 8,
                              decoration: BoxDecoration(
                                color: scheduledTask.projectColor,
                                borderRadius: BorderRadius.circular(isSubtask ? 3 : 4),
                              ),
                            ),
                ),
                const SizedBox(width: 12),
                // Main content - draggable area
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onOpenTaskDetail(scheduledTask),
                    child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text(
                          scheduledTask.task.title,
                          style: TextStyle(
                            fontSize: isSubtask ? 10 : 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                ),
                        SizedBox(height: 2),
            Row(
              children: [
                  Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                                color: _getPriorityColor(scheduledTask.task.priorityEnum).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                                  color: _getPriorityColor(scheduledTask.task.priorityEnum).withOpacity(0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                                _getPriorityText(scheduledTask.task.priorityEnum),
                      style: TextStyle(
                                  fontSize: isSubtask ? 6 : 8,
                                  color: _getPriorityColor(scheduledTask.task.priorityEnum),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                            const SizedBox(width: 6),
                            Text(
                              scheduledTask.projectName,
                    style: TextStyle(
                                fontSize: isSubtask ? 8 : 10,
                                color: Colors.grey[400],
                  ),
                ),
                ],
                        ),
                      ],
                  ),
                  ),
                ),
                // Trailing remove button - not draggable
                if (!isSubtask) ...[
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.purple[300],
                      ),
                      onPressed: () => widget.onExpandTask(context, scheduledTask),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      size: isSubtask ? 14 : 16,
                      color: Colors.red[400],
                    ),
                    onPressed: () => widget.onRemoveTask(scheduledTask),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddTaskDialog extends StatefulWidget {
  final String projectId;
  final Function(Task) onTaskCreated;
  final bool hasJiraIntegration;

  const AddTaskDialog({
    super.key,
    required this.projectId,
    required this.onTaskCreated,
    this.hasJiraIntegration = false,
  });

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _jiraTicketController = TextEditingController();
  final _emailAddressController = TextEditingController();
  final _emailSubjectController = TextEditingController();
  final _videoTitleController = TextEditingController();
  final _videoPublishDateController = TextEditingController();
  Priority _selectedPriority = Priority.medium;
  TaskType _selectedTaskType = TaskType.general;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _jiraTicketController.dispose();
    _emailAddressController.dispose();
    _emailSubjectController.dispose();
    _videoTitleController.dispose();
    _videoPublishDateController.dispose();
    super.dispose();
  }

  void _createTask() {
    String title;
    String description;

    if (_selectedTaskType == TaskType.email) {
      if (_emailAddressController.text.isEmpty || _emailSubjectController.text.isEmpty) return;
      
      title = "Email ${_emailAddressController.text} about ${_emailSubjectController.text}";
      
      // Combine email data with optional description
      final emailData = "address: ${_emailAddressController.text}, subject: ${_emailSubjectController.text}";
      final optionalDescription = _descriptionController.text.trim();
      
      if (optionalDescription.isNotEmpty) {
        description = "$emailData, notes: $optionalDescription";
      } else {
        description = emailData;
      }
    } else if (_selectedTaskType == TaskType.video) {
      if (_videoTitleController.text.isEmpty || _videoPublishDateController.text.isEmpty) return;
      
      title = "Video: ${_videoTitleController.text}";
      
      // Combine video data with optional description
      final videoData = "title: ${_videoTitleController.text}, publish_date: ${_videoPublishDateController.text}";
      final optionalDescription = _descriptionController.text.trim();
      
      if (optionalDescription.isNotEmpty) {
        description = "$videoData, notes: $optionalDescription";
      } else {
        description = videoData;
      }
    } else {
      if (_titleController.text.isEmpty) return;
      
      title = _titleController.text;
      description = _descriptionController.text;
    }

    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      key: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      projectId: widget.projectId,
      createdAt: DateTime.now(),
      status: 'To Do',
      jiraTicketId: _jiraTicketController.text.isEmpty ? null : _jiraTicketController.text,
      priorityEnum: _selectedPriority,
    );

    widget.onTaskCreated(task);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Task'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Task Type Selector
            DropdownButtonFormField<TaskType>(
              value: _selectedTaskType,
              decoration: const InputDecoration(
                labelText: 'Task Type',
                border: OutlineInputBorder(),
              ),
              items: TaskType.values.map((type) {
                IconData icon;
                Color color;
                
                switch (type) {
                  case TaskType.email:
                    icon = Icons.email;
                    color = Colors.blue;
                    break;
                  case TaskType.video:
                    icon = Icons.play_circle;
                    color = Colors.red;
                    break;
                  case TaskType.general:
                  default:
                    icon = Icons.task;
                    color = Colors.grey[600]!;
                    break;
                }
                
                return DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(width: 8),
                      Text(type.name.toUpperCase()),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (type) {
                if (type != null) {
                  setState(() {
                    _selectedTaskType = type;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            
            // Dynamic content based on task type
            if (_selectedTaskType == TaskType.email) ...[
              // Email task fields
              TextField(
                controller: _emailAddressController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  hintText: 'recipient@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailSubjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  hintText: 'What to email about',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Additional notes or context...',
                ),
                maxLines: 3,
              ),
            ] else if (_selectedTaskType == TaskType.video) ...[
              // Video task fields
              TextField(
                controller: _videoTitleController,
                decoration: const InputDecoration(
                  labelText: 'Video Title',
                  border: OutlineInputBorder(),
                  hintText: 'Enter video title',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _videoPublishDateController,
                decoration: const InputDecoration(
                  labelText: 'Publish Date',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., 2024-01-15 or "Next Monday"',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Video description, notes, or context...',
                ),
                maxLines: 3,
              ),
            ] else ...[
              // General task fields
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
            
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              value: _selectedPriority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: Priority.values.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getPriorityColor(priority),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_getPriorityText(priority)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (priority) {
                if (priority != null) {
                  setState(() {
                    _selectedPriority = priority;
                  });
                }
              },
            ),
            if (widget.hasJiraIntegration) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _jiraTicketController,
                decoration: const InputDecoration(
                  labelText: 'Jira Ticket ID (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., DEV-123',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createTask,
          child: const Text('Add Task'),
        ),
      ],
    );
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
      case Priority.critical:
        return Colors.purple;
    }
  }

  String _getPriorityText(Priority priority) {
    switch (priority) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
      case Priority.critical:
        return 'Critical';
    }
  }
}

class SettingsDialog extends StatefulWidget {
  final AppSettings settings;
  final Function(AppSettings) onSettingsChanged;
  final Function(Script)? onAddSharedScript;
  final Function(Script)? onUpdateSharedScript;
  final Function(String)? onRemoveSharedScript;

  const SettingsDialog({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onAddSharedScript,
    this.onUpdateSharedScript,
    this.onRemoveSharedScript,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _chatGptController;
  late TextEditingController _jiraTokenController;
  late TextEditingController _jiraUsernameController;

  @override
  void initState() {
    super.initState();
    _chatGptController = TextEditingController(text: widget.settings.chatGptToken ?? '');
    _jiraTokenController = TextEditingController(text: widget.settings.jiraToken ?? '');
    _jiraUsernameController = TextEditingController(text: widget.settings.jiraUsername ?? '');
  }

  @override
  void dispose() {
    _chatGptController.dispose();
    _jiraTokenController.dispose();
    _jiraUsernameController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final newSettings = AppSettings(
      chatGptToken: _chatGptController.text.isEmpty ? null : _chatGptController.text,
      jiraToken: _jiraTokenController.text.isEmpty ? null : _jiraTokenController.text,
      jiraUsername: _jiraUsernameController.text.isEmpty ? null : _jiraUsernameController.text,
    );
    widget.onSettingsChanged(newSettings);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'API Tokens (stored locally only)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _chatGptController,
              decoration: const InputDecoration(
                labelText: 'OpenAI Key',
                border: OutlineInputBorder(),
                hintText: 'sk-...',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _jiraTokenController,
              decoration: const InputDecoration(
                labelText: 'Jira API Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _jiraUsernameController,
              decoration: const InputDecoration(
                labelText: 'Jira Username',
                border: OutlineInputBorder(),
                hintText: 'your.username@company.com',
                helperText: 'Only tasks assigned to this user will be auto-scheduled',
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Shared Scripts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close settings dialog
                    showDialog(
                      context: context,
                      builder: (context) => SharedScriptsDialog(
                        sharedScripts: widget.settings.sharedScripts,
                        onAddSharedScript: widget.onAddSharedScript ?? (_) {},
                        onUpdateSharedScript: widget.onUpdateSharedScript ?? (_) {},
                        onRemoveSharedScript: widget.onRemoveSharedScript ?? (_) {},
                        onAddToProject: (_) {}, // Not used in settings context
                      ),
                    );
                  },
                  icon: const Icon(Icons.code),
                  label: const Text('Manage Shared Scripts'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.settings.sharedScripts.length} shared script(s) available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class EditProjectDialog extends StatefulWidget {
  final Project project;
  final Function(Project) onProjectUpdated;

  const EditProjectDialog({
    super.key,
    required this.project,
    required this.onProjectUpdated,
  });

  @override
  State<EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<EditProjectDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _projectSummaryController;
  late TextEditingController _techStackController;
  late TextEditingController _jiraProjectUrlController;
  late TextEditingController _githubRepoPathController;
  late ProjectType _selectedType;
  String? _setupScriptFileName;
  String? _setupScriptContent;
  late List<Script> _scripts;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _descriptionController = TextEditingController(text: widget.project.description);
    _projectSummaryController = TextEditingController(text: widget.project.projectSummary ?? '');
    _techStackController = TextEditingController(text: widget.project.techStack ?? '');
    _jiraProjectUrlController = TextEditingController(text: widget.project.jiraProjectUrl ?? '');
    _selectedType = widget.project.type;
    _scripts = List.from(widget.project.scripts);
    
    // Initialize development-specific fields
    if (widget.project is DevelopmentProject) {
      final devProject = widget.project as DevelopmentProject;
      _githubRepoPathController = TextEditingController(text: devProject.githubRepoPath ?? '');
      _setupScriptFileName = devProject.setupScriptPath;
      _setupScriptContent = devProject.setupScriptContent;
    } else {
      _githubRepoPathController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _projectSummaryController.dispose();
    _techStackController.dispose();
    _jiraProjectUrlController.dispose();
    _githubRepoPathController.dispose();
    super.dispose();
  }

  void _addScript() {
    showDialog(
      context: context,
      builder: (context) => AddScriptDialog(
        onScriptCreated: (script) {
          setState(() {
            _scripts.add(script);
          });
        },
      ),
    );
  }

  void _removeScript(int index) {
    setState(() {
      _scripts.removeAt(index);
    });
  }

  void _updateProject() {
    Project updatedProject;
    
    if (widget.project is DevelopmentProject) {
      updatedProject = (widget.project as DevelopmentProject).copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
        githubRepoPath: _githubRepoPathController.text.isEmpty ? null : _githubRepoPathController.text,
        setupScriptPath: _setupScriptFileName,
        setupScriptContent: _setupScriptContent,
        scripts: _scripts,
      );
    } else {
      updatedProject = widget.project.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        type: _selectedType,
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
        scripts: _scripts,
      );
    }
    
    widget.onProjectUpdated(updatedProject);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Project'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Project Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _projectSummaryController,
              decoration: const InputDecoration(
                labelText: 'Project Summary (optional)',
                border: OutlineInputBorder(),
                hintText: 'Brief summary of the project goals and objectives',
              ),
              maxLines: 2,
            ),
            if (_selectedType == ProjectType.development) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _techStackController,
                decoration: const InputDecoration(
                  labelText: 'Tech Stack (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Flutter, Dart, Firebase, REST APIs',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _jiraProjectUrlController,
                decoration: const InputDecoration(
                  labelText: 'Project URL (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., https://company.atlassian.net/jira/software/projects/MOBILE/boards/1',
                  helperText: 'Copy URL from your Jira project page',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _githubRepoPathController,
                decoration: const InputDecoration(
                  labelText: 'GitHub Repo Path (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., /path/to/your/local/repo',
                  helperText: 'Local path to your GitHub repository',
                ),
              ),
              const SizedBox(height: 16),
              // Setup script file upload
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Setup Script (optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Upload a setup script to run when setting up the project',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1'],
                              );

                              if (result != null) {
                                final file = File(result.files.single.path!);
                                final content = await file.readAsString();
                                setState(() {
                                  _setupScriptFileName = result.files.single.name;
                                  _setupScriptContent = content;
                                });
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error picking file: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose setup script'),
                        ),
                        const SizedBox(width: 12),
                        if (_setupScriptFileName != null)
                          Expanded(
                            child: Text(
                              '✓ $_setupScriptFileName',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Scripts section
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Custom Scripts',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _addScript,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Script'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add custom scripts that can be run within this project',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_scripts.isEmpty)
                      const Text(
                        'No scripts added yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      ..._scripts.asMap().entries.map((entry) {
                        final index = entry.key;
                        final script = entry.value;
                        return Card(
                          margin: const EdgeInsets.only(top: 8),
                          child: ListTile(
                            leading: const Icon(Icons.code),
                            title: Text(script.name),
                            subtitle: Text(
                              '${script.runCommand} ${script.filePath}${script.arguments.isNotEmpty ? '\n${script.arguments.length} argument(s)' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => EditScriptDialog(
                                        script: script,
                                        onScriptUpdated: (updatedScript) {
                                          setState(() {
                                            _scripts[index] = updatedScript;
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeScript(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _updateProject,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// TaskDetailPage moved to ui_task_details.dart

// TaskDetailPage implementation moved to ui_task_details.dart

class EditTaskDialog extends StatefulWidget {
  final Task task;
  final Function(Task) onTaskUpdated;

  const EditTaskDialog({
    super.key,
    required this.task,
    required this.onTaskUpdated,
  });

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _emailAddressController;
  late TextEditingController _emailSubjectController;
  late Priority _selectedPriority;
  late TaskType _taskType;

  @override
  void initState() {
    super.initState();
    
    // Determine if this is an email task
    final emailData = parseEmailTaskData(widget.task.description);
    _taskType = emailData != null ? TaskType.email : TaskType.general;
    
    if (_taskType == TaskType.email) {
      _emailAddressController = TextEditingController(text: emailData!['address']);
      _emailSubjectController = TextEditingController(text: emailData!['subject']);
      
      // Extract optional description from email task
      final notesMatch = RegExp(r'notes:\\s*(.+)').firstMatch(widget.task.description ?? '');
      final optionalDescription = notesMatch?.group(1)?.trim() ?? '';
      _descriptionController = TextEditingController(text: optionalDescription);
      
      _titleController = TextEditingController();
    } else {
      _titleController = TextEditingController(text: widget.task.title);
      _descriptionController = TextEditingController(text: widget.task.description);
      _emailAddressController = TextEditingController();
      _emailSubjectController = TextEditingController();
    }
    
    _selectedPriority = widget.task.priorityEnum;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _emailAddressController.dispose();
    _emailSubjectController.dispose();
    super.dispose();
  }

  void _saveTask() {
    String title;
    String description;

    if (_taskType == TaskType.email) {
      if (_emailAddressController.text.isEmpty || _emailSubjectController.text.isEmpty) return;
      
      title = "Email ${_emailAddressController.text} about ${_emailSubjectController.text}";
      
      // Combine email data with optional description
      final emailData = "address: ${_emailAddressController.text}, subject: ${_emailSubjectController.text}";
      final optionalDescription = _descriptionController.text.trim();
      
      if (optionalDescription.isNotEmpty) {
        description = "$emailData, notes: $optionalDescription";
      } else {
        description = emailData;
      }
    } else {
      if (_titleController.text.trim().isEmpty) return;
      
      title = _titleController.text.trim();
      description = _descriptionController.text.trim();
    }

    final updatedTask = widget.task.copyWith(
      title: title,
      description: description,
      priorityEnum: _selectedPriority,
    );

    widget.onTaskUpdated(updatedTask);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _taskType == TaskType.email ? Icons.email : Icons.task,
            color: _taskType == TaskType.email ? Colors.blue : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Text('Edit ${_taskType.name.toUpperCase()} Task'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_taskType == TaskType.email) ...[
              // Email task fields
              TextField(
                controller: _emailAddressController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  hintText: 'recipient@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailSubjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  hintText: 'What to email about',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Additional notes or context...',
                ),
                maxLines: 3,
              ),
            ] else ...[
              // General task fields
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              value: _selectedPriority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: Priority.values.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getPriorityColor(priority),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_getPriorityText(priority)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (priority) {
                if (priority != null) {
                  setState(() {
                    _selectedPriority = priority;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveTask,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
      case Priority.critical:
        return Colors.purple;
    }
  }

  String _getPriorityText(Priority priority) {
    switch (priority) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
      case Priority.critical:
        return 'Critical';
    }
  }
}

// Helper functions for priority handling
Color _getPriorityColorFromString(String? priority) {
  if (priority == null) return Colors.grey;
  switch (priority.toLowerCase()) {
    case 'low':
    case 'lowest':
      return Colors.green;
    case 'medium':
      return Colors.orange;
    case 'high':
      return Colors.red;
    case 'critical':
    case 'highest':
      return Colors.purple;
    default:
      return Colors.grey;
  }
}

String _getPriorityTextFromString(String? priority) {
  if (priority == null) return 'Medium';
  switch (priority.toLowerCase()) {
    case 'low':
    case 'lowest':
      return 'Low';
    case 'medium':
      return 'Medium';
    case 'high':
      return 'High';
    case 'critical':
    case 'highest':
      return 'Critical';
    default:
      return 'Medium';
  }
}



Color _getPriorityColorFromEnum(Priority priority) {
  switch (priority) {
    case Priority.low:
      return Colors.green;
    case Priority.medium:
      return Colors.orange;
    case Priority.high:
      return Colors.red;
    case Priority.critical:
      return Colors.purple;
  }
}

String _getPriorityTextFromEnum(Priority priority) {
  switch (priority) {
    case Priority.low:
      return 'Low';
    case Priority.medium:
      return 'Medium';
    case Priority.high:
      return 'High';
    case Priority.critical:
      return 'Critical';
  }
}

// Helper functions for parsing task data
Map<String, String>? parseEmailTaskData(String? description) {
  if (description == null || description.isEmpty) return null;
  
  final addressMatch = RegExp(r'address:\s*([^,]+)').firstMatch(description);
  final subjectMatch = RegExp(r'subject:\s*([^,]+)').firstMatch(description);
  
  if (addressMatch != null && subjectMatch != null) {
    return {
      'address': addressMatch.group(1)?.trim() ?? '',
      'subject': subjectMatch.group(1)?.trim() ?? '',
    };
  }
  
  return null;
}

Map<String, String>? parseVideoTaskData(String? description) {
  if (description == null || description.isEmpty) return null;
  
  final titleMatch = RegExp(r'title:\s*([^,]+)').firstMatch(description);
  final publishDateMatch = RegExp(r'publish_date:\s*([^,]+)').firstMatch(description);
  
  if (titleMatch != null && publishDateMatch != null) {
    return {
      'title': titleMatch.group(1)?.trim() ?? '',
      'publish_date': publishDateMatch.group(1)?.trim() ?? '',
    };
  }
  
  return null;
}

// Script management dialogs
class AddScriptDialog extends StatefulWidget {
  final Function(Script) onScriptCreated;

  const AddScriptDialog({
    super.key,
    required this.onScriptCreated,
  });

  @override
  State<AddScriptDialog> createState() => _AddScriptDialogState();
}

class _AddScriptDialogState extends State<AddScriptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _runCommandController = TextEditingController();
  final _filePathController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cronScheduleController = TextEditingController();
  final List<ScriptArgument> _arguments = [];

  @override
  void dispose() {
    _nameController.dispose();
    _runCommandController.dispose();
    _filePathController.dispose();
    _descriptionController.dispose();
    _cronScheduleController.dispose();
    super.dispose();
  }

  void _addArgument() {
    showDialog(
      context: context,
      builder: (context) => AddArgumentDialog(
        onArgumentCreated: (argument) {
          setState(() {
            _arguments.add(argument);
          });
        },
      ),
    );
  }

  void _removeArgument(int index) {
    setState(() {
      _arguments.removeAt(index);
    });
  }

  void _createScript() {
    if (_formKey.currentState!.validate()) {
      final script = Script(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        runCommand: _runCommandController.text.trim(),
        filePath: _filePathController.text.trim(),
        arguments: _arguments,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        cronSchedule: _cronScheduleController.text.trim().isEmpty ? null : _cronScheduleController.text.trim(),
        createdAt: DateTime.now(),
      );

      widget.onScriptCreated(script);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Custom Script'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Script Name',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Build Project',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a script name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _runCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Run Command',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., npm, python, bash',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a run command';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _filePathController,
                  decoration: const InputDecoration(
                    labelText: 'Script File Path',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., build.sh, main.py',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a file path';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'What this script does',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cronScheduleController,
                  decoration: const InputDecoration(
                    labelText: 'Cron Schedule (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 0 9 * * 1-5 (weekdays at 9 AM)',
                    helperText: 'Leave empty for manual execution only',
                  ),
                ),
                const SizedBox(height: 16),
                // Arguments section
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Script Arguments',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _addArgument,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Argument'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_arguments.isEmpty)
                        const Text(
                          'No arguments defined',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      else
                        ..._arguments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final argument = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: ListTile(
                              title: Text(argument.name),
                              subtitle: Text(
                                'Default: ${argument.defaultValue ?? 'None'}${argument.description != null ? '\n${argument.description}' : ''}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeArgument(index),
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createScript,
          child: const Text('Add Script'),
        ),
      ],
    );
  }
}

class AddArgumentDialog extends StatefulWidget {
  final Function(ScriptArgument) onArgumentCreated;

  const AddArgumentDialog({
    super.key,
    required this.onArgumentCreated,
  });

  @override
  State<AddArgumentDialog> createState() => _AddArgumentDialogState();
}

class _AddArgumentDialogState extends State<AddArgumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _defaultValueController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _defaultValueController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createArgument() {
    if (_formKey.currentState!.validate()) {
      final argument = ScriptArgument(
        name: _nameController.text.trim(),
        defaultValue: _defaultValueController.text.trim().isEmpty ? null : _defaultValueController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      );

      widget.onArgumentCreated(argument);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Script Argument'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Argument Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., environment, version',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an argument name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _defaultValueController,
                decoration: const InputDecoration(
                  labelText: 'Default Value (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., production, 1.0.0',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'What this argument does',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createArgument,
          child: const Text('Add Argument'),
        ),
      ],
    );
  }
}

class EditScriptDialog extends StatefulWidget {
  final Script script;
  final Function(Script) onScriptUpdated;

  const EditScriptDialog({
    super.key,
    required this.script,
    required this.onScriptUpdated,
  });

  @override
  State<EditScriptDialog> createState() => _EditScriptDialogState();
}

class _EditScriptDialogState extends State<EditScriptDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _runCommandController;
  late TextEditingController _filePathController;
  late TextEditingController _descriptionController;
  late TextEditingController _cronScheduleController;
  late List<ScriptArgument> _arguments;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.script.name);
    _runCommandController = TextEditingController(text: widget.script.runCommand);
    _filePathController = TextEditingController(text: widget.script.filePath);
    _descriptionController = TextEditingController(text: widget.script.description ?? '');
    _cronScheduleController = TextEditingController(text: widget.script.cronSchedule ?? '');
    _arguments = List.from(widget.script.arguments);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _runCommandController.dispose();
    _filePathController.dispose();
    _descriptionController.dispose();
    _cronScheduleController.dispose();
    super.dispose();
  }

  void _addArgument() {
    showDialog(
      context: context,
      builder: (context) => AddArgumentDialog(
        onArgumentCreated: (argument) {
          setState(() {
            _arguments.add(argument);
          });
        },
      ),
    );
  }

  void _removeArgument(int index) {
    setState(() {
      _arguments.removeAt(index);
    });
  }

  void _updateScript() {
    if (_formKey.currentState!.validate()) {
      final updatedScript = widget.script.copyWith(
        name: _nameController.text.trim(),
        runCommand: _runCommandController.text.trim(),
        filePath: _filePathController.text.trim(),
        arguments: _arguments,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        cronSchedule: _cronScheduleController.text.trim().isEmpty ? null : _cronScheduleController.text.trim(),
      );

      widget.onScriptUpdated(updatedScript);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Script'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Script Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a script name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _runCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Run Command',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a run command';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _filePathController,
                  decoration: const InputDecoration(
                    labelText: 'Script File Path',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a file path';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cronScheduleController,
                  decoration: const InputDecoration(
                    labelText: 'Cron Schedule (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 0 9 * * 1-5 (weekdays at 9 AM)',
                  ),
                ),
                const SizedBox(height: 16),
                // Arguments section
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Script Arguments',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _addArgument,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Argument'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_arguments.isEmpty)
                        const Text(
                          'No arguments defined',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      else
                        ..._arguments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final argument = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: ListTile(
                              title: Text(argument.name),
                              subtitle: Text(
                                'Default: ${argument.defaultValue ?? 'None'}${argument.description != null ? '\n${argument.description}' : ''}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeArgument(index),
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _updateScript,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}

class SharedScriptsDialog extends StatefulWidget {
  final List<Script> sharedScripts;
  final Function(Script) onAddSharedScript;
  final Function(Script) onUpdateSharedScript;
  final Function(String) onRemoveSharedScript;
  final Function(Script) onAddToProject;

  const SharedScriptsDialog({
    super.key,
    required this.sharedScripts,
    required this.onAddSharedScript,
    required this.onUpdateSharedScript,
    required this.onRemoveSharedScript,
    required this.onAddToProject,
  });

  @override
  State<SharedScriptsDialog> createState() => _SharedScriptsDialogState();
}

class _SharedScriptsDialogState extends State<SharedScriptsDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shared Scripts'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scripts available to all projects',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AddScriptDialog(
                        onScriptCreated: widget.onAddSharedScript,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Shared Script'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: widget.sharedScripts.isEmpty
                  ? const Center(
                      child: Text(
                        'No shared scripts available',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: widget.sharedScripts.length,
                      itemBuilder: (context, index) {
                        final script = widget.sharedScripts[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.code),
                            title: Text(script.name),
                            subtitle: Text(
                              '${script.runCommand} ${script.filePath}${script.arguments.isNotEmpty ? '\n${script.arguments.length} argument(s)' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.green),
                                  onPressed: () {
                                    widget.onAddToProject(script);
                                    Navigator.of(context).pop();
                                  },
                                  tooltip: 'Add to Project',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => EditScriptDialog(
                                        script: script,
                                        onScriptUpdated: widget.onUpdateSharedScript,
                                      ),
                                    );
                                  },
                                  tooltip: 'Edit Script',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Shared Script'),
                                        content: Text('Are you sure you want to delete "${script.name}"? This will remove it from all projects.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              widget.onRemoveSharedScript(script.id);
                                              Navigator.of(context).pop();
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  tooltip: 'Delete Script',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class RunScriptDialog extends StatefulWidget {
  final Script script;
  final Function(Script, Map<String, String>) onScriptRun;

  const RunScriptDialog({
    super.key,
    required this.script,
    required this.onScriptRun,
  });

  @override
  State<RunScriptDialog> createState() => _RunScriptDialogState();
}

class _RunScriptDialogState extends State<RunScriptDialog> {
  final Map<String, TextEditingController> _argumentControllers = {};
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers for each argument
    for (final argument in widget.script.arguments) {
      _argumentControllers[argument.name] = TextEditingController(
        text: argument.defaultValue ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _argumentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _runScript() async {
    setState(() {
      _isRunning = true;
    });

    try {
      // Collect argument values
      final argumentValues = <String, String>{};
      for (final argument in widget.script.arguments) {
        final controller = _argumentControllers[argument.name];
        if (controller != null) {
          argumentValues[argument.name] = controller.text.trim();
        }
      }

      await widget.onScriptRun(widget.script, argumentValues);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Script executed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error running script: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Run Script: ${widget.script.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.script.description != null) ...[
              Text(
                widget.script.description!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.script.arguments.isNotEmpty) ...[
              const Text(
                'Script Arguments:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.script.arguments.map((argument) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _argumentControllers[argument.name],
                    decoration: InputDecoration(
                      labelText: argument.name,
                      border: const OutlineInputBorder(),
                      hintText: argument.description ?? 'Enter value',
                      helperText: argument.defaultValue != null 
                          ? 'Default: ${argument.defaultValue}'
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ] else ...[
              const Text(
                'No arguments required for this script.',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isRunning ? null : _runScript,
          child: _isRunning 
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Running...'),
                  ],
                )
              : const Text('Run Script'),
        ),
      ],
    );
  }
}

bool isEmailTask(String? description) {
  return parseEmailTaskData(description) != null;
}

bool isVideoTask(String? description) {
  return parseVideoTaskData(description) != null;
}

Color _getStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'done':
    case 'closed':
    case 'resolved':
      return Colors.green;
    case 'in progress':
    case 'in review':
      return Colors.blue;
    case 'to do':
    case 'open':
      return Colors.grey;
    case 'blocked':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
