import 'package:flutter/foundation.dart';
import 'package:atlassian_apis/jira_platform.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

enum Priority { low, medium, high, critical }

class Task {
  final String id;
  final String key;
  final String title; // This maps to summary from Jira
  final String? description;
  final String status;
  final String? assignee;
  final String? assigneeEmail; // NEW FIELD
  final String? priority;
  final DateTime? createdAt; // This maps to created from Jira
  final DateTime? updated;
  final String? sprintName;
  final bool isInActiveSprint;
  final List<Task> subtasks;
  final String? parentKey;
  final bool isSubtask;
  final String projectId;
  final String? jiraTicketId; // This will be the same as key for Jira issues
  final Priority priorityEnum;
  final bool queuedForAI;

  Task({
    required this.id,
    required this.key,
    required this.title,
    this.description,
    required this.status,
    this.assignee,
    this.assigneeEmail, // NEW FIELD
    this.priority,
    this.createdAt,
    this.updated,
    this.sprintName,
    this.isInActiveSprint = false,
    this.subtasks = const [],
    this.parentKey,
    this.isSubtask = false,
    required this.projectId,
    this.jiraTicketId,
    this.priorityEnum = Priority.medium,
    this.queuedForAI = false,
  });

  // Getter for isCompleted - checks if status is "Done"
  bool get isCompleted {
    return status.toLowerCase() == 'done' || 
           status.toLowerCase() == 'closed' ||
           status.toLowerCase() == 'resolved';
  }

  // Getter for summary (alias for title)
  String get summary => title;

  // Getter for created (alias for createdAt)
  DateTime? get created => createdAt;

  Task copyWith({
    String? title,
    String? description,
    bool? isCompleted,
    String? jiraTicketId,
    Priority? priorityEnum,
    List<Task>? subtasks,
    String? parentKey,
    bool? isSubtask,
    String? status,
    String? assignee,
    String? assigneeEmail, // NEW FIELD
    String? priority,
    DateTime? updated,
    String? sprintName,
    bool? isInActiveSprint,
    String? projectId,
    bool? queuedForAI,
  }) {
    return Task(
      id: id,
      key: key,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? (isCompleted != null ? (isCompleted ? 'Done' : 'To Do') : this.status),
      assignee: assignee ?? this.assignee,
      assigneeEmail: assigneeEmail ?? this.assigneeEmail, // NEW FIELD
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updated: updated ?? this.updated,
      sprintName: sprintName ?? this.sprintName,
      isInActiveSprint: isInActiveSprint ?? this.isInActiveSprint,
      subtasks: subtasks ?? this.subtasks,
      parentKey: parentKey ?? this.parentKey,
      isSubtask: isSubtask ?? this.isSubtask,
      projectId: projectId ?? this.projectId,
      jiraTicketId: jiraTicketId ?? this.jiraTicketId,
      priorityEnum: priorityEnum ?? this.priorityEnum,
      queuedForAI: queuedForAI ?? this.queuedForAI,
    );
  }

