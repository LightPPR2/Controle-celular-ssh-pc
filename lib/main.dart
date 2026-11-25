import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SshTerminalApp());
}

// ============================================================
// CONFIGURAÇÃO
// ============================================================

const _secureStorage = FlutterSecureStorage();

const String _sessionsKey = 'ssh_sessions_v2';
const String _legacySessionsKey = 'ssh_sessions';

const Color _background = Color(0xFF090D12);
const Color _terminalBackground = Color(0xFF050708);
const Color _panelBackground = Color(0xFF111820);
const Color _accent = Color(0xFF00D9A6);

// ============================================================
// APP
// ============================================================

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
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _background,
        useMaterial3: true,
      ),
      home: const SessionsScreen(),
    );
  }
}

// ============================================================
// MODELO DE CONEXÃO
// ============================================================

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
    };
  }

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

// ============================================================
// TELA DE SESSÕES
// ============================================================

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

      final currentData = prefs.getString(_sessionsKey);
      final legacyData = prefs.getString(_legacySessionsKey);

      final raw = currentData ?? legacyData;

      if (raw != null) {
        final decoded = jsonDecode(raw);

        if (decoded is! List) {
          throw const FormatException('Formato de sessões inválido.');
        }

        final loaded = <SshProfile>[];

        for (final item in decoded) {
          if (item is! Map) continue;

          final map = Map<String, dynamic>.from(item);

          final legacyPassword = map['password'] as String?;

          final profile = SshProfile.fromJson(map);

          if (profile.host.isEmpty || profile.username.isEmpty) {
            continue;
          }

          if (legacyPassword != null && legacyPassword.isNotEmpty) {
            await _secureStorage.write(
              key: 'ssh_password_${profile.id}',
              value: legacyPassword,
            );
          }

          loaded.add(profile);
        }

        _profiles
          ..clear()
          ..addAll(loaded);

        await _saveProfiles();

        if (legacyData != null) {
          await prefs.remove(_legacySessionsKey);
        }
      }
    } catch (e) {
      _showMessage('Erro ao carregar sessões: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _sessionsKey,
      jsonEncode(_profiles.map((profile) => profile.toJson()).toList()),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _newId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<void> _addProfile() async {
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final username = TextEditingController();
    final password = TextEditingController();

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<SshProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nova conexão SSH'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nome da conexão',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: host,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Host / IP',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o host.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Porta',
                      prefixIcon: Icon(Icons.settings_ethernet),
                    ),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');

                      if (number == null || number < 1 || number > 65535) {
                        return 'Porta inválida.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: username,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o usuário.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Informe a senha.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;

                final parsedPort = int.parse(port.text.trim());

                Navigator.pop(
                  dialogContext,
                  SshProfile(
                    id: _newId(),
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
        );
      },
    );

    if (result != null) {
      try {
        await _secureStorage.write(
          key: 'ssh_password_${result.id}',
          value: password.text,
        );

        if (!mounted) return;

        setState(() => _profiles.add(result));

        await _saveProfiles();
        _showMessage('Conexão salva.');
      } catch (e) {
        _showMessage('Erro ao salvar conexão: $e');
      }
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
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remover conexão?'),
          content: Text(
            'Deseja remover "${profile.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _profiles.removeWhere((item) => item.id == profile.id);
      });

      await _secureStorage.delete(
        key: 'ssh_password_${profile.id}',
      );

      await _saveProfiles();

      _showMessage('Conexão removida.');
    } catch (e) {
      _showMessage('Erro ao remover conexão: $e');
    }
  }

  Future<void> _openProfile(SshProfile profile) async {
    try {
      final password = await _secureStorage.read(
        key: 'ssh_password_${profile.id}',
      );

      if (!mounted) return;

      if (password == null || password.isEmpty) {
        _showMessage(
          'Senha não encontrada. Cadastre novamente a conexão.',
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TerminalScreen(
            profile: profile,
            password: password,
          ),
        ),
      );
    } catch (e) {
      _showMessage('Erro ao abrir conexão: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: _accent),
            SizedBox(width: 10),
            Text('LightPPR2 SSH'),
          ],
        ),
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
                      Icon(
                        Icons.terminal,
                        size: 64,
                        color: Colors.white30,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Nenhuma conexão cadastrada',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 6),
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
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];

                    return Card(
                      color: _panelBackground,
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF18352F),
                          child: Icon(
                            Icons.dns_outlined,
                            color: _accent,
                          ),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${profile.username}@${profile.host}:${profile.port}',
                        ),
                        onTap: () => _openProfile(profile),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _deleteProfile(profile),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================
