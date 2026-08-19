import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      home: const TetrisGameScreen(),
    );
  }
}

class TetrisGameScreen extends StatefulWidget {
  const TetrisGameScreen({super.key});

  @override
  State<TetrisGameScreen> createState() => _TetrisGameScreenState();
}

class _TetrisGameScreenState extends State<TetrisGameScreen> {
  //---------------------------
  // JOGO
  //---------------------------

  late TetrisGame game;

  Timer? gameTimer;

// Velocidade inicial da peça
int dropInterval = 500;

// Última pontuação usada para calcular a velocidade
int lastSpeedScore = 0;

  final FocusNode focusNode = FocusNode();

  //---------------------------
  // CONTROLES
  //---------------------------

  bool softDrop = false;

  bool rotateClockwise = true;

  //---------------------------
  // CORES DAS PEÇAS
  //---------------------------

  final Map<int, Color> blockColors = {
    -1: Colors.white24, // Ghost Piece
    0: Colors.black,
    1: Colors.cyan,
    2: Colors.yellow,
    3: Colors.purple,
    4: Colors.green,
    5: Colors.red,
    6: Colors.blue,
    7: Colors.orange,
  };

  //---------------------------
  // INICIALIZAÇÃO
  //---------------------------

  @override
  void initState() {
    super.initState();

    game = TetrisGame();

    startGameLoop();
  }

  //---------------------------
  // FINALIZAÇÃO
  //---------------------------

  @override
  void dispose() {
    gameTimer?.cancel();
    focusNode.dispose();

    super.dispose();
  }
  //---------------------------
  // LOOP DO JOGO
  //---------------------------
void updateSpeedByScore() {
  // A cada 500 pontos aumenta a velocidade
  int speedLevel = game.score ~/ 1000;

  // Começa em 300 ms
  double speedMultiplier = 1.0;

  // Cada nível deixa 8% mais rápido
  for (int i = 0; i < speedLevel; i++) {
    speedMultiplier *= 0.95;
  }

  int newInterval = (300 * speedMultiplier).round();

  // Limite mínimo para não ficar impossível
  if (newInterval < 60) {
    newInterval = 60;
  }

  if (newInterval != dropInterval) {
    dropInterval = newInterval;
    startGameLoop();
  }

  lastSpeedScore = game.score;
}
  void startGameLoop() {
  gameTimer?.cancel();

  gameTimer = Timer.periodic(
    Duration(
      milliseconds: softDrop ? 40 : dropInterval,
    ),
    (_) {
      if (!mounted) return;
      if (game.isGameOver) return;

      setState(() {
        game.tick();

        // Verifica se a pontuação aumentou
        updateSpeedByScore();
      });
    },
  );
}

 void restartGame() {
  setState(() {
    game.reset();

    // Volta para a velocidade inicial
    dropInterval = 300;

    // Reseta o controle da pontuação
    lastSpeedScore = 0;
  });

  startGameLoop();
}

  //---------------------------
  // CONTROLE DO TECLADO
  //---------------------------

  void onKeyDown(LogicalKeyboardKey key) {
    if (game.isGameOver) return;

    setState(() {
      switch (key) {
        // ESQUERDA
        case LogicalKeyboardKey.keyA:
        case LogicalKeyboardKey.arrowLeft:
          game.movePiece(-1, 0);
          break;

        // DIREITA
        case LogicalKeyboardKey.keyD:
        case LogicalKeyboardKey.arrowRight:
          game.movePiece(1, 0);
          break;

        // GIRAR
        case LogicalKeyboardKey.keyE:
        case LogicalKeyboardKey.arrowUp:
          game.rotatePiece(clockwise: rotateClockwise);
          break;

        // SOFT DROP
        case LogicalKeyboardKey.keyW:
        case LogicalKeyboardKey.arrowDown:
          if (!softDrop) {
            softDrop = true;
            startGameLoop();
          }
          break;

        // HARD DROP
        case LogicalKeyboardKey.space:
          game.hardDrop();
          break;

        // HOLD
        case LogicalKeyboardKey.keyC:
          game.holdCurrentPiece();
          break;

        default:
          break;
      }
    });
  }

  void onKeyUp(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.arrowDown) {
      if (softDrop) {
        softDrop = false;
        startGameLoop();
      }
    }
  }

  void handleKeyboard(KeyEvent event) {
    if (event is KeyDownEvent) {
      onKeyDown(event.logicalKey);
    }

    if (event is KeyUpEvent) {
      onKeyUp(event.logicalKey);
    }
  }
    //---------------------------
  // INTERFACE
  //---------------------------

  @override
  Widget build(BuildContext context) {
    final display = game.getDisplayBoard();

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Flutter Tetris   |   Score: ${game.score}",
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

            
              // TABULEIRO
              

              Container(
                width: 300,
                height: 600,

                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                ),

                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),

                  itemCount: game.rows * game.cols,

                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
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
                          color: value == -1
                              ? Colors.white38
                              : Colors.black54,
                        ),

                      ),
                    );
                  },
                ),
              ),

              const SizedBox(width: 25),

              //==========================================
              // PAINEL LATERAL
              //==========================================

              SizedBox(
                width: 170,

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.center,

                  children: [

                    //---------------- HOLD ----------------

                    const Text(
                      "HOLD",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      width: 120,
                      height: 120,

                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                        ),
                      ),

                      child: game.holdPiece == null
                          ? const SizedBox()
                          : buildMiniPiece(
                              game.holdPiece!,
                            ),
                    ),

                    const SizedBox(height: 30),

                    //---------------- NEXT ----------------

                    const Text(
                      "NEXT",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      width: 120,
                      height: 120,

                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                        ),
                      ),

                      child: buildMiniPiece(
                        game.nextPiece,
                      ),
                    ),

                    const SizedBox(height: 30),

                    //---------------- SCORE ----------------

                    Text(
                      "SCORE\n${game.score}",

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 30),

                    //---------------- GAME OVER ----------------

                    if (game.isGameOver)

                      ElevatedButton(
                        onPressed: restartGame,

                        child: const Text(
                          "RESTART",
                        ),
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
    //---------------------------
  // DESENHA MINI PEÇAS (HOLD / NEXT)
  //---------------------------

  Widget buildMiniPiece(Tetromino piece) {
    return Padding(
      padding: const EdgeInsets.all(8),
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
                color: value == 0
                    ? Colors.transparent
                    : blockColors[value]!,
                border: value == 0
                    ? null
                    : Border.all(color: Colors.black54),
              ),
            );
          },
        ),
      ),
    );
  }

  //---------------------------
  // PAINEL DE CONTROLES
  //---------------------------

  Widget buildControls() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "CONTROLES",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 10),
        Text("A / ←  Mover para esquerda"),
        Text("D / →  Mover para direita"),
        Text("S / ↑  Girar"),
        Text("W / ↓  Soft Drop"),
        Text("Espaço  Hard Drop"),
        Text("C  Hold"),
      ],
    );
  }
}