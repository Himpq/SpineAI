import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../providers.dart';

class AiDoctorScreen extends ConsumerStatefulWidget {
  /// If non-null, attach to the first message for richer AI context.
  final Map<String, dynamic>? inferenceContext;
  const AiDoctorScreen({super.key, this.inferenceContext});

  @override
  ConsumerState<AiDoctorScreen> createState() => _AiDoctorScreenState();
}

class _AiDoctorScreenState extends ConsumerState<AiDoctorScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMsg> _messages = [];
  String? _sessionToken;
  bool _sending = false;
  bool _loading = true;
  bool _uploadingImage = false;
  Map<String, dynamic>? _latestInferenceContext;
  final List<String> _pendingImagePaths = [];
  final List<Map<String, dynamic>> _pendingInferenceResults = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isPatient {
    final auth = ref.read(authProvider);
    return auth.mode == AuthMode.patient;
  }

  String? get _portalToken {
    final auth = ref.read(authProvider);
    return auth.portalToken;
  }

  Future<void> _loadHistory() async {
    // When inferenceContext is provided (from exam detail / try-inference),
    // always start a fresh session instead of loading old history.
    if (widget.inferenceContext != null) {
      if (mounted) setState(() => _loading = false);
      // Auto-send interpretation request after frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.text = '请根据我的检查结果，给我详细解读各项指标含义、健康状况评估和建议。';
          _send();
        }
      });
      return;
    }
    // For patient mode, try to load existing sessions
    if (_isPatient && _portalToken != null) {
      try {
        final api = ApiClient.instance;
        final resp = await api.get(
          ApiEndpoints.publicPortalAiMessages(_portalToken!),
        );
        if (resp['ok'] == true && resp['data'] != null) {
          final data = resp['data'] as Map<String, dynamic>;
          // If sessions list returned, pick the first (most recent)
          if (data.containsKey('sessions')) {
            final sessions = data['sessions'] as List? ?? [];
            if (sessions.isNotEmpty) {
              final first = sessions.first as Map<String, dynamic>;
              _sessionToken = first['session_token'] as String?;
              if (_sessionToken != null) {
                await _loadSessionMessages();
              }
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSessionMessages() async {
    if (_sessionToken == null) return;
    try {
      final api = ApiClient.instance;
      Map<String, dynamic> resp;
      if (_isPatient && _portalToken != null) {
        resp = await api.get(
          ApiEndpoints.publicPortalAiMessages(_portalToken!),
          queryParameters: {'session_token': _sessionToken},
        );
      } else {
        resp = await api.get(
          ApiEndpoints.publicAiChatMessages(_sessionToken!),
        );
      }
      if (resp['ok'] == true && resp['data'] != null) {
        final msgs = (resp['data']['messages'] as List?) ?? [];
        _messages.clear();
        for (final m in msgs) {
          _messages.add(_ChatMsg(
            role: m['role'] as String,
            content: m['content'] as String,
          ));
        }
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadImage() async {
    if (_sending || _uploadingImage) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: source, imageQuality: 85);
    if (xFile == null) return;

    setState(() => _uploadingImage = true);

    try {
      final api = ApiClient.instance;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(xFile.path, filename: xFile.name),
      });
      final resp = await api.dio.post(
        ApiEndpoints.publicTryInference,
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      final data = resp.data as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? '推理失败');
      final result = data['data'] as Map<String, dynamic>;

      // Build inference context from result
      final ctx = <String, dynamic>{
        'spine_class': result['spine_class'],
        'spine_class_text': result['spine_class_text'],
        'spine_class_confidence': result['spine_class_confidence'],
      };
      if (result['cobb_angle'] != null) ctx['cobb_angle'] = result['cobb_angle'];
      if (result['severity_label'] != null) ctx['severity_label'] = result['severity_label'];
      if (result['cervical_metric'] != null) ctx['cervical_metric'] = result['cervical_metric'];

      setState(() {
        _pendingImagePaths.add(xFile.path);
        _pendingInferenceResults.add(ctx);
        _latestInferenceContext = ctx;
        _uploadingImage = false;
      });
    } catch (e) {
      setState(() => _uploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('影像上传失败：${ApiClient.friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Capture pending images before clearing
    final sentImagePaths = List<String>.from(_pendingImagePaths);

    setState(() {
      _messages.add(_ChatMsg(
        role: 'user',
        content: text,
        imagePaths: sentImagePaths.isNotEmpty ? sentImagePaths : null,
      ));
      _sending = true;
      _pendingImagePaths.clear();
    });
    _controller.clear();
    _scrollToBottom();

    // Add empty assistant bubble for streaming
    final assistantIdx = _messages.length;
    setState(() {
      _messages.add(_ChatMsg(role: 'assistant', content: ''));
    });

    try {
      final api = ApiClient.instance;
      final body = <String, dynamic>{
        'message': text,
      };
      if (_sessionToken != null) body['session_token'] = _sessionToken;
      // Attach inference context: from image upload or from navigation param
      final activeCtx = _latestInferenceContext ?? widget.inferenceContext;
      if (activeCtx != null &&
          _messages.where((m) => m.role == 'user').length == 1) {
        body['inference_context'] = activeCtx;
      }
      // Also attach if there were pending inference results for this message
      if (_pendingInferenceResults.isNotEmpty) {
        body['inference_context'] = _pendingInferenceResults.last;
        _pendingInferenceResults.clear();
      }

      String streamUrl;
      if (_isPatient && _portalToken != null) {
        streamUrl = ApiEndpoints.publicPortalAiChatStream(_portalToken!);
      } else {
        streamUrl = ApiEndpoints.publicAiChatStream;
      }

      final response = await api.dio.post<ResponseBody>(
        streamUrl,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      String buffer = '';
      final stream = response.data!.stream;

      await for (final bytes in stream) {
        buffer += utf8.decode(bytes);
        // Process complete SSE messages (separated by double newline)
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 2);

          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6);
          try {
            final data = json.decode(jsonStr) as Map<String, dynamic>;
            if (data.containsKey('delta')) {
              final delta = data['delta'] as String? ?? '';
              setState(() {
                _messages[assistantIdx] = _ChatMsg(
                  role: 'assistant',
                  content: _messages[assistantIdx].content + delta,
                );
              });
              _scrollToBottom();
            } else if (data.containsKey('done')) {
              _sessionToken = data['session_token'] as String?;
            } else if (data.containsKey('error')) {
              setState(() {
                _messages[assistantIdx] = _ChatMsg(
                  role: 'assistant',
                  content: 'AI回复失败：${data['error']}',
                  isError: true,
                );
              });
            }
          } catch (_) {}
        }
      }

      // If empty response
      if (_messages[assistantIdx].content.isEmpty && !_messages[assistantIdx].isError) {
        setState(() {
          _messages[assistantIdx] = _ChatMsg(
            role: 'assistant',
            content: '抱歉，AI未返回内容，请重试。',
            isError: true,
          );
        });
      }
    } catch (e) {
      // If the assistant bubble was already added but still empty
      if (assistantIdx < _messages.length && _messages[assistantIdx].content.isEmpty) {
        setState(() {
          _messages[assistantIdx] = _ChatMsg(
            role: 'assistant',
            content: '网络错误：${ApiClient.friendlyError(e)}',
            isError: true,
          );
        });
      } else {
        setState(() {
          _messages.add(_ChatMsg(
            role: 'assistant',
            content: '网络错误：${ApiClient.friendlyError(e)}',
            isError: true,
          ));
        });
      }
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startNewSession() {
    setState(() {
      _sessionToken = null;
      _messages.clear();
      _latestInferenceContext = null;
      _pendingImagePaths.clear();
      _pendingInferenceResults.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI医生',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
              letterSpacing: -0.3,
            )),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh,
                color: Color(0xFF8E8E93), size: 22),
            tooltip: '刷新对话',
            onPressed: _startNewSession,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Welcome view when no messages
          if (_messages.isEmpty && !_loading)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Minimal icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.smart_toy_outlined,
                            size: 30, color: Color(0xFFBBBBC3)),
                      ),
                      const SizedBox(height: 20),
                      const Text('AI脊柱健康助手',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.3,
                          )),
                      const SizedBox(height: 8),
                      const Text(
                        '解答脊柱侧弯、颈椎病、Cobb角解读\n与康复建议等相关问题',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8E8E93),
                          height: 1.5,
                        ),
                      ),
                      if (widget.inferenceContext != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: Color(0xFF34C759), size: 15),
                              SizedBox(width: 6),
                              Text('已关联推理结果',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF34C759))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Suggestion pills
                      _SuggestionPill('我的检测结果正常吗？', onTap: () {
                        _controller.text = '我的检测结果正常吗？';
                        _send();
                      }),
                      const SizedBox(height: 8),
                      _SuggestionPill('Cobb角多少度需要手术？', onTap: () {
                        _controller.text = 'Cobb角多少度需要手术？';
                        _send();
                      }),
                      const SizedBox(height: 8),
                      _SuggestionPill('日常如何保护脊柱？', onTap: () {
                        _controller.text = '日常如何保护脊柱？';
                        _send();
                      }),
                    ],
                  ),
                ),
              ),
            ),

          // Messages
          if (_messages.isNotEmpty || _loading)
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = _messages[i];
                        if (_sending &&
                            i == _messages.length - 1 &&
                            msg.role == 'assistant' &&
                            msg.content.isEmpty) {
                          return _buildTypingIndicator();
                        }
                        return _buildMessageBubble(msg);
                      },
                    ),
            ),

          // ── Image preview + Input bar ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pending image preview row
                  if (_pendingImagePaths.isNotEmpty || _uploadingImage)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: 72,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingImagePaths.length + (_uploadingImage ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (_uploadingImage && i == _pendingImagePaths.length) {
                            // Uploading indicator
                            return Container(
                              width: 72,
                              height: 72,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final path = _pendingImagePaths[i];
                          return Stack(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  image: DecorationImage(
                                    image: FileImage(File(path)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _pendingImagePaths.removeAt(i);
                                      if (i < _pendingInferenceResults.length) {
                                        _pendingInferenceResults.removeAt(i);
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: Color(0x99000000),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  // Input bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Image upload button
                        Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 7),
                          child: GestureDetector(
                            onTap: (_sending || _uploadingImage) ? null : _pickAndUploadImage,
                            child: Icon(
                              Icons.add_circle,
                              color: (_sending || _uploadingImage)
                                  ? const Color(0xFFD1D1D6)
                                  : const Color(0xFF3478F6),
                              size: 26,
                            ),
                          ),
                        ),
                        // Text field
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: '输入问题…',
                              hintStyle: TextStyle(
                                  color: Color(0xFFC7C7CC), fontSize: 15),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.fromLTRB(10, 11, 4, 11),
                              isDense: true,
                            ),
                            style: const TextStyle(
                                fontSize: 15, color: Color(0xFF1A1A1A)),
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        // Send button inside the input bar
                        Padding(
                          padding: const EdgeInsets.only(right: 5, bottom: 5),
                          child: GestureDetector(
                            onTap: _sending ? null : _send,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _sending
                                    ? const Color(0xFFD1D1D6)
                                    : const Color(0xFF3478F6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.arrow_upward,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isError
              ? const Color(0xFFFEF2F2)
              : isUser
                  ? const Color(0xFF3478F6)
                  : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image thumbnails
            if (msg.imagePaths != null && msg.imagePaths!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: msg.imagePaths!.map((path) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, size: 32),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            _MdContent(
              content: msg.content,
              textColor: msg.isError
                  ? const Color(0xFFDC2626)
                  : isUser
                      ? Colors.white
                      : const Color(0xFF1A1A1A),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF8E8E93),
              ),
            ),
            SizedBox(width: 8),
            Text('思考中…',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF8E8E93))),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  final String role;
  final String content;
  final bool isError;
  final List<String>? imagePaths;
  _ChatMsg({required this.role, required this.content, this.isError = false, this.imagePaths});
}

/// iOS-style full-width suggestion pill.
class _SuggestionPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionPill(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF3C3C43),
                  )),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}

