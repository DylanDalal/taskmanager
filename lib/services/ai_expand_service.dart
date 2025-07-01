import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SubtaskItem {
  final int id;
  final String title;
  final String prompt;

  SubtaskItem({
    required this.id,
    required this.title,
    required this.prompt,
  });

  factory SubtaskItem.fromJson(Map<String, dynamic> json) {
    return SubtaskItem(
      id: json['id'] as int,
      title: json['title'] as String,
      prompt: json['prompt'] as String,
    );
  }
}

class AIExpandService {
  static final AIExpandService _instance = AIExpandService._internal();
  factory AIExpandService() => _instance;
  AIExpandService._internal();

  Future<Map<String, String>> _loadApiKeys() async {
    final Map<String, String> apiKeys = {};
    
    try {
      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final apiKeysFile = File('${directory.path}/api_keys.txt');
      
      print('Looking for API keys file at: ${apiKeysFile.path}');
      
      if (await apiKeysFile.exists()) {
        print('Found api_keys.txt file');
        final contents = await apiKeysFile.readAsString();
        final lines = contents.split('\n');
        
        for (final line in lines) {
          if (line.trim().isNotEmpty && line.contains('=')) {
            final parts = line.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim();
              apiKeys[key] = value;
              print('Loaded API key: $key');
            }
          }
        }
      } else {
        print('API keys file not found at: ${apiKeysFile.path}');
        print('Please create this file with your API keys in the format:');
        print('OPENAI_API_KEY=your_openai_key_here');
        print('CLAUDE_API_KEY=your_claude_key_here');
        
        // Create a template file to help the user
        await apiKeysFile.writeAsString('''# API Keys Configuration
# Add your API keys below in the format KEY=VALUE
# Uncomment and fill in the keys you want to use:

# OPENAI_API_KEY=your_openai_key_here
# CLAUDE_API_KEY=your_claude_key_here
# JIRA_EMAIL=your_jira_email_here
# JIRA_API_TOKEN=your_jira_api_token_here
''');
        print('Created template file at: ${apiKeysFile.path}');
      }
    } catch (e) {
      print('Error loading API keys: $e');
    }
    
    // Also check environment variables as fallback
    apiKeys['OPENAI_API_KEY'] ??= Platform.environment['OPENAI_API_KEY'] ?? '';
    apiKeys['CLAUDE_API_KEY'] ??= Platform.environment['CLAUDE_API_KEY'] ?? '';
    
    final hasOpenAI = apiKeys['OPENAI_API_KEY']?.isNotEmpty == true;
    final hasClaude = apiKeys['CLAUDE_API_KEY']?.isNotEmpty == true;
    
    print('Final API key status - OpenAI: $hasOpenAI, Claude: $hasClaude');
    
    return apiKeys;
  }

  Future<String> _loadPromptTemplate(bool isDevelopmentProject) async {
    try {
      final fileName = isDevelopmentProject ? 'assets/expand_prompt_dev.txt' : 'assets/expand_prompt.txt';
      return await rootBundle.loadString(fileName);
    } catch (e) {
      print('Error loading prompt template: $e');
      rethrow;
    }
  }

  String _fillPromptTemplate(String template, {
    required String projectSummary,
    required String task,
    String? techStack,
  }) {
    String filledTemplate = template
        .replaceAll('{PROJECT_SUMMARY}', projectSummary)
        .replaceAll('{TASK}', task);
    
    if (techStack != null && techStack.isNotEmpty) {
      filledTemplate = filledTemplate.replaceAll('{TECH}', techStack);
    }
    
    return filledTemplate;
  }

  Future<List<SubtaskItem>> expandTaskWithOpenAI(String prompt) async {
    final apiKeys = await _loadApiKeys();
    final apiKey = apiKeys['OPENAI_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OpenAI API key not found. Please add OPENAI_API_KEY to api_keys.txt file.');
    }

    const url = 'https://api.openai.com/v1/chat/completions';
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final body = {
      'model': 'gpt-4o-mini', // Using gpt-4o-mini for cost efficiency
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'temperature': 0.7,
      'max_tokens': 2000,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        // Parse the JSON response
        return _parseAIResponse(content);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('OpenAI API error: ${errorData['error']['message']}');
      }
    } catch (e) {
      print('Error calling OpenAI API: $e');
      rethrow;
    }
  }

  Future<List<SubtaskItem>> expandTaskWithClaude(String prompt) async {
    final apiKeys = await _loadApiKeys();
    final apiKey = apiKeys['CLAUDE_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Claude API key not found. Please add CLAUDE_API_KEY to api_keys.txt file.');
    }

    const url = 'https://api.anthropic.com/v1/messages';
    
    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };

    final body = {
      'model': 'claude-3-haiku-20240307', // Using Haiku for cost efficiency
      'max_tokens': 2000,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'][0]['text'] as String;
        
        // Parse the JSON response
        return _parseAIResponse(content);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('Claude API error: ${errorData['error']['message']}');
      }
    } catch (e) {
      print('Error calling Claude API: $e');
      rethrow;
    }
  }

  List<SubtaskItem> _parseAIResponse(String content) {
    try {
      // Clean the response content to extract just the JSON part
      String jsonContent = content.trim();
      
      // Remove any markdown code blocks if present
      if (jsonContent.startsWith('```json')) {
        jsonContent = jsonContent.replaceFirst('```json', '').replaceFirst('```', '');
      } else if (jsonContent.startsWith('```')) {
        jsonContent = jsonContent.replaceFirst('```', '').replaceFirst('```', '');
      }
      
      jsonContent = jsonContent.trim();
      
      // Parse the JSON array
      final List<dynamic> jsonArray = jsonDecode(jsonContent);
      
      return jsonArray.map((item) => SubtaskItem.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error parsing AI response: $e');
      print('Content: $content');
      throw Exception('Failed to parse AI response. Please try again.');
    }
  }

  Future<List<SubtaskItem>> expandTask({
    required String taskDescription,
    required String projectSummary,
    required bool isDevelopmentProject,
    String? techStack,
    String? preferredAI, // 'openai' or 'claude'
  }) async {
    try {
      // Load the appropriate prompt template
      final template = await _loadPromptTemplate(isDevelopmentProject);
      
      // Fill the template with actual values
      final prompt = _fillPromptTemplate(
        template,
        projectSummary: projectSummary,
        task: taskDescription,
        techStack: techStack,
      );

      // Choose AI service based on preference and availability
      final apiKeys = await _loadApiKeys();
      final hasOpenAI = apiKeys['OPENAI_API_KEY']?.isNotEmpty == true;
      final hasClaude = apiKeys['CLAUDE_API_KEY']?.isNotEmpty == true;

      if (preferredAI == 'claude' && hasClaude) {
        return await expandTaskWithClaude(prompt);
      } else if (preferredAI == 'openai' && hasOpenAI) {
        return await expandTaskWithOpenAI(prompt);
      } else if (hasOpenAI) {
        return await expandTaskWithOpenAI(prompt);
      } else if (hasClaude) {
        return await expandTaskWithClaude(prompt);
      } else {
        throw Exception('No API keys found. Please add OPENAI_API_KEY or CLAUDE_API_KEY to api_keys.txt file.');
      }
    } catch (e) {
      print('Error in expandTask: $e');
      rethrow;
    }
  }
} 