import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tetris.dart';

void main() {
  runApp(const TetrisApp());
}

class TetrisApp extends StatelessWidget {
  const TetrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Tetris',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int highScore = 0;

  @override
  void initState() {
    super.initState();
    loadHighScore();
  }

  Future<void> loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      highScore = prefs.getInt('highScore') ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "FLUTTER TETRIS",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.cyan,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 30),
            if (highScore > 50000)
              const Text(
                "Parabéns, agora vá tocar uma grama",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              )
            else
              Text(
                "Melhor score feito: $highScore",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const TetrisGameScreen()),
                );
              },
              child: const Text("JOGAR"),
            ),
          ],
        ),
      ),
    );
  }
}

class TetrisGameScreen extends StatefulWidget {
  const TetrisGameScreen({super.key});

  @override
  State<TetrisGameScreen> createState() => _TetrisGameScreenState();
}

class _TetrisGameScreenState extends State<TetrisGameScreen> {
  late TetrisGame game;
  Timer? gameTimer;

  // CONTROLE DE PAUSA
  bool isPaused = false;

  // CONTROLE DE MOVIMENTAÇÃO CONTÍNUA (DAS / ARR)
  Timer? _leftTimer;
  Timer? _rightTimer;
  bool _isLeftPressed = false;
  bool _isRightPressed = false;

  // REPRODUTORES DE ÁUDIO
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _bgmPlayer = AudioPlayer();

  int dropInterval = 800;
  int globalHighScore = 0;
  int sessionHighScore = 0;
  int finalScore = 0;

  final FocusNode focusNode = FocusNode();
  bool softDrop = false;
  bool rotateClockwise = true;

  final Map<int, Color> blockColors = {
    -1: Colors.white24,
    0: Colors.black,
    1: Colors.cyan,
    2: Colors.yellow,
    3: Colors.purple,
    4: Colors.green,
    5: Colors.red,
    6: Colors.blue,
    7: Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    game = TetrisGame();

    // EVENTOS DE EFEITOS SONOROS (SFX)
    game.onPieceDrop = () {
      _playSfx('audio/drop.mp3');
    };

    game.onLineClear = (lines) {
      switch (lines) {
        case 1:
          _playSfx('audio/clear_1.mp3');
          break;
        case 2:
          _playSfx('audio/clear_2.mp3');
          break;
        case 3:
          _playSfx('audio/clear_3.mp3');
          break;
        case 4:
          _playSfx('audio/clear_4.mp3');
          break;
      }
    };

    loadHighScore();
    _startBgm();
    startGameLoop();
  }

  // CÁLCULO DE NÍVEL DE PROGRESSÃO (Nível 1 ao 31, limitado a 30.000 pontos)
  int get currentLevel {
    int cappedScore = game.score.clamp(0, 30000);
    return (cappedScore ~/ 1000) + 100;
  }

  // CÁLCULO DE VELOCIDADE COM TETO EM 30.000 PONTOS
  void updateSpeedByLevel() {
    int cappedScore = game.score.clamp(0, 30000); // Teto máximo de pontuação
    int baseInterval = 800; // Velocidade inicial (ms)
    int minInterval = 60;   // Velocidade máxima extrema (ms)

    // Redução proporcional e contínua até atingir os 30.000 pontos
    int speedReduction = ((cappedScore / 30000) * (baseInterval - minInterval)).round();
    int newInterval = baseInterval - speedReduction;

    if (newInterval != dropInterval) {
      dropInterval = newInterval;
      startGameLoop();
    }
  }

  // LÓGICA DE PAUSA (ESC)
  void togglePause() {
    if (game.isGameOver) return;

    setState(() {
      isPaused = !isPaused;
    });

    if (isPaused) {
      _stopLeftMove();
      _stopRightMove();
      gameTimer?.cancel();
      _bgmPlayer.pause();
    } else {
      _bgmPlayer.resume();
      startGameLoop();
    }
  }

