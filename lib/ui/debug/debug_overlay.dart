// lib/ui/debug/debug_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/console/console_session.dart';
import 'tilde_trigger.dart';
import 'record_commands.dart';

class DebugConsoleShell extends StatefulWidget {
  final Widget child;
  final ConsoleSession session;
  final VoidCallback? onCommandRun;

  const DebugConsoleShell({
    super.key,
    required this.child,
    required this.session,
    this.onCommandRun,   
  });

  @override
  State<DebugConsoleShell> createState() => _DebugConsoleShellState();
}

class _DebugConsoleShellState extends State<DebugConsoleShell> {
  bool _visible = false;
  late final TripleTildeDetector _detector;
  late final CommandRecorder _commandRecorder;
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  void _onSessionChanged() {
    if (mounted) setState(() {});
    widget.onCommandRun?.call(); 
  }

  @override
  void initState() {
    super.initState();
    _detector = TripleTildeDetector(
      onTriggered: () => setState(() => _visible = !_visible),
    );
    _commandRecorder = CommandRecorder();

    HardwareKeyboard.instance.addHandler(_onKey);
    widget.session.addListener(_onSessionChanged); 
  }

  
  bool _onKey(KeyEvent event) {
    _detector.handleKeyEvent(event);
    _commandRecorder.handleKeyEvent(event, _inputController);
    return false; // don't swallow the key elsewhere
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.session.removeListener(_onSessionChanged);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    widget.session.run(value);
    _commandRecorder.recordCommand(value);
    if (_commandRecorder.historyPointer == -1 && _commandRecorder.commandHistory.isNotEmpty) {
      _commandRecorder.historyPointer = _commandRecorder.commandHistory.length - 1;
    }
    _inputController.clear();


  }


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible)
          Positioned(
            top: 40,
            left: 40,
            right: 40,
            height: 420,
            child: Material(
              elevation: 12,
              color: Colors.black.withOpacity(0.9),
              child: Column(
                children: [
                  Container(
                    color: Colors.grey[900],
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        const Text('BASA Debug Console',
                            style: TextStyle(color: Colors.white)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 18),
                          onPressed: () => setState(() => _visible = false),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: widget.session.visibleEntries.map((e) {
                        final color = switch (e.type) {
                          ConsoleEntryType.input => Colors.white,
                          ConsoleEntryType.result => Colors.greenAccent,
                          ConsoleEntryType.log => Colors.orangeAccent,
                        };
                        final text = e.type == ConsoleEntryType.log
                            ? '[${e.source}] ${e.message}'
                            : e.message;
                        return Text(text,
                            style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12));
                      }).toList(),
                    ),
                  ),
                  TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      prefixText: '> ',
                      prefixStyle: TextStyle(color: Colors.greenAccent),
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Colors.black,
                    ),
                    onSubmitted: _submit,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}