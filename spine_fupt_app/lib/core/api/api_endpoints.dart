class ApiEndpoints {
  // Auth
  static const authSession = '/api/auth/session';
  static const authLogin = '/api/auth/login';
  static const authLogout = '/api/auth/logout';

  // Overview
  static const overview = '/api/overview';
  static const logs = '/api/logs';

  // Schedules
  static const schedules = '/api/schedules';

  // Patients
  static const patients = '/api/patients';
  static String patient(int id) => '/api/patients/$id';
  static String patientExams(int pid) => '/api/patients/$pid/exams';

  // Registration sessions
  static const registrationSessions = '/api/registration-sessions';
  static String registrationSession(String token) => '/api/registration-sessions/$token';
  static String registrationFocus(String token) => '/api/registration-sessions/$token/focus';
  static String registrationField(String token) => '/api/registration-sessions/$token/field';
  static String registrationSubmit(String token) => '/api/registration-sessions/$token/submit';

  // Reviews
  static const reviews = '/api/reviews';
  static String review(int eid) => '/api/reviews/$eid';
  static String reviewSubmit(int eid) => '/api/reviews/$eid/review';
  static String reviewShareLink(int eid) => '/api/reviews/$eid/share-link';
  static String reviewShareAccesses(int eid) => '/api/reviews/$eid/share-accesses';
  static String reviewComments(int eid) => '/api/reviews/$eid/comments';
  static String reviewShareUser(int eid) => '/api/reviews/$eid/share-user';

  // Chat
  static const chatUsers = '/api/chat/users';
  static const chatConversations = '/api/chat/conversations';
  static String chatMessages(int cid) => '/api/chat/conversations/$cid/messages';
  static String chatRead(int cid) => '/api/chat/conversations/$cid/read';

  // Questionnaires
  static const questionnaires = '/api/questionnaires';
  static String questionnaire(int qid) => '/api/questionnaires/$qid';
  static String questionnaireStop(int qid) => '/api/questionnaires/$qid/stop';
  static String questionnaireAssign(int qid) => '/api/questionnaires/$qid/assign';
  static String questionnaireResponses(int qid) => '/api/questionnaires/$qid/responses';
  static String questionnaireResponse(int qid, int rid) => '/api/questionnaires/$qid/responses/$rid';
  static String questionnaireSafeEdit(int qid) => '/api/questionnaires/$qid/safe-edit';

  // Public
  static String publicCase(String token) => '/api/public/case/$token';
  static String publicCaseComments(String token) => '/api/public/case/$token/comments';
  static String publicQuestionnaire(String token) => '/api/public/questionnaires/$token';
  static String publicQuestionnaireSubmit(String token) => '/api/public/questionnaires/$token/submit';
  static String publicPortal(String token) => '/api/public/portal/$token';
  static String publicPortalChat(String token) => '/api/public/portal/$token/chat';
  static String publicPortalMessages(String token) => '/api/public/portal/$token/messages';
  static String publicPortalExams(String token) => '/api/public/portal/$token/exams';
  static String publicPortalExam(String token, int eid) => '/api/public/portal/$token/exams/$eid';
  static String publicPortalProfile(String token) => '/api/public/portal/$token/profile';

  // Public registration
  static String publicRegister(String token) => '/api/public/register/$token';
  static String publicRegisterSubmit(String token) => '/api/public/register/$token/submit';

  // Anonymous inference trial
  static const publicTryInference = '/api/public/try-inference';

  // AI chat (anonymous)
  static const publicAiChat = '/api/public/ai-chat';
  static const publicAiChatStream = '/api/public/ai-chat/stream';
  static String publicAiChatMessages(String sessionToken) => '/api/public/ai-chat/$sessionToken/messages';

  // AI chat (patient portal)
  static String publicPortalAiChat(String token) => '/api/public/portal/$token/ai-chat';
  static String publicPortalAiChatStream(String token) => '/api/public/portal/$token/ai-chat/stream';
  static String publicPortalAiMessages(String token) => '/api/public/portal/$token/ai-messages';

  // System
  static const systemStatus = '/api/system/status';
  static const users = '/api/users';
  static String user(int uid) => '/api/users/$uid';
  static const shareTargets = '/api/users/share-targets';
  static const lookupsBase = '/api/lookups/base';
  static const healthz = '/healthz';

  // Screening Scales (doctor)
  static const screeningScales = '/api/screening-scales';
  static String screeningScale(int sid) => '/api/screening-scales/$sid';

  // Screening Scales (public)
  static const publicScreeningScales = '/api/public/screening-scales';
}