  Map<String, dynamic> toJson() {
    String priorityString;
    switch (priorityEnum) {
      case Priority.low:
        priorityString = 'low';
        break;
      case Priority.medium:
        priorityString = 'medium';
        break;
      case Priority.high:
        priorityString = 'high';
        break;
      case Priority.critical:
        priorityString = 'critical';
        break;
    }
    
    return {
      'id': id,
      'key': key,
      'title': title,
      'description': description,
      'status': status,
      'assignee': assignee,
      'assigneeEmail': assigneeEmail, // NEW FIELD
      'priority': priority,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updated': updated?.millisecondsSinceEpoch,
      'sprintName': sprintName,
      'isInActiveSprint': isInActiveSprint,
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'parentKey': parentKey,
      'isSubtask': isSubtask,
      'projectId': projectId,
      'jiraTicketId': jiraTicketId,
      'priorityEnum': priorityString,
      'queuedForAI': queuedForAI,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    final priorityString = json['priorityEnum'] as String? ?? json['priority'] as String?;
    Priority priorityEnum = Priority.medium;
    
    switch (priorityString?.toLowerCase()) {
      case 'low':
      case 'lowest':
        priorityEnum = Priority.low;
        break;
      case 'medium':
        priorityEnum = Priority.medium;
        break;
      case 'high':
        priorityEnum = Priority.high;
        break;
      case 'critical':
      case 'highest':
        priorityEnum = Priority.critical;
        break;
    }

    return Task(
      id: json['id'] as String,
      key: json['key'] as String? ?? json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: json['status'] as String? ?? (json['isCompleted'] == true ? 'Done' : 'To Do'),
      assignee: json['assignee'] as String?,
      assigneeEmail: json['assigneeEmail'] as String?, // NEW FIELD
      priority: json['priority'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int) : null,
      updated: json['updated'] != null ? DateTime.fromMillisecondsSinceEpoch(json['updated'] as int) : null,
      sprintName: json['sprintName'] as String?,
      isInActiveSprint: json['isInActiveSprint'] as bool? ?? false,
      subtasks: (json['subtasks'] as List<dynamic>?)
          ?.map((subtaskJson) => Task.fromJson(subtaskJson))
          .toList() ?? [],
      parentKey: json['parentKey'] as String?,
      isSubtask: json['isSubtask'] as bool? ?? false,
      projectId: json['projectId'] as String,
      jiraTicketId: json['jiraTicketId'] as String?,
      priorityEnum: priorityEnum,
      queuedForAI: json['queuedForAI'] as bool? ?? false,
    );
  }

  // Helper function to extract text from Jira's Atlassian Document Format (ADF)
  static String? _extractTextFromADF(dynamic descriptionField) {
    if (descriptionField == null) return null;
    
    try {
      // If it's a string, return as is
      if (descriptionField is String) {
        return descriptionField;
      }
      
      // If it's a map, try to parse as ADF
      Map<String, dynamic> adf;
      if (descriptionField is Map<String, dynamic>) {
        adf = descriptionField;
      } else {
        // Try to parse as JSON string
        adf = json.decode(descriptionField.toString());
      }
      
      // Recursively extract text from ADF content
      return _extractTextFromContent(adf);
    } catch (e) {
      print('Error parsing description: $e');
      return descriptionField.toString();
    }
  }
  
  static String? _extractTextFromContent(dynamic content) {
    if (content == null) return null;
    
    List<String> textParts = [];
    
    if (content is Map<String, dynamic>) {
      // Handle text nodes directly
      if (content['type'] == 'text' && content['text'] != null) {
        textParts.add(content['text'].toString());
      }
      
      // Recursively process content array
      if (content['content'] is List) {
        for (var item in content['content']) {
          final text = _extractTextFromContent(item);
          if (text != null && text.isNotEmpty) {
            textParts.add(text);
          }
        }
      }
    } else if (content is List) {
      for (var item in content) {
        final text = _extractTextFromContent(item);
        if (text != null && text.isNotEmpty) {
          textParts.add(text);
        }
      }
    }
    
    return textParts.isNotEmpty ? textParts.join(' ') : null;
  }

  factory Task.fromJiraIssue(IssueBean issue, String projectId) {
    // Extract sprint information
    String? sprintName;
    bool isInActiveSprint = false;
    
    // Check various possible sprint field names
    var sprintField = issue.fields?['sprint'] ?? issue.fields?['customfield_10020'];
    if (sprintField != null) {
      if (sprintField is List && sprintField.isNotEmpty) {
        // Sprint is usually an array, take the last (most recent) sprint
        var latestSprint = sprintField.last;
        if (latestSprint is Map<String, dynamic>) {
          sprintName = latestSprint['name']?.toString();
          isInActiveSprint = latestSprint['state']?.toString().toLowerCase() == 'active';
        }
      } else if (sprintField is Map<String, dynamic>) {
        sprintName = sprintField['name']?.toString();
        isInActiveSprint = sprintField['state']?.toString().toLowerCase() == 'active';
      }
    }
    
    // Extract subtasks information
    List<Task> subtasksList = [];
    if (issue.fields?['subtasks'] != null && issue.fields!['subtasks'] is List) {
      for (var subtaskData in issue.fields!['subtasks']) {
        if (subtaskData is Map<String, dynamic>) {
          // Create a simplified IssueBean-like structure for subtasks
          final subtaskIssue = IssueBean(
            id: subtaskData['id']?.toString(),
            key: subtaskData['key']?.toString(),
            fields: {
              'summary': subtaskData['fields']?['summary'],
              'status': subtaskData['fields']?['status'],
              'assignee': subtaskData['fields']?['assignee'],
              'priority': subtaskData['fields']?['priority'],
              'created': subtaskData['fields']?['created'],
              'updated': subtaskData['fields']?['updated'],
              'issuetype': subtaskData['fields']?['issuetype'],
              'parent': {'key': issue.key},
            },
          );
          subtasksList.add(Task.fromJiraIssue(subtaskIssue, projectId));
        }
      }
    }
    
    // Check if this is a subtask
    final issueType = issue.fields?['issuetype']?['name']?.toString();
    final parentKey = issue.fields?['parent']?['key']?.toString();
    
    // Precise subtask detection - only based on issue type, not parent relationship
    // In Jira, tasks can have parents (like being under an Epic) without being subtasks
    final isSubtask = issueType?.toLowerCase() == 'subtask';
    
    // Extract assignee email if available
    String? assigneeEmail;
    if (issue.fields?['assignee'] != null) {
      assigneeEmail = issue.fields?['assignee']?['emailAddress']?.toString();
    }
    
    // Convert Jira priority to our Priority enum
    Priority priorityEnum;
    final jiraPriority = issue.fields?['priority']?['name']?.toString();
    switch (jiraPriority?.toLowerCase()) {
      case 'highest':
      case 'critical':
        priorityEnum = Priority.critical;
        break;
      case 'high':
        priorityEnum = Priority.high;
        break;
      case 'medium':
        priorityEnum = Priority.medium;
        break;
      case 'lowest':
      case 'low':
        priorityEnum = Priority.low;
        break;
      default:
        priorityEnum = Priority.medium;
    }
    
    return Task(
      id: issue.id ?? '',
      key: issue.key ?? '',
      title: issue.fields?['summary']?.toString() ?? 'No summary',
      description: _extractTextFromADF(issue.fields?['description']),
      status: issue.fields?['status']?['name']?.toString() ?? 'Unknown',
      assignee: issue.fields?['assignee']?['displayName']?.toString(),
      assigneeEmail: assigneeEmail, // NEW FIELD
      priority: issue.fields?['priority']?['name']?.toString(),
      createdAt: issue.fields?['created'] != null ? DateTime.tryParse(issue.fields!['created'].toString()) : null,
      updated: issue.fields?['updated'] != null ? DateTime.tryParse(issue.fields!['updated'].toString()) : null,
      sprintName: sprintName,
      isInActiveSprint: isInActiveSprint,
      subtasks: subtasksList,
      parentKey: parentKey,
      isSubtask: isSubtask,
      projectId: projectId,
      jiraTicketId: issue.key,
      priorityEnum: priorityEnum,
    );
  }
}

class JiraService {
  static final JiraService _instance = JiraService._internal();
  static JiraService get instance => _instance;
  
