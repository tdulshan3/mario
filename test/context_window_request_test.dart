import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/openai_compatible_provider.dart';

class _CaptureClient extends http.BaseClient {
  String? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    body = await request.finalize().transform(utf8.decoder).join();
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: [DONE]\n\n')),
      200,
    );
  }
}

void main() {
  test('a chosen local context window is sent as num_ctx', () async {
    final client = _CaptureClient();
    final provider = OpenAiCompatibleProvider(
      id: 'local',
      displayName: 'Local',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'qwen',
      capabilities: const LlmCapabilities(contextTokens: 131072),
      clientFactory: () => client,
    );

    await provider.stream(const LlmRequest(messages: [])).drain<void>();
    final body = jsonDecode(client.body!) as Map<String, dynamic>;
    expect((body['options'] as Map)['num_ctx'], 131072);
  });

  test('a hosted model gets the budget without an unsupported options field',
      () async {
    final client = _CaptureClient();
    final provider = OpenAiCompatibleProvider(
      id: 'hosted',
      displayName: 'Hosted',
      baseUrl: 'https://api.openai.com/v1',
      model: 'model',
      capabilities: const LlmCapabilities(contextTokens: 131072),
      sendThinkingControls: false,
      sendContextWindowOption: false,
      clientFactory: () => client,
    );

    expect(provider.capabilities.contextTokens, 131072);
    await provider.stream(const LlmRequest(messages: [])).drain<void>();
    final body = jsonDecode(client.body!) as Map<String, dynamic>;
    expect(body, isNot(contains('options')));
  });
}
