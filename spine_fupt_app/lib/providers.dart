import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'core/api/api_client.dart';
import 'core/websocket/ws_client.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/user_model.dart';
import 'features/patients/data/patient_repository.dart';
import 'features/reviews/data/review_repository.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/portal/data/portal_repository.dart';
import 'features/overview/data/overview_repository.dart';
import 'features/questionnaires/data/questionnaire_repository.dart';
import 'features/models.dart';

// ── Server Config ──
const _kServerUrl = 'pref_server_url';
const _kThemeMode = 'pref_theme_mode';
const _defaultUrl = 'http://192.168.1.112:5000';

final serverUrlProvider = StateProvider<String>((ref) => _defaultUrl);

// ── Theme Mode ──
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Call once at startup after SharedPreferences is ready.
Future<void> loadSavedPrefs(ProviderContainer container) async {
  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString(_kServerUrl);
  if (savedUrl != null && savedUrl.isNotEmpty) {
    container.read(serverUrlProvider.notifier).state = savedUrl;
  }
  final savedTheme = prefs.getInt(_kThemeMode);
  if (savedTheme != null &&
      savedTheme >= 0 &&
      savedTheme < ThemeMode.values.length) {
    container.read(themeModeProvider.notifier).state =
        ThemeMode.values[savedTheme];
  }
}

Future<void> saveServerUrl(String url) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kServerUrl, url);
}

Future<void> saveThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kThemeMode, mode.index);
}

// ── Singletons ──
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final wsConnectedProvider = StateProvider<bool>((ref) => false);

/// Incremented each time the app resumes from background.
/// Screens with local state can listen to this to trigger refresh.
final appResumedProvider = StateProvider<int>((ref) => 0);

final wsClientProvider = Provider<WsClient>((ref) {
  final ws = WsClient();
  ws.onConnectionChanged = (connected) {
    ref.read(wsConnectedProvider.notifier).state = connected;
  };
  ref.onDispose(() => ws.disconnect());
  return ws;
});

// ── Network Connectivity ──
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield !initial.contains(ConnectivityResult.none);
  await for (final result in connectivity.onConnectivityChanged) {
    yield !result.contains(ConnectivityResult.none);
  }
});

// ── Repositories ──
final authRepoProvider = Provider(
  (ref) => AuthRepository(ref.read(apiClientProvider)),
);
final patientRepoProvider = Provider(
  (ref) => PatientRepository(ref.read(apiClientProvider)),
);
final reviewRepoProvider = Provider(
  (ref) => ReviewRepository(ref.read(apiClientProvider)),
);
final chatRepoProvider = Provider(
  (ref) => ChatRepository(ref.read(apiClientProvider)),
);
final portalRepoProvider = Provider(
  (ref) => PortalRepository(ref.read(apiClientProvider)),
);
final overviewRepoProvider = Provider(
  (ref) => OverviewRepository(ref.read(apiClientProvider)),
);
final questionnaireRepoProvider = Provider(
  (ref) => QuestionnaireRepository(ref.read(apiClientProvider)),
);

// ── Auth State ──
enum AuthMode { unauthenticated, doctor, patient }

class AuthState {
  final AuthMode mode;
  final UserModel? user;
  final String? portalToken;
  final Map<String, dynamic>? portalData;
  final bool loading;

  const AuthState({
    this.mode = AuthMode.unauthenticated,
    this.user,
    this.portalToken,
    this.portalData,
    this.loading = true,
  });

