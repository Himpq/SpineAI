import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/chat/data/chat_repository.dart';
import 'package:spine_fupt_app/features/models.dart';
import '../../../helpers/mock_api_client.dart';

void main() {
  late MockApiClient api;
  late ChatRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = ChatRepository(api);
  });

  group('getConversations', () {
    test('returns list of ConversationModel', () async {
      when(() => api.get(ApiEndpoints.chatConversations))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'items': [
                    {'id': 1, 'type': 'patient', 'name': '张三', 'patient_id': 1, 'unread': 2}
                  ],
                },
              });

      final conversations = await repo.getConversations();
      expect(conversations.length, 1);
      expect(conversations.first.id, 1);
      expect(conversations.first.unread, 2);
    });

    test('returns empty on failure', () async {
      when(() => api.get(ApiEndpoints.chatConversations))
          .thenAnswer((_) async => {'ok': false});

      final conversations = await repo.getConversations();
      expect(conversations, isEmpty);
    });
  });

  group('createConversation', () {
    test('returns ConversationModel on success', () async {
      when(() => api.post(ApiEndpoints.chatConversations,
              data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'conversation': {
                    'id': 5,
                    'type': 'patient',
                    'name': '张三',
                    'patient_id': 1,
                  }
                },
              });

      final conv =
          await repo.createConversation(type: 'patient', patientId: 1);
      expect(conv.id, 5);
      expect(conv.type, 'patient');
    });
  });

  group('sendMessage', () {
    test('returns MessageModel on success', () async {
      when(() => api.post(ApiEndpoints.chatMessages(5),
              data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'message': {
                    'id': 100,
                    'conversation_id': 5,
                    'sender_kind': 'user',
                    'sender_user_id': 1,
                    'sender_name': '管理员',
                    'message_type': 'text',
                    'content': '你好',
                    'created_at': '2025-01-01T00:00:00Z',
                  }
                },
              });

      final msg = await repo.sendMessage(5, content: '你好');
      expect(msg.id, 100);
      expect(msg.content, '你好');
    });
  });

  group('markRead', () {
    test('calls endpoint', () async {
      when(() => api.post(ApiEndpoints.chatRead(5)))
          .thenAnswer((_) async => {'ok': true});

      await repo.markRead(5);
      verify(() => api.post(ApiEndpoints.chatRead(5))).called(1);
    });
  });
}
