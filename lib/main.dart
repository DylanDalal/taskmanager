import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'services/jira_service.dart';

void main() {
  runApp(const TaskManagerApp());
}

// Data Models
enum ProjectType { development, general }

class Project {
  final String id;
  final String name;
  final String description;
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
    List<Task>? tasks,
    String? jiraProjectUrl,
    String? jiraProjectKey,
    ProjectType? type,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      color: type != null 
        ? (type == ProjectType.development ? Colors.purple[600]! : Colors.orange[600]!)
        : color,
      icon: type != null 
        ? (type == ProjectType.development ? Icons.code : Icons.task)
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
          return segments[i + 1];
        }
        if (segments[i] == 'browse' && i + 1 < segments.length) {
          final issueKey = segments[i + 1];
          // Extract project key from issue key (e.g., "PROJ-123" -> "PROJ")
          final dashIndex = issueKey.indexOf('-');
          if (dashIndex > 0) {
            return issueKey.substring(0, dashIndex);
          }
        }
      }
      
      // If no pattern matches, return the manually set project key
      return jiraProjectKey;
    } catch (e) {
      return jiraProjectKey;
    }
  }

  int get completedTasks => tasks.where((task) => task.isCompleted).length;
  
  // Calculate progress based on Jira issues if available, otherwise local tasks
  double getProgressPercentage(List<JiraIssue> jiraIssues) {
    if (jiraIssues.isNotEmpty) {
      final doneIssues = jiraIssues.where((issue) => 
        issue.status.toLowerCase() == 'done' || 
        issue.status.toLowerCase() == 'closed' ||
        issue.status.toLowerCase() == 'resolved'
      ).length;
      return jiraIssues.isEmpty ? 0.0 : (doneIssues / jiraIssues.length) * 100;
    } else {
      return tasks.isEmpty ? 0.0 : (completedTasks / tasks.length) * 100;
    }
  }
  
  double get progressPercentage => tasks.isEmpty ? 0.0 : (completedTasks / tasks.length) * 100;
}

class Task {
  final String id;
  final String title;
  final String description;
  final String projectId;
  final DateTime createdAt;
  final bool isCompleted;
  final String? jiraTicketId;
  final Priority priority;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.projectId,
    required this.createdAt,
    this.isCompleted = false,
    this.jiraTicketId,
    this.priority = Priority.medium,
  });

  Task copyWith({
    String? title,
    String? description,
    bool? isCompleted,
    String? jiraTicketId,
    Priority? priority,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      projectId: projectId,
      createdAt: createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
      jiraTicketId: jiraTicketId ?? this.jiraTicketId,
      priority: priority ?? this.priority,
    );
  }
}

