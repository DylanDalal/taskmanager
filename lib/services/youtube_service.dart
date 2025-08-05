import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// Top-level project-specific data class
class _ProjectYouTubeData {
  youtube.YouTubeApi? youtubeApi;
  AccessToken? accessToken;
  String? refreshToken;
  String? channelId;
}

class YouTubeService {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/youtube.readonly',
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/yt-analytics.readonly',
  ];

  static const String _redirectUri = 'http://localhost:8080/callback';
  static const String _authEndpoint = 'https://accounts.google.com/o/oauth2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  // Project-specific instances
  final Map<String, _ProjectYouTubeData> _projectData = {};

  // Get project-specific data
  _ProjectYouTubeData _getProjectData(String projectId) {
    if (!_projectData.containsKey(projectId)) {
      _projectData[projectId] = _ProjectYouTubeData();
    }
    return _projectData[projectId]!;
  }

  // Make this public
  Map<String, String?> getProjectCredentials(String projectId, String projectName) {
    try {
      final file = File('api_keys.txt');
      if (!file.existsSync()) return {'client_id': null, 'client_secret': null};
      
      final contents = file.readAsStringSync();
      final lines = contents.split('\n');
      final clientIdKey = '${projectName}_YouTube_Client_ID';
      final clientSecretKey = '${projectName}_YouTube_Client_Secret';
      
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

  // Make this public
  void setProjectCredentials(String projectName, String clientId, String clientSecret) {
    try {
      final file = File('api_keys.txt');
      final clientIdKey = '${projectName}_YouTube_Client_ID';
      final clientSecretKey = '${projectName}_YouTube_Client_Secret';
      
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
      print('Error saving YouTube credentials: $e');
    }
  }

  // Get YouTube API instance for a specific project
  youtube.YouTubeApi? getYouTubeApi(String projectId) {
    return _getProjectData(projectId).youtubeApi;
  }

  // Check if a project is authenticated
  bool isProjectAuthenticated(String projectId) {
    final data = _getProjectData(projectId);
    return data.youtubeApi != null && data.accessToken != null;
  }

  // Get channel ID for a specific project
  String? getProjectChannelId(String projectId) {
    return _getProjectData(projectId).channelId;
  }

  // Initialize the service for a specific project
  Future<void> initializeProject(String projectId, String projectName) async {
    await _loadProjectTokens(projectId, projectName);
    final data = _getProjectData(projectId);
    if (data.refreshToken != null) {
      await _refreshProjectAccessToken(projectId, projectName);
    }
  }

  // Load stored tokens for a specific project
  Future<void> _loadProjectTokens(String projectId, String projectName) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _getProjectData(projectId);
    
    data.refreshToken = prefs.getString('youtube_refresh_token_$projectId');
    final accessTokenString = prefs.getString('youtube_access_token_$projectId');
    final expiryString = prefs.getString('youtube_token_expiry_$projectId');
    
    if (accessTokenString != null && expiryString != null) {
      final expiry = DateTime.parse(expiryString);
      if (DateTime.now().isBefore(expiry)) {
        data.accessToken = AccessToken('Bearer', accessTokenString, expiry);
      }
    }
  }

  // Save tokens to storage for a specific project
  Future<void> _saveProjectTokens(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _getProjectData(projectId);
    
    if (data.refreshToken != null) {
      await prefs.setString('youtube_refresh_token_$projectId', data.refreshToken!);
    }
    if (data.accessToken != null) {
      await prefs.setString('youtube_access_token_$projectId', data.accessToken!.data);
      await prefs.setString('youtube_token_expiry_$projectId', data.accessToken!.expiry.toIso8601String());
    }
  }

  // Start OAuth2 flow for a specific project
  Future<bool> authenticateProject(BuildContext context, String projectId, String projectName) async {
    try {
      // Get project-specific credentials
      final credentials = getProjectCredentials(projectId, projectName);
      final clientId = credentials['client_id'];
      final clientSecret = credentials['client_secret'];
      
      if (clientId == null || clientSecret == null) {
        throw Exception('YouTube credentials not found for project "$projectName". Please add them to api_keys.txt');
      }
      
      // Generate state parameter for security
      final state = _generateRandomString(32);
      
      // Build authorization URL
      final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });

      // Launch browser for authentication
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        
        // Start local server to handle OAuth callback
        final authCode = await _startOAuthServer(context, state);
        if (authCode != null) {
          return await _exchangeCodeForTokens(authCode, projectId, projectName, clientId, clientSecret);
        }
      }
      
      return false;
    } catch (e) {
      print('Authentication error: $e');
      return false;
    }
  }

  // Start local server to handle OAuth callback
  Future<String?> _startOAuthServer(BuildContext context, String expectedState) async {
    final completer = Completer<String?>();
    HttpServer? server;
    
    try {
      // Start local server on port 8080
      server = await HttpServer.bind('localhost', 8080);
      print('OAuth server started on http://localhost:8080');
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('YouTube Authorization'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Please complete the authorization in your browser...',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  completer.complete(null);
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
      
      // Listen for OAuth callback
      await for (HttpRequest request in server) {
        if (request.uri.path == '/callback') {
          final queryParams = request.uri.queryParameters;
          final code = queryParams['code'];
          final state = queryParams['state'];
          final error = queryParams['error'];
          
          if (error != null) {
            // Handle error
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write('''
                <html>
                  <body>
                    <h2>Authorization Failed</h2>
                    <p>Error: $error</p>
                    <p>You can close this window and try again.</p>
                  </body>
                </html>
              ''')
              ..close();
            
            Navigator.of(context).pop(); // Close loading dialog
            completer.complete(null);
            break;
          }
          
          if (code != null && state == expectedState) {
            // Success - return authorization code
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write('''
                <html>
                  <body>
                    <h2>Authorization Successful!</h2>
                    <p>You can close this window now.</p>
                    <script>window.close();</script>
                  </body>
                </html>
              ''')
              ..close();
            
            Navigator.of(context).pop(); // Close loading dialog
            completer.complete(code);
            break;
          } else {
            // Invalid state or missing code
            request.response
              ..statusCode = 400
              ..headers.contentType = ContentType.html
              ..write('''
                <html>
                  <body>
                    <h2>Authorization Error</h2>
                    <p>Invalid response from Google. Please try again.</p>
                  </body>
                </html>
              ''')
              ..close();
            
            Navigator.of(context).pop(); // Close loading dialog
            completer.complete(null);
            break;
          }
        } else {
          // Handle other requests
          request.response
            ..statusCode = 404
            ..write('Not Found')
            ..close();
        }
      }
    } catch (e) {
      print('OAuth server error: $e');
      Navigator.of(context).pop(); // Close loading dialog
      completer.complete(null);
    } finally {
      // Clean up server
      await server?.close();
      print('OAuth server stopped');
    }
    
    return completer.future;
  }

  // Exchange authorization code for tokens for a specific project
  Future<bool> _exchangeCodeForTokens(String authCode, String projectId, String projectName, String clientId, String clientSecret) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': authCode,
          'grant_type': 'authorization_code',
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        final data = _getProjectData(projectId);
        
        data.accessToken = AccessToken(
          'Bearer',
          tokenData['access_token'],
          DateTime.now().toUtc().add(Duration(seconds: tokenData['expires_in'])),
        );
        data.refreshToken = tokenData['refresh_token'];
        
        await _saveProjectTokens(projectId);
        await _initializeProjectYouTubeApi(projectId);
        return true;
      } else {
        print('Token exchange failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Token exchange error: $e');
      return false;
    }
  }

  // Refresh access token for a specific project
  Future<bool> _refreshProjectAccessToken(String projectId, String projectName) async {
    final data = _getProjectData(projectId);
    if (data.refreshToken == null) return false;

    try {
      final credentials = getProjectCredentials(projectId, projectName);
      final clientId = credentials['client_id'];
      final clientSecret = credentials['client_secret'];
      
      if (clientId == null || clientSecret == null) return false;

      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': data.refreshToken!,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        data.accessToken = AccessToken(
          'Bearer',
          tokenData['access_token'],
          DateTime.now().toUtc().add(Duration(seconds: tokenData['expires_in'])),
        );
        
        await _saveProjectTokens(projectId);
        await _initializeProjectYouTubeApi(projectId);
        return true;
      } else {
        print('Token refresh failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Token refresh error: $e');
      return false;
    }
  }

  // Initialize YouTube API client for a specific project
  Future<void> _initializeProjectYouTubeApi(String projectId) async {
    final data = _getProjectData(projectId);
    if (data.accessToken == null) return;

    final credentials = AccessCredentials(
      data.accessToken!,
      null,
      _scopes,
    );

    final client = authenticatedClient(http.Client(), credentials);
    data.youtubeApi = youtube.YouTubeApi(client);
  }

  // Get channel information for a specific project
  Future<youtube.Channel?> getProjectChannelInfo(String projectId) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return null;

    try {
      final response = await data.youtubeApi!.channels.list(
        ['snippet', 'statistics', 'contentDetails'],
        mine: true,
      );

      if (response.items != null && response.items!.isNotEmpty) {
        final channel = response.items!.first;
        data.channelId = channel.id;
        return channel;
      }
      return null;
    } catch (e) {
      print('Error getting channel info: $e');
      return null;
    }
  }

  // Get channel analytics for a specific project
  Future<Map<String, dynamic>> getProjectChannelAnalytics(String projectId) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return {};

    try {
      final channel = await getProjectChannelInfo(projectId);
      if (channel == null) return {};

      final analytics = <String, dynamic>{
        'channelId': channel.id,
        'channelTitle': channel.snippet?.title,
        'subscriberCount': channel.statistics?.subscriberCount,
        'videoCount': channel.statistics?.videoCount,
        'viewCount': channel.statistics?.viewCount,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Get recent videos
      final videosResponse = await data.youtubeApi!.search.list(
        ['snippet'],
        channelId: channel.id,
        order: 'date',
        type: ['video'],
        maxResults: 10,
      );

      if (videosResponse.items != null) {
        analytics['recentVideos'] = videosResponse.items!.map((video) {
          return {
            'videoId': video.id?.videoId,
            'title': video.snippet?.title,
            'publishedAt': video.snippet?.publishedAt?.toIso8601String(),
            'description': video.snippet?.description,
            'thumbnails': video.snippet?.thumbnails?.toJson(),
          };
        }).toList();
      }

      return analytics;
    } catch (e) {
      print('Error getting channel analytics: $e');
      return {};
    }
  }

  // Get video analytics for a specific project
  Future<Map<String, dynamic>> getProjectVideoAnalytics(String projectId, String videoId) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return {};

    try {
      final response = await data.youtubeApi!.videos.list(
        ['snippet', 'statistics', 'contentDetails'],
        id: [videoId],
      );

      if (response.items != null && response.items!.isNotEmpty) {
        final video = response.items!.first;
        return {
          'videoId': video.id,
          'title': video.snippet?.title,
          'description': video.snippet?.description,
          'publishedAt': video.snippet?.publishedAt?.toIso8601String(),
          'viewCount': video.statistics?.viewCount,
          'likeCount': video.statistics?.likeCount,
          'commentCount': video.statistics?.commentCount,
          'duration': video.contentDetails?.duration,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      return {};
    } catch (e) {
      print('Error getting video analytics: $e');
      return {};
    }
  }

  // Upload video for a specific project
  Future<String?> uploadProjectVideo({
    required String projectId,
    required String filePath,
    required String title,
    required String description,
    List<String> tags = const [],
    String privacyStatus = 'private',
  }) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return null;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Video file not found: $filePath');
      }

      final video = youtube.Video(
        snippet: youtube.VideoSnippet(
          title: title,
          description: description,
          tags: tags,
          categoryId: '22', // People & Blogs
        ),
        status: youtube.VideoStatus(
          privacyStatus: privacyStatus,
        ),
      );

      final media = youtube.Media(
        file.openRead(),
        await file.length(),
      );

      final response = await data.youtubeApi!.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      return response.id;
    } catch (e) {
      print('Error uploading video: $e');
      return null;
    }
  }

  // Update video for a specific project
  Future<bool> updateProjectVideo({
    required String projectId,
    required String videoId,
    String? title,
    String? description,
    List<String>? tags,
    String? privacyStatus,
  }) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return false;

    try {
      final video = youtube.Video(
        id: videoId,
        snippet: youtube.VideoSnippet(
          title: title,
          description: description,
          tags: tags,
        ),
        status: privacyStatus != null
            ? youtube.VideoStatus(privacyStatus: privacyStatus)
            : null,
      );

      await data.youtubeApi!.videos.update(
        video,
        ['snippet', 'status'],
      );

      return true;
    } catch (e) {
      print('Error updating video: $e');
      return false;
    }
  }

  // Delete video for a specific project
  Future<bool> deleteProjectVideo(String projectId, String videoId) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return false;

    try {
      await data.youtubeApi!.videos.delete(videoId);
      return true;
    } catch (e) {
      print('Error deleting video: $e');
      return false;
    }
  }

  // Get upload status for a specific project
  Future<Map<String, dynamic>> getProjectUploadStatus(String projectId, String videoId) async {
    final data = _getProjectData(projectId);
    if (data.youtubeApi == null) return {};

    try {
      final response = await data.youtubeApi!.videos.list(
        ['status', 'processingDetails'],
        id: [videoId],
      );

      if (response.items != null && response.items!.isNotEmpty) {
        final video = response.items!.first;
        return {
          'videoId': video.id,
          'uploadStatus': video.status?.uploadStatus,
          'privacyStatus': video.status?.privacyStatus,
          'processingStatus': video.processingDetails?.processingStatus,
          'processingProgress': video.processingDetails?.processingProgress?.toJson(),
        };
      }
      return {};
    } catch (e) {
      print('Error getting upload status: $e');
      return {};
    }
  }

  // Logout from a specific project
  Future<void> logoutProject(String projectId) async {
    final data = _getProjectData(projectId);
    data.youtubeApi = null;
    data.accessToken = null;
    data.refreshToken = null;
    data.channelId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('youtube_refresh_token_$projectId');
    await prefs.remove('youtube_access_token_$projectId');
    await prefs.remove('youtube_token_expiry_$projectId');
  }

  // Generate random string for state parameter
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }
} 