// ─── Markdown + LaTeX content widget ──────────────────────────────

/// Renders markdown text with inline/block LaTeX.
/// Inline: `$...$`  Block: `$$...$$`
class _MdContent extends StatelessWidget {
  final String content;
  final Color textColor;
  const _MdContent({required this.content, required this.textColor});

  @override
  Widget build(BuildContext context) {
    // Pre-process: convert LaTeX blocks into HTML-style tags that the
    // custom inline syntax can pick up. Block-level $$ must come first.
    final processed = content;

    return MarkdownBody(
      data: processed,
      selectable: true,
      shrinkWrap: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [
          _LatexBlockSyntax(),
          _LatexInlineSyntax(),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
      builders: {
        'latex': _LatexBuilder(textColor: textColor),
        'latexBlock': _LatexBlockBuilder(textColor: textColor),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 15, height: 1.5, color: textColor),
        strong: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
        em: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: textColor),
        h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor),
        h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
        h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
        listBullet: TextStyle(fontSize: 15, color: textColor),
        code: TextStyle(
          fontSize: 13,
          color: textColor,
          backgroundColor: textColor == Colors.white
              ? Colors.white.withOpacity(0.15)
              : const Color(0xFFF0F0F3),
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: textColor == Colors.white
              ? Colors.white.withOpacity(0.1)
              : const Color(0xFFF0F0F3),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockSpacing: 10,
      ),
    );
  }
}

/// Matches `$$...$$` (block LaTeX).
class _LatexBlockSyntax extends md.InlineSyntax {
  _LatexBlockSyntax() : super(r'\$\$([^$]+?)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('latexBlock', match[1]!.trim());
    parser.addNode(el);
    return true;
  }
}

/// Matches `$...$` (inline LaTeX) — single $ only.
class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax() : super(r'\$([^$\n]+?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('latex', match[1]!.trim());
    parser.addNode(el);
    return true;
  }
}

/// Renders inline LaTeX as styled italic text.
class _LatexBuilder extends MarkdownElementBuilder {
  final Color textColor;
  _LatexBuilder({required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Text(
      tex,
      style: TextStyle(
        fontSize: 15,
        color: textColor,
        fontStyle: FontStyle.italic,
        fontFamily: 'serif',
      ),
    );
  }
}

/// Renders block LaTeX centered as styled text.
class _LatexBlockBuilder extends MarkdownElementBuilder {
  final Color textColor;
  _LatexBlockBuilder({required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          tex,
          style: TextStyle(
            fontSize: 17,
            color: textColor,
            fontStyle: FontStyle.italic,
            fontFamily: 'serif',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
