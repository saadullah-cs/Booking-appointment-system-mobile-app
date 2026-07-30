import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _input = '0';
  String _expression = '';
  String? _operator;
  double? _prevValue;
  bool _isNewInput = false;

  final List<String> _history = [];
  bool _showHistoryOnMobile = true;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyPress(String value) {
    setState(() {
      if (value == 'AC') {
        _input = '0';
        _expression = '';
        _operator = null;
        _prevValue = null;
        _isNewInput = false;
      } else if (value == '⌫') {
        if (_input.isNotEmpty && _input != '0' && _input != 'Error') {
          _input = _input.substring(0, _input.length - 1);
          if (_input.isEmpty || _input == '-') {
            _input = '0';
          }
        }
      } else if (value == '⁺/₋') {
        if (_input != '0' && _input != 'Error') {
          if (_input.startsWith('-')) {
            _input = _input.substring(1);
          } else {
            _input = '-$_input';
          }
        }
      } else if (value == '%') {
        final val = double.tryParse(_input) ?? 0;
        final res = val / 100;
        _input = _formatNumber(res);
      } else if (value == '+' || value == '−' || value == '×' || value == '÷') {
        final currentVal = double.tryParse(_input);
        if (currentVal != null) {
          if (_operator != null && !_isNewInput) {
            _calculateIntermediate(currentVal);
          } else {
            _prevValue = currentVal;
          }
        }
        _operator = value;
        _expression = '${_formatNumber(_prevValue!)} $value';
        _isNewInput = true;
      } else if (value == '=') {
        final currentVal = double.tryParse(_input);
        if (_operator != null && _prevValue != null && currentVal != null) {
          final double prev = _prevValue!;
          final String op = _operator!;
          double result = 0;
          switch (op) {
            case '+':
              result = prev + currentVal;
              break;
            case '−':
              result = prev - currentVal;
              break;
            case '×':
              result = prev * currentVal;
              break;
            case '÷':
              if (currentVal == 0) {
                _input = 'Error';
                _operator = null;
                _prevValue = null;
                _isNewInput = true;
                return;
              }
              result = prev / currentVal;
              break;
          }
          final formattedPrev = _formatNumber(prev);
          final formattedCurrent = _formatNumber(currentVal);
          final formattedResult = _formatNumber(result);

          _expression = '$formattedPrev $op $formattedCurrent =';
          _input = formattedResult;

          // Save to history list
          _history.insert(0, '$_expression $formattedResult');
          if (_history.length > 50) {
            _history.removeLast(); // Keep limit to 50 items
          }

          _prevValue = result;
          _operator = null;
          _isNewInput = true;
        }
      } else {
        // Digits & decimal point
        if (_isNewInput || _input == '0' || _input == 'Error') {
          if (value == '.') {
            _input = '0.';
          } else {
            _input = value;
          }
          _isNewInput = false;
        } else {
          if (value == '.') {
            if (!_input.contains('.')) {
              _input += '.';
            }
          } else {
            if (_input.length < 15) {
              _input += value;
            }
          }
        }
      }
    });
  }

  void _calculateIntermediate(double currentVal) {
    if (_operator == null || _prevValue == null) return;
    double result = 0;
    switch (_operator) {
      case '+':
        result = _prevValue! + currentVal;
        break;
      case '−':
        result = _prevValue! - currentVal;
        break;
      case '×':
        result = _prevValue! * currentVal;
        break;
      case '÷':
        if (currentVal == 0) {
          _input = 'Error';
          _operator = null;
          _prevValue = null;
          _isNewInput = true;
          return;
        }
        result = _prevValue! / currentVal;
        break;
    }
    _prevValue = result;
  }

  String _formatNumber(double numValue) {
    if (numValue.isInfinite || numValue.isNaN) return 'Error';
    if (numValue % 1 == 0) {
      return numValue.toInt().toString();
    }
    String res = numValue.toString();
    if (res.length > 12) {
      res = numValue.toStringAsFixed(6);
      while (res.endsWith('0') && res.contains('.')) {
        res = res.substring(0, res.length - 1);
      }
      if (res.endsWith('.')) {
        res = res.substring(0, res.length - 1);
      }
    }
    return res;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final character = event.character;
      final logicalKey = event.logicalKey;

      if (character != null && RegExp(r'[0-9.]').hasMatch(character)) {
        _onKeyPress(character);
      } else if (character == '+') {
        _onKeyPress('+');
      } else if (character == '-') {
        _onKeyPress('−');
      } else if (character == '*') {
        _onKeyPress('×');
      } else if (character == '/') {
        _onKeyPress('÷');
      } else if (character == '%' || character == '=') {
        _onKeyPress(character!);
      } else if (logicalKey == LogicalKeyboardKey.enter ||
          logicalKey == LogicalKeyboardKey.numpadEnter) {
        _onKeyPress('=');
      } else if (logicalKey == LogicalKeyboardKey.backspace) {
        _onKeyPress('⌫');
      } else if (logicalKey == LogicalKeyboardKey.escape) {
        _onKeyPress('AC');
      }
    }
  }

  void _loadHistoryItem(String item) {
    final parts = item.split('=');
    if (parts.length == 2) {
      setState(() {
        final resultStr = parts[1].trim();
        _input = resultStr;
        _expression = '${parts[0].trim()} =';
        _operator = null;
        _prevValue = double.tryParse(resultStr);
        _isNewInput = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 750;

    final List<List<String>> buttons = [
      ['AC', '⁺/₋', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['0', '⌫', '.', '='],
    ];

    Widget buildLcdDisplay() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.15),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Expression Text
            Container(
              height: 24,
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Text(
                  _expression,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Result input text with soft neon glow shadow
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _input,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(
                      color: cs.primary.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildButtonsGrid() {
      return Column(
        children: buttons.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((btn) {
                final isOperator = ['÷', '×', '−', '+', '='].contains(btn);
                final isSpecial = ['AC', '⁺/₋', '%', '⌫'].contains(btn);

                Color btnColor;
                Color textColor;

                if (isOperator) {
                  btnColor = btn == '='
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0.15);
                  textColor = btn == '=' ? Colors.white : cs.primary;
                } else if (isSpecial) {
                  btnColor = isDark
                      ? const Color(0xFF1E2A3B)
                      : const Color(0xFFE2E8F0);
                  textColor = isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF475569);
                } else {
                  btnColor = isDark
                      ? const Color(0xFF1E2A3B)
                      : const Color(0xFFF8FAFC);
                  textColor = isDark ? Colors.white : const Color(0xFF0F172A);
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: AspectRatio(
                      aspectRatio: 1.1,
                      child: _CalcButton(
                        text: btn,
                        bgColor: btnColor,
                        textColor: textColor,
                        onTap: () => _onKeyPress(btn),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      );
    }

    Widget buildCalculatorCard() {
      return PremiumCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Desk Calculator',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (!isWide)
                  IconButton(
                    icon: Icon(
                      _showHistoryOnMobile
                          ? Icons.history_toggle_off_rounded
                          : Icons.history_rounded,
                      color: cs.primary,
                    ),
                    onPressed: () => setState(
                      () => _showHistoryOnMobile = !_showHistoryOnMobile,
                    ),
                    tooltip: 'Toggle History Log',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            buildLcdDisplay(),
            const SizedBox(height: 20),
            buildButtonsGrid(),
          ],
        ),
      );
    }

    Widget buildHistoryCard() {
      return PremiumCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Calculation History',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                if (_history.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _history.clear()),
                    child: Text(
                      'Clear',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.error,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            _history.isEmpty
                ? Expanded(
                    child: Center(
                      child: Text(
                        'No history yet',
                        style: GoogleFonts.poppins(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final parts = item.split(' = ');
                        final expr = parts.isNotEmpty ? parts[0] : '';
                        final val = parts.length > 1 ? parts[1] : '';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _loadHistoryItem(item),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.15),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    expr,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '= $val',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 10,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      );
    }

    return AppShellScaffold(
      title: 'Calculator',
      currentRoute: '/calculator',
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: isWide
                ? IntrinsicHeight(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Column: Calculator Card
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: buildCalculatorCard(),
                        ),
                        const SizedBox(width: 20),
                        // Right Column: History Card
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: buildHistoryCard(),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: buildCalculatorCard(),
                      ),
                      if (_showHistoryOnMobile) ...[
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 380,
                            maxHeight: 220,
                          ),
                          child: buildHistoryCard(),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CalcButton extends StatefulWidget {
  const _CalcButton({
    required this.text,
    required this.bgColor,
    required this.textColor,
    required this.onTap,
  });

  final String text;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  State<_CalcButton> createState() => _CalcButtonState();
}

class _CalcButtonState extends State<_CalcButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          decoration: BoxDecoration(
            color: widget.bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isPressed
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              widget.text,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
