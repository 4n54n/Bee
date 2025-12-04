import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;

const int messageExpiryMs = 5000; // 5-second tolerance window
Completer<void>? pongCompleter;
Timer? onlineTimer;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await FcmHandler.handleIncomingMessage(message);
}

class FcmHandler {
  static Future<void> handleIncomingMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];
    final sender = data['sender'] ?? 'unknown';
    final ts = int.tryParse(data['ts'] ?? '0') ?? 0;
    
    // Calculate age and handle negative values
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    int age = currentTime - ts;
    if (age < 0) age = 0; // Ignore negative age values

    if (age > messageExpiryMs) {
      return; // Discard stale messages
    }

    switch (type) {
      case 'ping':
        await sendPongBack(sender);
        break;
      case 'pong':
        pongCompleter?.complete();
        break;
      case 'vibrate_start':
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(pattern: [0, 1000], repeat: 0);
        }
        break;
      case 'vibrate_stop':
        Vibration.cancel();
        break;
      case 'text':
        await handleTextMessage(data);
        break;
    }
  }

  static Future<void> handleTextMessage(Map<String, dynamic> data) async {
    final msg = (data['message'] ?? '').toString().toLowerCase();
    if (msg.startsWith('bee')) {
      final secs = int.tryParse(msg.replaceFirst('bee', '')) ?? 0;
      final duration = secs.clamp(0, 100);
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: duration * 1000);
      }
    }
  }

  static Future<void> sendPongBack(String senderId) async {
    final dbRef = FirebaseDatabase.instance.ref('users');
    final snapshot = await dbRef.get();
    final users = _parseUsersSnapshot(snapshot);
    if (users.isEmpty) return;
    final senderToken = users[senderId]?['token'];
    if (senderToken == null) return;
    final myId = users.keys.firstWhere((k) => k != senderId, orElse: () => '');
    if (myId.isEmpty) return;

    await sendFcmMessage(
      targetToken: senderToken,
      data: {'type': 'pong', 'sender': myId, 'ts': nowMs()},
    );
  }

  static Future<void> sendFcmMessage({
    required String targetToken,
    required Map<String, dynamic> data,
  }) async {
    try {
      final creds = await getAccessToken();
      final projectId = jsonDecode(
          await rootBundle.loadString('assets/service-account.json'))['project_id'];
      final url = Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send');
      final msg = {
        "message": {
          "token": targetToken,
          "data": data,
          "android": {"priority": "high"},
          "apns": {
            "headers": {"apns-priority": "10"},
            "payload": {"aps": {"content-available": 1}}
          }
        }
      };
      
      await http
          .post(
            url,
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer ${creds.accessToken.data}",
            },
            body: jsonEncode(msg),
          )
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      // Silent fail for FCM send errors
    }
  }

  static Future<AccessCredentials> getAccessToken() async {
    final creds = ServiceAccountCredentials.fromJson(
        await rootBundle.loadString('assets/service-account.json'));
    final client = await clientViaServiceAccount(
        creds, ['https://www.googleapis.com/auth/firebase.messaging']);
    final c = client.credentials;
    client.close();
    return c;
  }
}

String nowMs() => DateTime.now().millisecondsSinceEpoch.toString();

// Helper function to parse Firebase snapshot safely
Map<String, dynamic> _parseUsersSnapshot(DataSnapshot snapshot) {
  if (!snapshot.exists) return {};
  final value = snapshot.value;
  
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  
  if (value is List) {
    final Map<String, dynamic> result = {};
    for (int i = 0; i < value.length; i++) {
      if (value[i] != null) {
        result[i.toString()] = value[i];
      }
    }
    return result;
  }
  
  return {};
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imoji Sync with Bee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.yellow,
        useMaterial3: true,
      ),
      home: const IdChecker(),
    );
  }
}

class IdChecker extends StatefulWidget {
  const IdChecker({super.key});

  @override
  State<IdChecker> createState() => _IdCheckerState();
}

class _IdCheckerState extends State<IdChecker> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadId();
  }

  Future<void> _loadId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('userId');
    if (savedId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askForId());
    } else {
      setState(() => _userId = savedId);
    }
  }

  Future<void> _askForId() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Center(
          child: Text(
            'Enter your User ID',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use your existing ID or create a new one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'e.g. user123',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              onPressed: () async {
                final enteredId = controller.text.trim();
                if (enteredId.isNotEmpty) {
                  final dbRef = FirebaseDatabase.instance.ref('users');
                  final snapshot = await dbRef.get();
                  final users = _parseUsersSnapshot(snapshot);
                  
                  // FIX: Allow creating second user or connecting to existing one
                  if (users.length >= 2 && !users.containsKey(enteredId)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Maximum 2 users allowed!')),
                      );
                    }
                    return;
                  }
                  
                  Navigator.of(context).pop(enteredId);
                }
              },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
    if (id != null && id.isNotEmpty) {      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', id);
      setState(() => _userId = id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ImojiHomePage(currentUserId: _userId!);
  }
}

