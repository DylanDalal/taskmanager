import 'package:flutter/material.dart';
import 'services/jira_service.dart';

// Import the data models from main.dart
import 'main.dart';
import 'ui_task_details.dart';

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
  final Function(Script)? onAddSharedScript;
  final Function(Script)? onUpdateSharedScript;
  final Function(String)? onRemoveSharedScript;
  final List<Script>? sharedScripts;
  final VoidCallback? onBack;

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
    this.onAddSharedScript,
    this.onUpdateSharedScript,
    this.onRemoveSharedScript,
    this.sharedScripts,
    this.onBack,
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
        hasJiraIntegration: _project.jiraProjectUrl != null && 
                           _project.jiraProjectUrl!.isNotEmpty && 
                           _project.extractedJiraProjectKey != null,
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
        hasJiraIntegration: _project.jiraProjectUrl != null && 
                           _project.jiraProjectUrl!.isNotEmpty && 
                           _project.extractedJiraProjectKey != null,
      ),
    );
  }

  void _addScript(Script script) {
    setState(() {
      final updatedScripts = [..._project.scripts, script];
      _project = _project.copyWith(scripts: updatedScripts);
    });
    widget.onProjectUpdated(_project);
  }

  void _updateScript(Script updatedScript) {
    setState(() {
      final updatedScripts = _project.scripts.map((script) {
        if (script.id == updatedScript.id) {
          return updatedScript;
        }
        return script;
      }).toList();
      _project = _project.copyWith(scripts: updatedScripts);
    });
    widget.onProjectUpdated(_project);
  }

  void _removeScript(String scriptId) {
    setState(() {
      final updatedScripts = _project.scripts.where((script) => script.id != scriptId).toList();
      _project = _project.copyWith(scripts: updatedScripts);
    });
    widget.onProjectUpdated(_project);
  }

  void _runScript(Script script, Map<String, String> argumentValues) async {
    try {
      await script.runScript(argumentValues);
    } catch (e) {
      rethrow;
    }
  }

  void _showSharedScriptsDialog() {
    showDialog(
      context: context,
      builder: (context) => SharedScriptsDialog(
        sharedScripts: widget.sharedScripts ?? [],
        onAddSharedScript: widget.onAddSharedScript ?? (_) {},
        onUpdateSharedScript: widget.onUpdateSharedScript ?? (_) {},
        onRemoveSharedScript: widget.onRemoveSharedScript ?? (_) {},
        onAddToProject: (script) {
          // Create a new script instance with a new ID for this project
          final projectScript = Script(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: script.name,
            runCommand: script.runCommand,
            filePath: script.filePath,
            arguments: script.arguments,
            description: script.description,
            cronSchedule: script.cronSchedule,
            createdAt: DateTime.now(),
          );
          _addScript(projectScript);
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
      
      // For non-done tasks, prioritize sprint tasks first, then by priority
      if (!aIsDone && !bIsDone) {
        // Sprint tasks come first
        if (a.isInActiveSprint && !b.isInActiveSprint) return -1;
        if (!a.isInActiveSprint && b.isInActiveSprint) return 1;
        
        // Within same group (both sprint or both non-sprint), sort by priority (Critical to Low)
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

  List<Task> _getSortedLocalTasks() {
    final localTasks = _project.tasks.where((task) => !task.isSubtask).toList();
    localTasks.sort((a, b) {
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
    return localTasks;
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
                    
                    // Custom Scripts
                    const SizedBox(height: 20),
                    _buildScriptsSection(),
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
          const SizedBox(height: 4),
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

  Widget _buildScriptsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 16,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Custom Scripts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showSharedScriptsDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    icon: const Icon(Icons.folder_shared, size: 14),
                    label: const Text('Shared', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AddScriptDialog(
                          onScriptCreated: _addScript,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_project.scripts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
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
                    'No scripts added yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[800],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a custom script or browse shared scripts',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._project.scripts.map((script) => _buildScriptCard(script)).toList(),
        ],
      ),
    );
  }

  Widget _buildScriptCard(Script script) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[800]!.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        script.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (script.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          script.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[300],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => RunScriptDialog(
                            script: script,
                            onScriptRun: _runScript,
                          ),
                        );
                      },
                      tooltip: 'Run Script',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => EditScriptDialog(
                            script: script,
                            onScriptUpdated: _updateScript,
                          ),
                        );
                      },
                      tooltip: 'Edit Script',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Script'),
                            content: Text('Are you sure you want to delete "${script.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  _removeScript(script.id);
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
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[600]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Command: ${script.runCommand} ${script.filePath}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (script.arguments.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Arguments: ${script.arguments.map((arg) => arg.name).join(', ')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[300],
                      ),
                    ),
                  ],
                  if (script.cronSchedule != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Schedule: ${script.cronSchedule}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[300],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
    final progressPercentage = _project.getProgressPercentage(sortedJiraIssues);
    final hasJiraConnection = _project.extractedJiraProjectKey != null && _jiraError == null;

    return Column(
      children: [
        // Fixed Header - Project Info Card
        Container(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (widget.onBack != null) {
                            widget.onBack!();
                          }
                        },
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
        ),
        
        // Scrollable Content Area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content List
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
                  if (_project.extractedJiraProjectKey != null) const SizedBox(height: 24),
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
                    ..._getSortedLocalTasks().map((task) => _buildLocalTaskCard(task)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getPriorityColor(dynamic priority) {
    if (priority is Priority) {
      // Handle enum-based priority (local tasks)
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
    } else if (priority is String) {
      // Handle string-based priority (Jira issues)
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
    return Colors.grey;
  }

  String _getPriorityText(dynamic priority) {
    if (priority is Priority) {
      // Handle enum-based priority (local tasks)
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
    } else if (priority is String) {
      // Handle string-based priority (Jira issues)
      switch (priority.toLowerCase()) {
        case 'lowest':
        case 'low':
          return 'Low';
        case 'medium':
          return 'Medium';
        case 'high':
          return 'High';
        case 'highest':
        case 'critical':
          return 'Critical';
        default:
          return 'Medium';
      }
    }
    return 'Medium';
  }

  Widget _buildJiraIssueCard(Task issue) {
    final isDone = issue.isCompleted;
    final isSprintTask = issue.isInActiveSprint && !isDone;
    
    // Determine card background color
    Color? cardColor;
    if (isDone) {
      cardColor = Colors.grey[100];  // Grey for done tasks
    } else if (isSprintTask) {
      cardColor = const Color(0xFFCCF7FF);  // Light blue for sprint tasks (matches sprint progress bar)
    } else {
      cardColor = const Color(0xFF1E1E1E);  // Gray background for non-sprint tasks
    }
    
    // Determine text colors based on background
    final titleColor = isDone 
      ? Colors.grey[600] 
      : isSprintTask 
        ? Colors.black87  // Dark text on light blue background
        : Colors.white;   // White text on gray background
    
    final subtitleColor = isDone 
      ? Colors.grey[500] 
      : isSprintTask 
        ? Colors.black54  // Dark text on light blue background
        : Colors.grey[300]; // Light gray text on gray background
    
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
              : isSprintTask 
                ? const Color(0xFF0066CC).withOpacity(0.2)
                : Colors.blue[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            isSprintTask ? Icons.timer : Icons.link,
            color: isDone 
              ? Colors.grey[600] 
              : isSprintTask 
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
                  color: titleColor,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isSprintTask) ...[
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
                  color: subtitleColor,
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
                      color: _getPriorityColor(issue.priority!).withOpacity(isDone ? 0.3 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getPriorityColor(issue.priority!).withOpacity(isDone ? 0.2 : 0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      issue.priority!,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDone 
                          ? _getPriorityColor(issue.priority!).withOpacity(0.7)
                          : _getPriorityColor(issue.priority!),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (issue.assignee != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDone 
                        ? Colors.grey[300]!.withOpacity(0.3)
                        : Colors.blue[100]!.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isDone 
                          ? Colors.grey[400]!.withOpacity(0.3)
                          : Colors.blue[300]!.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person,
                          size: 10,
                          color: isDone ? Colors.grey[500] : Colors.blue[700],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          issue.assignee!,
                          style: TextStyle(
                            fontSize: 9,
                            color: isDone ? Colors.grey[500] : Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
    final isSprintTask = task.isInActiveSprint && !task.isCompleted;
    final isEmailTaskType = isEmailTask(task.description);
    final isVideoTaskType = isVideoTask(task.description);
    
    // Determine card background color
    Color? cardColor;
    if (task.isCompleted) {
      cardColor = Colors.grey[100];  // Grey for completed tasks
    } else if (isSprintTask) {
      cardColor = const Color(0xFFCCF7FF);  // Light blue for sprint tasks
    } else {
      cardColor = const Color(0xFF1E1E1E);  // Gray background for non-sprint tasks
    }
    
    // Determine text colors based on background
    final titleColor = task.isCompleted 
      ? Colors.grey[600] 
      : isSprintTask 
        ? Colors.black87  // Dark text on light blue background
        : Colors.white;   // White text on gray background
    
    final subtitleColor = task.isCompleted 
      ? Colors.grey[500] 
      : isSprintTask 
        ? Colors.black54  // Dark text on light blue background
        : Colors.grey[300]; // Light gray text on gray background
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      child: ListTile(
        onTap: () => _openLocalTaskDetail(task),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _toggleTaskCompletion(task),
              icon: Icon(
                task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.isCompleted ? Colors.green : Colors.grey[400],
              ),
            ),
            if (isEmailTaskType)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.email,
                  size: 16,
                  color: Colors.blue[700],
                ),
              ),
            if (isVideoTaskType)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.play_circle,
                  size: 16,
                  color: Colors.red[700],
                ),
              ),
          ],
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            fontWeight: FontWeight.w500,
            color: titleColor,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description?.isNotEmpty == true) ...[
              Text(
                task.description ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtitleColor),
              ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(task.priorityEnum).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getPriorityColor(task.priorityEnum).withOpacity(0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    _getPriorityText(task.priorityEnum),
                    style: TextStyle(
                      fontSize: 10,
                      color: _getPriorityColor(task.priorityEnum),
                      fontWeight: FontWeight.w600,
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



  Task _convertJiraIssueToTask(Task issue) {
    return issue.copyWith(projectId: _project.id);
  }
} 