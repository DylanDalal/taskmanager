import 'dart:convert';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'youtube_service.dart';

class YouTubeAnalyticsService {
  static const String _analyticsTaskName = 'youtube_analytics_task';
  static const String _uploadTaskName = 'youtube_upload_task';
  
  static final YouTubeAnalyticsService _instance = YouTubeAnalyticsService._internal();
  factory YouTubeAnalyticsService() => _instance;
  YouTubeAnalyticsService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final YouTubeService _youtubeService = YouTubeService();
  bool _notificationsInitialized = false;

  // Initialize the service
  Future<void> initialize() async {
    await _initializeNotifications();
    await _initializeWorkManager();
  }

  // Initialize a specific project
  Future<void> initializeProject(String projectId, String projectName) async {
    await _youtubeService.initializeProject(projectId, projectName);
  }

  // Initialize local notifications
  Future<void> _initializeNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(initSettings);
      
      // Check notification permissions on iOS
      if (Platform.isIOS) {
        final settings = await _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        print('iOS notification permissions: $settings');
      }
      
      _notificationsInitialized = true;
    } catch (e) {
      print('Error initializing notifications: $e');
      // Continue without notifications if initialization fails
      _notificationsInitialized = false;
    }
  }

  // Initialize WorkManager for background tasks
  Future<void> _initializeWorkManager() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
  }

  // Schedule weekly analytics collection
  Future<void> scheduleWeeklyAnalytics(String projectId, String projectName) async {
    await Workmanager().registerPeriodicTask(
      '${_analyticsTaskName}_$projectId',
      _analyticsTaskName,
      frequency: const Duration(days: 7),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      inputData: {
        'projectId': projectId,
        'projectName': projectName,
      },
    );
  }

  // Schedule video upload task
  Future<void> scheduleVideoUpload({
    required String projectId,
    required String projectName,
    required String videoPath,
    required String title,
    required String description,
    List<String> tags = const [],
    String privacyStatus = 'private',
    DateTime? scheduledTime,
  }) async {
    final delay = scheduledTime?.difference(DateTime.now()) ?? Duration.zero;
    
    if (delay.isNegative) {
      // Upload immediately if scheduled time has passed
      await _uploadVideoImmediately(
        projectId: projectId,
        projectName: projectName,
        videoPath: videoPath,
        title: title,
        description: description,
        tags: tags,
        privacyStatus: privacyStatus,
      );
    } else {
      // Schedule for later
      await Workmanager().registerOneOffTask(
        '${_uploadTaskName}_${DateTime.now().millisecondsSinceEpoch}',
        _uploadTaskName,
        initialDelay: delay,
        inputData: {
          'projectId': projectId,
          'projectName': projectName,
          'videoPath': videoPath,
          'title': title,
          'description': description,
          'tags': jsonEncode(tags),
          'privacyStatus': privacyStatus,
        },
      );
    }
  }

  // Upload video immediately
  Future<void> _uploadVideoImmediately({
    required String projectId,
    required String projectName,
    required String videoPath,
    required String title,
    required String description,
    List<String> tags = const [],
    String privacyStatus = 'private',
  }) async {
    try {
      if (!_youtubeService.isProjectAuthenticated(projectId)) {
        await _showNotification(
          'YouTube Upload Failed',
          'Please authenticate with YouTube for project "$projectName" first',
        );
        return;
      }

      final videoId = await _youtubeService.uploadProjectVideo(
        projectId: projectId,
        filePath: videoPath,
        title: title,
        description: description,
        tags: tags,
        privacyStatus: privacyStatus,
      );

      if (videoId != null) {
        await _showNotification(
          'Video Uploaded Successfully',
          'Video "$title" has been uploaded to YouTube for project "$projectName"',
        );
        
        // Save upload record
        await _saveUploadRecord(projectId, videoId, title, videoPath);
      } else {
        await _showNotification(
          'Upload Failed',
          'Failed to upload video "$title" for project "$projectName"',
        );
      }
    } catch (e) {
      await _showNotification(
        'Upload Error',
        'Error uploading video for project "$projectName": $e',
      );
    }
  }

  // Save upload record
  Future<void> _saveUploadRecord(String projectId, String videoId, String title, String videoPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final uploadsFile = File('${dir.path}/youtube_uploads.json');
      
      List<Map<String, dynamic>> uploads = [];
      if (await uploadsFile.exists()) {
        final content = await uploadsFile.readAsString();
        uploads = List<Map<String, dynamic>>.from(jsonDecode(content));
      }
      
      uploads.add({
        'projectId': projectId,
        'videoId': videoId,
        'title': title,
        'videoPath': videoPath,
        'uploadedAt': DateTime.now().toIso8601String(),
      });
      
      await uploadsFile.writeAsString(jsonEncode(uploads));
    } catch (e) {
      print('Error saving upload record: $e');
    }
  }

  // Collect analytics data
  Future<void> collectAnalytics(String projectId, String projectName) async {
    try {
      if (!_youtubeService.isProjectAuthenticated(projectId)) {
        print('Analytics Collection Failed: Please authenticate with YouTube for project "$projectName" first');
        // Temporarily disable notifications to prevent crashes
        // await _showNotification(
        //   'Analytics Collection Failed',
        //   'Please authenticate with YouTube for project "$projectName" first',
        // );
        return;
      }

      final analytics = await _youtubeService.getProjectChannelAnalytics(projectId);
      
      if (analytics.isNotEmpty) {
        await _saveAnalyticsSnapshot(projectId, analytics);
        print('Analytics Updated: Channel analytics for "$projectName" have been updated');
        // Temporarily disable notifications to prevent crashes
        // await _showNotification(
        //   'Analytics Updated',
        //   'Channel analytics for "$projectName" have been updated',
        // );
      } else {
        print('Analytics Collection Failed: No analytics data available for "$projectName"');
        // Temporarily disable notifications to prevent crashes
        // await _showNotification(
        //   'Analytics Collection Failed',
        //   'No analytics data available for "$projectName"',
        // );
      }
    } catch (e) {
      print('Error collecting analytics: $e');
      // Temporarily disable notifications to prevent crashes
      // try {
      //   await _showNotification(
      //     'Analytics Error',
      //     'Error collecting analytics for project "$projectName": $e',
      //   );
      // } catch (notificationError) {
      //   print('Error showing notification: $notificationError');
      //   // Analytics collection succeeded but notification failed - this is okay
      // }
    }
  }

  // Save analytics snapshot
  Future<void> _saveAnalyticsSnapshot(String projectId, Map<String, dynamic> analytics) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final analyticsFile = File('${dir.path}/youtube_analytics_$projectId.json');
      
      List<Map<String, dynamic>> snapshots = [];
      if (await analyticsFile.exists()) {
        final content = await analyticsFile.readAsString();
        snapshots = List<Map<String, dynamic>>.from(jsonDecode(content));
      }
      
      snapshots.add({
        'timestamp': DateTime.now().toIso8601String(),
        'data': analytics,
      });
      
      // Keep only last 52 weeks of data (1 year)
      if (snapshots.length > 52) {
        snapshots = snapshots.sublist(snapshots.length - 52);
      }
      
      await analyticsFile.writeAsString(jsonEncode(snapshots));
    } catch (e) {
      print('Error saving analytics snapshot: $e');
    }
  }

  // Get analytics history
  Future<List<Map<String, dynamic>>> getAnalyticsHistory(String projectId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final analyticsFile = File('${dir.path}/youtube_analytics_$projectId.json');
      
      if (await analyticsFile.exists()) {
        final content = await analyticsFile.readAsString();
        return List<Map<String, dynamic>>.from(jsonDecode(content));
      }
      return [];
    } catch (e) {
      print('Error loading analytics history: $e');
      return [];
    }
  }

  // Get upload history
  Future<List<Map<String, dynamic>>> getUploadHistory(String projectId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final uploadsFile = File('${dir.path}/youtube_uploads.json');
      
      if (await uploadsFile.exists()) {
        final content = await uploadsFile.readAsString();
        final allUploads = List<Map<String, dynamic>>.from(jsonDecode(content));
        return allUploads.where((upload) => upload['projectId'] == projectId).toList();
      }
      return [];
    } catch (e) {
      print('Error loading upload history: $e');
      return [];
    }
  }

  // Show notification
  Future<void> _showNotification(String title, String body) async {
    if (!_notificationsInitialized) {
      print('Notifications not initialized, skipping: $title - $body');
      return;
    }
    
    try {
      const androidDetails = AndroidNotificationDetails(
        'youtube_service',
        'YouTube Service',
        channelDescription: 'Notifications from YouTube analytics and upload service',
        importance: Importance.high,
        priority: Priority.high,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
      );
    } catch (e) {
      print('Error showing notification: $e');
      // Continue without showing notification if it fails
      // This prevents the app from crashing when notification permissions are denied
    }
  }

  // Cancel scheduled tasks for a project
  Future<void> cancelScheduledTasks(String projectId) async {
    await Workmanager().cancelByUniqueName('${_analyticsTaskName}_$projectId');
  }

  // Get analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary(String projectId) async {
    final history = await getAnalyticsHistory(projectId);
    if (history.isEmpty) return {};

    final latest = history.last['data'] as Map<String, dynamic>;
    final previous = history.length > 1 ? history[history.length - 2]['data'] as Map<String, dynamic> : null;

    final summary = <String, dynamic>{
      'current': latest,
      'trends': {},
    };

    if (previous != null) {
      final currentSubs = int.tryParse(latest['subscriberCount'] ?? '0') ?? 0;
      final previousSubs = int.tryParse(previous['subscriberCount'] ?? '0') ?? 0;
      final currentViews = int.tryParse(latest['viewCount'] ?? '0') ?? 0;
      final previousViews = int.tryParse(previous['viewCount'] ?? '0') ?? 0;

      summary['trends'] = {
        'subscriberGrowth': currentSubs - previousSubs,
        'viewGrowth': currentViews - previousViews,
        'subscriberGrowthPercent': previousSubs > 0 ? ((currentSubs - previousSubs) / previousSubs * 100).toStringAsFixed(1) : '0',
        'viewGrowthPercent': previousViews > 0 ? ((currentViews - previousViews) / previousViews * 100).toStringAsFixed(1) : '0',
      };
    }

    return summary;
  }
}