  JiraPlatformApi? _jiraApi;
  String? _email;
  String? _apiToken;
  String? _currentBaseUrl;
  
  JiraService._internal();

  Future<void> _initializeIfNeeded([String? baseUrl]) async {
    // Always reload config to get latest credentials from file
    final config = await _loadConfig();
    final newEmail = config['JIRA_EMAIL'];
    final newApiToken = config['JIRA_API_TOKEN'];
    
    // Check if credentials have changed or if we need to initialize
    final credentialsChanged = _email != newEmail || _apiToken != newApiToken;
    final needsInit = _jiraApi == null || _currentBaseUrl != baseUrl || credentialsChanged;
    
    _email = newEmail;
    _apiToken = newApiToken;
    
    if (!needsInit) {
      return;
    }
    
    if (_email == null || _apiToken == null) {
      throw Exception('Jira email and API token must be configured. Email: ${_email ?? 'missing'}, Token: ${_apiToken?.substring(0, 10) ?? 'missing'}...');
    }
    
    if (baseUrl != null) {
      _currentBaseUrl = baseUrl;
      final uri = Uri.parse(baseUrl);
      final client = ApiClient.basicAuthentication(
        uri,
        user: _email!,
        apiToken: _apiToken!,
      );
      _jiraApi = JiraPlatformApi(client);
    }
  }

