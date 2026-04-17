import 'package:flutter_test/flutter_test.dart';
import 'package:spine_fupt_app/features/models.dart';
import 'package:spine_fupt_app/features/auth/domain/user_model.dart';

void main() {
  group('UserModel.fromJson', () {
    test('parses all fields', () {
      final user = UserModel.fromJson({
        'id': 1,
        'username': 'admin',
        'display_name': '管理员',
        'role': 'admin',
        'is_active': true,
        'modules': ['patients', 'reviews'],
        'last_login_at': '2025-01-01T00:00:00Z',
      });

      expect(user.id, 1);
      expect(user.username, 'admin');
      expect(user.displayName, '管理员');
      expect(user.isAdmin, true);
      expect(user.modules, ['patients', 'reviews']);
      expect(user.hasModule('patients'), true);
      expect(user.hasModule('unknown'), true); // admin has all modules
    });

    test('handles module_permissions as JSON string', () {
      final user = UserModel.fromJson({
        'id': 2,
        'username': 'doc1',
        'role': 'doctor',
        'is_active': true,
        'module_permissions': '["patients"]',
      });

      expect(user.modules, ['patients']);
      expect(user.hasModule('patients'), true);
      expect(user.hasModule('reviews'), false);
    });

    test('defaults missing fields', () {
      final user = UserModel.fromJson({'id': 3});

      expect(user.username, '');
      expect(user.role, 'doctor');
      expect(user.isActive, true);
      expect(user.isAdmin, false);
    });
  });

  group('PatientModel.fromJson', () {
    test('parses all fields', () {
      final p = PatientModel.fromJson({
        'id': 1,
        'name': '张三',
        'age': 25,
        'sex': 'male',
        'phone': '13800000000',
        'status': 'active',
        'exam_count': 3,
      });

      expect(p.id, 1);
      expect(p.name, '张三');
      expect(p.age, 25);
      expect(p.examCount, 3);
    });
  });

  group('ExamModel.fromJson', () {
    test('parses standard fields', () {
      final e = ExamModel.fromJson({
        'id': 10,
        'patient_id': 1,
        'status': 'reviewed',
        'spine_class': 'lumbar',
        'cobb_angle': 15.5,
      });

      expect(e.id, 10);
      expect(e.isLumbar, true);
      expect(e.isCervical, false);
      expect(e.isReviewed, true);
      expect(e.cobbAngle, 15.5);
    });

    test('handles inference as Map', () {
      final e = ExamModel.fromJson({
        'id': 11,
        'patient_id': 1,
        'status': 'pending_review',
        'inference': {'angle': 12.0},
      });

      expect(e.inferenceJson, isNotNull);
      expect(e.inferenceJson!['angle'], 12.0);
      expect(e.isPendingReview, true);
    });
  });

  group('ConversationModel.fromJson', () {
    test('parses all fields', () {
      final c = ConversationModel.fromJson({
        'id': 1,
        'type': 'patient',
        'name': '张三',
        'patient_id': 5,
        'unread': 3,
      });

      expect(c.id, 1);
      expect(c.type, 'patient');
      expect(c.unread, 3);
    });
  });

  group('MessageModel.fromJson', () {
    test('parses all fields', () {
      final m = MessageModel.fromJson({
        'id': 100,
        'conversation_id': 1,
        'sender_kind': 'user',
        'sender_user_id': 1,
        'sender_name': '管理员',
        'message_type': 'text',
        'content': '你好',
        'created_at': '2025-01-01T00:00:00Z',
      });

      expect(m.id, 100);
      expect(m.content, '你好');
      expect(m.senderKind, 'user');
    });
  });
}
