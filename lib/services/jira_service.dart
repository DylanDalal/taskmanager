import 'package:flutter/foundation.dart';
import 'package:atlassian_apis/jira_platform.dart';
import 'dart:io';
import 'dart:convert';

class JiraIssue {
  final String id;
  final String key;
  final String summary;
  final String? description;
  final String status;
  final String? assignee;
  final String? priority;
  final DateTime? created;
  final DateTime? updated;

  JiraIssue({
    required this.id,
    required this.key,
    required this.summary,
    this.description,
    required this.status,
    this.assignee,
    this.priority,
    this.created,
    this.updated,
  });

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

  factory JiraIssue.fromJiraIssue(IssueBean issue) {
    return JiraIssue(
      id: issue.id ?? '',
      key: issue.key ?? '',
      summary: issue.fields?['summary']?.toString() ?? 'No summary',
      description: _extractTextFromADF(issue.fields?['description']),
      status: issue.fields?['status']?['name']?.toString() ?? 'Unknown',
      assignee: issue.fields?['assignee']?['displayName']?.toString(),
      priority: issue.fields?['priority']?['name']?.toString(),
      created: issue.fields?['created'] != null ? DateTime.tryParse(issue.fields!['created'].toString()) : null,
      updated: issue.fields?['updated'] != null ? DateTime.tryParse(issue.fields!['updated'].toString()) : null,
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
    if (_jiraApi != null && _currentBaseUrl == baseUrl) return;
    
    final config = await _loadConfig();
    _email = config['JIRA_EMAIL'];
    _apiToken = config['JIRA_API_TOKEN'];
    
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
        // For desktop/mobile, read from api_keys.txt file
        try {
          final file = File('api_keys.txt');
          final contents = await file.readAsString();
          
          final config = <String, String>{};
          for (final line in contents.split('\n')) {
            if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
            
            final parts = line.split('=');
            if (parts.length == 2) {
              config[parts[0].trim()] = parts[1].trim();
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

  Future<List<JiraIssue>> fetchProjectIssues(String baseUrl, String projectKey) async {
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
        fields: ['summary', 'description', 'status', 'assignee', 'priority', 'created', 'updated'],
      );

      if (searchResult.issues != null) {
        print('Found ${searchResult.issues!.length} issues');
        return searchResult.issues!
            .map((issue) => JiraIssue.fromJiraIssue(issue))
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
      if (_jiraApi == null) return false;
      
      // Try to get myself info as a connection test (this is a simple authenticated endpoint)
      await _jiraApi!.myself.getCurrentUser();
      return true;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }
} 