  Future<Map<String, String>> _loadConfig() async {
    try {
      if (kIsWeb) {
        // For web, we'll use hardcoded values from your api_keys.txt file
        // In production, you'd want to use environment variables or a secure config service
        return {
          'JIRA_EMAIL': 'dylanmax@gmail.com',
          'JIRA_API_TOKEN': 'ATATT3xFfGF0WpM202ZrjRrJb13hAQEk2fFmGuQtviJt9bCPmXGonC8UVHOosXmozQR1CCIeotqnhlGu9BKxahxHc6OBEF240vvgHO2Gvtn54iFZUwuhfF_uRD9sryQpUcns0CldmGJHZQkfClCdq7BOHufcW49HbvIEwbqyDn9XaIsgu7m0uYI=52E89D40',
        };
      } else {
        // For desktop/mobile, read from api_keys.txt file in the application documents directory
        try {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/api_keys.txt');
          
          final contents = await file.readAsString();
          
          final config = <String, String>{};
          for (final line in contents.split('\n')) {
            if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
            
            final parts = line.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim();
              config[key] = value;
            }
          }
          
          return config;
        } catch (e) {
          print('Error reading api_keys.txt file: $e');
          // Fallback to hardcoded values
          return {
            'JIRA_EMAIL': 'dylanmax@gmail.com',
            'JIRA_API_TOKEN': 'ATATT3xFfGF0WpM202ZrjRrJb13hAQEk2fFmGuQtviJt9bCPmXGonC8UVHOosXmozQR1CCIeotqnhlGu9BKxahxHc6OBEF240vvgHO2Gvtn54iFZUwuhfF_uRD9sryQpUcns0CldmGJHZQkfClCdq7BOHufcW49HbvIEwbqyDn9XaIsgu7m0uYI=52E89D40',
          };
        }
      }
    } catch (e) {
      print('Error loading config: $e');
      return {};
    }
  }

  Future<List<Task>> fetchProjectIssues(String baseUrl, String projectKey) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Fetching issues for project: $projectKey from: $baseUrl');

      // Use JQL to search for issues in the project
      final searchResult = await _jiraApi!.issueSearch.searchForIssuesUsingJql(
        jql: 'project = $projectKey ORDER BY created DESC',
        maxResults: 50,
        fields: ['summary', 'description', 'status', 'assignee', 'priority', 'created', 'updated', 'sprint', 'customfield_10020', 'subtasks', 'parent', 'issuetype'],
      );