class ImojiHomePage extends StatefulWidget {
  final String currentUserId;
  const ImojiHomePage({super.key, required this.currentUserId});

  @override
  State<ImojiHomePage> createState() => _ImojiHomePageState();
}

class _ImojiHomePageState extends State<ImojiHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseMessaging _msg = FirebaseMessaging.instance;
  late final String currentUserId;
  String? otherUserId;

  String _myImoji = '🙂';
  String _otherImoji = '🙂';
  StreamSubscription<DatabaseEvent>? _otherSub;
  StreamSubscription<DatabaseEvent>? _mySub;
  StreamSubscription<DatabaseEvent>? _usersSub;

  bool _isOtherOnline = false;
  bool _isVibrating = false;
  int _consecutiveOfflineCount = 0; // Track consecutive offline pings
  late AnimationController _pulseController;
  late AnimationController _vibrationController;

  final List<String> _emojiOptions = [
    '😀','😁','😂','😅','😊','😇','🙂','😉','😍','😘','🤩','😎',
    '🤔','😴','😢','😭','😡','🤯','👍','👎','🙏','👏','🔥','💯','❤️'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    currentUserId = widget.currentUserId;
    
    _initializeFcm();
    _ensureImojiExistsAndListen();
    _listenForOtherUser();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
      lowerBound: 0.97,
      upperBound: 1.03,
    )..repeat(reverse: true);
    
    _vibrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    
    startAutoPing();
  }

  Future<void> _initializeFcm() async {
    final token = await _msg.getToken();
    
    // Update token without overwriting emoji
    await _db.child('users').child(currentUserId).update({
      'token': token,
    });
    
    FirebaseMessaging.onMessage.listen(FcmHandler.handleIncomingMessage);
  }

  void _listenForOtherUser() {
    _usersSub = _db.child('users').onValue.listen((event) {
      final users = _parseUsersSnapshot(event.snapshot);
      if (users.isNotEmpty) {
        final otherUsers = users.keys.where((k) => k != currentUserId).toList();
        if (otherUsers.isNotEmpty) {
          setState(() {
            otherUserId = otherUsers.first;
          });
          
          // Listen to the specific other user's emoji changes
          _listenToOtherUserEmoji(otherUsers.first);
        } else {
          setState(() {
            otherUserId = null;
            _isOtherOnline = false;
            _consecutiveOfflineCount = 0; // Reset counter when no user exists
          });
        }
      }
    });
  }

  void _listenToOtherUserEmoji(String otherUserId) {
    _otherSub?.cancel(); // Cancel previous subscription
    _otherSub = _db.child('users').child(otherUserId).child('imoji').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is String && data.isNotEmpty) {
        setState(() => _otherImoji = data);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startAutoPing();
    } else if (state == AppLifecycleState.paused) {
      onlineTimer?.cancel();
    }
  }

  void startAutoPing() {
    onlineTimer?.cancel();
    onlineTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkOnline());
  }

  Future<void> _checkOnline() async {
    if (otherUserId == null) {
      setState(() => _isOtherOnline = false);
      _consecutiveOfflineCount = 0;
      return;
    }

    pongCompleter = Completer<void>();
    await _sendFcm({'type': 'ping', 'sender': currentUserId});
    try {
      await pongCompleter!.future.timeout(const Duration(seconds: 2));
      // Success - user is online
      setState(() {
        _isOtherOnline = true;
        _consecutiveOfflineCount = 0; // Reset counter on successful ping
      });
    } catch (_) {
      // Failed ping - increment counter
      _consecutiveOfflineCount++;
      
      // Only show offline after 3 consecutive failures
      if (_consecutiveOfflineCount >= 3) {
        setState(() {
          _isOtherOnline = false;
        });
      }
      // If less than 3 failures, keep showing online (don't update _isOtherOnline)
    }
  }

  Future<void> _sendFcm(Map<String, dynamic> data) async {
    if (otherUserId == null) return;
    
    final snapshot = await _db.child('users').get();
    final users = _parseUsersSnapshot(snapshot);
    if (users.isEmpty) return;
    final token = users[otherUserId]?['token'];
    if (token == null) return;
    data['ts'] = nowMs();
    await FcmHandler.sendFcmMessage(targetToken: token, data: data);
  }

  Future<void> _ensureImojiExistsAndListen() async {
    final currentRef = _db.child('users').child(currentUserId);

    final currentSnap = await currentRef.get();
    
    // Only set default emoji if user doesn't exist or has no emoji
    if (!currentSnap.exists) {
      // User doesn't exist at all - create with default emoji
      await currentRef.set({
        'imoji': _myImoji,
        'token': '' // token will be updated in _initializeFcm
      });
    } else if (currentSnap.child('imoji').value == null) {
      // User exists but has no emoji - set default
      await currentRef.update({'imoji': _myImoji});
    } else {
      // User exists and has emoji - use existing emoji
      final val = currentSnap.child('imoji').value;
      if (val is String && val.isNotEmpty) {
        _myImoji = val;
      }
    }

    // Listen to our own emoji changes
    _mySub?.cancel(); // Cancel previous subscription
    _mySub = currentRef.child('imoji').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is String && data.isNotEmpty) {
        setState(() => _myImoji = data);
      }
    });

    // Listen for other user creation and emoji changes
    _usersSub?.cancel(); // Cancel previous subscription
    _usersSub = _db.child('users').onChildChanged.listen((event) {
      if (event.snapshot.key != currentUserId) {
        final imoji = event.snapshot.child('imoji').value;
        if (imoji is String && imoji.isNotEmpty) {
          setState(() => _otherImoji = imoji);
        }
      }
    });

    _usersSub = _db.child('users').onChildAdded.listen((event) {
      if (event.snapshot.key != currentUserId) {
        final imoji = event.snapshot.child('imoji').value;
        if (imoji is String && imoji.isNotEmpty) {
          setState(() {
            otherUserId = event.snapshot.key;
            _otherImoji = imoji;
          });
        }
      }
    });
  }

  Future<void> _updateMyImoji(String newImoji) async {
    await _db.child('users').child(currentUserId).update({'imoji': newImoji});
    setState(() => _myImoji = newImoji);
  }

  Future<void> _showEmojiPicker() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: _emojiOptions.length,
            itemBuilder: (context, i) {
              final e = _emojiOptions[i];
              return GestureDetector(
                onTap: () => Navigator.pop(context, e),
                child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 26))),
              );
            },
          ),
        );
      },
    );

    if (chosen != null) await _updateMyImoji(chosen);
  }

  Future<void> _startVibration() async {
    if (!_isOtherOnline || otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${otherUserId ?? "Other user"} is offline')),
      );
      return;
    }

    setState(() => _isVibrating = true);
    _vibrationController.repeat(reverse: true);
    
    await _sendFcm({'type': 'vibrate_start', 'sender': currentUserId});
  }

  Future<void> _stopVibration() async {
    if (_isVibrating) {
      await _sendFcm({'type': 'vibrate_stop', 'sender': currentUserId});
      _vibrationController.stop();
      setState(() => _isVibrating = false);
    }
  }

  Widget _buildEmojiCircle(String emoji, {required bool isMine}) {
    final yellow = Colors.amberAccent;
    return ScaleTransition(
      scale: _pulseController,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: yellow.withOpacity(0.25), width: 8),
            ),
          ),
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.8), width: 4),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.3),
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 56),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeeButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startVibration(),
      onLongPressEnd: (_) => _stopVibration(),
      child: ScaleTransition(
        scale: _vibrationController.drive(
          Tween<double>(begin: 1.0, end: 1.1),
        ),
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: _isVibrating ? Colors.orange : Colors.yellow.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🐝',
                style: TextStyle(
                  fontSize: 32,
                  color: _isVibrating ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isVibrating ? 'Vibrating...' : 'Hold to Bee',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isVibrating ? Colors.white : Colors.black,
                ),
              ),
              if (_isVibrating) ...[
                const SizedBox(height: 4),
                const Text(
                  'Release to stop',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otherSub?.cancel();
    _mySub?.cancel();
    _usersSub?.cancel();
    onlineTimer?.cancel();
    _pulseController.dispose();
    _vibrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/images/mona_lisa.jpg'),
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'You: $currentUserId',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isOtherOnline ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${otherUserId ?? "No user"}: ${_isOtherOnline ? 'Online' : 'Offline'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Center(child: _buildEmojiCircle(_otherImoji, isMine: false)),

                const Spacer(flex: 2),

                Center(child: _buildBeeButton()),

                const Spacer(flex: 2),

                GestureDetector(
                  onTap: _showEmojiPicker,
                  child: Center(child: _buildEmojiCircle(_myImoji, isMine: true)),
                ),

                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}