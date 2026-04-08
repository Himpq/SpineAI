import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/server_config_screen.dart';
import '../../features/auth/presentation/qr_scan_screen.dart';
import '../../features/overview/presentation/overview_screen.dart';
import '../../features/patients/presentation/patient_list_screen.dart';
import '../../features/patients/presentation/patient_detail_screen.dart';
import '../../features/patients/presentation/patient_register_screen.dart';
import '../../features/reviews/presentation/review_list_screen.dart';
import '../../features/reviews/presentation/review_detail_screen.dart';
import '../../features/chat/presentation/chat_list_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/portal/presentation/portal_home_screen.dart';
import '../../features/portal/presentation/portal_timeline_screen.dart';
import '../../features/portal/presentation/portal_upload_screen.dart';
import '../../features/portal/presentation/portal_chat_screen.dart';
import '../../features/portal/presentation/portal_exam_detail_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import '../../features/more/presentation/user_management_screen.dart';
import '../../features/shared_case/presentation/shared_case_screen.dart';
import '../../features/questionnaires/presentation/questionnaire_list_screen.dart';
import '../../features/questionnaires/presentation/questionnaire_detail_screen.dart';
import '../../features/questionnaires/presentation/questionnaire_edit_screen.dart';
import '../../features/questionnaires/presentation/public_questionnaire_screen.dart';
import '../../features/notifications/presentation/notification_list_screen.dart';
import '../../features/portal/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/registration_form_screen.dart';
import '../../features/ai/presentation/try_inference_screen.dart';
import '../../features/ai/presentation/ai_doctor_screen.dart';
import '../../features/ai/presentation/login_required_screen.dart';
import '../../features/screening/presentation/spine_screening_screen.dart';
import '../../features/screening/presentation/disease_selection_screen.dart';
import '../../features/screening/presentation/screening_scale_manage_screen.dart';
import '../../shells/doctor_shell.dart';
import '../../shells/patient_shell.dart';
import '../../shells/trial_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _doctorShellKey = GlobalKey<NavigatorState>();
final _patientShellKey = GlobalKey<NavigatorState>();
final _trialShellKey = GlobalKey<NavigatorState>();

