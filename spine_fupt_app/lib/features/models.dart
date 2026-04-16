class PatientModel {
  final int id;
  final String name;
  final int? age;
  final String? sex;
  final String? phone;
  final String? email;
  final String? note;
  final String? portalToken;
  final String? portalUrl;
  final int? createdByUserId;
  final String? createdAt;
  final String? updatedAt;
  // List enrichments
  final String? status;
  final int? unreadCount;
  final String? lastExamDate;
  final int? examCount;

  PatientModel({
    required this.id,
    required this.name,
    this.age,
    this.sex,
    this.phone,
    this.email,
    this.note,
    this.portalToken,
    this.portalUrl,
    this.createdByUserId,
    this.createdAt,
    this.updatedAt,
    this.status,
    this.unreadCount,
    this.lastExamDate,
    this.examCount,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      age: json['age'] as int?,
      sex: json['sex'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      note: json['note'] as String?,
      portalToken: json['portal_token'] as String?,
      portalUrl: json['portal_url'] as String?,
      createdByUserId: json['created_by_user_id'] as int?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      status: json['status'] as String?,
      unreadCount: json['unread_count'] as int? ?? json['unread'] as int?,
      lastExamDate:
          json['last_exam_date'] as String? ?? json['last_followup'] as String?,
      examCount: json['exam_count'] as int?,
    );
  }
}

class ExamModel {
  final int id;
  final int patientId;
  final String? patientName;
  final String? imagePath;
  final String? imageUrl;
  final String? rawImageUrl;
  final String? inferenceImagePath;
  final String? inferenceImageUrl;
  final String status;
  final String? spineClass;
  final String? spineClassText;
  final int? spineClassId;
  final double? spineClassConfidence;
  final double? cobbAngle;
  final double? curveValue;
  final String? severityLabel;
  final double? improvementValue;
  final String? reviewNote;
  final int? reviewedByUserId;
  final String? reviewedAt;
  final Map<String, dynamic>? inferenceJson;
  final Map<String, dynamic>? cervicalMetric;
  final Map<String, dynamic>? shareLink;
  final List<Map<String, dynamic>>? comments;
  final String? commentChannel;
  final String? createdAt;
  final String? uploadedByKind;
  final String? uploadedByLabel;

  ExamModel({
    required this.id,
    required this.patientId,
    this.patientName,
    this.imagePath,
    this.imageUrl,
    this.rawImageUrl,
    this.inferenceImagePath,
    this.inferenceImageUrl,
    required this.status,
    this.spineClass,
    this.spineClassText,
    this.spineClassId,
    this.spineClassConfidence,
    this.cobbAngle,
    this.curveValue,
    this.severityLabel,
    this.improvementValue,
    this.reviewNote,
    this.reviewedByUserId,
    this.reviewedAt,
    this.inferenceJson,
    this.cervicalMetric,
    this.shareLink,
    this.comments,
    this.commentChannel,
    this.createdAt,
    this.uploadedByKind,
    this.uploadedByLabel,
  });

  factory ExamModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? infJson;
    if (json['inference'] is Map) {
      infJson = json['inference'] as Map<String, dynamic>;
    } else if (json['inference_json'] is Map) {
      infJson = json['inference_json'] as Map<String, dynamic>;
    }

    List<Map<String, dynamic>>? cmts;
    if (json['comments'] is List) {
      cmts = (json['comments'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    }

    return ExamModel(
      id: json['id'] as int,
      patientId: json['patient_id'] as int? ?? 0,
      patientName: json['patient_name'] as String?,
      imagePath: json['image_path'] as String?,
      imageUrl: json['image_url'] as String?,
      rawImageUrl: json['raw_image_url'] as String?,
      inferenceImagePath: json['inference_image_path'] as String?,
      inferenceImageUrl: json['inference_image_url'] as String?,
      status: json['status'] as String? ?? 'pending_review',
      spineClass: json['spine_class'] as String?,
      spineClassText: json['spine_class_text'] as String?,
      spineClassId: json['spine_class_id'] as int?,
      spineClassConfidence: (json['spine_class_confidence'] as num?)
          ?.toDouble(),
      cobbAngle: (json['cobb_angle'] as num?)?.toDouble(),
      curveValue: (json['curve_value'] as num?)?.toDouble(),
      severityLabel: json['severity_label'] as String?,
      improvementValue: (json['improvement_value'] as num?)?.toDouble(),
      reviewNote: json['review_note'] as String?,
      reviewedByUserId: json['reviewed_by_user_id'] as int?,
      reviewedAt: json['reviewed_at'] as String?,
      inferenceJson: infJson,
      cervicalMetric: json['cervical_metric'] as Map<String, dynamic>?,
      shareLink: json['share_link'] as Map<String, dynamic>?,
      comments: cmts,
      commentChannel: json['comment_channel'] as String?,
      createdAt:
          json['created_at'] as String? ?? json['upload_date'] as String?,
      uploadedByKind: json['uploaded_by_kind'] as String?,
      uploadedByLabel: json['uploaded_by_label'] as String?,
    );
  }

  bool get isLumbar => spineClass == 'lumbar';
  bool get isCervical => spineClass == 'cervical';
  bool get hasAiImage =>
      inferenceImageUrl != null && inferenceImageUrl!.isNotEmpty;
  bool get isInferring => status == 'inferring';
  bool get isPendingReview => status == 'pending_review';
  bool get isReviewed => status == 'reviewed';
  bool get isFailed => status == 'inference_failed';
}

class ConversationModel {
  final int id;
  final String type;
  final String? name;
  final int? patientId;
  final String? updatedAt;
  final int unread;
  final Map<String, dynamic>? lastMessage;

  ConversationModel({
    required this.id,
    required this.type,
    this.name,
    this.patientId,
    this.updatedAt,
    this.unread = 0,
    this.lastMessage,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'private',
      name: json['name'] as String?,
      patientId: json['patient_id'] as int?,
      updatedAt: json['updated_at'] as String?,
      unread: json['unread'] as int? ?? 0,
      lastMessage: json['last_message'] as Map<String, dynamic>?,
    );
  }
}

class MessageModel {
  final int id;
  final int conversationId;
  final String senderKind;
  final int? senderUserId;
  final String senderName;
  final String messageType;
  final String content;
  final Map<String, dynamic>? payload;
  final String? createdAt;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderKind,
    this.senderUserId,
    required this.senderName,
    required this.messageType,
    required this.content,
    this.payload,
    this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int? ?? 0,
      senderKind: json['sender_kind'] as String? ?? 'user',
      senderUserId: json['sender_user_id'] as int?,
      senderName: json['sender_name'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      payload: json['payload'] is Map
          ? json['payload'] as Map<String, dynamic>
          : null,
      createdAt: json['created_at'] as String?,
    );
  }
}
