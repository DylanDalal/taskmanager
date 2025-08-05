import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'services/jira_service.dart';
import 'services/youtube_service.dart';

// Import the data models from main.dart
import 'main.dart';
import 'ui_project_details.dart';

// Widget definitions
class CreateProjectDialog extends StatefulWidget {
  final Function(Project, bool) onProjectCreated;
  final Function(Script)? onAddSharedScript;
  final Function(Script)? onUpdateSharedScript;
  final Function(String)? onRemoveSharedScript;
  final List<Script>? sharedScripts;

  const CreateProjectDialog({
    super.key,
    required this.onProjectCreated,
    this.onAddSharedScript,
    this.onUpdateSharedScript,
    this.onRemoveSharedScript,
    this.sharedScripts,
  });

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _projectSummaryController = TextEditingController();
  final _techStackController = TextEditingController();
  final _jiraProjectUrlController = TextEditingController();
  final _githubRepoPathController = TextEditingController();
  ProjectType _selectedType = ProjectType.general;
  bool _isProfessional = true;
  String? _setupScriptFileName;
  String? _setupScriptContent;
  final List<Script> _scripts = [];
  bool _youtubeLinked = false;

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
          setState(() {
            _scripts.add(projectScript);
          });
        },
      ),
    );
  }

  void _createProject() {
    if (_formKey.currentState!.validate()) {
      Project project;
      
      if (_selectedType == ProjectType.development) {
        project = DevelopmentProject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          projectSummary: _projectSummaryController.text.trim().isEmpty ? null : _projectSummaryController.text.trim(),
          techStack: _techStackController.text.trim().isEmpty ? null : _techStackController.text.trim(),
          color: Colors.grey[600]!,
          icon: Icons.code,
          jiraProjectUrl: _jiraProjectUrlController.text.trim().isEmpty ? null : _jiraProjectUrlController.text.trim(),
          githubRepoPath: _githubRepoPathController.text.trim().isEmpty ? null : _githubRepoPathController.text.trim(),
          setupScriptPath: _setupScriptFileName,
          setupScriptContent: _setupScriptContent,
          scripts: _scripts,
          createdAt: DateTime.now(),
        );
      } else if (_selectedType == ProjectType.youtube) {
        project = YouTubeProject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          projectSummary: _projectSummaryController.text.trim().isEmpty ? null : _projectSummaryController.text.trim(),
          techStack: _techStackController.text.trim().isEmpty ? null : _techStackController.text.trim(),
          color: Colors.red[600]!,
          icon: Icons.video_library,
          jiraProjectUrl: _jiraProjectUrlController.text.trim().isEmpty ? null : _jiraProjectUrlController.text.trim(),
          channelLink: '', // Will be set in project details
          scripts: _scripts,
          createdAt: DateTime.now(),
        );
      } else {
        project = Project(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          projectSummary: _projectSummaryController.text.trim().isEmpty ? null : _projectSummaryController.text.trim(),
          techStack: _techStackController.text.trim().isEmpty ? null : _techStackController.text.trim(),
          type: _selectedType,
          color: Colors.orange[600]!,
          icon: Icons.task,
          jiraProjectUrl: _jiraProjectUrlController.text.trim().isEmpty ? null : _jiraProjectUrlController.text.trim(),
          scripts: _scripts,
          createdAt: DateTime.now(),
        );
      }

      widget.onProjectCreated(project, _isProfessional);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Project'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ProjectType>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Project Type',
                    border: OutlineInputBorder(),
                  ),
                  items: ProjectType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(
                            type == ProjectType.development 
                                ? Icons.code 
                                : type == ProjectType.youtube 
                                  ? Icons.video_library 
                                  : Icons.task,
                            color: type == ProjectType.development 
                                ? Colors.grey[600] 
                                : type == ProjectType.youtube 
                                  ? Colors.red[600] 
                                  : Colors.orange[600],
                          ),
                          const SizedBox(width: 8),
                          Text(type.name.toUpperCase()),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Project Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a project name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _projectSummaryController,
                  decoration: const InputDecoration(
                    labelText: 'Project Summary (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Brief summary of the project goals and objectives',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                if (_selectedType == ProjectType.development) ...[
                  TextFormField(
                    controller: _techStackController,
                    decoration: const InputDecoration(
                      labelText: 'Tech Stack (optional)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Flutter, Dart, Firebase, REST APIs',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 16),
                if (_selectedType == ProjectType.youtube) ...[
                  // YouTube Channel Authentication Section
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red[400]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.video_library, color: Colors.red[600]),
                            const SizedBox(width: 8),
                            const Text(
                              'YouTube Channel Setup',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Link your YouTube channel to enable analytics tracking and video uploads',
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
                                final projectName = _nameController.text.trim();
                                if (projectName.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter a project name first'),
                                    ),
                                  );
                                  return;
                                }

                                // Show the credentials setup dialog
                                final result = await showDialog<Map<String, String>>(
                                  context: context,
                                  builder: (context) => _YouTubeCredentialsDialog(
                                    projectName: projectName,
                                  ),
                                );

                                // If credentials were successfully processed, proceed with authentication
                                if (result != null && context.mounted) {
                                  try {
                                    // Create the project first to get its ID, then authenticate
                                    final project = YouTubeProject(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      name: projectName,
                                      description: _descriptionController.text.trim(),
                                      projectSummary: _projectSummaryController.text.trim().isEmpty ? null : _projectSummaryController.text.trim(),
                                      techStack: _techStackController.text.trim().isEmpty ? null : _techStackController.text.trim(),
                                      color: Colors.red[600]!,
                                      icon: Icons.video_library,
                                      jiraProjectUrl: _jiraProjectUrlController.text.trim().isEmpty ? null : _jiraProjectUrlController.text.trim(),
                                      channelLink: '', // Will be set after authentication
                                      scripts: _scripts,
                                      createdAt: DateTime.now(),
                                    );
                                    
                                    final youtubeService = YouTubeService();
                                    
                                    final success = await youtubeService.authenticateProject(
                                      context, 
                                      project.id, 
                                      projectName,
                                    );
                                    
                                    if (success) {
                                      setState(() {
                                        _youtubeLinked = true;
                                      });
                                      
                                      // Create the project with the linked status
                                      widget.onProjectCreated(project, _isProfessional);
                                      Navigator.of(context).pop();
                                      
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('YouTube channel linked successfully for "$projectName"!'),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Failed to link YouTube channel'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Authentication error: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.link),
                              label: const Text('Link YouTube Channel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[600],
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _youtubeLinked ? 'Linked ✓' : 'Not linked',
                                style: TextStyle(
                                  color: _youtubeLinked ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _jiraProjectUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Jira Project URL (optional)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., https://company.atlassian.net/jira/software/projects/MOBILE/boards/1',
                      helperText: 'Copy URL from your Jira project page',
                    ),
                    maxLines: 2,
                  ),
                ],
                if (_selectedType == ProjectType.development) ...[
                  const SizedBox(height: 16),
                  TextFormField(
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _showSharedScriptsDialog,
                                icon: const Icon(Icons.folder_shared),
                                label: const Text('Shared'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add custom scripts or browse shared scripts that can be run within this project',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_scripts.isEmpty)
                        const Text(
                          'No scripts added yet. Add a custom script or browse shared scripts.',
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
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeScript(index),
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Project Category: '),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Professional'),
                      selected: _isProfessional,
                      onSelected: (selected) {
                        setState(() {
                          _isProfessional = selected;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Personal'),
                      selected: !_isProfessional,
                      onSelected: (selected) {
                        setState(() {
                          _isProfessional = !selected;
                        });
                      },
                    ),
                  ],
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
          onPressed: _createProject,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _YouTubeCredentialsDialog extends StatefulWidget {
  final String projectName;

  const _YouTubeCredentialsDialog({required this.projectName});

  @override
  State<_YouTubeCredentialsDialog> createState() => _YouTubeCredentialsDialogState();
}

class _YouTubeCredentialsDialogState extends State<_YouTubeCredentialsDialog> {
  String? _selectedFilePath;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.video_library, color: Colors.red[600]),
          const SizedBox(width: 8),
          const Text('YouTube Channel Setup'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[200]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[200]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: TextStyle(color: Colors.green[700]),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'To link your YouTube channel, you need to provide your OAuth credentials:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📋 Get Your OAuth Credentials:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                                  const Text('1. Go to Google Cloud Console'),
                  const Text('2. Create a new project (or use existing)'),
                  const Text('   • Enable YouTube Data API v3 (APIs & Services > Library > YouTube Data API v3)'),
                  const Text('3. Configure OAuth consent screen:'),
                  const Text('   • Go to "APIs & Services" > "OAuth consent screen"'),
                  const Text('   • Choose "Testing" mode (not Production)'),
                  const Text('   • Add your email as a test user (Audience > Test users)'),
                  const Text('   • Add these scopes to your app:'),
                  SelectableText(
                    '     • https://www.googleapis.com/auth/youtube.readonly',
                    style: const TextStyle(fontSize: 12),
                  ),
                  SelectableText(
                    '     • https://www.googleapis.com/auth/youtube.upload',
                    style: const TextStyle(fontSize: 12),
                  ),
                  SelectableText(
                    '     • https://www.googleapis.com/auth/yt-analytics.readonly',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Text('4. Create OAuth 2.0 credentials:'),
                  const Text('   • Go to "APIs & Services" > "Credentials"'),
                  const Text('   • Click "Create Credentials" > "OAuth 2.0 Client IDs"'),
                  const Text('   • Choose "Desktop application"'),
                  const Text('   • Download the JSON file'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _selectCredentialsFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Select Credentials File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                if (_selectedFilePath != null)
                  Expanded(
                    child: Text(
                      '✓ ${_selectedFilePath!.split('/').last}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            if (_selectedFilePath != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _processCredentials,
                  icon: _isProcessing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                  label: Text(_isProcessing ? 'Processing...' : 'Link YouTube Channel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                  ),
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
      ],
    );
  }

  Future<void> _selectCredentialsFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select YouTube OAuth Credentials JSON File',
      );

      if (result != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _errorMessage = null;
          _successMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error selecting file: $e';
      });
    }
  }

  Future<void> _processCredentials() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Read and parse the JSON file directly in Dart
      final file = File(_selectedFilePath!);
      if (!await file.exists()) {
        throw Exception('Selected file does not exist');
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Handle different credential file formats
      Map<String, dynamic> credentials;
      if (data.containsKey('installed')) {
        // Desktop application credentials
        credentials = data['installed'];
      } else if (data.containsKey('web')) {
        // Web application credentials
        credentials = data['web'];
      } else {
        // Direct credentials object
        credentials = data;
      }

      final clientId = credentials['client_id'];
      final clientSecret = credentials['client_secret'];

      if (clientId == null || clientSecret == null) {
        throw Exception('Could not find client_id or client_secret in the credentials file');
      }

      // Add credentials to api_keys.txt
      final youtubeService = YouTubeService();
      youtubeService.setProjectCredentials(widget.projectName, clientId, clientSecret);

      setState(() {
        _successMessage = 'Credentials extracted and saved successfully!';
      });

      // Wait a moment to show success message, then proceed with authentication
      await Future.delayed(const Duration(seconds: 1));

      // Close this dialog and proceed with authentication
      if (mounted) {
        Navigator.of(context).pop(<String, String>{
          'projectName': widget.projectName,
          'clientId': clientId.toString(),
          'clientSecret': clientSecret.toString(),
        });
      }

    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing credentials: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}

class ProjectCard extends StatelessWidget {
  final Project project;
  final List<Task> jiraIssues;
  final Function(Project) onProjectUpdated;
  final Function(String) onDeleteProject;
  final Function(Task, Project) onAddToSchedule;
  final Function(Project) onFetchJiraIssues;
  final List<Project> professionalProjects;
  final List<Project> personalProjects;
  final List<ScheduledTask> scheduledTasks;
  final Function(ScheduledTask) onRemoveTask;
  final Function(ScheduledTask) onOpenTaskDetail;
  final Function(ProjectDetailPage)? onScheduleUpdated;
  final Function(Function()) onRegisterScheduleUpdate;
  final Function(Function()) onUnregisterScheduleUpdate;
  final Function(Project)? onProjectSelected;

  const ProjectCard({
    super.key,
    required this.project,
    required this.jiraIssues,
    required this.onProjectUpdated,
    required this.onDeleteProject,
    required this.onAddToSchedule,
    required this.onFetchJiraIssues,
    required this.professionalProjects,
    required this.personalProjects,
    required this.scheduledTasks,
    required this.onRemoveTask,
    required this.onOpenTaskDetail,
    this.onScheduleUpdated,
    required this.onRegisterScheduleUpdate,
    required this.onUnregisterScheduleUpdate,
    this.onProjectSelected,
  });

  @override
  Widget build(BuildContext context) {
    final progressPercentage = project.getProgressPercentage(jiraIssues);
    final sprintProgress = project.getSprintProgressPercentage(jiraIssues);
    final currentSprintName = project.getCurrentSprintName(jiraIssues);
    final sprintIssueCount = project.getSprintIssueCount(jiraIssues);
    final completedSprintIssues = project.getCompletedSprintIssueCount(jiraIssues);

    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          onProjectSelected?.call(project);
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    project.icon,
                    color: project.color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditProjectDialog(context);
                      } else if (value == 'delete') {
                        _showDeleteConfirmation(context);
                      } else if (value == 'refresh_jira') {
                        onFetchJiraIssues(project);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      if (project.jiraProjectUrl != null)
                        const PopupMenuItem(
                          value: 'refresh_jira',
                          child: Row(
                            children: [
                              Icon(Icons.refresh),
                              SizedBox(width: 8),
                              Text('Refresh Jira'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                project.description,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 9,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 150,
                    width: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularPercentIndicator(
                          radius: 60,
                          lineWidth: 12,
                          percent: progressPercentage / 100,
                          backgroundColor: Colors.grey[400]!,
                          progressColor: Colors.blue[400]!,
                          center: Container(),
                        ),
                        if (currentSprintName != null)
                          CircularPercentIndicator(
                            radius: 60,
                            lineWidth: 6,
                            percent: sprintProgress / 100,
                            backgroundColor: Colors.transparent,
                            progressColor: const Color(0xFFd5f6fe),
                            center: Container(),
                          ),
                        Text(
                          '${progressPercentage.toInt()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 2,
                                color: Colors.black26,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  void _showEditProjectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditProjectDialog(
        project: project,
        onProjectUpdated: onProjectUpdated,
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Are you sure you want to delete "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onDeleteProject(project.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
} 

// New widget to display a grid of projects
class ProjectGrid extends StatelessWidget {
  final List<Project> projects;
  final bool isProfessional;
  final Map<String, List<Task>> projectJiraIssues;
  final Function(Project) onUpdateProject;
  final Function(String) onDeleteProject;
  final Function(Task, Project) onAddTaskToSchedule;
  final Function(Project) onFetchJiraIssues;
  final List<Project> professionalProjects;
  final List<Project> personalProjects;
  final List<ScheduledTask> scheduledTasks;
  final Function(ScheduledTask) onRemoveTask;
  final Function(ScheduledTask) onOpenTaskDetail;
  final Function(ProjectDetailPage)? onScheduleUpdated;
  final Function(Function()) onRegisterScheduleUpdate;
  final Function(Function()) onUnregisterScheduleUpdate;
  final Function(Project)? onProjectSelected;

  const ProjectGrid({
    super.key,
    required this.projects,
    required this.isProfessional,
    required this.projectJiraIssues,
    required this.onUpdateProject,
    required this.onDeleteProject,
    required this.onAddTaskToSchedule,
    required this.onFetchJiraIssues,
    required this.professionalProjects,
    required this.personalProjects,
    required this.scheduledTasks,
    required this.onRemoveTask,
    required this.onOpenTaskDetail,
    this.onScheduleUpdated,
    required this.onRegisterScheduleUpdate,
    required this.onUnregisterScheduleUpdate,
    this.onProjectSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isProfessional ? Icons.business : Icons.person,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${isProfessional ? 'Professional' : 'Personal'} Projects',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first project to get started',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine number of columns: 3 by default, 2 when width < 80% of 1200 (~960)
        final screenWidth = MediaQuery.of(context).size.width;
        // Use 80% of full screen width as threshold
        final threshold = screenWidth * 0.5;
        final columns = constraints.maxWidth < threshold ? 2 : 3;

        // Adjust aspect ratio slightly for different column counts
        final aspectRatio = columns == 3 ? 0.9 : 1.2;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: aspectRatio,
          ),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            final jiraIssues = projectJiraIssues[project.id] ?? [];
            return ProjectCard(
              project: project,
              jiraIssues: jiraIssues,
              onProjectUpdated: onUpdateProject,
              onDeleteProject: onDeleteProject,
              onAddToSchedule: onAddTaskToSchedule,
              onFetchJiraIssues: onFetchJiraIssues,
              professionalProjects: professionalProjects,
              personalProjects: personalProjects,
              scheduledTasks: scheduledTasks,
              onRemoveTask: onRemoveTask,
              onOpenTaskDetail: onOpenTaskDetail,
              onScheduleUpdated: onScheduleUpdated,
              onRegisterScheduleUpdate: onRegisterScheduleUpdate,
              onUnregisterScheduleUpdate: onUnregisterScheduleUpdate,
              onProjectSelected: onProjectSelected,
            );
          },
        );
      },
    );
  }
} 