  AuthState copyWith({
    AuthMode? mode,
    UserModel? user,
    String? portalToken,
    Map<String, dynamic>? portalData,
    bool? loading,
  }) {
    return AuthState(
      mode: mode ?? this.mode,
      user: user ?? this.user,
      portalToken: portalToken ?? this.portalToken,
      portalData: portalData ?? this.portalData,
      loading: loading ?? this.loading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;
  AuthNotifier(this.ref) : super(const AuthState()) {
    _checkSession();
  }

  static const _portalTokenKey = 'portal_token';
  static const _portalHistoryKey = 'portal_login_history';

  /// Get saved login history: list of {token, name, timestamp}
  Future<List<Map<String, dynamic>>> getPortalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_portalHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToHistory(String token, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getPortalHistory();
    // Remove existing entry with same token
    history.removeWhere((e) => e['token'] == token);
    // Add new entry at top
    history.insert(0, {
      'token': token,
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
    });
    // Keep at most 10 entries
    if (history.length > 10) history.removeRange(10, history.length);
    await prefs.setString(_portalHistoryKey, json.encode(history));
  }

  Future<void> removeFromHistory(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getPortalHistory();
    history.removeWhere((e) => e['token'] == token);
    await prefs.setString(_portalHistoryKey, json.encode(history));
  }

  Future<void> _checkSession() async {
    try {
      // Try doctor session first (cookie-based)
      final user = await ref.read(authRepoProvider).checkSession();
      if (user != null) {
        state = AuthState(mode: AuthMode.doctor, user: user, loading: false);
        _connectWs(user);
        return;
      }
      // Try restoring portal token
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_portalTokenKey);
      if (savedToken != null && savedToken.isNotEmpty) {
        try {
          final data =
              await ref.read(portalRepoProvider).getPortalData(savedToken);
          state = AuthState(
            mode: AuthMode.patient,
            portalToken: savedToken,
            portalData: data,
            loading: false,
          );
          final ws = ref.read(wsClientProvider);
          final url = ref.read(serverUrlProvider);
          ws.connect(
            url,
            kind: 'patient',
            name: data['patient']?['name'] ?? '患者',
          );
          ws.subscribe('system');
          _subscribePatientChatChannel(savedToken);
          return;
        } catch (_) {
          await prefs.remove(_portalTokenKey);
        }
      }
      state = const AuthState(mode: AuthMode.unauthenticated, loading: false);
    } catch (_) {
      state = const AuthState(mode: AuthMode.unauthenticated, loading: false);
    }
  }

  Future<void> login(String username, String password) async {
    final user = await ref.read(authRepoProvider).login(username, password);
    state = AuthState(mode: AuthMode.doctor, user: user, loading: false);
    _connectWs(user);
  }

  Future<void> enterPortal(String token) async {
    final data = await ref.read(portalRepoProvider).getPortalData(token);
    // Persist portal token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_portalTokenKey, token);
    // Save to login history
    final patientName =
        (data['patient'] as Map<String, dynamic>?)?['name'] as String? ?? '患者';
    await _saveToHistory(token, patientName);
    state = AuthState(
      mode: AuthMode.patient,
      portalToken: token,
      portalData: data,
      loading: false,
    );
    final ws = ref.read(wsClientProvider);
    final url = ref.read(serverUrlProvider);
    ws.connect(url, kind: 'patient', name: data['patient']?['name'] ?? '患者');
    ws.subscribe('system');
    _subscribePatientChatChannel(token);
  }

  Future<void> _subscribePatientChatChannel(String token) async {
    try {
      final chatData = await ref.read(portalRepoProvider).getPortalChat(token);
      final conv = chatData['conversation'] as Map<String, dynamic>?;
      final convId = conv?['id'] ?? chatData['conversation_id'];
      if (convId != null) {
        ref.read(wsClientProvider).subscribe('chat:$convId');
      }
    } catch (_) {}
  }

  void _connectWs(UserModel user) {
    final ws = ref.read(wsClientProvider);
    final url = ref.read(serverUrlProvider);
    ws.connect(url, kind: 'doctor', name: user.displayName, userId: user.id);
    ws.subscribe('system');
    ws.subscribe('patients');
    // Subscribe to all chat channels + auto-refresh list on new messages
    ws.on('chat_message', _onGlobalChatMessage);
    ws.on('patient_created', _onPatientCreated);
    ws.on('toast', _onToast);
    ws.on('feed_new', _onFeedNew);
    _subscribeDoctorChatChannels();
  }

  void _onGlobalChatMessage(Map<String, dynamic> _) {
    ref.invalidate(conversationListProvider);
    ref.invalidate(overviewProvider);
  }

  void _onPatientCreated(Map<String, dynamic> _) {
    ref.invalidate(patientListProvider);
    ref.invalidate(overviewProvider);
  }

  void _onToast(Map<String, dynamic> msg) {
    final title = msg['title'] as String? ?? '';
    final message = msg['message'] as String? ?? '';
    final level = msg['level'] as String? ?? 'info';
    ref.read(toastStreamProvider.notifier).state = ToastMessage(
      title: title,
      message: message,
      level: level,
    );
  }

  void _onFeedNew(Map<String, dynamic> payload) {
    ref.invalidate(overviewProvider);
    final item = payload['item'] as Map<String, dynamic>? ?? {};
    final eventType = item['event_type'] as String? ?? '';
    if ({
      'xray_upload',
      'inference_result',
      'inference_failed',
      'review_done',
      'review_deleted',
      'review_queue_add',
    }.contains(eventType)) {
      ref.invalidate(reviewListProvider);
      ref.invalidate(patientListProvider);
    }
  }

  Future<void> _subscribeDoctorChatChannels() async {
    try {
      final convs = await ref.read(chatRepoProvider).getConversations();
      final ws = ref.read(wsClientProvider);
      for (final c in convs) {
        ws.subscribe('chat:${c.id}');
      }
    } catch (_) {}
  }

  /// Doctor logout — clears server session + cookies + portal token.
  Future<void> logout() async {
    await ref.read(authRepoProvider).logout();
    ref.read(wsClientProvider).disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_portalTokenKey);
    state = const AuthState(mode: AuthMode.unauthenticated, loading: false);
  }