GoRouter createRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: ref.read(authChangeNotifierProvider),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.loading) return null;

      final isLoginPage = state.matchedLocation == '/login';
      final isServerConfig = state.matchedLocation == '/server-config';
      final isQrScan = state.matchedLocation == '/qr-scan';
      final isRegisterForm = state.matchedLocation == '/register-form';
      final isPublic = state.matchedLocation.startsWith('/case/') || state.matchedLocation.startsWith('/q/');
      final isTrial = state.matchedLocation.startsWith('/trial/');
      final isTryInference = state.matchedLocation == '/try-inference';
      final isAiDoctor = state.matchedLocation == '/ai-doctor';

      if (isPublic || isServerConfig || isQrScan || isRegisterForm || isTryInference || isAiDoctor || isTrial) return null;

      if (auth.mode == AuthMode.unauthenticated && !isLoginPage) {
        return '/login';
      }
      if (auth.mode == AuthMode.doctor) {
        if (isLoginPage) return '/doctor/overview';
        if (state.matchedLocation.startsWith('/portal/')) return '/doctor/overview';
      }
      if (auth.mode == AuthMode.patient) {
        if (isLoginPage) return '/portal/home';
        if (state.matchedLocation.startsWith('/doctor/')) return '/portal/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/server-config', builder: (_, __) => const ServerConfigScreen()),
      GoRoute(path: '/qr-scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(path: '/register-form', builder: (_, state) {
        final regToken = state.extra as String;
        return RegistrationFormScreen(regToken: regToken);
      }),
      GoRoute(path: '/try-inference', builder: (_, __) => const TryInferenceScreen()),
      GoRoute(path: '/ai-doctor', builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return AiDoctorScreen(inferenceContext: extra?['inference_context'] as Map<String, dynamic>?);
      }),

      // Doctor shell
      ShellRoute(
        navigatorKey: _doctorShellKey,
        builder: (_, __, child) => DoctorShell(child: child),
        routes: [
          GoRoute(path: '/doctor/overview', builder: (_, __) => const OverviewScreen()),
          GoRoute(path: '/doctor/patients', builder: (_, __) => const PatientListScreen()),
          GoRoute(path: '/doctor/reviews', builder: (_, __) => const ReviewListScreen()),
          GoRoute(path: '/doctor/chat', builder: (_, __) => const ChatListScreen()),
          GoRoute(path: '/doctor/questionnaires', builder: (_, __) => const QuestionnaireListScreen()),
          GoRoute(path: '/doctor/more', builder: (_, __) => const MoreScreen()),
        ],
      ),

      // Doctor detail routes (outside shell for full screen)
      GoRoute(path: '/doctor/patients/:id', builder: (_, state) {
        final id = int.parse(state.pathParameters['id']!);
        return PatientDetailScreen(patientId: id);
      }),
      GoRoute(path: '/doctor/patients/:id/register', builder: (_, state) {
        final id = int.parse(state.pathParameters['id']!);
        return PatientRegisterScreen(patientId: id);
      }),
      GoRoute(path: '/doctor/register', builder: (_, __) => const PatientRegisterScreen()),
      GoRoute(path: '/doctor/notifications', builder: (_, __) => const NotificationListScreen()),
      GoRoute(path: '/doctor/reviews/:id', builder: (_, state) {
        final id = int.parse(state.pathParameters['id']!);
        return ReviewDetailScreen(examId: id);
      }),
      GoRoute(path: '/doctor/users', builder: (_, __) => const UserManagementScreen()),
      GoRoute(path: '/doctor/chat/:id', builder: (_, state) {
        final id = int.parse(state.pathParameters['id']!);
        final name = state.uri.queryParameters['name'];
        return ChatRoomScreen(conversationId: id, conversationName: name);
      }),
      GoRoute(path: '/doctor/questionnaires/create', builder: (_, __) => const QuestionnaireEditScreen()),
      GoRoute(path: '/doctor/questionnaires/edit', builder: (_, state) {
        final data = state.extra as Map<String, dynamic>;
        return QuestionnaireEditScreen(initialData: data);
      }),
      GoRoute(path: '/doctor/questionnaires/:id', builder: (_, state) {
        final id = int.parse(state.pathParameters['id']!);
        return QuestionnaireDetailScreen(questionnaireId: id);
      }),

      // Patient shell
      ShellRoute(
        navigatorKey: _patientShellKey,
        builder: (_, __, child) => PatientShell(child: child),
        routes: [
          GoRoute(path: '/portal/home', builder: (_, __) => const PortalHomeScreen()),
          GoRoute(path: '/portal/timeline', builder: (_, __) => const PortalTimelineScreen()),
          GoRoute(path: '/portal/upload', builder: (_, __) => const PortalUploadScreen()),
          GoRoute(path: '/portal/chat', builder: (_, __) => const PortalChatScreen()),
          GoRoute(path: '/portal/ai-doctor', builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return AiDoctorScreen(inferenceContext: extra?['inference_context'] as Map<String, dynamic>?);
          }),
          GoRoute(path: '/portal/exam/detail', builder: (_, state) {
            final exam = state.extra as Map<String, dynamic>;
            return PortalExamDetailScreen(exam: exam);
          }),
        ],
      ),

      // Patient screening (outside shell - full screen)
      GoRoute(path: '/portal/screening', builder: (_, __) => const DiseaseSelectionScreen()),
      GoRoute(path: '/portal/screening/scoliosis', builder: (_, __) => const SpineScreeningScreen()),

      // Doctor screening scale management (outside shell - full screen)
      GoRoute(path: '/doctor/screening-scales', builder: (_, __) => const ScreeningScaleListScreen()),

      // Patient complete profile (outside shell - full screen)
      GoRoute(path: '/portal/complete-profile', builder: (_, __) => const CompleteProfileScreen()),

      // Trial shell (same layout as patient, login-gated tabs show placeholder)
      ShellRoute(
        navigatorKey: _trialShellKey,
        builder: (_, __, child) => TrialShell(child: child),
        routes: [
          GoRoute(path: '/trial/home', builder: (_, __) => const LoginRequiredScreen(featureName: '首页')),
          GoRoute(path: '/trial/timeline', builder: (_, __) => const LoginRequiredScreen(featureName: '随访')),
          GoRoute(path: '/trial/upload', builder: (_, __) => const TryInferenceScreen()),
          GoRoute(path: '/trial/chat', builder: (_, __) => const LoginRequiredScreen(featureName: '聊天')),
          GoRoute(path: '/trial/ai-doctor', builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return AiDoctorScreen(inferenceContext: extra?['inference_context'] as Map<String, dynamic>?);
          }),
        ],
      ),

      // Public routes
      GoRoute(path: '/case/:token', builder: (_, state) {
        return SharedCaseScreen(token: state.pathParameters['token']!);
      }),
      GoRoute(path: '/q/:token', builder: (_, state) {
        return PublicQuestionnaireScreen(token: state.pathParameters['token']!);
      }),
    ],
  );
}
