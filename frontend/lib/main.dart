import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class AppConfig {
  static const String defaultBackendUrl = 'http://localhost:8080';
  static const String androidEmulatorBackendUrl = 'http://10.0.2.2:8080';
  static const Duration connectionTimeout = Duration(seconds: 30);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tree7 TTS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TTSHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TTSHomePage extends StatefulWidget {
  const TTSHomePage({super.key});

  @override
  State<TTSHomePage> createState() => _TTSHomePageState();
}

class _TTSHomePageState extends State<TTSHomePage> {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String? _audioUrl;
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _errorMessage;
  String? _successMessage;
  int _selectedVoice = 0;
  double _speed = 1.0;
  
  String _backendUrl = AppConfig.defaultBackendUrl;
  final TextEditingController _urlController = TextEditingController();
  bool _showUrlSettings = false;
  
  PlayerState _playerState = PlayerState.stopped;
  Duration? _audioDuration;
  Duration? _audioPosition;

  @override
  void initState() {
    super.initState();
    _urlController.text = _backendUrl;
    _initAudioPlayer();
    _detectPlatform();
  }

  void _detectPlatform() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (kDebugMode) {
        print('Detected Android platform, considering 10.0.2.2 for emulator');
      }
    }
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (kDebugMode) {
        print('Audio player state changed: $state');
      }
      setState(() {
        _playerState = state;
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (kDebugMode) {
        print('Audio duration: $duration');
      }
      setState(() {
        _audioDuration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _audioPosition = position;
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (kDebugMode) {
        print('Audio playback complete');
      }
      setState(() {
        _isPlaying = false;
        _audioPosition = Duration.zero;
      });
    });

    _audioPlayer.onLog.listen((logMessage) {
      if (kDebugMode) {
        print('Audio player log: ${logMessage.message}');
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (kDebugMode) {
        print('Testing connection to: $_backendUrl/health');
      }

      final response = await http.get(
        Uri.parse('$_backendUrl/health'),
      ).timeout(AppConfig.connectionTimeout);

      if (kDebugMode) {
        print('Health check response: ${response.statusCode}');
        print('Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _successMessage = 'Connected successfully! Model: ${data['model']}';
          _errorMessage = null;
        });
        _showMessage('Backend connection successful!');
      } else {
        setState(() {
          _errorMessage = 'Server responded with status: ${response.statusCode}';
        });
        _showMessage(_errorMessage!, isError: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Connection error: $e');
      }
      setState(() {
        _errorMessage = 'Connection failed: $e';
      });
      _showMessage(_errorMessage!, isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateSpeech() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter some text';
      });
      _showMessage('Please enter some text', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _audioUrl = null;
    });

    try {
      if (kDebugMode) {
        print('Generating speech for: $text');
        print('Backend URL: $_backendUrl');
      }

      final response = await http.post(
        Uri.parse('$_backendUrl/api/tts'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'voice': _selectedVoice,
          'speed': _speed,
        }),
      ).timeout(AppConfig.connectionTimeout);

      if (kDebugMode) {
        print('Response status: ${response.statusCode}');
        print('Response headers: ${response.headers}');
        print('Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final audioUrl = data['audio_url'] as String?;
          if (audioUrl != null) {
            final fullAudioUrl = _backendUrl + audioUrl;
            if (kDebugMode) {
              print('Generated audio URL: $fullAudioUrl');
            }
            setState(() {
              _audioUrl = fullAudioUrl;
              _successMessage = 'Audio generated successfully!';
            });
            _showMessage('Audio generated! Click play button to listen.');
          } else {
            setState(() {
              _errorMessage = 'No audio URL in response';
            });
            _showMessage(_errorMessage!, isError: true);
          }
        } else {
          final message = data['message'] ?? 'Failed to generate speech';
          setState(() {
            _errorMessage = message;
          });
          _showMessage(message, isError: true);
        }
      } else if (response.statusCode == 500) {
        try {
          final data = jsonDecode(response.body);
          final message = data['message'] ?? 'Server error';
          setState(() {
            _errorMessage = message;
          });
          _showMessage('Server Error: $message', isError: true);
        } catch (e) {
          setState(() {
            _errorMessage = 'Server error: ${response.statusCode}';
          });
          _showMessage(_errorMessage!, isError: true);
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
        });
        _showMessage(_errorMessage!, isError: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error generating speech: $e');
      }
      setState(() {
        _errorMessage = 'Error: $e';
      });
      _showMessage(_errorMessage!, isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioUrl == null) {
      _showMessage('No audio to play', isError: true);
      return;
    }

    if (kDebugMode) {
      print('Toggle playback for: $_audioUrl');
      print('Current state: $_playerState');
    }

    try {
      if (_isPlaying) {
        if (kDebugMode) {
          print('Pausing audio...');
        }
        await _audioPlayer.pause();
      } else {
        if (kDebugMode) {
          print('Playing audio from: $_audioUrl');
        }
        
        final source = UrlSource(_audioUrl!);
        final result = await _audioPlayer.play(source);
        
        if (kDebugMode) {
          print('Play result: $result');
        }
        
        if (result == PlayerState.playing || result == PlayerState.stopped) {
        } else {
          _showMessage('Failed to start playback', isError: true);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Playback error: $e');
      }
      _showMessage('Playback error: $e', isError: true);
    }
  }

  Future<void> _stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _audioPosition = Duration.zero;
    });
  }

  void _updateBackendUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      setState(() {
        _backendUrl = url;
        _showUrlSettings = false;
      });
      _showMessage('Backend URL updated: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tree7 TTS - Kokoro-82M'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              setState(() {
                _showUrlSettings = !_showUrlSettings;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showUrlSettings) ...[
              Card(
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.link, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text(
                            'Backend URL Settings',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Backend URL',
                          hintText: 'http://localhost:8080',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              _urlController.text = AppConfig.defaultBackendUrl;
                            },
                            icon: const Icon(Icons.computer),
                            label: const Text('localhost'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              _urlController.text = AppConfig.androidEmulatorBackendUrl;
                            },
                            icon: const Icon(Icons.phone_android),
                            label: const Text('Android Emulator'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _testConnection,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi),
                              label: const Text('Test Connection'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _updateBackendUrl,
                              icon: const Icon(Icons.check),
                              label: const Text('Save'),
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

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Text',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Type something to convert to speech...\n\n'
                            'Supports: Chinese, English, Japanese, etc.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Voice:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<int>(
                                value: _selectedVoice,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('Voice 0 (Default)')),
                                  DropdownMenuItem(value: 1, child: Text('Voice 1')),
                                  DropdownMenuItem(value: 2, child: Text('Voice 2')),
                                  DropdownMenuItem(value: 3, child: Text('Voice 3')),
                                  DropdownMenuItem(value: 4, child: Text('Voice 4')),
                                  DropdownMenuItem(value: 5, child: Text('Voice 5')),
                                  DropdownMenuItem(value: 6, child: Text('Voice 6')),
                                  DropdownMenuItem(value: 7, child: Text('Voice 7')),
                                ],
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _selectedVoice = value ?? 0;
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Speed: ${_speed.toStringAsFixed(1)}x',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Slider(
                                value: _speed,
                                min: 0.5,
                                max: 2.5,
                                divisions: 20,
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _speed = value;
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateSpeech,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.record_voice_over),
                        label: Text(_isLoading ? 'Generating...' : 'Generate Speech'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            if (_successMessage != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_errorMessage != null) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_audioUrl != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.audio_file, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          const Text(
                            'Audio Generated!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 48,
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle : Icons.play_circle,
                              color: Colors.blue,
                              size: 48,
                            ),
                            onPressed: _togglePlayback,
                            tooltip: _isPlaying ? 'Pause' : 'Play',
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.stop),
                            onPressed: _isPlaying ? _stopPlayback : null,
                            tooltip: 'Stop',
                            color: Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_audioDuration != null) ...[
                        Slider(
                          value: _audioPosition?.inMilliseconds.toDouble() ?? 0,
                          min: 0,
                          max: _audioDuration!.inMilliseconds.toDouble(),
                          onChanged: (value) async {
                            final position = Duration(milliseconds: value.round());
                            await _audioPlayer.seek(position);
                            setState(() {
                              _audioPosition = position;
                            });
                          },
                        ),
                        Text(
                          '${_formatDuration(_audioPosition)} / ${_formatDuration(_audioDuration)}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ] else
                        Text(
                          _isPlaying ? 'Playing...' : 'Click play button to listen',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'About & Help',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This app uses the Kokoro-82M ONNX model for text-to-speech synthesis. '
                      'The backend is built with Go and sherpa-onnx.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Troubleshooting:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1. Ensure backend is running (./scripts/start_backend.sh)\n'
                      '2. Click Settings (⚙️) to verify backend URL\n'
                      '3. For Android emulator, use: http://10.0.2.2:8080\n'
                      '4. For real devices, use your computer\'s IP address',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current backend: $_backendUrl',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