  // LÓGICA DE MOVIMENTO CONTÍNUO AO SEGURAR TECLA
  void _startLeftMove() {
    _stopLeftMove();
    if (game.isGameOver || isPaused) return;

    setState(() {
      game.movePiece(-1, 0);
    });

    _leftTimer = Timer(const Duration(milliseconds: 170), () {
      _leftTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || game.isGameOver || isPaused) return;
        setState(() {
          game.movePiece(-1, 0);
        });
      });
    });
  }

  void _stopLeftMove() {
    _leftTimer?.cancel();
    _leftTimer = null;
  }

  void _startRightMove() {
    _stopRightMove();
    if (game.isGameOver || isPaused) return;

    setState(() {
      game.movePiece(1, 0);
    });

    _rightTimer = Timer(const Duration(milliseconds: 170), () {
      _rightTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || game.isGameOver || isPaused) return;
        setState(() {
          game.movePiece(1, 0);
        });
      });
    });
  }

  void _stopRightMove() {
    _rightTimer?.cancel();
    _rightTimer = null;
  }

  // MÚSICA DE FUNDO (BGM)
  void _startBgm() async {
    try {
      await _bgmPlayer.stop();
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.play(AssetSource('audio/tetris.mp3'));
    } catch (e) {
      debugPrint("Erro ao tocar música de fundo: $e");
    }
  }

  void _stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (e) {
      debugPrint("Erro ao parar música de fundo: $e");
    }
  }

  // EFEITOS SONOROS (SFX)
  void _playSfx(String assetPath) async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint("Erro ao tocar efeito sonoro: $e");
    }
  }

  Future<void> loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      globalHighScore = prefs.getInt('highScore') ?? 0;
    });
  }

  Future<void> checkAndUpdateHighScore() async {
    if (game.score > sessionHighScore) {
      setState(() {
        sessionHighScore = game.score;
      });
    }

    if (game.score > globalHighScore) {
      setState(() {
        globalHighScore = game.score;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('highScore', globalHighScore);
    }
  }

  @override
  void dispose() {
    _stopLeftMove();
    _stopRightMove();
    _stopBgm();
    gameTimer?.cancel();
    _sfxPlayer.dispose();
    _bgmPlayer.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void startGameLoop() {
    gameTimer?.cancel();

    gameTimer = Timer.periodic(
      Duration(milliseconds: softDrop ? 40 : dropInterval),
      (_) async {
        if (!mounted || game.isGameOver || isPaused) return;

        setState(() {
          game.tick();
          updateSpeedByLevel();
        });

        await checkAndUpdateHighScore();

        if (game.isGameOver) {
          _stopLeftMove();
          _stopRightMove();
          await checkAndUpdateHighScore();
          setState(() {
            finalScore = game.score;
          });
          _stopBgm();
          gameTimer?.cancel();
        }
      },
    );
  }

  // REINICIAR RUN (BACKSPACE OU BOTÃO)
  void restartGame() {
    _stopLeftMove();
    _stopRightMove();
    _isLeftPressed = false;
    _isRightPressed = false;
    setState(() {
      isPaused = false;
      game.reset();
      finalScore = 0;
      dropInterval = 800;
    });
    _startBgm();
    startGameLoop();
  }

  void goToHomeScreen() {
    _stopLeftMove();
    _stopRightMove();
    _stopBgm();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void onKeyDown(LogicalKeyboardKey key) {
    // ATALHO PARA PAUSAR/RESUMIR (ESC)
    if (key == LogicalKeyboardKey.escape) {
      togglePause();
      return;
    }

    // ATALHO PARA RESETAR RUN (BACKSPACE)
    if (key == LogicalKeyboardKey.backspace) {
      restartGame();
      return;
    }

    if (game.isGameOver && key == LogicalKeyboardKey.enter) {
      restartGame();
      return;
    }

    if (game.isGameOver || isPaused) return;

    switch (key) {
      case LogicalKeyboardKey.keyA:
      case LogicalKeyboardKey.arrowLeft:
        if (!_isLeftPressed) {
          _isLeftPressed = true;
          _startLeftMove();
        }
        break;
      case LogicalKeyboardKey.keyD:
      case LogicalKeyboardKey.arrowRight:
        if (!_isRightPressed) {
          _isRightPressed = true;
          _startRightMove();
        }
        break;
      case LogicalKeyboardKey.keyS:
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          game.rotatePiece(clockwise: rotateClockwise);
        });
        break;
      case LogicalKeyboardKey.keyW:
      case LogicalKeyboardKey.arrowDown:
        if (!softDrop) {
          softDrop = true;
          startGameLoop();
        }
        break;
      case LogicalKeyboardKey.space:
        setState(() {
          game.hardDrop();
        });
        checkAndUpdateHighScore();
        break;
      case LogicalKeyboardKey.keyC:
        setState(() {
          game.holdCurrentPiece();
        });
        break;
      default:
        break;
    }
  }

  void onKeyUp(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
      _isLeftPressed = false;
      _stopLeftMove();
    }
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
      _isRightPressed = false;
      _stopRightMove();
    }
    if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowDown) {
      if (softDrop) {
        softDrop = false;
        startGameLoop();
      }
    }
  }

  void handleKeyboard(KeyEvent event) {
    if (event is KeyDownEvent) onKeyDown(event.logicalKey);
    if (event is KeyUpEvent) onKeyUp(event.logicalKey);
  }

  @override
  Widget build(BuildContext context) {
    final display = game.getDisplayBoard();
    int displayScore = game.isGameOver ? finalScore : game.score;
    double progressRatio = game.score.clamp(0, 30000) / 30000;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Flutter Tetris   |   Score: $displayScore   |   Sessão: $sessionHighScore",
        ),
      ),
      body: KeyboardListener(
        autofocus: true,
        focusNode: focusNode,
        onKeyEvent: handleKeyboard,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // GRID DE JOGO COM OVERLAY DE PAUSA
              Stack(
                children: [
                  Container(
                    width: 300,
                    height: 600,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: game.rows * game.cols,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: game.cols,
                      ),
                      itemBuilder: (context, index) {
                        int r = index ~/ game.cols;
                        int c = index % game.cols;
                        int value = display[r][c];

                        return Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: blockColors[value] ?? Colors.white,
                            border: Border.all(
                              color: value == -1 ? Colors.white38 : Colors.black54,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (isPaused)
                    Container(
                      width: 300,
                      height: 600,
                      color: Colors.black.withOpacity(0.75),
                      child: const Center(
                        child: Text(
                          "PAUSADO",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellowAccent,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 25),
              // PAINEL LATERAL DE INFORMAÇÕES E PROGRESSÃO
              SizedBox(
                width: 170,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("HOLD", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white)),
                      child: game.holdPiece == null ? const SizedBox() : buildMiniPiece(game.holdPiece!),
                    ),
                    const SizedBox(height: 15),
                    const Text("NEXT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white)),
                      child: buildMiniPiece(game.nextPiece),
                    ),
                    const SizedBox(height: 15),
                    // INDICADOR DE NIVEL E PROGRESSO
                    Text(
                      "NÍVEL $currentLevel ${game.score >= 30000 ? '(MAX)' : ''}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressRatio,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "SCORE\n$displayScore",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 15),
                    if (!game.isGameOver) ...[
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPaused ? Colors.green : Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: togglePause,
                        child: Text(isPaused ? "RESUMIR (ESC)" : "PAUSAR (ESC)"),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: restartGame,
                        child: const Text("RESET (BKSP)"),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      ElevatedButton(
                        onPressed: restartGame,
                        child: const Text("RESTART"),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                      onPressed: goToHomeScreen,
                      child: const Text("MENU"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildMiniPiece(Tetromino piece) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: piece.matrix.length * piece.matrix.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: piece.matrix.length,
          ),
          itemBuilder: (context, index) {
            int r = index ~/ piece.matrix.length;
            int c = index % piece.matrix.length;
            int value = piece.matrix[r][c];

            return Container(
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: value == 0 ? Colors.transparent : blockColors[value]!,
                border: value == 0 ? null : Border.all(color: Colors.black54),
              ),
            );
          },
        ),
      ),
    );
  }
}