  /// Portal (patient) leave — only clears local token + WS, no server call.
  Future<void> leavePortal() async {
    ref.read(wsClientProvider).disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_portalTokenKey);
    state = const AuthState(mode: AuthMode.unauthenticated, loading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);

/// Bridges Riverpod auth state → GoRouter refreshListenable
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

final authChangeNotifierProvider = Provider<AuthChangeNotifier>(
  (ref) => AuthChangeNotifier(ref),
);

// ── Patient List ──
final patientListProvider = FutureProvider.autoDispose<List<PatientModel>>((
  ref,
) async {
  return ref.read(patientRepoProvider).getPatients();
});

// ── Review List ──
final reviewListProvider = FutureProvider.autoDispose<List<ExamModel>>((
  ref,
) async {
  return ref.read(reviewRepoProvider).getReviews();
});

// ── Chat Conversations ──
final conversationListProvider =
    FutureProvider.autoDispose<List<ConversationModel>>((ref) async {
  return ref.read(chatRepoProvider).getConversations();
});

// ── Questionnaire List ──
final questionnaireListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(questionnaireRepoProvider).getQuestionnaires();
});

// ── Overview ──
final overviewProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(overviewRepoProvider).getOverview();
});

// ── Badge Counts (derived from overview stats) ──
final chatUnreadCountProvider = Provider<int>((ref) {
  final ov = ref.watch(overviewProvider);
  return ov.whenOrNull(
        data: (d) => (d['stats'] as Map?)?['unread_messages'] as int? ?? 0,
      ) ??
      0;
});

final pendingReviewCountProvider = Provider<int>((ref) {
  final ov = ref.watch(overviewProvider);
  return ov.whenOrNull(
        data: (d) => (d['stats'] as Map?)?['pending_reviews'] as int? ?? 0,
      ) ??
      0;
});

// ── Toast Stream ──
class ToastMessage {
  final String title;
  final String message;
  final String level;
  ToastMessage({
    required this.title,
    required this.message,
    this.level = 'info',
  });
}

final toastStreamProvider = StateProvider<ToastMessage?>((ref) => null);
