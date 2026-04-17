import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../models.dart';

class ChatRepository {
  final ApiClient _api;
  ChatRepository(this._api);

  Future<List<Map<String, dynamic>>> getChatUsers({String? query}) async {
    final res = await _api.get(ApiEndpoints.chatUsers, queryParameters: {
      if (query != null && query.isNotEmpty) 'query': query,
    });
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<ConversationModel>> getConversations() async {
    final res = await _api.get(ApiEndpoints.chatConversations);
    if (res['ok'] == true) {
      final items = res['data']?['items'] as List? ?? [];
      return items.map((e) => ConversationModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<ConversationModel> createConversation({
    required String type,
    int? targetUserId,
    int? patientId,
    String? name,
    List<int>? memberUserIds,
  }) async {
    final data = <String, dynamic>{'type': type};
    if (targetUserId != null) data['target_user_id'] = targetUserId;
    if (patientId != null) data['patient_id'] = patientId;
    if (name != null) data['name'] = name;
    if (memberUserIds != null) data['member_user_ids'] = memberUserIds;

    final res = await _api.post(ApiEndpoints.chatConversations, data: data);
    if (res['ok'] == true) {
      final conv = res['data']?['conversation'] ?? res['data'];
      return ConversationModel.fromJson(conv as Map<String, dynamic>);
    }
    throw Exception(res['error']?['message'] ?? '创建会话失败');
  }

  Future<Map<String, dynamic>> getMessages(int conversationId, {int limit = 50, int? beforeId}) async {
    final res = await _api.get(ApiEndpoints.chatMessages(conversationId), queryParameters: {
      'limit': limit,
      if (beforeId != null) 'before_id': beforeId,
    });
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取消息失败');
  }

  Future<MessageModel> sendMessage(int conversationId, {
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post(ApiEndpoints.chatMessages(conversationId), data: {
      'content': content,
      'message_type': messageType,
      if (payload != null) 'payload': payload,
    });
    if (res['ok'] == true) {
      return MessageModel.fromJson(res['data']['message'] as Map<String, dynamic>);
    }
    throw Exception(res['error']?['message'] ?? '发送失败');
  }

  Future<void> markRead(int conversationId) async {
    await _api.post(ApiEndpoints.chatRead(conversationId));
  }
}
