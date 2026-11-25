import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartssh2/dartssh2.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    home: HomeScreen(),
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
        name: json['name'],
        host: json['host'],
        port: json['port'],
        username: json['username'],
        password: json['password'],
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
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('ssh_sessions');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        sessions = decoded.map((e) => SshSessionModel.fromJson(e)).toList();
      });
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
      builder: (context) => AlertDialog(
        title: const Text('Registrar Sessão SSH'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome (ex: Meu PC)')),
              TextField(controller: hostCtrl, decoration: const InputDecoration(labelText: 'IP SSH (ex: 192.168.1.10)')),
              TextField(controller: portCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Porta')),
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Usuário')),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (hostCtrl.text.isEmpty || userCtrl.text.isEmpty) return;
              setState(() {
                sessions.add(SshSessionModel(
                  name: nameCtrl.text.isEmpty ? hostCtrl.text : nameCtrl.text,
                  host: hostCtrl.text.trim(),
                  port: int.tryParse(portCtrl.text) ?? 22,
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                ));
              });
              _saveSessions();
              Navigator.pop(context);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controle PC via SSH')),
      body: Column(
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
                        selectedTileColor: Colors.blue.withOpacity(0.2),
                        leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
                        title: Text(s.name),
                        subtitle: Text('${s.username}@${s.host}:${s.port}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () {
                            setState(() {
                              sessions.removeAt(index);
                              if (selectedIndex == index) selectedIndex = null;
                            });
                            _saveSessions();
                          },
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

  Future<void> _runSshCommand(String command, String label) async {
    setState(() => isLoading = true);
    try {
      final socket = await SSHSocket.connect(widget.session.host, widget.session.port, timeout: const Duration(seconds: 5));
      final client = SSHClient(
        socket,
        username: widget.session.username,
        onPasswordRequest: () => widget.session.password,
      );
      await client.run(command);
      client.close();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Comando "$label" enviado!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro SSH: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
              onPressed: isLoading ? null : () => _runSshCommand('explorer', 'Abrir Explorer'),
              icon: const Icon(Icons.folder_open),
              label: const Text('Abrir Explorer', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: Colors.orange),
              onPressed: isLoading ? null : () => _runSshCommand('shutdown /f /r /t 0', 'Reiniciar PC'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reiniciar PC', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: Colors.red),
              onPressed: isLoading ? null : () => _runSshCommand('shutdown /f /s /t 0', 'Desligar PC'),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Desligar PC', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
 