      if (searchResult.issues != null) {
        print('Found ${searchResult.issues!.length} issues');
        return searchResult.issues!
            .map((issue) => Task.fromJiraIssue(issue, projectKey))
            .toList();
      } else {
        print('No issues found in response');
        return [];
      }
    } catch (e) {
      String errorMessage = 'Error fetching Jira issues: $e';
      if (kIsWeb && e.toString().contains('Failed to fetch')) {
        errorMessage += '\n\nNote: This might be a CORS issue. Jira Cloud requires CORS configuration for web apps. Consider using a proxy server or running the app on mobile/desktop.';
      }
      print(errorMessage);
      rethrow;
    }
  }

  Future<bool> testConnection(String baseUrl) async {
    try {
      await _initializeIfNeeded(baseUrl);
      if (_jiraApi == null) {
        return false;
      }
      
      // Try to get myself info as a connection test (this is a simple authenticated endpoint)
      final user = await _jiraApi!.myself.getCurrentUser();
      print('Connection test successful! User: ${user.displayName}');
      return true;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  Future<Task> createIssue({
    required String baseUrl,
    required String projectKey,
    required String summary,
    required String description,
    String priority = 'Medium',
    String issueType = 'Task',
  }) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Creating Jira issue in project: $projectKey');

      // Create the issue using the Jira API
      final issueUpdateDetails = IssueUpdateDetails(
        fields: {
          'project': {
            'key': projectKey,
          },
          'summary': summary,
          'description': {
            'type': 'doc',
            'version': 1,
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': description,
                  }
                ]
              }
            ]
          },
          'issuetype': {
            'name': issueType,
          },
          'priority': {
            'name': priority,
          },
        },
      );

      final createdIssue = await _jiraApi!.issues.createIssue(
        body: issueUpdateDetails,
      );

      print('Successfully created issue: ${createdIssue.key}');

      // Fetch the created issue to get full details
      final issueBean = await _jiraApi!.issues.getIssue(
        issueIdOrKey: createdIssue.key!,
        fields: ['summary', 'description', 'status', 'assignee', 'priority', 'created', 'updated'],
      );

      return Task.fromJiraIssue(issueBean, projectKey);
    } catch (e) {
      String errorMessage = 'Error creating Jira issue: $e';
      print(errorMessage);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableTransitions(String baseUrl, String issueKey) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      final transitions = await _jiraApi!.issues.getTransitions(issueIdOrKey: issueKey);
      
      return transitions.transitions?.map((transition) => {
        'id': transition.id,
        'name': transition.name,
        'to': transition.to?.name,
      }).toList() ?? [];
    } catch (e) {
      print('Error getting transitions: $e');
      rethrow;
    }
  }

  Future<void> transitionIssue(String baseUrl, String issueKey, String transitionId) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      await _jiraApi!.issues.doTransition(
        issueIdOrKey: issueKey,
        body: IssueUpdateDetails(
          transition: IssueTransition(id: transitionId),
        ),
      );
    } catch (e) {
      print('Error transitioning issue: $e');
      rethrow;
    }
  }

  Future<void> assignIssueToMe(String baseUrl, String issueKey) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      // Get current user info
      final user = await _jiraApi!.myself.getCurrentUser();
      
      await _jiraApi!.issues.editIssue(
        issueIdOrKey: issueKey,
        body: IssueUpdateDetails(
          fields: {
            'assignee': {
              'accountId': user.accountId,
            },
          },
        ),
      );
    } catch (e) {
      print('Error assigning issue: $e');
      rethrow;
    }
  }

  Future<void> addComment(String baseUrl, String issueKey, String commentText) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      await _jiraApi!.issueComments.addComment(
        issueIdOrKey: issueKey,
        body: Comment(
          body: {
            'type': 'doc',
            'version': 1,
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': commentText,
                  }
                ]
              }
            ]
          },
        ),
      );
    } catch (e) {
      print('Error adding comment: $e');
      rethrow;
    }
  }

  Future<Task> createSubtask({
    required String baseUrl,
    required String projectKey,
    required String parentIssueKey,
    required String summary,
    String priority = 'Medium',
  }) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Creating Jira subtask for parent: $parentIssueKey');

      // Create the subtask using the Jira API (only use Sub-task issue type)
      final issueUpdateDetails = IssueUpdateDetails(
        fields: {
          'project': {
            'key': projectKey,
          },
          'parent': {
            'key': parentIssueKey,
          },
          'summary': summary, // Only summary field, no separate description
          'issuetype': {
            'name': 'subtask',
          },
          'priority': {
            'name': priority,
          },
        },
      );

      final createdIssue = await _jiraApi!.issues.createIssue(
        body: issueUpdateDetails,
      );

      print('Successfully created subtask: ${createdIssue.key}');

      // Fetch the created subtask to get full details
      final issueBean = await _jiraApi!.issues.getIssue(
        issueIdOrKey: createdIssue.key!,
        fields: ['summary', 'status', 'assignee', 'priority', 'created', 'updated', 'parent', 'issuetype'],
      );

      return Task.fromJiraIssue(issueBean, projectKey);
    } catch (e) {
      String errorMessage = 'Error creating Jira subtask: $e';
      print(errorMessage);
      rethrow;
    }
  }

  Future<void> editIssue({
    required String baseUrl,
    required String issueKey,
    required String summary,
    String? description,
    String? priority,
  }) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Editing Jira issue: $issueKey');

      Map<String, dynamic> fieldsToUpdate = {
        'summary': summary,
      };

      if (description != null && description.isNotEmpty) {
        fieldsToUpdate['description'] = {
          'type': 'doc',
          'version': 1,
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {
                  'type': 'text',
                  'text': description,
                }
              ]
            }
          ]
        };
      }

      if (priority != null && priority.isNotEmpty) {
        fieldsToUpdate['priority'] = {
          'name': priority,
        };
      }

      final issueUpdateDetails = IssueUpdateDetails(
        fields: fieldsToUpdate,
      );

      await _jiraApi!.issues.editIssue(
        issueIdOrKey: issueKey,
        body: issueUpdateDetails,
      );

      print('Successfully edited issue: $issueKey');
    } catch (e) {
      String errorMessage = 'Error editing Jira issue: $e';
      print(errorMessage);
      rethrow;
    }
  }

  Future<void> deleteIssue({
    required String baseUrl,
    required String issueKey,
  }) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Deleting Jira issue: $issueKey');

      await _jiraApi!.issues.deleteIssue(
        issueIdOrKey: issueKey,
        deleteSubtasks: 'true', // Delete subtasks as well
      );

      print('Successfully deleted issue: $issueKey');
    } catch (e) {
      String errorMessage = 'Error deleting Jira issue: $e';
      print(errorMessage);
      rethrow;
    }
  }

  Future<String?> getCurrentUserEmail() async {
    return _email;
  }

  Future<String?> getCurrentUserDisplayName() async {
    try {
      if (_jiraApi == null) {
        return null;
      }
      
      final user = await _jiraApi!.myself.getCurrentUser();
      return user.displayName;
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  Future<List<Task>> fetchMyAssignedIssues(String baseUrl, String projectKey) async {
    try {
      await _initializeIfNeeded(baseUrl);
      
      if (_jiraApi == null) {
        throw Exception('Failed to initialize Jira API');
      }

      print('Fetching assigned issues for current user in project: $projectKey');

      // Get current user info
      final user = await _jiraApi!.myself.getCurrentUser();
      final userAccountId = user.accountId;

      // Use JQL to search for issues assigned to current user in the project
      final searchResult = await _jiraApi!.issueSearch.searchForIssuesUsingJql(
        jql: 'project = $projectKey AND assignee = $userAccountId ORDER BY priority DESC, created DESC',
        maxResults: 50,
        fields: ['summary', 'description', 'status', 'assignee', 'priority', 'created', 'updated', 'sprint', 'customfield_10020', 'subtasks', 'parent', 'issuetype'],
      );

      if (searchResult.issues != null) {
        print('Found ${searchResult.issues!.length} assigned issues');
        return searchResult.issues!
            .map((issue) => Task.fromJiraIssue(issue, projectKey))
            .toList();
      } else {
        print('No assigned issues found in response');
        return [];
      }
    } catch (e) {
      String errorMessage = 'Error fetching assigned Jira issues: $e';
      print(errorMessage);
      rethrow;
    }
  }
} 