enum Priority { low, medium, high, critical }

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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  Map<String, List<JiraIssue>> _projectJiraIssues = {}; // Store Jira issues by project ID

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

  void _initializeProjects() {
    // Initialize with empty project lists
    _professionalProjects = [];
    _personalProjects = [];
    
    // Fetch Jira issues for any existing Jira projects
    _refreshAllJiraIssues();
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

  void _showCreateProjectDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateProjectDialog(
        onProjectCreated: _addProject,
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

  void _addProject(Project project) {
    setState(() {
      if (project.type == ProjectType.development) {
        _professionalProjects.add(project);
      } else {
        _personalProjects.add(project);
      }
    });
    
    // Fetch Jira issues for new Jira projects
    if (project.extractedJiraProjectKey != null) {
      _fetchJiraIssuesForProject(project);
    }
  }

  Future<void> _fetchJiraIssuesForProject(Project project) async {
    if (project.jiraBaseUrl == null || project.extractedJiraProjectKey == null) return;
    
    try {
      final jiraService = JiraService.instance;
      final issues = await jiraService.fetchProjectIssues(
        project.jiraBaseUrl!,
        project.extractedJiraProjectKey!,
      );
      
      setState(() {
        _projectJiraIssues[project.id] = issues;
      });
    } catch (e) {
      print('Error fetching Jira issues for ${project.name}: $e');
      // Don't show error in dashboard, just use local counts
    }
  }

  int _getProjectTaskCount(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return jiraIssues.length;
    }
    return project.tasks.length;
  }

  int _getProjectCompletedCount(Project project) {
    final jiraIssues = _projectJiraIssues[project.id];
    if (jiraIssues != null) {
      return jiraIssues.where((issue) => 
        issue.status.toLowerCase() == 'done' || 
        issue.status.toLowerCase() == 'closed' ||
        issue.status.toLowerCase() == 'resolved'
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

  void _editProject(Project project) {
    showDialog(
      context: context,
      builder: (context) => EditProjectDialog(
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
                final isProfessional = project.type == ProjectType.development;
                final projectList = isProfessional ? _professionalProjects : _personalProjects;
                projectList.removeWhere((p) => p.id == project.id);
              });
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
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: SafeArea(
        child: Column(
          children: [
            // Dashboard Title and Tabs
            Container(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Dashboard Title with Settings
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      Text(
                        'DASHBOARD',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                          letterSpacing: 2.0,
                        ),
                      ),
                      IconButton(
                        onPressed: _showSettingsDialog,
                        icon: Icon(Icons.settings, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Tab Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        color: Colors.blue[600],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey[600],
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      tabs: const [
                        Tab(
                          text: 'Professional',
                          icon: Icon(Icons.work, size: 20),
                        ),
                        Tab(
                          text: 'Personal',
                          icon: Icon(Icons.home, size: 20),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
        ),
      ),
    );
  }

  Widget _buildTabContent(String title, List<Project> projects) {
    return Container(
      margin: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[600]!.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        title == 'Professional' ? Icons.work : Icons.home,
                        color: Colors.blue[600],
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _showCreateProjectDialog,
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
            
            const SizedBox(height: 20),
            
            // Projects List
            Expanded(
              child: projects.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        return _buildProjectCard(projects[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
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
            color: Colors.grey[400],
          ),
          const SizedBox(height: 15),
          Text(
            'No projects yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by creating your first project',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _openProjectDetail(project),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: project.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      project.icon,
                      color: project.color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                project.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                        if (project.extractedJiraProjectKey != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Jira Project: ${project.extractedJiraProjectKey}',
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_getProjectTaskCount(project)} tasks',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_getProjectCompletedCount(project)} completed',
                                style: TextStyle(
                                  color: Colors.green[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          PopupMenuButton(
                            icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
                            onSelected: (String value) {
                              if (value == 'edit') {
                                _editProject(project);
                              } else if (value == 'delete') {
                                _deleteProject(project);
                              }
                            },
                            itemBuilder: (BuildContext context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Project Description
              Text(
                project.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 12),
              
              // Progress Bar
              if (_getProjectTaskCount(project) > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _getProjectProgress(project) / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(project.color),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_getProjectProgress(project).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: project.color,
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
  final _jiraProjectUrlController = TextEditingController();
  ProjectType _selectedType = ProjectType.development;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _jiraProjectUrlController.dispose();
    super.dispose();
  }

  void _createProject() {
    if (_nameController.text.isEmpty) return;

    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      description: _descriptionController.text,
      type: _selectedType,
      color: _selectedType == ProjectType.development ? Colors.purple[600]! : Colors.orange[600]!,
      icon: _selectedType == ProjectType.development ? Icons.code : Icons.task,
      tasks: [],
      jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
      createdAt: DateTime.now(),
    );

    widget.onProjectCreated(project);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Project'),
      content: SizedBox(
        width: 400,
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
                      Icon(Icons.code, color: Colors.purple, size: 20),
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
            if (_selectedType == ProjectType.development) ...[
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
          onPressed: _createProject,
          child: const Text('Create Project'),
        ),
      ],
    );
  }
}

class ProjectDetailPage extends StatefulWidget {
  final Project project;
  final Function(Project) onProjectUpdated;

  const ProjectDetailPage({
    super.key,
    required this.project,
    required this.onProjectUpdated,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late Project _project;
  List<JiraIssue> _jiraIssues = [];
  bool _isLoadingJiraIssues = false;
  String? _jiraError;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _fetchJiraIssues();
  }

  void _addTask(Task task) {
    setState(() {
      _project = _project.copyWith(
        tasks: [..._project.tasks, task],
      );
    });
    widget.onProjectUpdated(_project);
  }

  void _openJiraIssueDetail(JiraIssue issue) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JiraIssueDetailPage(
          issue: issue,
          projectName: _project.name,
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
      builder: (context) => AddJiraTaskDialog(
        project: _project,
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
        builder: (context) => LocalTaskDetailPage(
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

  List<JiraIssue> _getSortedJiraIssues() {
    final sortedIssues = List<JiraIssue>.from(_jiraIssues);
    sortedIssues.sort((a, b) {
      // Check if either task is "Done"
      final aIsDone = a.status.toLowerCase() == 'done' || 
                     a.status.toLowerCase() == 'closed' ||
                     a.status.toLowerCase() == 'resolved';
      final bIsDone = b.status.toLowerCase() == 'done' || 
                     b.status.toLowerCase() == 'closed' ||
                     b.status.toLowerCase() == 'resolved';
      
      // Done tasks go to bottom
      if (aIsDone && !bIsDone) return 1;
      if (!aIsDone && bIsDone) return -1;
      
      // If both are done or both are not done, sort by priority
      final aPriority = _getPriorityValue(a.priority);
      final bPriority = _getPriorityValue(b.priority);
      return bPriority.compareTo(aPriority); // Highest to lowest
    });
    return sortedIssues;
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_project.name),
        backgroundColor: _project.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: hasJiraConnection ? _showAddJiraTaskDialog : _showAddTaskDialog,
            icon: const Icon(Icons.add),
            tooltip: hasJiraConnection ? 'Add Jira Task' : 'Add Local Task',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _project.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _project.icon,
                            color: _project.color,
                            size: 24,
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
                                ? '${sortedJiraIssues.where((issue) => issue.status.toLowerCase() == 'done' || issue.status.toLowerCase() == 'closed' || issue.status.toLowerCase() == 'resolved').length}/${sortedJiraIssues.length}'
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
                    const SizedBox(height: 16),
                    Text(
                      _project.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
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
                        ..._project.tasks.map((task) => _buildLocalTaskCard(task)),
                    ],
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

  Widget _buildJiraIssueCard(JiraIssue issue) {
    final isDone = issue.status.toLowerCase() == 'done' || 
                   issue.status.toLowerCase() == 'closed' ||
                   issue.status.toLowerCase() == 'resolved';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDone ? Colors.grey[100] : null,
      child: ListTile(
        onTap: () => _openJiraIssueDetail(issue),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDone ? Colors.grey[300] : Colors.blue[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.link,
            color: isDone ? Colors.grey[600] : Colors.blue[700],
            size: 16,
          ),
        ),
        title: Text(
          issue.summary,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDone ? Colors.grey[600] : null,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
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
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isDone ? Colors.grey[400] : Colors.grey[400],
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
            if (task.description.isNotEmpty) ...[
              Text(task.description),
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
                    color: _getPriorityColor(task.priority).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getPriorityText(task.priority),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getPriorityColor(task.priority),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey[400],
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
      title: _titleController.text,
      description: _descriptionController.text,
      projectId: widget.projectId,
      createdAt: DateTime.now(),
      jiraTicketId: _jiraTicketController.text.isEmpty ? null : _jiraTicketController.text,
      priority: _selectedPriority,
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
                labelText: 'ChatGPT Access Token',
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
  late TextEditingController _jiraProjectUrlController;
  late ProjectType _selectedType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _descriptionController = TextEditingController(text: widget.project.description);
    _jiraProjectUrlController = TextEditingController(text: widget.project.jiraProjectUrl ?? '');
    _selectedType = widget.project.type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _jiraProjectUrlController.dispose();
    super.dispose();
  }

  void _updateProject() {
    final updatedProject = widget.project.copyWith(
      name: _nameController.text,
      description: _descriptionController.text,
      type: _selectedType,
      jiraProjectUrl: _jiraProjectUrlController.text.isEmpty ? null : _jiraProjectUrlController.text,
    );
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
                      Icon(Icons.code, color: Colors.purple, size: 20),
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
              ],
              onChanged: (type) {
                setState(() {
                  _selectedType = type!;
                });
              },
            ),
            if (_selectedType == ProjectType.development) ...[
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

class JiraIssueDetailPage extends StatelessWidget {
  final JiraIssue issue;
  final String projectName;

  const JiraIssueDetailPage({
    super.key,
    required this.issue,
    required this.projectName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(issue.key),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
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
                          issue.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (issue.priority != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(issue.priority!).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            issue.priority!,
                            style: TextStyle(
                              color: _getPriorityColor(issue.priority!),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    issue.summary,
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
                          color: _getStatusColor(issue.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          issue.status,
                          style: TextStyle(
                            color: _getStatusColor(issue.status),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (issue.assignee != null) ...[
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              issue.assignee!,
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
            if (issue.description != null && issue.description!.isNotEmpty) ...[
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
                      issue.description!,
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
                          onPressed: () {
                            // TODO: Implement transition to status
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Status transition feature coming soon!')),
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Change Status'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
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
                  SizedBox(
                    width: double.infinity,
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
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Issue Metadata
            const SizedBox(height: 20),
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
                  if (issue.created != null)
                    _buildDetailRow('Created', _formatDate(issue.created!)),
                  if (issue.updated != null)
                    _buildDetailRow('Updated', _formatDate(issue.updated!)),
                  _buildDetailRow('Project', projectName),
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
}

class AddJiraTaskDialog extends StatefulWidget {
  final Project project;
  final Function(Task) onTaskCreated;

  const AddJiraTaskDialog({
    super.key,
    required this.project,
    required this.onTaskCreated,
  });

  @override
  State<AddJiraTaskDialog> createState() => _AddJiraTaskDialogState();
}

class _AddJiraTaskDialogState extends State<AddJiraTaskDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  Priority _selectedPriority = Priority.medium;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createTask() {
    if (_titleController.text.trim().isEmpty) return;

    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      projectId: widget.project.id,
      createdAt: DateTime.now(),
      priority: _selectedPriority,
    );

    widget.onTaskCreated(task);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.link, color: widget.project.color),
          const SizedBox(width: 8),
          const Text('Create Jira Task'),
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
                      'This will create a task in Jira project ${widget.project.extractedJiraProjectKey}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Summary',
                border: OutlineInputBorder(),
              ),
              maxLines: 1,
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
          onPressed: _createTask,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.project.color,
            foregroundColor: Colors.white,
          ),
          child: const Text('Create in Jira'),
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

class LocalTaskDetailPage extends StatefulWidget {
  final Task task;
  final Project project;
  final Function(Task) onTaskUpdated;

  const LocalTaskDetailPage({
    super.key,
    required this.task,
    required this.project,
    required this.onTaskUpdated,
  });

  @override
  State<LocalTaskDetailPage> createState() => _LocalTaskDetailPageState();
}

class _LocalTaskDetailPageState extends State<LocalTaskDetailPage> {
  late Task _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  void _toggleCompletion() {
    setState(() {
      _task = _task.copyWith(isCompleted: !_task.isCompleted);
    });
    widget.onTaskUpdated(_task);
  }

  void _showComingSoonMessage(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Local Task'),
        backgroundColor: widget.project.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _toggleCompletion,
            icon: Icon(
              _task.isCompleted ? Icons.radio_button_unchecked : Icons.check_circle,
            ),
            tooltip: _task.isCompleted ? 'Mark as incomplete' : 'Mark as complete',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.project.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.task_alt,
                            color: widget.project.color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _task.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              decoration: _task.isCompleted ? TextDecoration.lineThrough : null,
                              color: _task.isCompleted ? Colors.grey[600] : null,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _task.isCompleted ? Colors.green : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _task.isCompleted ? 'COMPLETED' : 'PENDING',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _task.isCompleted ? Colors.white : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_task.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _task.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action Buttons Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Actions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showComingSoonMessage('Edit Task'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.project.color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit Task'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showComingSoonMessage('Add Comment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.comment, size: 18),
                            label: const Text('Add Comment'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showComingSoonMessage('Delete Task'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Task Details Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Task Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Priority', _getPriorityText(_task.priority)),
                    _buildDetailRow('Project', widget.project.name),
                    _buildDetailRow('Created', _formatDate(_task.createdAt)),
                    if (_task.jiraTicketId != null)
                      _buildDetailRow('Jira Ticket', _task.jiraTicketId!),
                  ],
                ),
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
