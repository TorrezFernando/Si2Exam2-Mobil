import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/theme.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class ChatMessage {
  final String role;
  final String content;
  ChatMessage({required this.role, required this.content});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [
    ChatMessage(role: 'model', content: '¡Hola! Soy tu Asistente Inteligente de Moda. ¿En qué te puedo ayudar hoy? ✨')
  ];
  bool _isLoading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  late FlutterTts _flutterTts;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initTts();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done') {
            setState(() => _isListening = false);
            if (_controller.text.isNotEmpty) {
              _sendMessage();
            }
          }
        },
        onError: (val) => print('onError: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _controller.text = val.recognizedWords;
          }),
          localeId: 'es_ES',
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      if (_controller.text.isNotEmpty) {
        _sendMessage();
      }
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final messagesJson = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();
      final response = await ApiService.post('/ai/chat/', {'messages': messagesJson});
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _messages.add(ChatMessage(role: 'model', content: data['response']));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(role: 'model', content: 'Lo siento, ocurrió un error de comunicación. 😅'));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: 'model', content: 'Error de red. Inténtalo de nuevo.'));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✨ Asistente IA'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? AppTheme.bgHover : AppTheme.primary.withOpacity(0.1),
                      border: isUser ? null : Border.all(color: AppTheme.primary.withOpacity(0.2)),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.content,
                          style: TextStyle(
                            color: isUser ? AppTheme.textPrimary : AppTheme.primary,
                            fontSize: 15,
                          ),
                        ),
                        if (!isUser)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: InkWell(
                              onTap: () => _speak(msg.content),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.volume_up, size: 16, color: AppTheme.accent),
                                  const SizedBox(width: 4),
                                  Text("Escuchar", style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Escribiendo...', style: TextStyle(color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Pregunta sobre moda...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppTheme.bgHover,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPress: _listen,
                  onLongPressUp: _listen,
                  child: CircleAvatar(
                    backgroundColor: _isListening ? Colors.red : AppTheme.accent.withOpacity(0.2),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? Colors.white : AppTheme.accent,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppTheme.accent,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
