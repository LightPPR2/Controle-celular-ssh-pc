import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SshTerminalApp());
}

class SshTerminalApp extends StatelessWidget {
  const SshTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LightPPR2 SSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D9A6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090D12),
        useMaterial3: true,
      ),
      home: const SessionsScreen(),
    );
  }
}

const _secureStorage = FlutterSecureStorage();
const _sessionsKey = 'ssh_sessions_v2';

class SshProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;

  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
      };

  factory SshProfile.fromJson(Map<String, dynamic> json) {
      return SshProfile(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? 'SSH',
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: (json['username'] as String?) ?? '',
    );
  }
}

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final List<SshProfile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionsKey) ??
          prefs.getString('ssh_sessions');

      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item as Map);
          final legacyPassword = map['password'] as String?;
          final profile = SshProfile.fromJson(map);

          if (legacyPassword != null && legacyPassword.isNotEmpty) {
            await _secureStorage.write(
              key: 'ssh_password_${profile.id}',
              value: legacyPassword,
            );
          }

          if (profile.host.isNotEmpty && profile.username.isNotEmpty) {
            _profiles.add(profile);
          }
        }
        await _saveProfiles();
        await prefs.remove('ssh_sessions');
      }
    } catch (e) {
      _showMessage('Não foi possível carregar as sessões: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addProfile() async {
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final username = TextEditingController();
    final password = TextEditingController();

    final result = await showDialog<SshProfile>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nova conexão SSH'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(
                controller: host,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Host / IP'),
              ),
              TextField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Porta'),
              ),
              TextField(controller: username, decoration: const InputDecoration(labelText: 'Usuário')),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final parsedPort = int.tryParse(port.text.trim());
              if (host.text.trim().isEmpty ||
                  username.text.trim().isEmpty ||
                  parsedPort == null ||
                  parsedPort < 1 ||
                  parsedPort > 65535) {
                return;
              }

              final id = DateTime.now().microsecondsSinceEpoch.toString();
              Navigator.pop(
                dialogContext,
                SshProfile(
                  id: id,
                  name: name.text.trim().isEmpty
                      ? host.text.trim()
                      : name.text.trim(),
                  host: host.text.trim(),
                  port: parsedPort,
                  username: username.text.trim(),
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _secureStorage.write(
        key: 'ssh_password_${result.id}',
        value: password.text,
      );
      setState(() => _profiles.add(result));
      await _saveProfiles();
    }

    name.dispose();
    host.dispose();
    port.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> _deleteProfile(SshProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover conexão?'),
        content: Text(profile.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _profiles.removeWhere((p) => p.id == profile.id));
    await _secureStorage.delete(key: 'ssh_password_${profile.id}');
    await _saveProfiles();
  }

  Future<void> _openProfile(SshProfile profile) async {
    final password = await _secureStorage.read(
      key: 'ssh_password_${profile.id}',
    );
    if (!mounted) return;

    if (password == null || password.isEmpty) {
      _showMessage('Senha não cadastrada. Remova e registre a sessão novamente.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          profile: profile,
          password: password,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LightPPR2 SSH'),
        actions: [
          IconButton(
            onPressed: _addProfile,
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar conexão',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProfile,
        icon: const Icon(Icons.add),
        label: const Text('Nova conexão'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.terminal, size: 56, color: Colors.white38),
                      SizedBox(height: 12),
                      Text('Nenhuma conexão cadastrada'),
                      Text(
                        'Adicione um servidor SSH para começar.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: _profiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.dns_outlined),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${profile.username}@${profile.host}:${profile.port}',
                        ),
                        onTap: () => _openProfile(profile),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteProfile(profile),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  final SshProfile profile;
  final String password;

  const TerminalScreen({
    super.key,
    required this.profile,
    required this.password,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  bool _ctrlLatched = false;

  bool _connecting = false;
  bool _connected = false;
  bool _disposed = false;
  String _status = 'Desconectado';

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminal.onOutput = _sendToShell;
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  void _write(String text) {
    if (_disposed) return;
    _terminal.write(text);
  }

  Future<void> _connect() async {
    if (_connecting || _connected || _disposed) return;

    setState(() {
      _connecting = true;
      _status = 'Conectando...';
    });
    _write('\x1b[1;36mConectando a ${widget.profile.username}@${widget.profile.host}:${widget.profile.port}...\x1b[0m\r\n');

    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        widget.profile.host,
        widget.profile.port,
        timeout: const Duration(seconds: 15),
      );

      client = SSHClient(
        socket,
        username: widget.profile.username,
        onPasswordRequest: () => widget.password,
      );

      await client.authenticated.timeout(const Duration(seconds: 20));
      if (_disposed) {
        client.close();
        return;
      }

      _client = client;

      // Uma shell com PTY mantém o mesmo processo e o mesmo diretório
      // entre comandos, ao contrário de SSHClient.execute().
      final shell = await client.shell(
        pty: const SSHPtyConfig(
          type: 'xterm-256color',
          width: 80,
          height: 24,
        ),
      );

      if (_disposed) {
        shell.close();
        client.close();
        return;
      }

      _shell = shell;
      _stdoutSubscription = shell.stdout.listen(
        (data) => _write(utf8.decode(data, allowMalformed: true)),
        onError: (error) => _handleDisconnect('Erro na saída SSH: $error'),
        onDone: () => _handleDisconnect('Shell encerrado pelo servidor.'),
      );
      _stderrSubscription = shell.stderr.listen(
        (data) => _write(utf8.decode(data, allowMalformed: true)),
        onError: (error) => _handleDisconnect('Erro stderr: $error'),
      );

      setState(() {
        _connected = true;
        _connecting = false;
        _status = 'Conectado';
      });
      _write('\r\n\x1b[1;32mConexão SSH estabelecida.\x1b[0m\r\n');
    } catch (e) {
      client?.close();
      if (!_disposed && mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _status = 'Falha na conexão';
        });
        _write('\r\n\x1b[1;31mFalha SSH: $e\x1b[0m\r\n');
      }
    }
  }

  void _sendToShell(String data) {
    final shell = _shell;
    if (shell == null || !_connected) return;

    try {
      var outgoing = data;
      if (_ctrlLatched && data.length == 1) {
        final code = data.toLowerCase().codeUnitAt(0);
        if (code >= 97 && code <= 122) {
          outgoing = String.fromCharCode(code - 96);
        }
        _ctrlLatched = false;
      }
      shell.stdin.add(Uint8List.fromList(utf8.encode(outgoing))); 
    } catch (e) {
      _write('\r\n\x1b[31mFalha ao enviar dados: $e\x1b[0m\r\n');
    }
  }

  void _handleDisconnect(String message) {
    if (_disposed || !mounted) return;
    setState(() {
      _connected = false;
      _connecting = false;
      _status = 'Desconectado';
    });
    _write('\r\n\x1b[1;33m$message\x1b[0m\r\n');
  }

  Future<void> _disconnect() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    _shell?.close();
    _shell = null;
    _client?.close();
    _client = null;

    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _status = 'Desconectado';
      });
    }
  }

  Future<void> _reconnect() async {
    await _disconnect();
    _write('\r\n\x1b[1;36mTentando reconectar...\x1b[0m\r\n');
    await _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _shell?.close();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _connected
        ? Colors.greenAccent
        : (_connecting ? Colors.amber : Colors.redAccent);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.profile.name, style: const TextStyle(fontSize: 16)),
            Text(
              '${widget.profile.username}@${widget.profile.host}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Row(
                children: [
                  Icon(Icons.circle, size: 10, color: statusColor),
                  const SizedBox(width: 6),
                  Text(_status, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reconectar',
            onPressed: _connecting ? null : _reconnect,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Limpar terminal',
            onPressed: () => _terminal.write('\x1b[2J\x1b[H'),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFF050708),
                child: TerminalView(
                  _terminal,
                  autofocus: true,
                ),
              ),
            ),
            if (_connecting) const LinearProgressIndicator(minHeight: 2),
            Container(
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFF111820),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: [
                  _keyButton('ESC', '\x1b'),
                  _keyButton('TAB', '\t'),
                  _keyButton('CTRL', '__CTRL__'),
                  _keyButton('↑', '\x1b[A'),
                  _keyButton('↓', '\x1b[B'),
                  _keyButton('←', '\x1b[D'),
                  _keyButton('→', '\x1b[C'),
                  _keyButton('|', '|'),
                  _keyButton('/', '/'),
                  _keyButton('~', '~'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyButton(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(42, 32),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: !_connected
            ? null
            : () {
                if (value == '__CTRL__') {
                  setState(() => _ctrlLatched = !_ctrlLatched);
                  return;
                }
                _sendToShell(value);
              },
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
