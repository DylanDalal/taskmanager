import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math; 
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'services/jira_service.dart';
import 'services/ai_expand_service.dart';

void main() {
  runApp(const TaskManagerApp());
}

// Data Models
enum ProjectType { development, general, youtube }

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
  final String? jiraBaseUrl;

  AppSettings({
    this.chatGptToken,
    this.jiraToken,
    this.jiraBaseUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'chatGptToken': chatGptToken,
      'jiraToken': jiraToken,
      'jiraBaseUrl': jiraBaseUrl,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      chatGptToken: json['chatGptToken'],
      jiraToken: json['jiraToken'],
      jiraBaseUrl: json['jiraBaseUrl'],
    );
  }

  AppSettings copyWith({
    String? chatGptToken,
    String? jiraToken,
    String? jiraBaseUrl,
  }) {
    return AppSettings(
      chatGptToken: chatGptToken ?? this.chatGptToken,
      jiraToken: jiraToken ?? this.jiraToken,
      jiraBaseUrl: jiraBaseUrl ?? this.jiraBaseUrl,
    );
  }
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});

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
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
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
      if (project.extractedJiraProjectKey != null) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${task.title}" is already in the schedule'),
          backgroundColor: Colors.orange,
        ),
      );
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
      // Sort by priority: Critical > High > Medium > Low
      _scheduledTasks.sort((a, b) => _comparePriority(a.task.priorityEnum, b.task.priorityEnum));
    });
    
    _saveScheduledTasks();
    
    // Notify any open ProjectDetailPage to refresh its schedule
    _notifyScheduleUpdate();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${task.title}" to schedule'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeTaskFromSchedule(ScheduledTask scheduledTask) {
    setState(() {
      _scheduledTasks.removeWhere((task) => task.id == scheduledTask.id);
    });
    
    _saveScheduledTasks();
    
    // Notify any open ProjectDetailPage to refresh its schedule
    _notifyScheduleUpdate();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${scheduledTask.task.title}" from schedule'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _fetchAndScheduleAssignedIssues() async {
    print('Fetching assigned Jira issues from all projects...');
    
    // Get all Jira-enabled projects
    final allProjects = [..._professionalProjects, ..._personalProjects];
    final jiraProjects = allProjects.where((project) => 
      project.jiraBaseUrl != null && project.extractedJiraProjectKey != null
    ).toList();
    
    if (jiraProjects.isEmpty) {
      print('No Jira projects found');
      return;
    }
    
    final jiraService = JiraService.instance;
    List<ScheduledTask> newScheduledTasks = [];
    
    // Fetch assigned issues from each Jira project
    for (final project in jiraProjects) {
      try {
        print('Fetching assigned issues for project: ${project.name}');
        final assignedIssues = await jiraService.fetchMyAssignedIssues(
          project.jiraBaseUrl!,
          project.extractedJiraProjectKey!,
        );
        
        print('Found ${assignedIssues.length} assigned issues in ${project.name}');
        
        // Convert Jira issues to scheduled tasks
        for (final issue in assignedIssues) {
          // Skip if already in schedule
          final existingTask = _scheduledTasks.any((st) => st.task.jiraTicketId == issue.key);
          if (existingTask) {
            continue;
          }
          
          // Convert Jira issue to Task
          final task = _convertJiraIssueToTaskForSchedule(issue, project.id);
          
          final scheduledTask = ScheduledTask(
            id: 'auto_${issue.key}_${DateTime.now().millisecondsSinceEpoch}',
            task: task,
            projectId: project.id,
            projectName: project.name,
            projectColor: project.color,
            scheduledAt: DateTime.now(),
          );
          
          newScheduledTasks.add(scheduledTask);
        }
      } catch (e) {
        print('Error fetching assigned issues for ${project.name}: $e');
        // Continue with other projects
      }
    }
    
    if (newScheduledTasks.isNotEmpty) {
      setState(() {
        _scheduledTasks.addAll(newScheduledTasks);
        // Sort by priority: Critical > High > Medium > Low
        _scheduledTasks.sort((a, b) => _comparePriority(a.task.priorityEnum, b.task.priorityEnum));
      });
      
      _saveScheduledTasks();
      
      // Notify any open ProjectDetailPage to refresh its schedule
      _notifyScheduleUpdate();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${newScheduledTasks.length} assigned Jira tasks to schedule'),
          backgroundColor: Colors.green,
        ),
      );
      
      print('Added ${newScheduledTasks.length} assigned tasks to schedule');
    } else {
      print('No new assigned issues found or all already scheduled');
    }
  }

  int _comparePriority(Priority a, Priority b) {
    const priorityOrder = {
      Priority.critical: 4,
      Priority.high: 3,
      Priority.medium: 2,
      Priority.low: 1,
    };
    
    return (priorityOrder[b] ?? 0) - (priorityOrder[a] ?? 0);
  }

  Task _convertJiraIssueToTaskForSchedule(Task issue, String projectId) {
    return issue.copyWith(projectId: projectId);
  }

  void _notifyScheduleUpdate() {
    // Notify all registered callbacks about schedule updates
    for (final callback in _scheduleUpdateCallbacks) {
      callback();
    }
  }

  void _registerScheduleUpdateCallback(Function() callback) {
    _scheduleUpdateCallbacks.add(callback);
  }

  void _unregisterScheduleUpdateCallback(Function() callback) {
    _scheduleUpdateCallbacks.remove(callback);
  }

  void _showCreateProjectDialog(bool isProfessional) {
    showDialog(
      context: context,
      builder: (context) => CreateProjectDialog(
        onProjectCreated: (project) => _addProject(project, isProfessional),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        settings: _settings,
        onSettingsChanged: (newSettings) {
          setState(() {
            _settings = newSettings;
          });
          _saveSettings();
        },
      ),
    );
  }

  void _addProject(Project project, bool isProfessional) {
    print('Adding project: ${project.name}, type: ${project.type}, context: ${isProfessional ? 'Professional' : 'Personal'}');
    setState(() {
      if (isProfessional) {
        _professionalProjects.add(project);
        print('Added to professional projects. Total: ${_professionalProjects.length}');
      } else {
        _personalProjects.add(project);
        print('Added to personal projects. Total: ${_personalProjects.length}');
      }
    });
    
    print('Current state - Professional: ${_professionalProjects.length}, Personal: ${_personalProjects.length}');
    
    // Save projects to storage
    _saveProjects();
    
    // Fetch Jira issues for new Jira projects
    if (project.extractedJiraProjectKey != null) {
      _fetchJiraIssuesForProject(project);
    }
  }

  Future<void> _fetchJiraIssuesForProject(Project project) async {
    if (project.jiraBaseUrl == null || project.extractedJiraProjectKey == null) {
      print('Skipping Jira fetch for ${project.name}: baseUrl=${project.jiraBaseUrl}, projectKey=${project.extractedJiraProjectKey}');
      return;
    }
    
    print('Fetching Jira issues for ${project.name}:');
    print('  Base URL: ${project.jiraBaseUrl}');
    print('  Project Key: ${project.extractedJiraProjectKey}');
    print('  Project URL: ${project.jiraProjectUrl}');
    
    try {
      final jiraService = JiraService.instance;
      final issues = await jiraService.fetchProjectIssues(
        project.jiraBaseUrl!,
        project.extractedJiraProjectKey!,
      );
      
      setState(() {
        _projectJiraIssues[project.id] = issues;
      });
      print('Successfully fetched ${issues.length} issues for ${project.name}');
    } catch (e) {
      print('Error fetching Jira issues for ${project.name}: $e');
      print('  This might be due to:');
      print('  - Project key "${project.extractedJiraProjectKey}" not existing in Jira');
      print('  - Insufficient permissions');
      print('  - Project being moved or renamed');
      print('  - Network connectivity issues');
      // Don't show error in dashboard, just use local counts
    }
  }

  int _getProjectTaskCount(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      // Exclude subtasks from task count
      return jiraIssues.where((issue) => !issue.isSubtask).length;
    }
    return project.tasks.where((task) => !task.isSubtask).length;
  }

  int _getProjectCompletedCount(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      // Exclude subtasks from completed count
      return jiraIssues.where((issue) => 
        !issue.isSubtask && (
          issue.status.toLowerCase() == 'done' || 
          issue.status.toLowerCase() == 'closed' ||
          issue.status.toLowerCase() == 'resolved'
        )
      ).length;
    }
    return project.completedTasks;
  }

  double _getProjectProgress(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return project.getProgressPercentage(jiraIssues);
    }
    return project.progressPercentage;
  }

  double _getSprintProgress(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return project.getSprintProgressPercentage(jiraIssues);
    }
    return 0.0;
  }

  int _getSprintIssueCount(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return project.getSprintIssueCount(jiraIssues);
    }
    return 0;
  }

  String? _getCurrentSprintName(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return project.getCurrentSprintName(jiraIssues);
    }
    return null;
  }

  void _editProject(Project project) {
    showDialog(
      context: context,
      builder: (context) => EditProjectDialog(
        project: project,
        onProjectUpdated: (updatedProject) {
          setState(() {
            // Check both lists to find where the project actually is
            bool foundInProfessional = false;
            final professionalIndex = _professionalProjects.indexWhere((p) => p.id == project.id);
            if (professionalIndex != -1) {
              _professionalProjects[professionalIndex] = updatedProject;
              foundInProfessional = true;
            } else {
              final personalIndex = _personalProjects.indexWhere((p) => p.id == project.id);
              if (personalIndex != -1) {
                _personalProjects[personalIndex] = updatedProject;
              }
            }
          });
          _saveProjects();
        },
      ),
    );
  }

  void _deleteProject(Project project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Are you sure you want to delete "${project.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Check both lists to find where the project actually is
                final professionalIndex = _professionalProjects.indexWhere((p) => p.id == project.id);
                if (professionalIndex != -1) {
                  _professionalProjects.removeAt(professionalIndex);
                } else {
                  final personalIndex = _personalProjects.indexWhere((p) => p.id == project.id);
                  if (personalIndex != -1) {
                    _personalProjects.removeAt(personalIndex);
                  }
                }
              });
              _saveProjects();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openProjectDetail(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProjectDetailPage(
          project: project,
          onProjectUpdated: (updatedProject) {
            setState(() {
              final isProfessional = project.type == ProjectType.development;
              final projectList = isProfessional ? _professionalProjects : _personalProjects;
              final index = projectList.indexWhere((p) => p.id == project.id);
              if (index != -1) {
                projectList[index] = updatedProject;
              }
            });
            _saveProjects();
          },
          onAddToSchedule: _addTaskToSchedule,
          professionalProjects: _professionalProjects,
          personalProjects: _personalProjects,
          scheduledTasks: _scheduledTasks,
          onRemoveTask: _removeTaskFromSchedule,
          onOpenTaskDetail: _openScheduledTaskDetail,
          onRegisterScheduleUpdate: _registerScheduleUpdateCallback,
          onUnregisterScheduleUpdate: _unregisterScheduleUpdateCallback,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Dashboard Title (unrestricted)
            Padding(
              padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Text(
                    'DASHBOARD',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                  IconButton(
                    onPressed: _showSettingsDialog,
                    icon: Icon(Icons.settings, color: Colors.grey[300]),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Three-column layout
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    // Left Panel - Schedule (20%)
                    Expanded(
                      flex: 20,
                      child: Hero(
                        tag: 'schedule_panel',
                        child: Material(
                          color: Colors.transparent,
                          child: _buildSchedulePanel(),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 20),
                    
                    // Center Panel - Dashboard (60%)
                    Expanded(
                      flex: 60,
                      child: _buildDashboardPanel(),
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

  Widget _buildTabContent(String title, List<Project> projects) {
    return Column(
      children: [
        // Header Section (simplified and shrunk)
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA), // Header color matching cards
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                spreadRadius: 2,
                blurRadius: 12,
                offset: const Offset(0, 100), // Shadow cast downward onto grid
              ),
            ],
          ),
        ),
        
        // Projects Grid Section
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Grid color (darker than header)
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: projects.isEmpty
                  ? _buildEmptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Responsive grid: min 200px, max 300px per card, preferred ~250px
                        final minCardWidth = 200.0;
                        final maxCardWidth = 300.0;
                        final preferredCardWidth = 250.0;
                        
                        // Calculate cross axis count based on available width
                        int crossAxisCount = (constraints.maxWidth / preferredCardWidth).floor();
                        crossAxisCount = crossAxisCount.clamp(1, 6); // Min 1, max 6 columns
                        
                        // Calculate actual card width
                        final actualCardWidth = (constraints.maxWidth - (crossAxisCount - 1) * 16.0) / crossAxisCount;
                        
                        // Clamp card width between min and max
                        final clampedCardWidth = actualCardWidth.clamp(minCardWidth, maxCardWidth);
                        
                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: 0.8,
                            crossAxisSpacing: 16.0,
                            mainAxisSpacing: 16.0,
                          ),
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            return _buildProjectCard(projects[index]);
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 15),
          Text(
            'No projects yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by creating your first project',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    return ProjectCard(
      project: project,
      projectProgress: _getProjectProgress(project),
      sprintProgress: _getSprintProgress(project),
      hasSprintData: _projectJiraIssues[project.id] != null && _getSprintIssueCount(project) > 0,
      onTap: () => _openProjectDetail(project),
      onEdit: () => _editProject(project),
      onDelete: () => _deleteProject(project),
    );
  }

  Widget _buildSchedulePanel() {
    return SharedSchedulePanel(
      onRefresh: _fetchAndScheduleAssignedIssues,
      refreshTooltip: 'Refresh Assigned Tasks',
      scheduledTasks: _scheduledTasks,
      onRemoveTask: _removeTaskFromSchedule,
      onOpenTaskDetail: _openScheduledTaskDetail,
      showFullSchedule: true,
    );
  }

  void _openScheduledTaskDetail(ScheduledTask scheduledTask) {
    // Find the project for this task
    final project = [..._professionalProjects, ..._personalProjects]
        .firstWhere((p) => p.id == scheduledTask.projectId);
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskDetailPage(
          task: scheduledTask.task,
          project: project,
          onTaskUpdated: (updatedTask) {
            // Update the task in the project
            setState(() {
              final projectIndex = _professionalProjects.indexWhere((p) => p.id == project.id);
              if (projectIndex != -1) {
                final updatedTasks = _professionalProjects[projectIndex].tasks.map((t) {
                  if (t.id == updatedTask.id) {
                    return updatedTask;
                  }
                  return t;
                }).toList();
                _professionalProjects[projectIndex] = _professionalProjects[projectIndex].copyWith(tasks: updatedTasks);
              } else {
                final personalIndex = _personalProjects.indexWhere((p) => p.id == project.id);
                if (personalIndex != -1) {
                  final updatedTasks = _personalProjects[personalIndex].tasks.map((t) {
                    if (t.id == updatedTask.id) {
                      return updatedTask;
                    }
                    return t;
                  }).toList();
                  _personalProjects[personalIndex] = _personalProjects[personalIndex].copyWith(tasks: updatedTasks);
                }
              }
              
              // Update the scheduled task
              final scheduledIndex = _scheduledTasks.indexWhere((st) => st.task.id == updatedTask.id);
              if (scheduledIndex != -1) {
                _scheduledTasks[scheduledIndex] = ScheduledTask(
                  id: _scheduledTasks[scheduledIndex].id,
                  task: updatedTask,
                  projectId: _scheduledTasks[scheduledIndex].projectId,
                  projectName: _scheduledTasks[scheduledIndex].projectName,
                  projectColor: _scheduledTasks[scheduledIndex].projectColor,
                  scheduledAt: _scheduledTasks[scheduledIndex].scheduledAt,
                  dueDate: _scheduledTasks[scheduledIndex].dueDate,
                );
              }
            });
            _saveProjects();
            _saveScheduledTasks();
          },
          onTaskDeleted: (deletedTask) {
            // Remove from project and schedule
            setState(() {
              final projectIndex = _professionalProjects.indexWhere((p) => p.id == project.id);
              if (projectIndex != -1) {
                final updatedTasks = _professionalProjects[projectIndex].tasks.where((t) => t.id != deletedTask.id).toList();
                _professionalProjects[projectIndex] = _professionalProjects[projectIndex].copyWith(tasks: updatedTasks);
              } else {
                final personalIndex = _personalProjects.indexWhere((p) => p.id == project.id);
                if (personalIndex != -1) {
                  final updatedTasks = _personalProjects[personalIndex].tasks.where((t) => t.id != deletedTask.id).toList();
                  _personalProjects[personalIndex] = _personalProjects[personalIndex].copyWith(tasks: updatedTasks);
                }
              }
              
              // Remove from schedule
              _scheduledTasks.removeWhere((st) => st.task.id == deletedTask.id);
            });
            _saveProjects();
            _saveScheduledTasks();
          },
        ),
      ),
    );
  }

  Widget _buildDashboardPanel() {
    return Column(
      children: [
        // Tab Bar with inline Add Project button
        Row(
          children: [
            // Tab Bar Container
            Container(
              width: MediaQuery.of(context).size.width * 0.25,
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    topRight: Radius.circular(5),
                  ),
                  color: const Color(0xFFFAFAFA),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: const Color(0xFF333333),
                unselectedLabelColor: Colors.grey[300],
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                tabs: const [
                  Tab(text: 'Professional'),
                  Tab(text: 'Personal'),
                ],
              ),
            ),
            // Spacer
            const Spacer(),
            // Add Project Button
            ElevatedButton.icon(
              onPressed: () => _showCreateProjectDialog(_tabController.index == 0),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Project',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        
        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTabContent('Professional', _professionalProjects),
              _buildTabContent('Personal', _personalProjects),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpdatesPanel() {
    return Hero(
      tag: 'right_panel_transform',
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1),
          ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UPDATES',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Recent activity placeholder
                    _buildUpdateItem(
                      'Task Completed',
                      'PP-123: Implement user authentication',
                      '2 hours ago',
                      Icons.check_circle,
                      Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildUpdateItem(
                      'Comment Added',
                      'PP-456: Fix navigation bug',
                      '4 hours ago',
                      Icons.comment,
                      Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _buildUpdateItem(
                      'Issue Created',
                      'PP-789: Add dark mode support',
                      '1 day ago',
                      Icons.bug_report,
                      Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildUpdateItem(
                      'Sprint Started',
                      'Sprint 24: Mobile improvements',
                      '2 days ago',
                      Icons.play_arrow,
                      Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildUpdateItem(String title, String description, String time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatefulWidget {
  final Project project;
  final double projectProgress;
  final double sprintProgress;
  final bool hasSprintData;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ProjectCard({
    super.key,
    required this.project,
    required this.projectProgress,
    required this.sprintProgress,
    required this.hasSprintData,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        transform: _isHovered
            ? (Matrix4.identity()..translate(0.0, -5.0, 0.0))
            : Matrix4.identity(),
        child: Card(
          clipBehavior: Clip.hardEdge,                     // chops stray px
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isHovered ? 12 : 4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _isHovered
                  ? const Color(0xFFc0c0c0)
                  : const Color(0xFFFAFAFA),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHovered ? 0.2 : 0.1),
                  blurRadius: _isHovered ? 20 : 8,
                  offset: Offset(0, _isHovered ? 8 : 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                // Stack lets us FLOAT the menu icon so it doesn't eat height
                child: Stack(
                  children: [
                    // ── floating menu button ────────────────────────────────
                    Positioned(
                      top: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isHovered ? 1.0 : 0.0,
                        child: PopupMenuButton(
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (String value) {
                            if (value == 'edit') {
                              widget.onEdit();
                            } else if (value == 'delete') {
                              widget.onDelete();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── main content ───────────────────────────────────────
                    Align(
                      alignment: const Alignment(0, -0.15), // shift UP only
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // progress rings
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // KEEP YOUR ORIGINAL SIZE MATH
                              final maxRadius =
                                  (constraints.maxWidth * 0.42)
                                      .clamp(36.0, 96.0);
                              final innerRadius = maxRadius * 0.88;
                              final lineWidth =
                                  (maxRadius * 0.15).clamp(6.0, 15.0);
                              final fontSize =
                                  (maxRadius * 0.25).clamp(12.0, 18.0);

                              return SizedBox(
                                width: maxRadius * 2 + lineWidth,
                                height: maxRadius * 2 + lineWidth,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // outer (project) ring
                                    CircularPercentIndicator(
                                      radius: maxRadius,
                                      lineWidth: lineWidth,
                                      percent: widget.projectProgress / 100,
                                      backgroundColor:
                                          const Color(0xFF6c6c6c),
                                      progressColor:
                                          const Color(0xFF4286de), // green
                                      center: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (widget.hasSprintData)
                                            CircularPercentIndicator(
                                              radius: innerRadius,
                                              lineWidth: lineWidth * 0.8,
                                              percent:
                                                  widget.sprintProgress / 100,
                                              backgroundColor:
                                                  const Color(0xFF6c6c6c),
                                              progressColor:
                                                  const Color(0xFF87CEEB), // blue
                                            ),
                                                                                     Text(
                                             '${(widget.hasSprintData ? widget.sprintProgress : widget.projectProgress).toInt()}%',
                                             style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                               color: const Color(0xFF333333),
                                               shadows: [
                                                 Shadow(
                                                   offset: const Offset(0, 1),
                                                   blurRadius: 2,
                                                   color: Colors.black
                                                       .withOpacity(0.3),
                                                 ),
                                               ],
                                             ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                                                     // project name
                           Text(
                             widget.project.name,
                             textAlign: TextAlign.center,
                             style: Theme.of(context).textTheme.titleMedium?.copyWith(
                               color: const Color(0xFF333333),
                             ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                        ],
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
}

class CreateProjectDialog extends StatefulWidget {
  final Function(Project) onProjectCreated;

  const CreateProjectDialog({
    super.key,
    required this.onProjectCreated,
  });

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _projectSummaryController = TextEditingController();
  final _techStackController = TextEditingController();
  final _jiraProjectUrlController = TextEditingController();
  // YouTube-specific controllers
  final _channelLinkController = TextEditingController();
  final _pipelinePathController = TextEditingController();
  final _uploadScheduleController = TextEditingController();
  String? _credentialsFileName;
  String? _credentialsContent;
  // Development-specific controllers
  final _githubRepoPathController = TextEditingController();
  String? _setupScriptFileName;
  String? _setupScriptContent;
  ProjectType _selectedType = ProjectType.development;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _projectSummaryController.dispose();
    _techStackController.dispose();
    _jiraProjectUrlController.dispose();
    _channelLinkController.dispose();
    _pipelinePathController.dispose();
    _uploadScheduleController.dispose();
    _githubRepoPathController.dispose();
    super.dispose();
  }

  void _createProject() {
    if (_nameController.text.isEmpty) return;
    
    // Validate YouTube-specific required fields
    if (_selectedType == ProjectType.youtube && _channelLinkController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Channel Link is required for YouTube projects')),
      );
      return;
    }

    Project project;
    
    if (_selectedType == ProjectType.youtube) {
      project = YouTubeProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        color: Colors.red[600]!,
        icon: Icons.video_library,
        tasks: [],
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
        createdAt: DateTime.now(),
        channelLink: _channelLinkController.text,
        pipelinePath: _pipelinePathController.text.isEmpty ? null : _pipelinePathController.text,
        uploadSchedule: _uploadScheduleController.text.isEmpty ? null : _uploadScheduleController.text,
      );
      
      // Process credentials.json if provided
      if (_credentialsContent != null) {
        try {
          (project as YouTubeProject).processCredentialsJson(_credentialsContent!);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Credentials successfully imported and stored securely')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error processing credentials: $e')),
            );
          }
          return;
        }
      }
    } else if (_selectedType == ProjectType.development) {
      project = DevelopmentProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        color: Colors.grey[600]!,
        icon: Icons.code,
        tasks: [],
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
        createdAt: DateTime.now(),
        githubRepoPath: _githubRepoPathController.text.isEmpty ? null : _githubRepoPathController.text,
        setupScriptContent: _setupScriptContent,
        setupScriptPath: _setupScriptFileName,
      );
    } else {
      project = Project(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        type: _selectedType,
        color: Colors.orange[600]!,
        icon: Icons.task,
        tasks: [],
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
        createdAt: DateTime.now(),
      );
    }

    widget.onProjectCreated(project);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Project'),
      content: SizedBox(
        width: 400,
        height: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ProjectType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Project Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: ProjectType.development,
                    child: Row(
                      children: [
                        Icon(Icons.code, color: Colors.grey, size: 20),
                        SizedBox(width: 8),
                        Text('Development'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.general,
                    child: Row(
                      children: [
                        Icon(Icons.task, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text('General'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.youtube,
                    child: Row(
                      children: [
                        Icon(Icons.video_library, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('YouTube'),
                      ],
                    ),
                  ),
                ],
                onChanged: (type) {
                  setState(() {
                    _selectedType = type!;
                  });
                },
              ),
              const SizedBox(height: 16),
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
              ],
              if (_selectedType == ProjectType.youtube) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _channelLinkController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube Channel Link *',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., https://www.youtube.com/@yourchannelname',
                    helperText: 'Required - Your YouTube channel URL',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pipelinePathController,
                  decoration: const InputDecoration(
                    labelText: 'Pipeline Path (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., /path/to/video/pipeline',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _uploadScheduleController,
                  decoration: const InputDecoration(
                    labelText: 'Upload Schedule (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Mondays and Thursdays at 3 PM',
                  ),
                ),
                const SizedBox(height: 16),
                // Credentials file upload
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google API Credentials (optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload your credentials.json file from Google Cloud Console',
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
                                  allowedExtensions: ['json'],
                                  allowMultiple: false,
                                );
                                
                                if (result != null && result.files.single.bytes != null) {
                                  final bytes = result.files.single.bytes!;
                                  final content = String.fromCharCodes(bytes);
                                  
                                  // Validate JSON structure
                                  try {
                                    final json = jsonDecode(content);
                                    if (!json.containsKey('installed') && !json.containsKey('web')) {
                                      throw Exception('Invalid credentials.json format');
                                    }
                                    
                                    setState(() {
                                      _credentialsFileName = result.files.single.name;
                                      _credentialsContent = content;
                                    });
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Invalid credentials file: $e')),
                                      );
                                    }
                                  }
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
                            label: const Text('Choose credentials.json'),
                          ),
                          const SizedBox(width: 12),
                          if (_credentialsFileName != null)
                            Expanded(
                              child: Text(
                                '✓ $_credentialsFileName',
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
              ],
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
          onPressed: _createProject,
          child: const Text('Create Project'),
        ),
      ],
    );
  }
}

// Shared Schedule Panel Widget
class SharedSchedulePanel extends StatefulWidget {
  final VoidCallback? onRefresh;
  final String? refreshTooltip;
  final bool showProjectSpecificMessage;
  final String? projectName;
  final List<ScheduledTask>? scheduledTasks;
  final Function(ScheduledTask)? onRemoveTask;
  final Function(ScheduledTask)? onOpenTaskDetail;
  final bool showFullSchedule;

  const SharedSchedulePanel({
    Key? key,
    this.onRefresh,
    this.refreshTooltip,
    this.showProjectSpecificMessage = false,
    this.projectName,
    this.scheduledTasks,
    this.onRemoveTask,
    this.onOpenTaskDetail,
    this.showFullSchedule = false,
  }) : super(key: key);

  @override
  State<SharedSchedulePanel> createState() => _SharedSchedulePanelState();
}

class _SharedSchedulePanelState extends State<SharedSchedulePanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'SCHEDULE',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                if (widget.onRefresh != null)
                  StatefulBuilder(
                    builder: (context, setState) {
                      bool isHovered = false;
                      
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => isHovered = true),
                        onExit: (_) => setState(() => isHovered = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isHovered ? Colors.blue[300]!.withOpacity(0.1) : Colors.transparent,
                          ),
                          child: IconButton(
                            onPressed: widget.onRefresh,
                            icon: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              transform: isHovered 
                                ? (Matrix4.identity()..rotateZ(0.5))
                                : Matrix4.identity(),
                              child: Icon(
                                Icons.refresh, 
                                color: isHovered ? Colors.blue[400] : Colors.blue[300],
                              ),
                            ),
                            tooltip: widget.refreshTooltip ?? 'Refresh Assigned Tasks',
                            iconSize: 20,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Today's date
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[600]!.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[600]!.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[300],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateTime.now().toString().split(' ')[0],
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Show scheduled tasks if available and showFullSchedule is true
                    if (widget.showFullSchedule && widget.scheduledTasks != null)
                      if (widget.scheduledTasks!.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 32,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No scheduled tasks',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add tasks from projects',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...(widget.scheduledTasks!.map((scheduledTask) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildScheduledTaskCard(scheduledTask),
                        )))
                    else if (widget.showFullSchedule && widget.scheduledTasks == null)
                      // Show loading or empty state when scheduledTasks is null
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 32,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Loading schedule...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // Show project-specific message for project detail page
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 32,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.showProjectSpecificMessage 
                                ? 'Schedule shared across pages'
                                : 'No scheduled tasks',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.showProjectSpecificMessage 
                                ? 'Use refresh to add ${widget.projectName} tasks'
                                : 'Add tasks from projects',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildScheduledTaskCard(ScheduledTask scheduledTask) {
    // Check if this is a subtask
    final isSubtask = scheduledTask.task.isSubtask;
    
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        
        Widget cardWidget = MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: GestureDetector(
            onTap: () => widget.onOpenTaskDetail?.call(scheduledTask),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isHovered ? const Color(0xFFFFFFFF) : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: isHovered 
                  ? Border.all(color: scheduledTask.projectColor.withOpacity(0.5), width: 1)
                  : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isHovered ? 0.15 : 0.1),
                    blurRadius: isHovered ? 8 : 4,
                    offset: Offset(0, isHovered ? 4 : 2),
                  ),
                ],
              ),
              transform: isHovered 
                ? (Matrix4.identity()..scale(1.02))
                : Matrix4.identity(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Task title and remove button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          scheduledTask.task.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isHovered ? const Color(0xFF222222) : const Color(0xFF333333),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => widget.onRemoveTask?.call(scheduledTask),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isHovered ? Colors.red.withOpacity(0.1) : Colors.transparent,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: isHovered ? Colors.red[700] : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Project name
                  Text(
                    scheduledTask.projectName,
                    style: TextStyle(
                      fontSize: 10,
                      color: isHovered 
                        ? scheduledTask.projectColor
                        : scheduledTask.projectColor.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  
                  // Priority badge
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isHovered 
                        ? _getPriorityColor(scheduledTask.task.priorityEnum)
                        : _getPriorityColor(scheduledTask.task.priorityEnum).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isHovered ? [
                        BoxShadow(
                          color: _getPriorityColor(scheduledTask.task.priorityEnum).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Text(
                      _getPriorityText(scheduledTask.task.priorityEnum),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        
        // If it's a subtask, make it narrower and right-aligned
        if (isSubtask) {
          return Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.95,
              child: cardWidget,
            ),
          );
        }
        
        // Regular tasks use full width
        return cardWidget;
      },
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

class ProjectDetailPage extends StatefulWidget {
  final Project project;
  final Function(Project) onProjectUpdated;
  final Function(Task, Project)? onAddToSchedule;
  final List<Project> professionalProjects;
  final List<Project> personalProjects;
  final List<ScheduledTask>? scheduledTasks;
  final Function(ScheduledTask)? onRemoveTask;
  final Function(ScheduledTask)? onOpenTaskDetail;
  final Function(ProjectDetailPage)? onScheduleUpdated;
  final Function(Function())? onRegisterScheduleUpdate;
  final Function(Function())? onUnregisterScheduleUpdate;

  const ProjectDetailPage({
    super.key,
    required this.project,
    required this.onProjectUpdated,
    this.onAddToSchedule,
    required this.professionalProjects,
    required this.personalProjects,
    this.scheduledTasks,
    this.onRemoveTask,
    this.onOpenTaskDetail,
    this.onScheduleUpdated,
    this.onRegisterScheduleUpdate,
    this.onUnregisterScheduleUpdate,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late Project _project;
  List<Task> _jiraIssues = [];
  bool _isLoadingJiraIssues = false;
  String? _jiraError;
  List<ScheduledTask>? _currentScheduledTasks;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _currentScheduledTasks = widget.scheduledTasks;
    _fetchJiraIssues();
    
    // Register for schedule updates
    widget.onRegisterScheduleUpdate?.call(_onScheduleUpdate);
  }

  @override
  void dispose() {
    // Unregister from schedule updates
    widget.onUnregisterScheduleUpdate?.call(_onScheduleUpdate);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update local state if the scheduledTasks prop changes
    if (oldWidget.scheduledTasks != widget.scheduledTasks) {
      _currentScheduledTasks = widget.scheduledTasks;
    }
  }

  void _onScheduleUpdate() {
    // Force rebuild when schedule updates
    if (mounted) {
      setState(() {
        _currentScheduledTasks = widget.scheduledTasks;
      });
    }
  }



  void _addTask(Task task) {
    setState(() {
      _project = _project.copyWith(
        tasks: [..._project.tasks, task],
      );
    });
    widget.onProjectUpdated(_project);
  }

  void _openJiraIssueDetail(Task issue) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskDetailPage(
          task: issue,
          project: _project,
          projectName: _project.name,
          jiraBaseUrl: _project.jiraBaseUrl!,
          projectKey: _project.extractedJiraProjectKey!,
          onAddToSchedule: widget.onAddToSchedule,
        ),
      ),
    );
  }

  Future<void> _fetchJiraIssues() async {
    if (_project.jiraProjectUrl == null || _project.jiraProjectUrl!.isEmpty) {
      return;
    }

    final baseUrl = _project.jiraBaseUrl;
    final projectKey = _project.extractedJiraProjectKey;

    if (baseUrl == null || projectKey == null) {
      setState(() {
        _jiraError = 'Invalid Jira Project URL. Please check the URL format.';
        _isLoadingJiraIssues = false;
      });
      return;
    }

    setState(() {
      _isLoadingJiraIssues = true;
      _jiraError = null;
    });

    try {
      final jiraService = JiraService.instance;
      final issues = await jiraService.fetchProjectIssues(
        baseUrl,
        projectKey,
      );
      setState(() {
        _jiraIssues = issues;
        _isLoadingJiraIssues = false;
      });
    } catch (e) {
      setState(() {
        _jiraError = e.toString();
        _isLoadingJiraIssues = false;
      });
    }
  }

  void _toggleTaskCompletion(Task task) {
    setState(() {
      final updatedTasks = _project.tasks.map((t) {
        if (t.id == task.id) {
          return t.copyWith(isCompleted: !t.isCompleted);
        }
        return t;
      }).toList();
      
      _project = _project.copyWith(tasks: updatedTasks);
    });
    widget.onProjectUpdated(_project);
  }

  void _showAddTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => AddTaskDialog(
        projectId: _project.id,
        onTaskCreated: _addTask,
      ),
    );
  }

  void _showAddJiraTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => AddTaskDialog(
        projectId: _project.id,
        onTaskCreated: (task) async {
          // TODO: Create task in Jira
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating Jira task... (Feature coming soon!)')),
          );
          // For now, refresh Jira issues to see if the task appears
          await _fetchJiraIssues();
        },
      ),
    );
  }

  void _openLocalTaskDetail(Task task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskDetailPage(
          task: task,
          project: _project,
          onTaskUpdated: (updatedTask) {
            setState(() {
              final updatedTasks = _project.tasks.map((t) {
                if (t.id == task.id) {
                  return updatedTask;
                }
                return t;
              }).toList();
              
              _project = _project.copyWith(tasks: updatedTasks);
            });
            widget.onProjectUpdated(_project);
          },
          onTaskDeleted: (deletedTask) {
            setState(() {
              final updatedTasks = _project.tasks.where((t) => t.id != deletedTask.id).toList();
              _project = _project.copyWith(tasks: updatedTasks);
            });
            widget.onProjectUpdated(_project);
          },
          onAddToSchedule: widget.onAddToSchedule,
        ),
      ),
    );
  }

  int _getPriorityValue(String? priority) {
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

  List<Task> _getSortedJiraIssues() {
    final sortedIssues = List<Task>.from(_jiraIssues);
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
      
      // For non-done tasks, prioritize sprint tasks
      if (!aIsDone && !bIsDone) {
        // Sprint tasks come first
        if (a.isInActiveSprint && !b.isInActiveSprint) return -1;
        if (!a.isInActiveSprint && b.isInActiveSprint) return 1;
        
        // Within same group (both sprint or both non-sprint), sort by priority
        final aPriority = _getPriorityValue(a.priority);
        final bPriority = _getPriorityValue(b.priority);
        return bPriority.compareTo(aPriority); // Highest to lowest
      }
      
      // For done tasks, also sort by priority but they're already at bottom
      final aPriority = _getPriorityValue(a.priority);
      final bPriority = _getPriorityValue(b.priority);
      return bPriority.compareTo(aPriority); // Highest to lowest
    });
    return sortedIssues;
  }

  Widget _buildProjectInfoPanel() {
    return Hero(
      tag: 'right_panel_transform',
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1),
          ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROJECT INFO',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Project Description
                    _buildInfoSection(
                      'Description',
                      Icons.description,
                      _project.description,
                    ),
                    
                    // Tech Stack (for development projects)
                    if (_project.techStack != null && _project.techStack!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildInfoSection(
                        'Tech Stack',
                        Icons.build_circle,
                        _project.techStack!,
                      ),
                    ],
                    
                    // Development Setup (for development projects)
                    if (_project is DevelopmentProject) ...[
                      const SizedBox(height: 20),
                      _buildDevelopmentSetupSection(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, IconData icon, String content) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800]!.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[600]!.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.grey[300],
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[200],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevelopmentSetupSection() {
    final devProject = _project as DevelopmentProject;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _project.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _project.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.developer_mode,
                size: 16,
                color: _project.color,
              ),
              const SizedBox(width: 8),
              Text(
                'Development Setup',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _project.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // GitHub Repo Path
          if (devProject.githubRepoPath != null) ...[
            _buildDevInfoItem(
              'Repository Path',
              Icons.folder,
              devProject.githubRepoPath!,
              isMonospace: true,
            ),
            const SizedBox(height: 12),
          ],
          
          // Setup Script
          if (devProject.setupScriptContent != null) ...[
            _buildDevInfoItem(
              'Setup Script',
              Icons.play_circle_outline,
              devProject.setupScriptContent!,
              isMonospace: true,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await devProject.runSetupScript();
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
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run Script', style: TextStyle(fontSize: 12)),
              ),
            ),
          ] else if (devProject.githubRepoPath == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue[600],
                    size: 20,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No setup configured',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[800],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edit project to configure',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDevInfoItem(
    String label,
    IconData icon,
    String content, {
    bool isMonospace = false,
    int? maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: Colors.grey[300],
            ),
            const SizedBox(width: 6),
            Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey[300],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMonospace ? Colors.grey[900] : Colors.grey[100],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontFamily: isMonospace ? 'monospace' : null,
              fontSize: 10,
              color: isMonospace ? Colors.white : Colors.black87,
              height: 1.3,
            ),
            maxLines: maxLines,
            overflow: maxLines != null ? TextOverflow.ellipsis : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sort Jira issues: Done tasks at bottom, others by priority (highest to lowest)
    final sortedJiraIssues = _getSortedJiraIssues();

    // Calculate progress using Jira issues if available
    final progressPercentage = _project.getProgressPercentage(sortedJiraIssues);
    final hasJiraConnection = _project.extractedJiraProjectKey != null && _jiraError == null;
    final hasJiraIssues = sortedJiraIssues.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Title area to match dashboard layout
            Padding(
              padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0, bottom: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: Colors.grey[300]),
                  ),
                  // Project name in dashboard title style
                  Text(
                    _project.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                  // Add task button
                  IconButton(
                    onPressed: hasJiraConnection ? _showAddJiraTaskDialog : _showAddTaskDialog,
                    icon: Icon(Icons.add, color: Colors.grey[300]),
                    tooltip: hasJiraConnection ? 'Add Jira Task' : 'Add Local Task',
                  ),
                ],
              ),
            ),
            
            // Three-column layout to match dashboard exactly
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    // Left Panel - Schedule (20%) - Same as dashboard
                    Expanded(
                      flex: 20,
                      child: Hero(
                        tag: 'schedule_panel',
                        child: Material(
                          color: Colors.transparent,
                          child: _buildSchedulePanelForProject(),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 20),
                    
                    // Center Panel - Project Content (60%) to match dashboard center panel
                    Expanded(
                      flex: 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Project Info Card
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => Navigator.of(context).pop(),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.arrow_back,
                                            color: Colors.grey[600],
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _project.name,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (_project.extractedJiraProjectKey != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Jira Project: ${_project.extractedJiraProjectKey}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.blue[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            hasJiraConnection 
                                              ? '${sortedJiraIssues.where((issue) => !issue.isSubtask && issue.isCompleted).length}/${sortedJiraIssues.where((issue) => !issue.isSubtask).length}'
                                              : '${_project.completedTasks}/${_project.tasks.length}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'completed',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if ((hasJiraConnection ? sortedJiraIssues.isNotEmpty : _project.tasks.isNotEmpty)) ...[
                                    const SizedBox(height: 16),
                                    LinearProgressIndicator(
                                      value: progressPercentage / 100,
                                      backgroundColor: Colors.grey[200],
                                      valueColor: AlwaysStoppedAnimation<Color>(_project.color),
                                      minHeight: 8,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${progressPercentage.toInt()}% Complete',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _project.color,
                                      ),
                                    ),
                                    
                                    // Sprint Progress Bar
                                    if (hasJiraConnection && _project.getSprintIssueCount(sortedJiraIssues) > 0) ...[
                                      const SizedBox(height: 12),
                                      LinearProgressIndicator(
                                        value: _project.getSprintProgressPercentage(sortedJiraIssues) / 100,
                                        backgroundColor: Colors.grey[200],
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFCCF7FF)),
                                        minHeight: 6,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${_project.getSprintProgressPercentage(sortedJiraIssues).toInt()}% Sprint Complete',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF0066CC),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Content List
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Jira Issues Section (if connected)
                                  if (_project.extractedJiraProjectKey != null) ...[
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.link,
                                              size: 20,
                                              color: _project.color,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Jira Issues',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_isLoadingJiraIssues)
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else
                                          IconButton(
                                            onPressed: _fetchJiraIssues,
                                            icon: Icon(Icons.refresh, color: _project.color),
                                            tooltip: 'Refresh Jira Issues',
                                          ),
                                      ],
                                    ),
                                    
                                    const SizedBox(height: 8),
                                    
                                    if (_jiraError != null)
                                      Card(
                                        color: Colors.red[50],
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.error, color: Colors.red[600]),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Failed to load Jira issues',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.red[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _jiraError!,
                                                style: TextStyle(color: Colors.red[600]),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (_isLoadingJiraIssues)
                                      const Card(
                                        child: Padding(
                                          padding: EdgeInsets.all(32),
                                          child: Center(
                                            child: Column(
                                              children: [
                                                CircularProgressIndicator(),
                                                SizedBox(height: 16),
                                                Text('Loading Jira issues...'),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    else if (sortedJiraIssues.isEmpty)
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(32),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.link_off,
                                                size: 48,
                                                color: Colors.grey[400],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No Jira issues found',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Project: ${_project.extractedJiraProjectKey}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      ...sortedJiraIssues.map((issue) => _buildJiraIssueCard(issue)),
                                  ],
                                  
                                  // Local Tasks Section (only if no Jira connection)
                                  if (!hasJiraConnection) ...[
                                    if (_project.extractedJiraProjectKey != null) 
                                      const SizedBox(height: 24),
                                      
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.task_alt,
                                              size: 20,
                                              color: _project.color,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Local Tasks',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _showAddTaskDialog,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _project.color,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text('Add Task'),
                                        ),
                                      ],
                                    ),
                                    
                                    const SizedBox(height: 8),
                                    
                                    // Local Tasks List
                                    if (_project.tasks.isEmpty)
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(32),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.assignment,
                                                size: 48,
                                                color: Colors.grey[400],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No local tasks yet',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Add tasks for notes and reminders',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              ElevatedButton.icon(
                                                onPressed: _showAddTaskDialog,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: _project.color,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 24,
                                                    vertical: 12,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                icon: const Icon(Icons.add),
                                                label: const Text(
                                                  'Add Your First Task',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      ..._project.tasks.where((task) => !task.isSubtask).map((task) => _buildLocalTaskCard(task)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(width: 20),
                    
                    // Right Panel - Project Info (20%) - Exact position as Updates column
                    Expanded(
                      flex: 20,
                      child: _buildProjectInfoPanel(),
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

  Widget _buildJiraIssueCard(Task issue) {
    final isDone = issue.isCompleted;
    
    // Determine card background color
    Color? cardColor;
    if (isDone) {
      cardColor = Colors.grey[100];  // Grey for done tasks
    } else if (issue.isInActiveSprint) {
      cardColor = const Color(0xFFCCF7FF);  // Light blue for sprint tasks
    } else {
      cardColor = null;  // Default for non-sprint, non-done tasks
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      child: ListTile(
        onTap: () => _openJiraIssueDetail(issue),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDone 
              ? Colors.grey[300] 
              : issue.isInActiveSprint 
                ? const Color(0xFF0066CC).withOpacity(0.2)
                : Colors.blue[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            issue.isInActiveSprint && !isDone ? Icons.timer : Icons.link,
            color: isDone 
              ? Colors.grey[600] 
              : issue.isInActiveSprint 
                ? const Color(0xFF0066CC)
                : Colors.blue[700],
            size: 16,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                issue.title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDone ? Colors.grey[600] : null,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (issue.isInActiveSprint && !isDone) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066CC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'SPRINT',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (issue.description != null && issue.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                issue.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDone ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    issue.key,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDone 
                      ? Colors.green  // Keep Done status green
                      : _getStatusColor(issue.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    issue.status,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDone 
                        ? Colors.white  // White text on green background for Done
                        : _getStatusColor(issue.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (issue.priority != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getJiraPriorityColor(issue.priority!).withOpacity(isDone ? 0.3 : 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      issue.priority!,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDone 
                          ? _getJiraPriorityColor(issue.priority!).withOpacity(0.7)
                          : _getJiraPriorityColor(issue.priority!),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (issue.assignee != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.person,
                    size: 12,
                    color: isDone ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 2),
                  Text(
                    issue.assignee!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDone ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: StatefulBuilder(
          builder: (context, setState) {
            bool isHovered = false;
            
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: isHovered
                    ? (Matrix4.identity()..translate(0.0, -2.5, 0.0))
                    : Matrix4.identity(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isHovered ? const Color(0xFFc0c0c0) : const Color(0xFFFAFAFA),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isHovered ? 0.2 : 0.1),
                      blurRadius: isHovered ? 20 : 8,
                      offset: Offset(0, isHovered ? 8 : 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () => widget.onAddToSchedule?.call(_convertJiraIssueToTask(issue), _project),
                  icon: Icon(
                    Icons.schedule, 
                    size: 20,
                    color: isHovered ? Colors.green[700] : Colors.green[600],
                  ),
                  tooltip: 'Add to Schedule',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLocalTaskCard(Task task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openLocalTaskDetail(task),
        leading: IconButton(
          onPressed: () => _toggleTaskCompletion(task),
          icon: Icon(
            task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.isCompleted ? Colors.green : Colors.grey[400],
          ),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                              if (task.description?.isNotEmpty == true) ...[
                              Text(task.description ?? ''),
              const SizedBox(height: 4),
            ],
            Row(
              children: [
                if (task.jiraTicketId != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      task.jiraTicketId!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(task.priorityEnum).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getPriorityText(task.priorityEnum),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getPriorityColor(task.priorityEnum),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: StatefulBuilder(
          builder: (context, setState) {
            bool isHovered = false;
            
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: isHovered
                    ? (Matrix4.identity()..translate(0.0, -2.5, 0.0))
                    : Matrix4.identity(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isHovered ? const Color(0xFFc0c0c0) : const Color(0xFFFAFAFA),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isHovered ? 0.2 : 0.1),
                      blurRadius: isHovered ? 20 : 8,
                      offset: Offset(0, isHovered ? 8 : 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () => widget.onAddToSchedule?.call(task, _project),
                  icon: Icon(
                    Icons.schedule, 
                    size: 20,
                    color: isHovered ? Colors.green[700] : Colors.green[600],
                  ),
                  tooltip: 'Add to Schedule',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'closed':
      case 'resolved':
        return Colors.green;
      case 'in progress':
      case 'in development':
        return Colors.blue;
      case 'to do':
      case 'open':
      case 'new':
        return Colors.grey;
      case 'blocked':
      case 'on hold':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color _getJiraPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'lowest':
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'highest':
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Task _convertJiraIssueToTask(Task issue) {
    return issue.copyWith(projectId: _project.id);
  }

  // Reuse the dashboard's schedule panel with project-specific refresh
  Widget _buildSchedulePanelForProject() {
    return SharedSchedulePanel(
      onRefresh: () async {
        // Refresh assigned issues for this specific project
        if (_project.extractedJiraProjectKey != null) {
          try {
            final jiraService = JiraService.instance;
            final assignedIssues = await jiraService.fetchMyAssignedIssues(
              _project.jiraBaseUrl!,
              _project.extractedJiraProjectKey!,
            );
            
            int addedCount = 0;
            for (final issue in assignedIssues) {
              final task = _convertJiraIssueToTask(issue);
              widget.onAddToSchedule?.call(task, _project);
              addedCount++;
            }
            
            if (addedCount > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added $addedCount assigned tasks to schedule'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error fetching assigned issues: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      refreshTooltip: 'Refresh Assigned Tasks for ${_project.name}',
      scheduledTasks: _currentScheduledTasks,
      onRemoveTask: widget.onRemoveTask,
      onOpenTaskDetail: widget.onOpenTaskDetail,
      showFullSchedule: true,
    );
  }

  
}

class AddTaskDialog extends StatefulWidget {
  final String projectId;
  final Function(Task) onTaskCreated;

  const AddTaskDialog({
    super.key,
    required this.projectId,
    required this.onTaskCreated,
  });

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();

}class _AddTaskDialogState extends State<AddTaskDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _jiraTicketController = TextEditingController();
  Priority _selectedPriority = Priority.medium;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _jiraTicketController.dispose();
    super.dispose();
  }

  void _createTask() {
    if (_titleController.text.isEmpty) return;

    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      key: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text,
      description: _descriptionController.text,
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

  const SettingsDialog({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _chatGptController;
  late TextEditingController _jiraTokenController;
  late TextEditingController _jiraUrlController;

  @override
  void initState() {
    super.initState();
    _chatGptController = TextEditingController(text: widget.settings.chatGptToken ?? '');
    _jiraTokenController = TextEditingController(text: widget.settings.jiraToken ?? '');
    _jiraUrlController = TextEditingController(text: widget.settings.jiraBaseUrl ?? '');
  }

  @override
  void dispose() {
    _chatGptController.dispose();
    _jiraTokenController.dispose();
    _jiraUrlController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final newSettings = AppSettings(
      chatGptToken: _chatGptController.text.isEmpty ? null : _chatGptController.text,
      jiraToken: _jiraTokenController.text.isEmpty ? null : _jiraTokenController.text,
      jiraBaseUrl: _jiraUrlController.text.isEmpty ? null : _jiraUrlController.text,
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
              controller: _jiraUrlController,
              decoration: const InputDecoration(
                labelText: 'Jira Base URL',
                border: OutlineInputBorder(),
                hintText: 'https://your-domain.atlassian.net',
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _descriptionController = TextEditingController(text: widget.project.description);
    _projectSummaryController = TextEditingController(text: widget.project.projectSummary ?? '');
    _techStackController = TextEditingController(text: widget.project.techStack ?? '');
    _jiraProjectUrlController = TextEditingController(text: widget.project.jiraProjectUrl ?? '');
    _selectedType = widget.project.type;
    
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
      );
    } else {
      updatedProject = widget.project.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        projectSummary: _projectSummaryController.text.isEmpty ? null : _projectSummaryController.text,
        techStack: _techStackController.text.isEmpty ? null : _techStackController.text,
        type: _selectedType,
        jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
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

// Removed broken EditTaskDialog - using the working one below

class TaskDetailPage extends StatefulWidget {
  final Task task;
  final Project project;
  final String? projectName;
  final String? jiraBaseUrl;
  final String? projectKey;
  final Function(Task, Project)? onAddToSchedule;
  final Function(Task)? onTaskUpdated;
  final Function(Task)? onTaskDeleted;

  const TaskDetailPage({
    super.key,
    required this.task,
    required this.project,
    this.projectName,
    this.jiraBaseUrl,
    this.projectKey,
    this.onAddToSchedule,
    this.onTaskUpdated,
    this.onTaskDeleted,
  });

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late Task _task;
  bool _isLoading = false;
  bool _isExpandingTask = false;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  // Check if this is a Jira task
  bool get isJiraTask => widget.jiraBaseUrl != null && widget.projectKey != null && _task.jiraTicketId != null;

  void _toggleCompletion() {
    setState(() {
      _task = _task.copyWith(isCompleted: !_task.isCompleted);
    });
    widget.onTaskUpdated?.call(_task);
  }

  Future<void> _expandTaskWithAI() async {
    if (widget.project.projectSummary == null || widget.project.projectSummary!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project summary is required for AI Expand. Please add a project summary in project settings.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isExpandingTask = true;
    });

    try {
      final aiService = AIExpandService();
      final taskDescription = _task.description?.isNotEmpty == true ? _task.description! : _task.title;
      
      final subtaskItems = await aiService.expandTask(
        taskDescription: taskDescription,
        projectSummary: widget.project.projectSummary!,
        isDevelopmentProject: widget.project.type == ProjectType.development,
        techStack: widget.project.techStack,
      );

      if (mounted) {
        if (isJiraTask) {
          // Create actual Jira subtasks
          final jiraService = JiraService.instance;
          List<Task> createdSubtasks = [];
          
          for (final item in subtaskItems) {
            try {
              final subtask = await jiraService.createSubtask(
                baseUrl: widget.jiraBaseUrl!,
                projectKey: widget.projectKey!,
                parentIssueKey: _task.key,
                summary: '${item.title}: ${item.prompt}', // Combine title and description
                priority: 'Medium',
              );
              createdSubtasks.add(subtask);
              print('Created subtask: ${subtask.key} - ${subtask.title}');
            } catch (e) {
              print('Failed to create subtask "${item.title}": $e');
            }
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully created ${createdSubtasks.length} of ${subtaskItems.length} AI-generated subtasks!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh the issue to show the new subtasks
          await _refreshIssue();
        } else {
          // Create local subtasks
          final List<Task> newSubtasks = [];
          
          for (final item in subtaskItems) {
            final subtask = Task(
              id: DateTime.now().millisecondsSinceEpoch.toString() + '_${item.id}',
              key: DateTime.now().millisecondsSinceEpoch.toString() + '_${item.id}',
              title: item.title,
              description: item.prompt,
              projectId: widget.project.id,
              createdAt: DateTime.now(),
              status: 'To Do',
              priorityEnum: Priority.medium,
              parentKey: _task.key,
              isSubtask: true,
            );
            newSubtasks.add(subtask);
            print('Created local subtask: ${subtask.title}');
          }
          
          // Update the current task with the new subtasks
          setState(() {
            _task = _task.copyWith(subtasks: [..._task.subtasks, ...newSubtasks]);
          });
          widget.onTaskUpdated?.call(_task);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully created ${newSubtasks.length} AI-generated subtasks!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
          
          // Show subtasks dialog for local tasks
          _showSubtasksDialog(newSubtasks);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error expanding task: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExpandingTask = false;
        });
      }
    }
  }

  Future<void> _refreshIssue() async {
    try {
      final jiraService = JiraService.instance;
      final issues = await jiraService.fetchProjectIssues(
                            widget.jiraBaseUrl!,
                    widget.projectKey!,
      );
      
      final updatedIssue = issues.firstWhere(
        (issue) => issue.key == _task.key,
        orElse: () => _task,
      );
      
      if (mounted) {
        setState(() {
          _task = updatedIssue;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh issue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editTask() {
    showDialog(
      context: context,
      builder: (context) => EditTaskDialog(
        task: _task,
        onTaskUpdated: (updatedTask) {
          setState(() {
            _task = updatedTask;
          });
          widget.onTaskUpdated?.call(_task);
        },
      ),
    );
  }

  void _deleteTask() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isJiraTask ? 'Delete Jira Issue' : 'Delete Task'),
        content: Text('Are you sure you want to delete "${_task.title}"? This action cannot be undone${isJiraTask ? ' and will delete the issue from Jira' : ''}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // Close dialog
              
              if (isJiraTask) {
                try {
                  setState(() {
                    _isLoading = true;
                  });
                  
                  final jiraService = JiraService.instance;
                  await jiraService.deleteIssue(
                    baseUrl: widget.jiraBaseUrl!,
                    issueKey: _task.key,
                  );
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Successfully deleted issue ${_task.key}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.of(context).pop(); // Go back to project view
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete issue: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              } else {
                // Local task deletion
                Navigator.of(context).pop(); // Go back to project view
                widget.onTaskDeleted?.call(_task);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSubtasksDialog(List<Task> subtasks) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple),
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
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to project view
            },
            child: const Text('View in Project'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSubtaskDialog() async {
    final summaryController = TextEditingController();
    final descriptionController = TextEditingController();
    Priority selectedPriority = Priority.medium;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.subdirectory_arrow_right, color: Colors.green[600]),
              const SizedBox(width: 8),
              const Text('Add Subtask'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[600], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Creating subtask for ${_task.key}',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: summaryController,
                  decoration: const InputDecoration(
                    labelText: 'Subtask Summary',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Priority>(
                  value: selectedPriority,
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
                              color: _getPriorityColorFromEnum(priority),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_getPriorityTextFromEnum(priority)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (priority) {
                    if (priority != null) {
                      setDialogState(() {
                        selectedPriority = priority;
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
            ElevatedButton.icon(
              onPressed: () {
                if (summaryController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop({
                    'summary': summaryController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'priority': selectedPriority,
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Subtask'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _createSubtask(
        result['summary'],
        result['description'],
        result['priority'],
      );
    }
  }

  Future<void> _createSubtask(String summary, String description, Priority priority) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final jiraService = JiraService.instance;
      
      // Map Priority enum to Jira priority strings
      String jiraPriority;
      switch (priority) {
        case Priority.low:
          jiraPriority = 'Low';
          break;
        case Priority.medium:
          jiraPriority = 'Medium';
          break;
        case Priority.high:
          jiraPriority = 'High';
          break;
        case Priority.critical:
          jiraPriority = 'Highest';
          break;
      }

      await jiraService.createSubtask(
        baseUrl: widget.jiraBaseUrl!,
        projectKey: widget.projectKey!,
        parentIssueKey: _task.key,
        summary: description.isNotEmpty ? '$summary: $description' : summary, // Combine summary and description
        priority: jiraPriority,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully created subtask: $summary'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the issue to show the new subtask
      await _refreshIssue();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create subtask: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSubtaskCard(Task subtask) {
    final isDone = subtask.status.toLowerCase() == 'done' || 
                   subtask.status.toLowerCase() == 'closed' ||
                   subtask.status.toLowerCase() == 'resolved';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDone ? Colors.grey[100] : null,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDone ? Colors.grey[300] : Colors.green[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.subdirectory_arrow_right,
            color: isDone ? Colors.grey[600] : Colors.green[700],
            size: 14,
          ),
        ),
        title: Text(
          subtask.summary,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDone ? Colors.grey[600] : null,
            decoration: isDone ? TextDecoration.lineThrough : null,
            fontSize: 14,
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getJiraPriorityColor(subtask.priority ?? 'Medium').withOpacity(isDone ? 0.3 : 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                subtask.priority ?? 'Medium',
                style: TextStyle(
                  fontSize: 9,
                  color: isDone 
                    ? _getJiraPriorityColor(subtask.priority ?? 'Medium').withOpacity(0.7)
                    : _getJiraPriorityColor(subtask.priority ?? 'Medium'),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDone 
                  ? Colors.green
                  : Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isDone ? 'COMPLETED' : 'PENDING',
                style: TextStyle(
                  fontSize: 9,
                  color: isDone 
                    ? Colors.white
                    : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: isDone ? Colors.grey[400] : Colors.grey[600],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TaskDetailPage(
                task: subtask,
                project: widget.project,
                onTaskUpdated: (updatedSubtask) {
                  setState(() {
                    final updatedSubtasks = _task.subtasks.map((s) {
                      if (s.id == subtask.id) {
                        return updatedSubtask;
                      }
                      return s;
                    }).toList();
                    _task = _task.copyWith(subtasks: updatedSubtasks);
                  });
                  widget.onTaskUpdated?.call(_task);
                },
                onTaskDeleted: (deletedSubtask) {
                  setState(() {
                    final updatedSubtasks = _task.subtasks.where((s) => s.id != deletedSubtask.id).toList();
                    _task = _task.copyWith(subtasks: updatedSubtasks);
                  });
                  widget.onTaskUpdated?.call(_task);
                },
                onAddToSchedule: widget.onAddToSchedule,
              ),
            ),
          );
        },
      ),
    );
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

  Color _getJiraPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'lowest':
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'highest':
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
          return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: Text(isJiraTask ? _task.key : 'Task'),
          backgroundColor: widget.project.color,
          foregroundColor: Colors.white,
                    actions: [
            if (!isJiraTask)
              IconButton(
                onPressed: _toggleCompletion,
                icon: Icon(
                  _task.isCompleted ? Icons.radio_button_unchecked : Icons.check_circle,
                ),
                tooltip: _task.isCompleted ? 'Mark as incomplete' : 'Mark as complete',
              ),
            if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Issue Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _task.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_task.priority != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getPriorityColorFromString(_task.priority).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getPriorityTextFromString(_task.priority),
                            style: TextStyle(
                              color: _getPriorityColorFromString(_task.priority),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _task.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(_task.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _task.status,
                          style: TextStyle(
                            color: _getStatusColor(_task.status),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_task.assignee != null) ...[
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              _task.assignee!,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Issue Description
            if (_task.description != null && _task.description!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _task.description!,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
            ],
            
            // Action Buttons (placeholders for future features)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _editTask,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit Issue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Implement assign to me
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Assign feature coming soon!')),
                            );
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Assign to Me'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Implement add comment
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Comment feature coming soon!')),
                            );
                          },
                          icon: const Icon(Icons.comment),
                          label: const Text('Add Comment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _deleteTask,
                          icon: const Icon(Icons.delete),
                          label: const Text('Delete Issue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => widget.onAddToSchedule?.call(_convertJiraIssueToTask(_task), widget.project),
                      icon: const Icon(Icons.schedule),
                      label: const Text('Add to Schedule'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.project.projectSummary != null && widget.project.projectSummary!.isNotEmpty && !_isExpandingTask
                        ? _expandTaskWithAI
                        : null,
                      icon: _isExpandingTask
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                      label: Text(_isExpandingTask ? 'Expanding...' : 'AI Expand'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        disabledForegroundColor: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Subtasks Section
            if (_task.subtasks.isNotEmpty || !_task.isSubtask) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtasks (${_task.subtasks.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_task.isSubtask)
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _showAddSubtaskDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Subtask'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                      ],
                    ),
                    if (_task.subtasks.isEmpty && !_task.isSubtask) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.subdirectory_arrow_right,
                              size: 32,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No subtasks yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_task.subtasks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                                              ..._task.subtasks.map((subtask) => _buildSubtaskCard(subtask)),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
            ],
            
            // Issue Metadata
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_task.createdAt != null)
                    _buildDetailRow('Created', _formatDate(_task.createdAt!)),
                  if (_task.updated != null)
                    _buildDetailRow('Updated', _formatDate(_task.updated!)),
                                      _buildDetailRow('Project', widget.projectName ?? widget.project.name),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
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
      case 'todo':
      case 'open':
      case 'backlog':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
      case 'highest':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow[700]!;
      case 'low':
      case 'lowest':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Task _convertJiraIssueToTask(Task issue) {
    // Convert Jira priority to our Priority enum
    Priority priority;
    switch (issue.priority?.toLowerCase()) {
      case 'highest':
      case 'critical':
        priority = Priority.critical;
        break;
      case 'high':
        priority = Priority.high;
        break;
      case 'medium':
        priority = Priority.medium;
        break;
      case 'lowest':
      case 'low':
        priority = Priority.low;
        break;
      default:
        priority = Priority.medium;
    }

    return Task(
      id: 'jira_${issue.key}',
      key: issue.key,
      title: issue.title,
      description: issue.description ?? '',
      projectId: widget.project.id,
      createdAt: issue.createdAt ?? DateTime.now(),
      status: issue.status,
      jiraTicketId: issue.key,
      priorityEnum: priority,
    );
  }
}

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
  late Priority _selectedPriority;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(text: widget.task.description);
    _selectedPriority = widget.task.priorityEnum;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _saveTask() {
    if (_titleController.text.trim().isEmpty) return;

    final updatedTask = widget.task.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      priorityEnum: _selectedPriority,
    );

    widget.onTaskUpdated(updatedTask);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Task'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
