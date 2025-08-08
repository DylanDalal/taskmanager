import 'package:flutter/material.dart';
import 'dart:io';
import 'services/jira_service.dart';
import 'services/ai_expand_service.dart';
import 'services/ai_email_draft_service.dart';

// Import the data models from main.dart
import 'main.dart';

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
  bool _isDraftingEmail = false;

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

  void _toggleAIQueue(bool? value) {
    setState(() {
      _task = _task.copyWith(queuedForAI: value ?? false);
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
          
          // Update the current task with the new subtasks and mark as expanded
          setState(() {
            _task = _task.copyWith(
              subtasks: [..._task.subtasks, ...newSubtasks],
              hasBeenExpandedWithAI: true,
            );
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

  Future<void> _draftEmailWithAI() async {
    if (widget.project.projectSummary == null || widget.project.projectSummary!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project summary is required for AI Draft. Please add a project summary in project settings.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Parse email data from task description
    final emailData = parseEmailTaskData(_task.description);
    if (emailData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This task does not appear to be an email task.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isDraftingEmail = true;
    });

    try {
      final aiService = AIEmailDraftService();
      final taskDescription = _task.description?.isNotEmpty == true ? _task.description! : _task.title;
      
      final emailDraft = await aiService.draftEmail(
        address: emailData['address']!,
        subject: emailData['subject']!,
        description: taskDescription,
        projectSummary: widget.project.projectSummary!,
      );

      if (mounted) {
        // Append the draft to the task description
        final currentDescription = _task.description ?? '';
        final updatedDescription = currentDescription.isEmpty 
          ? "draft: $emailDraft"
          : "$currentDescription, draft: $emailDraft";
        
        setState(() {
          _task = _task.copyWith(description: updatedDescription);
        });
        widget.onTaskUpdated?.call(_task);

        // Open mailto: URL with the email content
        final mailtoUrl = 'mailto:${emailData['address']}?subject=${Uri.encodeComponent(emailData['subject']!)}&body=${Uri.encodeComponent(emailDraft)}';
        
        // Launch the mailto: URL
        try {
          await Process.run('open', [mailtoUrl]);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email draft created and opened in Mail app!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          // If mailto: fails, just show success message about the draft
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Email draft created and saved to task! Mail app could not be opened: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error drafting email: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDraftingEmail = false;
        });
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
                    Row(
                      children: [
                        Icon(
                          isEmailTask(_task.description) ? Icons.email : Icons.description,
                          color: isEmailTask(_task.description) ? Colors.blue : Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isEmailTask(_task.description) ? 'Email Details' : 'Description',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isEmailTask(_task.description)) ...[
                      _buildEmailTaskDetails(_task.description!),
                    ] else ...[
                      Text(
                        _task.description!,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
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
                  Row(
                    children: [
                      Checkbox(
                        value: _task.queuedForAI,
                        onChanged: _toggleAIQueue,
                      ),
                      const SizedBox(width: 8),
                      const Text('Queue for AI'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_task.isSubtask && !_task.hasBeenExpandedWithAI) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.project.projectSummary != null &&
                                 widget.project.projectSummary!.isNotEmpty &&
                                 !_isExpandingTask &&
                                 !_isDraftingEmail &&
                                 (isEmailTask(_task.description) ? true : !_isExpandingTask)
                          ? (isEmailTask(_task.description) ? _draftEmailWithAI : _expandTaskWithAI)
                          : null,
                        icon: _isExpandingTask || _isDraftingEmail
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(isEmailTask(_task.description) ? Icons.email : Icons.auto_awesome),
                        label: Text(_isExpandingTask 
                          ? 'Expanding...' 
                          : _isDraftingEmail 
                            ? 'Drafting...' 
                            : isEmailTask(_task.description) 
                              ? 'AI Draft' 
                              : 'AI Expand'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEmailTask(_task.description) ? Colors.blue : Colors.purple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[300],
                          disabledForegroundColor: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
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
      case 'new':
        return Colors.grey;
      case 'blocked':
      case 'on hold':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildEmailTaskDetails(String description) {
    final emailData = parseEmailTaskData(description);
    if (emailData == null) {
      return Text(
        description,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.email, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Email Task',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildEmailDetailRow('To:', emailData['address'] ?? ''),
              const SizedBox(height: 8),
              _buildEmailDetailRow('Subject:', emailData['subject'] ?? ''),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
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