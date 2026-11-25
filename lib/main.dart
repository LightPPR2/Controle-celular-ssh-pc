import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartssh2/dartssh2.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    themeMode: ThemeMode.dark,
    home: const HomeScreen(),
  ));
}

class SshSessionModel {
  String name;
  String host;
  int port;
  String username;
  String password;

  SshSessionModel({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };

  factory SshSessionModel.fromJson(Map<String, dynamic> json) => SshSessionModel(
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 22,
        username: json['username'] as String,
        password: (json['password'] as String?) ?? '',
      );
}

// ───────────────────────── TELA INICIAL ─────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SshSessionModel> sessions = [];
  int? selectedIndex;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('ssh_sessions');
      if (data != null) {
        final List decoded = jsonDecode(data);
        if (!mounted) return;
        setState(() {
          sessions = decoded
              .map((e) => SshSessionModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        });
      }
    } catch (_) {
      // dados corrompidos: começa vazio
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(sessions.map((e) => e.toJson()).toList());
    await prefs.setString('ssh_sessions', encoded);
  }

  void _openRegisterDialog() {
    final nameCtrl = TextEditingController();
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '22');
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar Sessão SSH'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome (ex: Meu PC)')),
              TextField(controller: hostCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'IP SSH (ex: 192.168.1.10)')),
              TextField(controller: portCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Porta')),
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Usuário')),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (hostCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty) return;
              setState(() {
                sessions.add(SshSessionModel(
                  name: nameCtrl.text.trim().isEmpty ? hostCtrl.text.trim() : nameCtrl.text.trim(),
                  host: hostCtrl.text.trim(),
                  port: int.tryParse(portCtrl.text.trim()) ?? 22,
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                ));
              });
              _saveSessions();
              Navigator.pop(dialogContext);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      hostCtrl.dispose();
      portCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
    });
  }

  Future<void> _confirmDelete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remover sessão?'),
        content: Text(sessions[index].name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      sessions.removeAt(index);
      if (selectedIndex == index) {
        selectedIndex = null;
      } else if (selectedIndex != null && selectedIndex! > index) {
        selectedIndex = selectedIndex! - 1;
      }
    });
    _saveSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controle PC via SSH')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: sessions.isEmpty
                  ? const Center(child: Text('Nenhuma sessão salva.\nClique em Registrar abaixo.', textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final s = sessions[index];
                        final isSelected = selectedIndex == index;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withValues(alpha: 0.2),
                          leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
                          title: Text(s.name),
                          subtitle: Text('${s.username}@${s.host}:${s.port}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _confirmDelete(index),
                          ),
                          onTap: () => setState(() => selectedIndex = index),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openRegisterDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Registrar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: selectedIndex == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ControlScreen(session: sessions[selectedIndex!]),
                                ),
                              );
                            },
                      icon: const Icon(Icons.login),
                      label: const Text('Logar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── TELA DE CONTROLE ─────────────────────────

enum LogKind { info, input, output, error }

class _LogLine {
  final String text;
  final LogKind kind;
  _LogLine(this.text, this.kind);
}

class _Shortcut {
  final String label;
  final IconData icon;
  final Color color;
  final String command;
  final bool confirm;
  final bool expectDisconnect;

  const _Shortcut({
    required this.label,
    required this.icon,
    required this.color,
    required this.command,
    this.confirm = false,
    this.expectDisconnect = false,
  });
}

class ControlScreen extends StatefulWidget {
  final SshSessionModel session;
  const ControlScreen({super.key, required this.session});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  static const double _btnWidth = 298;
  static const double _btnHeight = 120;
  static const int _maxLogLines = 500;

  SSHClient? _client;
  bool _connected = false;
  bool _connecting = false;
  bool _busy = false;

  final List<_LogLine> _log = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // O SSH do Windows roda na sessão 0 (sem tela). Para o Explorer aparecer
  // na área de trabalho usamos uma tarefa agendada interativa (/it).
  late final List<_Shortcut> _shortcuts = [
    _Shortcut(
      label: 'Abrir Explorer',
      icon: Icons.folder_open,
      color: Colors.blue,
      command: 'schtasks /create /tn "RemoteExplorer" /tr "explorer.exe" /sc once '
          '/st 00:00 /ru "${widget.session.username}" /it /f && '
          'schtasks /run /tn "RemoteExplorer"',
    ),
    const _Shortcut(
      label: 'Reiniciar PC',
      icon: Icons.restart_alt,
      color: Colors.orange,
      command: 'shutdown /f /r /t 0',
      confirm: true,
      expectDisconnect: true,
    ),
    const _Shortcut(
      label: 'Desligar PC',
      icon: Icons.power_settings_new,
      color: Colors.red,
      command: 'shutdown /f /s /t 0',
      confirm: true,
      expectDisconnect: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _client?.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── log ──

  void _addLog(String text, LogKind kind) {
    if (!mounted) return;
    setState(() {
      _log.add(_LogLine(text, kind));
      if (_log.length > _maxLogLines) {
        _log.removeRange(0, _log.length - _maxLogLines);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  String _decode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  // ── conexão ──

  Future<bool> _connect() async {
    final current = _client;
    if (_connected && current != null && !current.isClosed) return true;
    if (_connecting) return false;

    setState(() => _connecting = true);
    _addLog('Conectando em ${widget.session.host}:${widget.session.port}...', LogKind.info);
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        widget.session.host,
        widget.session.port,
        timeout: const Duration(seconds: 8),
      );
      client = SSHClient(
        socket,
        username: widget.session.username,
        onPasswordRequest: () => widget.session.password,
      );
      await client.authenticated.timeout(const Duration(seconds: 10));

      final c = client;
      c.done.then((_) {
        if (mounted && _client == c) {
          setState(() => _connected = false);
          _addLog('Conexão encerrada.', LogKind.info);
        }
      }, onError: (_) {
        if (mounted && _client == c) setState(() => _connected = false);
      });

      _client = client;
      if (mounted) setState(() => _connected = true);
      _addLog('Conectado.', LogKind.info);
      return true;
    } catch (e) {
      client?.close();
      if (mounted) setState(() => _connected = false);
      _addLog('Falha ao conectar: $e', LogKind.error);
      return false;
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  // ── execução de comandos ──

  Future<void> _exec(String command, {bool expectDisconnect = false}) async {
    command = command.trim();
    if (command.isEmpty || _busy) return;

    setState(() => _busy = true);
    _addLog('> $command', LogKind.input);

    try {
      if (!await _connect()) return;

      final session = await _client!.execute(command);
      final outBytes = <int>[];
      final errBytes = <int>[];
      session.stdout.listen(outBytes.addAll, onError: (_) {});
      session.stderr.listen(errBytes.addAll, onError: (_) {});

      try {
        await session.done.timeout(const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 50));
      } on TimeoutException {
        _addLog('(sem fim em 15s; o comando pode continuar rodando no PC)', LogKind.info);
        session.close();
      }

      final out = _decode(outBytes).trimRight();
      final err = _decode(errBytes).trimRight();
      if (out.isNotEmpty) _addLog(out, LogKind.output);
      if (err.isNotEmpty) _addLog(err, LogKind.error);

      final code = session.exitCode;
      if (out.isEmpty && err.isEmpty) {
        _addLog(code == null || code == 0 ? '(ok, sem saída)' : '(código de saída: $code)', LogKind.info);
      } else if (code != null && code != 0) {
        _addLog('(código de saída: $code)', LogKind.info);
      }
    } catch (e) {
      if (expectDisconnect) {
        _addLog('Comando enviado. O PC está desligando/reiniciando.', LogKind.info);
      } else {
        _addLog('Erro SSH: $e', LogKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runShortcut(_Shortcut s) async {
    if (s.confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.label),
          content: const Text('Tem certeza?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _exec(s.command, expectDisconnect: s.expectDisconnect);
  }

  void _sendTyped() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty || _busy) return;
    _inputCtrl.clear();
    final lower = text.toLowerCase();
    _exec(
      text,
      expectDisconnect: lower.contains('shutdown') || lower.contains('restart-computer'),
    );
    _inputFocus.requestFocus();
  }

  // ── UI ──

  Color _colorFor(LogKind k) {
    switch (k) {
      case LogKind.input:
        return Colors.cyanAccent;
      case LogKind.output:
        return Colors.white;
      case LogKind.error:
        return Colors.redAccent;
      case LogKind.info:
        return Colors.amberAccent;
    }
  }

  Widget _buildShortcutButton(_Shortcut s) {
    return SizedBox(
      width: _btnWidth,
      height: _btnHeight,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _busy ? null : () => _runShortcut(s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(s.icon, size: 38),
            const SizedBox(height: 8),
            Text(s.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3);
    return Container(
      color: const Color(0xFF0C0C0C),
      child: Column(
        children: [
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(10),
                itemCount: _log.length,
                itemBuilder: (context, i) {
                  final line = _log[i];
                  return Text(line.text, style: mono.copyWith(color: _colorFor(line.kind)));
                },
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text('>', style: mono.copyWith(color: Colors.cyanAccent, fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
                    style: mono.copyWith(color: Colors.white, fontSize: 14),
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendTyped(),
                    decoration: const InputDecoration(
                      hintText: 'Digite um comando...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.cyanAccent),
                  onPressed: _busy ? null : _sendTyped,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.name),
        actions: [
          Icon(
            Icons.circle,
            size: 12,
            color: _connecting
                ? Colors.amber
                : (_connected ? Colors.greenAccent : Colors.redAccent),
          ),
          IconButton(
            tooltip: 'Reconectar',
            icon: const Icon(Icons.refresh),
            onPressed: _connecting
                ? null
                : () {
                    _client?.close();
                    _connected = false;
                    _connect();
                  },
          ),
          IconButton(
            tooltip: 'Limpar terminal',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => setState(_log.clear),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: _shortcuts.map(_buildShortcutButton).toList(),
                  ),
                ),
              ),
            ),
            Expanded(flex: 4, child: _buildTerminal()),
          ],
        ),
      ),
    );
  }
}
