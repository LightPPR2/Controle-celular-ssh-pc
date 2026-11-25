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
        selectedIndex = selectedIndex! - 1; // corrige o índice selecionado após remoção
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

class ControlScreen extends StatefulWidget {
  final SshSessionModel session;
  const ControlScreen({super.key, required this.session});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool isLoading = false;

  /// [expectDisconnect]: para shutdown/restart, a conexão cai e isso é normal.
  Future<void> _runSshCommand(
    String command,
    String label, {
    bool expectDisconnect = false,
  }) async {
    if (isLoading) return;
    setState(() => isLoading = true);
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

      // Garante que o login funcionou antes de rodar o comando
      await client.authenticated.timeout(const Duration(seconds: 10));

      try {
        await client.run(command).timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // comando disparado; não precisamos esperar terminar
      } catch (e) {
        if (!expectDisconnect) rethrow;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Comando "$label" enviado!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro SSH: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      client?.close();
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _confirmAndRun(
    String command,
    String label, {
    bool expectDisconnect = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(label),
        content: const Text('Tem certeza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) {
      await _runSshCommand(command, label, expectDisconnect: expectDisconnect);
    }
  }

  // O SSH do Windows roda na sessão 0 (sem tela). Rodar "explorer" direto
  // trava a conexão e não aparece na área de trabalho. Por isso usamos uma
  // tarefa agendada interativa (/it), que abre na sessão do usuário logado.
  String get _openExplorerCmd {
    final user = widget.session.username;
    return 'schtasks /create /tn "RemoteExplorer" /tr "explorer.exe" /sc once '
        '/st 00:00 /ru "$user" /it /f && schtasks /run /tn "RemoteExplorer"';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.name)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLoading) const LinearProgressIndicator(),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18)),
              onPressed: isLoading ? null : () => _runSshCommand(_openExplorerCmd, 'Abrir Explorer'),
              icon: const Icon(Icons.folder_open),
              label: const Text('Abrir Explorer', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: Colors.orange),
              onPressed: isLoading
                  ? null
                  : () => _confirmAndRun('shutdown /f /r /t 0', 'Reiniciar PC', expectDisconnect: true),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reiniciar PC', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: Colors.red),
              onPressed: isLoading
                  ? null
                  : () => _confirmAndRun('shutdown /f /s /t 0', 'Desligar PC', expectDisconnect: true),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Desligar PC', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
