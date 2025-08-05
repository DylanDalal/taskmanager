import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'services/youtube_service.dart';
import 'services/youtube_analytics_service.dart';
import 'services/jira_service.dart';
import 'main.dart';
import 'ui_task_details.dart';

class YouTubeProjectDetailsPage extends StatefulWidget {
  final YouTubeProject project;
  final Function(YouTubeProject)? onProjectUpdated;
  final Function(Task, YouTubeProject)? onAddToSchedule;

  const YouTubeProjectDetailsPage({
    super.key,
    required this.project,
    this.onProjectUpdated,
    this.onAddToSchedule,
  });

  @override
  State<YouTubeProjectDetailsPage> createState() => _YouTubeProjectDetailsPageState();
}

class _YouTubeProjectDetailsPageState extends State<YouTubeProjectDetailsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final YouTubeService _youtubeService = YouTubeService();
  final YouTubeAnalyticsService _analyticsService = YouTubeAnalyticsService();
  
  bool _isLoading = false;
  bool _isAuthenticated = false;
  Map<String, dynamic> _channelInfo = {};
  Map<String, dynamic> _analyticsSummary = {};
  List<Map<String, dynamic>> _analyticsHistory = [];
  List<Map<String, dynamic>> _uploadHistory = [];
  
  // Upload form controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  String _selectedPrivacy = 'private';
  String? _selectedVideoPath;
  DateTime? _scheduledTime;
  
  // Task management
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    
    try {
      await _youtubeService.initializeProject(widget.project.id, widget.project.name);
      _isAuthenticated = _youtubeService.isProjectAuthenticated(widget.project.id);
      
      // Load project tasks
      _tasks = widget.project.tasks;
      
      if (_isAuthenticated) {
        await _loadChannelData();
        await _loadAnalyticsData();
        await _loadUploadHistory();
      }
    } catch (e) {
      print('Error initializing data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChannelData() async {
    try {
      final channel = await _youtubeService.getProjectChannelInfo(widget.project.id);
      if (channel != null) {
        setState(() {
          _channelInfo = {
            'id': channel.id,
            'title': channel.snippet?.title,
            'description': channel.snippet?.description,
            'subscriberCount': channel.statistics?.subscriberCount,
            'videoCount': channel.statistics?.videoCount,
            'viewCount': channel.statistics?.viewCount,
            'thumbnails': {
              'default': channel.snippet?.thumbnails?.default_?.url,
              'medium': channel.snippet?.thumbnails?.medium?.url,
              'high': channel.snippet?.thumbnails?.high?.url,
            },
          };
        });
      }
    } catch (e) {
      print('Error loading channel data: $e');
    }
  }

  Future<void> _loadAnalyticsData() async {
    try {
      _analyticsSummary = await _analyticsService.getAnalyticsSummary(widget.project.id);
      _analyticsHistory = await _analyticsService.getAnalyticsHistory(widget.project.id);
      setState(() {});
    } catch (e) {
      print('Error loading analytics data: $e');
    }
  }

  Future<void> _loadUploadHistory() async {
    try {
      _uploadHistory = await _analyticsService.getUploadHistory(widget.project.id);
      setState(() {});
    } catch (e) {
      print('Error loading upload history: $e');
    }
  }

  Future<void> _authenticateWithYouTube() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await _youtubeService.authenticateProject(context, widget.project.id, widget.project.name);
      if (success) {
        setState(() => _isAuthenticated = true);
        await _loadChannelData();
        await _loadAnalyticsData();
        
        // Schedule weekly analytics
        await _analyticsService.scheduleWeeklyAnalytics(
          widget.project.id,
          widget.project.name,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('YouTube channel linked successfully for "${widget.project.name}"!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to link YouTube channel')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _collectAnalyticsNow() async {
    setState(() => _isLoading = true);
    
    try {
      await _analyticsService.collectAnalytics(widget.project.id, widget.project.name);
      await _loadAnalyticsData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analytics collected successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error collecting analytics: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectVideoFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedVideoPath = result.files.single.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting video: $e')),
      );
    }
  }

  Future<void> _uploadVideo() async {
    if (_selectedVideoPath == null || _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video and enter a title')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final tags = _tagsController.text.isNotEmpty 
          ? _tagsController.text.split(',').map((tag) => tag.trim()).toList()
          : <String>[];

      await _analyticsService.scheduleVideoUpload(
        projectId: widget.project.id,
        projectName: widget.project.name,
        videoPath: _selectedVideoPath!,
        title: _titleController.text,
        description: _descriptionController.text,
        tags: tags,
        privacyStatus: _selectedPrivacy,
        scheduledTime: _scheduledTime,
      );

      // Clear form
      _titleController.clear();
      _descriptionController.clear();
      _tagsController.clear();
      _selectedVideoPath = null;
      _scheduledTime = null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video upload scheduled successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scheduling upload: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        backgroundColor: widget.project.color,
        foregroundColor: Colors.white,
        actions: [
          if (_isAuthenticated) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _collectAnalyticsNow,
              tooltip: 'Refresh Analytics',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await _youtubeService.logoutProject(widget.project.id);
                setState(() => _isAuthenticated = false);
              },
              tooltip: 'Disconnect YouTube',
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.upload), text: 'Upload'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildAnalyticsTab(),
                _buildUploadTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    if (!_isAuthenticated) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'YouTube Channel Not Linked',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Link your YouTube channel to start tracking analytics and uploading videos',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _authenticateWithYouTube,
              icon: const Icon(Icons.link),
              label: const Text('Link YouTube Channel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel Info Card with Stats Row
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Channel Icon
                  if (_channelInfo['thumbnails'] != null && 
                      _channelInfo['thumbnails']['default'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _channelInfo['thumbnails']['default'],
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.image, color: Colors.grey),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.video_library, color: Colors.grey),
                    ),
                  const SizedBox(width: 16),
                  
                  // Channel Name
                  Expanded(
                    child: Text(
                      _channelInfo['title'] ?? 'Unknown Channel',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  // Stats in a row
                  Row(
                    children: [
                      _buildInlineStatCard(
                        'Subscribers',
                        (_channelInfo['subscriberCount'] ?? '0').toString(),
                        Icons.people,
                        Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _buildInlineStatCard(
                        'Views',
                        _formatNumber((_channelInfo['viewCount'] ?? '0').toString()),
                        Icons.visibility,
                        Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      _buildInlineStatCard(
                        'Videos',
                        (_channelInfo['videoCount'] ?? '0').toString(),
                        Icons.video_library,
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _buildInlineStatCard(
                        'Analytics Points',
                        (_analyticsHistory.length).toString(),
                        Icons.analytics,
                        Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Quick Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _collectAnalyticsNow,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh Analytics'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _tabController.animateTo(2),
                          icon: const Icon(Icons.upload),
                          label: const Text('Upload Video'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showAddTaskDialog,
                          icon: const Icon(Icons.add_task),
                          label: const Text('Add Task'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _tabController.animateTo(3),
                          icon: const Icon(Icons.history),
                          label: const Text('View History'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Tasks Section
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.task_alt,
                            size: 20,
                            color: widget.project.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Tasks',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddTaskDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.project.color,
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
                  const SizedBox(height: 16),
                  if (_tasks.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.assignment,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No tasks yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add tasks for video ideas, editing notes, and reminders',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showAddTaskDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.project.color,
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
                    )
                  else
                    ..._getSortedTasks().map((task) => _buildTaskCard(task)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (!_isAuthenticated) {
      return const Center(child: Text('Please link your YouTube channel first'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_analyticsSummary.isNotEmpty) ...[
            // Trends Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Growth Trends',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTrendCard(
                            'Subscribers',
                            (_analyticsSummary['trends']?['subscriberGrowth'] ?? 0).toString(),
                            (_analyticsSummary['trends']?['subscriberGrowthPercent'] ?? 0).toString(),
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTrendCard(
                            'Views',
                            (_analyticsSummary['trends']?['viewGrowth'] ?? 0).toString(),
                            (_analyticsSummary['trends']?['viewGrowthPercent'] ?? 0).toString(),
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Analytics History
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analytics History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_analyticsHistory.isEmpty)
                    const Center(
                      child: Text(
                        'No analytics data available yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ..._analyticsHistory.reversed.take(10).map((snapshot) {
                      final data = snapshot['data'] as Map<String, dynamic>;
                      final timestamp = DateTime.parse(snapshot['timestamp']);
                      
                      return ListTile(
                        leading: const Icon(Icons.analytics),
                        title: Text('${data['subscriberCount'] ?? '0'} subscribers'),
                        subtitle: Text('${data['viewCount'] ?? '0'} total views'),
                        trailing: Text(
                          DateFormat('MMM dd, yyyy').format(timestamp),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadTab() {
    if (!_isAuthenticated) {
      return const Center(child: Text('Please link your YouTube channel first'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload Video',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Video File Selection
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Video File'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _selectVideoFile,
                              icon: const Icon(Icons.video_file),
                              label: const Text('Select Video'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedVideoPath ?? 'No video selected',
                                style: TextStyle(
                                  color: _selectedVideoPath != null ? Colors.green : Colors.grey,
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
                  
                  // Video Details
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Video Title *',
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
                  
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma-separated)',
                      border: OutlineInputBorder(),
                      hintText: 'tag1, tag2, tag3',
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Privacy Settings
                  DropdownButtonFormField<String>(
                    value: _selectedPrivacy,
                    decoration: const InputDecoration(
                      labelText: 'Privacy',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'private', child: Text('Private')),
                      DropdownMenuItem(value: 'unlisted', child: Text('Unlisted')),
                      DropdownMenuItem(value: 'public', child: Text('Public')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedPrivacy = value!);
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Upload Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _uploadVideo,
                      icon: const Icon(Icons.upload),
                      label: const Text('Upload Video'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (!_isAuthenticated) {
      return const Center(child: Text('Please link your YouTube channel first'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upload History
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_uploadHistory.isEmpty)
                    const Center(
                      child: Text(
                        'No uploads yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ..._uploadHistory.map((upload) {
                      final timestamp = DateTime.parse(upload['uploadedAt']);
                      
                      return ListTile(
                        leading: const Icon(Icons.video_file),
                        title: Text(upload['title']),
                        subtitle: Text('Uploaded on ${DateFormat('MMM dd, yyyy').format(timestamp)}'),
                        trailing: const Icon(Icons.check_circle, color: Colors.green),
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineStatCard(String title, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTrendCard(String title, String change, String percent, Color color) {
    final isPositive = (double.tryParse(percent) ?? 0) >= 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              change,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            Text(
              '${isPositive ? '+' : ''}$percent%',
              style: TextStyle(
                color: isPositive ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(String number) {
    final num = int.tryParse(number) ?? 0;
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return num.toString();
  }

  // Task management methods
  void _addTask(Task task) {
    setState(() {
      _tasks = [..._tasks, task];
    });
    // Update the project with new tasks
    final updatedProject = widget.project.copyWith(tasks: _tasks);
    widget.onProjectUpdated?.call(updatedProject);
  }

  void _toggleTaskCompletion(Task task) {
    setState(() {
      _tasks = _tasks.map((t) {
        if (t.id == task.id) {
          return t.copyWith(isCompleted: !t.isCompleted);
        }
        return t;
      }).toList();
    });
    // Update the project with updated tasks
    final updatedProject = widget.project.copyWith(tasks: _tasks);
    widget.onProjectUpdated?.call(updatedProject);
  }

  void _showAddTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => AddTaskDialog(
        projectId: widget.project.id,
        onTaskCreated: _addTask,
        hasJiraIntegration: false, // YouTube projects don't have Jira integration
      ),
    );
  }

  void _openTaskDetail(Task task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskDetailPage(
          task: task,
          project: widget.project,
          onTaskUpdated: (updatedTask) {
            setState(() {
              _tasks = _tasks.map((t) {
                if (t.id == task.id) {
                  return updatedTask;
                }
                return t;
              }).toList();
            });
            // Update the project with updated tasks
            final updatedProject = widget.project.copyWith(tasks: _tasks);
            widget.onProjectUpdated?.call(updatedProject);
          },
          onTaskDeleted: (deletedTask) {
            setState(() {
              _tasks = _tasks.where((t) => t.id != deletedTask.id).toList();
            });
            // Update the project with updated tasks
            final updatedProject = widget.project.copyWith(tasks: _tasks);
            widget.onProjectUpdated?.call(updatedProject);
          },
        ),
      ),
    );
  }

  List<Task> _getSortedTasks() {
    final sortedTasks = List<Task>.from(_tasks);
    sortedTasks.sort((a, b) {
      // Check if either task is completed
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      
      // For non-completed tasks, sort by priority (Critical to Low)
      if (!a.isCompleted && !b.isCompleted) {
        final aPriority = _getPriorityValue(a.priorityEnum);
        final bPriority = _getPriorityValue(b.priorityEnum);
        return bPriority.compareTo(aPriority); // Highest to lowest
      }
      
      // For completed tasks, also sort by priority but they're already at bottom
      final aPriority = _getPriorityValue(a.priorityEnum);
      final bPriority = _getPriorityValue(b.priorityEnum);
      return bPriority.compareTo(aPriority); // Highest to lowest
    });
    return sortedTasks;
  }

  int _getPriorityValue(Priority priority) {
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

  bool isEmailTask(String? description) {
    return description?.toLowerCase().contains('email') == true ||
           description?.toLowerCase().contains('mail') == true;
  }

  bool isVideoTask(String? description) {
    return description?.toLowerCase().contains('video') == true ||
           description?.toLowerCase().contains('publish') == true ||
           description?.toLowerCase().contains('upload') == true;
  }

  Widget _buildTaskCard(Task task) {
    final isEmailTaskType = isEmailTask(task.description);
    final isVideoTaskType = isVideoTask(task.description);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: task.isCompleted ? Colors.grey[100] : const Color(0xFF1E1E1E),
      child: ListTile(
        onTap: () => _openTaskDetail(task),
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
            color: task.isCompleted ? Colors.grey[600] : Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description?.isNotEmpty == true) ...[
              Text(
                task.description ?? '',
                style: TextStyle(
                  color: task.isCompleted ? Colors.grey[500] : Colors.grey[300],
                ),
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
                  onPressed: () => widget.onAddToSchedule?.call(task, widget.project),
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
} 