// Background task callback for analytics collection
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName.startsWith('youtube_analytics_task')) {
        final projectId = inputData?['projectId'] as String?;
        final projectName = inputData?['projectName'] as String?;
        
        if (projectId != null && projectName != null) {
          final analyticsService = YouTubeAnalyticsService();
          await analyticsService.collectAnalytics(projectId, projectName);
        }
      } else if (taskName.startsWith('youtube_upload_task')) {
        final projectId = inputData?['projectId'] as String?;
        final projectName = inputData?['projectName'] as String?;
        final videoPath = inputData?['videoPath'] as String?;
        final title = inputData?['title'] as String?;
        final description = inputData?['description'] as String?;
        final tagsJson = inputData?['tags'] as String?;
        final privacyStatus = inputData?['privacyStatus'] as String?;
        
        if (projectId != null && projectName != null && videoPath != null && 
            title != null && description != null) {
          final tags = tagsJson != null ? List<String>.from(jsonDecode(tagsJson)) : [];
          
          final analyticsService = YouTubeAnalyticsService();
          await analyticsService._uploadVideoImmediately(
            projectId: projectId,
            projectName: projectName,
            videoPath: videoPath,
            title: title,
            description: description,
            tags: tags.cast<String>(),
            privacyStatus: privacyStatus ?? 'private',
          );
        }
      }
      return true;
    } catch (e) {
      print('Background task error: $e');
      return false;
    }
  });
} 