// TERMINAL SSH
// ============================================================

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

  bool _connecting = false;
  bool _connected = false;
  bool _disposed = false;
  bool _ctrlLatched = false;

  String _status = 'Desconectado';

  int _generation = 0;

  int _terminalColumns = 80;
  int _terminalRows = 24;

  @override
  void initState() {
    super.initState();

    _terminal = Terminal(maxLines: 10000);

    _terminal.onOutput = _sendToShell;

    // O xterm informa quando o tamanho visual muda.
    // O tamanho também será enviado ao PTY SSH.
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      if (width <= 0 || height <= 0) return;

      _terminalColumns = width;
      _terminalRows = height;

      _resizeRemoteTerminal();
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect();
    });
  }

  // ----------------------------------------------------------
  // SAÍDA LOCAL
  // ----------------------------------------------------------

  void _write(String text) {
    if (_disposed) return;
    _terminal.write(text);
  }

  void _writeInfo(String message) {
    _write('\r\n\x1B[1;36m$message\x1B[0m\r\n');
  }

  void _writeError(String message) {
    _write('\r\n\x1B[1;31m$message\x1B[0m\r\n');
  }

  // ----------------------------------------------------------
  // CONEXÃO SSH
  // ----------------------------------------------------------

  Future<void> _connect() async {
    if (_disposed || _connecting || _connected) return;

    final attempt = ++_generation;

    setState(() {
      _connecting = true;
      _connected = false;
      _status = 'Conectando...';
    });

    _writeInfo(
      'Conectando a ${widget.profile.username}@'
      '${widget.profile.host}:${widget.profile.port}...',
    );

    SSHClient? client;
    SSHSession? shell;

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

      await client.authenticated.timeout(
        const Duration(seconds: 20),
      );

      if (!_isCurrentAttempt(attempt)) {
        client.close();
        return;
      }

      _writeInfo('Autenticação concluída. Abrindo shell...');

      shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _terminalColumns,
          height: _terminalRows,
        ),
      );

      if (!_isCurrentAttempt(attempt)) {
        shell.close();
        client.close();
        return;
      }

      _client = client;
      _shell = shell;

      // Sincroniza o tamanho atual com o PTY remoto.
      _resizeRemoteTerminal();

      _stdoutSubscription = shell.stdout.listen(
        (data) {
          if (!_isCurrentAttempt(attempt)) return;

          _write(
            utf8.decode(data, allowMalformed: true),
          );
        },
        onError: (error) {
          _handleDisconnect(
            attempt,
            'Erro na saída SSH: $error',
          );
        },
        onDone: () {
          _handleDisconnect(
            attempt,
            'Shell encerrado pelo servidor.',
          );
        },
      );

      _stderrSubscription = shell.stderr.listen(
        (data) {
          if (!_isCurrentAttempt(attempt)) return;

          _write(
            utf8.decode(data, allowMalformed: true),
          );
        },
        onError: (error) {
          _handleDisconnect(
            attempt,
            'Erro no canal stderr: $error',
          );
        },
      );

      if (!_isCurrentAttempt(attempt)) {
        await _cleanupAttempt(shell, client);
        return;
      }

      setState(() {
        _connecting = false;
        _connected = true;
        _status = 'Conectado';
      });

      _write('\r\n\x1B[1;32mSSH conectado com sucesso.\x1B[0m\r\n');
    } catch (e) {
      await _cleanupAttempt(shell, client);

      if (!_isCurrentAttempt(attempt)) return;

      _stdoutSubscription?.cancel();
      _stderrSubscription?.cancel();

      _stdoutSubscription = null;
      _stderrSubscription = null;

      _shell = null;
      _client = null;

      setState(() {
        _connecting = false;
        _connected = false;
        _status = 'Falha na conexão';
      });

      _writeError('Falha SSH: $e');
    }
  }

  bool _isCurrentAttempt(int attempt) {
    return !_disposed &&
        mounted &&
        attempt == _generation;
  }

  Future<void> _cleanupAttempt(
    SSHSession? shell,
    SSHClient? client,
  ) async {
    try {
      shell?.close();
    } catch (_) {}

    try {
      client?.close();
    } catch (_) {}
  }

  // ----------------------------------------------------------
  // REDIMENSIONAMENTO DO PTY
  // ----------------------------------------------------------

  void _resizeRemoteTerminal() {
    final shell = _shell;

    if (shell == null || !_connected) return;

    try {
      shell.resizeTerminal(
        _terminalColumns,
        _terminalRows,
      );
    } catch (e) {
      // Uma falha de resize não deve derrubar a conexão.
      debugPrint('SSH resize: $e');
    }
  }

  // ----------------------------------------------------------
  // ENVIO DE DADOS AO SHELL
  // ----------------------------------------------------------

  void _sendToShell(String data) {
    final shell = _shell;

    if (shell == null || !_connected || _disposed) return;

    var outgoing = data;

    if (_ctrlLatched) {
      _ctrlLatched = false;

      if (data.length == 1) {
        final code = data.codeUnitAt(0);

        if (code >= 97 && code <= 122) {
          outgoing = String.fromCharCode(code - 96);
        } else if (code >= 65 && code <= 90) {
          outgoing = String.fromCharCode(code - 64);
        } else if (code >= 64 && code <= 95) {
          outgoing = String.fromCharCode(code - 64);
        }
      }
    }

    try {
      shell.write(
        Uint8List.fromList(
          utf8.encode(outgoing),
        ),
      );
    } catch (e) {
      _writeError('Erro ao enviar dados: $e');
    }
  }

  // ----------------------------------------------------------
  // DESCONEXÃO
  // ----------------------------------------------------------

  void _handleDisconnect(int attempt, String message) {
    if (!_isCurrentAttempt(attempt)) return;

    // Invalida callbacks antigos imediatamente.
    _generation++;

    final oldShell = _shell;
    final oldClient = _client;

    _shell = null;
    _client = null;

    final stdout = _stdoutSubscription;
    final stderr = _stderrSubscription;

    _stdoutSubscription = null;
    _stderrSubscription = null;

    setState(() {
      _connected = false;
      _connecting = false;
      _status = 'Desconectado';
    });

    _write('\r\n\x1B[1;33m$message\x1B[0m\r\n');

    stdout?.cancel();
    stderr?.cancel();

    _cleanupAttempt(oldShell, oldClient);
  }

  Future<void> _disconnect() async {
    // Invalida qualquer conexão que ainda esteja autenticando.
    _generation++;

    final stdout = _stdoutSubscription;
    final stderr = _stderrSubscription;

    final shell = _shell;
    final client = _client;

    _stdoutSubscription = null;
    _stderrSubscription = null;

    _shell = null;
    _client = null;

    _ctrlLatched = false;

    await stdout?.cancel();
    await stderr?.cancel();

    await _cleanupAttempt(shell, client);

    if (!mounted || _disposed) return;

    setState(() {
      _connected = false;
      _connecting = false;
      _status = 'Desconectado';
    });
  }

  Future<void> _reconnect() async {
    if (_disposed || _connecting) return;

    await _disconnect();

    if (!mounted || _disposed) return;

    _writeInfo('Tentando reconectar...');

    await _connect();
  }

  // ----------------------------------------------------------
  // TECLAS AUXILIARES
  // ----------------------------------------------------------

  void _sendSpecialKey(String value) {
    if (!_connected) return;

    if (value == '__CTRL__') {
      setState(() {
        _ctrlLatched = !_ctrlLatched;
      });
      return;
    }

    _sendToShell(value);
  }

  Widget _keyButton(String label, String value) {
    final isCtrl = value == '__CTRL__';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 6,
      ),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isCtrl && _ctrlLatched
              ? _accent.withValues(alpha: 0.18)
              : Colors.transparent,
          foregroundColor: isCtrl && _ctrlLatched
              ? _accent
              : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(42, 34),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: !_connected
            ? null
            : () => _sendSpecialKey(value),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CICLO DE VIDA
  // ----------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _generation++;

    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();

    _stdoutSubscription = null;
    _stderrSubscription = null;

    _shell?.close();
    _client?.close();

    _shell = null;
    _client = null;

    super.dispose();
  }

  // ----------------------------------------------------------
  // INTERFACE
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final statusColor = _connected
        ? Colors.greenAccent
        : _connecting
            ? Colors.amber
            : Colors.redAccent;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.name,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              '${widget.profile.username}@${widget.profile.host}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _status,
                    style: const TextStyle(fontSize: 11),
                  ),
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
            tooltip: 'Desconectar',
            onPressed: _connected ? _disconnect : null,
            icon: const Icon(Icons.power_settings_new),
          ),
          IconButton(
            tooltip: 'Limpar terminal',
            onPressed: () {
              _terminal.write('\x1B[2J\x1B[H');
            },
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: _terminalBackground,
                child: TerminalView(
                  _terminal,
                  autofocus: true,
                  autoResize: true,
                ),
              ),
            ),

            if (_connecting)
              const LinearProgressIndicator(
                minHeight: 2,
              ),

            Container(
              height: 48,
              decoration: const BoxDecoration(
                color: _panelBackground,
                border: Border(
                  top: BorderSide(color: Colors.white12),
                ),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: [
                  _keyButton('ESC', '\x1B'),
                  _keyButton('TAB', '\t'),
                  _keyButton('CTRL', '__CTRL__'),
                  _keyButton('↑', '\x1B[A'),
                  _keyButton('↓', '\x1B[B'),
                  _keyButton('←', '\x1B[D'),
                  _keyButton('→', '\x1B[C'),
                  _keyButton('HOME', '\x1B[H'),
                  _keyButton('END', '\x1B[F'),
                  _keyButton('PGUP', '\x1B[5~'),
                  _keyButton('PGDN', '\x1B[6~'),
                  _keyButton('|', '|'),
                  _keyButton('/', '/'),
                  _keyButton('~', '~'),
                ],
              ),
            ),

            Container(
              height: 28,
              color: const Color(0xFF0B1016),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal,
                    size: 13,
                    color: _connected ? _accent : Colors.white38,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _connected
                        ? 'PTY ${_terminalColumns}x$_terminalRows'
                        : 'Terminal SSH',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                  const Spacer(),
                  if (_ctrlLatched)
                    const Text(
                      'CTRL ATIVO',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

