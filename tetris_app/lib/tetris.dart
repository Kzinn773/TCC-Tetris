import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
/// ===============================================
/// TIPOS DE PEÇAS
/// ===============================================

enum TetrominoShape {
  I,
  O,
  T,
  S,
  Z,
  J,
  L,
}

/// ===============================================
/// CLASSE DA PEÇA
/// ===============================================

class Tetromino {
  final TetrominoShape shape;

  List<List<int>> matrix;

  int x;
  int y;

  Tetromino(
    this.shape,
    this.matrix, {
    this.x = 0,
    this.y = 0,
  });

  factory Tetromino.create(
    TetrominoShape shape, {
    int boardCols = 10,
  }) {
    late List<List<int>> matrix;

    switch (shape) {
      case TetrominoShape.I:
        matrix = [
          [0, 0, 0, 0],
          [1, 1, 1, 1],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ];
        break;

      case TetrominoShape.O:
        matrix = [
          [2, 2],
          [2, 2],
        ];
        break;

      case TetrominoShape.T:
        matrix = [
          [0, 3, 0],
          [3, 3, 3],
          [0, 0, 0],
        ];
        break;

      case TetrominoShape.S:
        matrix = [
          [0, 4, 4],
          [4, 4, 0],
          [0, 0, 0],
        ];
        break;

      case TetrominoShape.Z:
        matrix = [
          [5, 5, 0],
          [0, 5, 5],
          [0, 0, 0],
        ];
        break;

      case TetrominoShape.J:
        matrix = [
          [6, 0, 0],
          [6, 6, 6],
          [0, 0, 0],
        ];
        break;

      case TetrominoShape.L:
        matrix = [
          [0, 0, 7],
          [7, 7, 7],
          [0, 0, 0],
        ];
        break;
    }

    return Tetromino(
      shape,
      matrix,
      x: (boardCols - matrix[0].length) ~/ 2,
      y: 0,
    );
  }

  /// Rotação horária
  void rotateClockwise() {
    int n = matrix.length;

    List<List<int>> rotated = List.generate(
      n,
      (_) => List.filled(n, 0),
    );

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        rotated[c][n - 1 - r] = matrix[r][c];
      }
    }

    matrix = rotated;
  }

  /// Rotação anti-horária
  void rotateCounterClockwise() {
    int n = matrix.length;

    List<List<int>> rotated = List.generate(
      n,
      (_) => List.filled(n, 0),
    );

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        rotated[n - 1 - c][r] = matrix[r][c];
      }
    }

    matrix = rotated;
  }

  /// Cópia da peça
  Tetromino clone() {
    return Tetromino(
      shape,
      matrix.map((e) => List<int>.from(e)).toList(),
      x: x,
      y: y,
    );
  }
}

/// ===============================================
/// SISTEMA 7-BAG
/// ===============================================

class PieceBag {
  final Random _random = Random();

  final List<TetrominoShape> _bag = [];

  TetrominoShape next() {
    if (_bag.isEmpty) {
      _bag.addAll(TetrominoShape.values);
      _bag.shuffle(_random);
    }

    return _bag.removeAt(0);
  }
}
/// ===============================================
/// LÓGICA PRINCIPAL DO JOGO
/// ===============================================

class TetrisGame {
  //=========================
  // TAMANHO DO TABULEIRO
  //=========================

  final int rows = 20;
  final int cols = 10;

  //=========================
  // TABULEIRO
  //=========================

  late List<List<int>> board;

  //=========================
  // PEÇAS
  //=========================

  late Tetromino currentPiece;
  late Tetromino nextPiece;

  Tetromino? holdPiece;

  //=========================
  // GERADOR 7-BAG
  //=========================

  final PieceBag _bag = PieceBag();

  //=========================
  // CONTROLE DO JOGO
  //=========================

  bool canHold = true;

  bool isGameOver = false;

  //=========================
  // PONTUAÇÃO
  //=========================

  int score = 0;

  /// Maior pontuação salva no computador
  int highScore = 0;

TetrisGame() {
  reset();
  loadHighScore();
}

Future<void> loadHighScore() async {
  final prefs = await SharedPreferences.getInstance();
  highScore = prefs.getInt('highScore') ?? 0;
}

Future<void> saveHighScore() async {
  if (score > highScore) {
    highScore = score;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('highScore', highScore);
  }
}

 void reset() {
  board = List.generate(
    rows,
    (_) => List.filled(cols, 0),
  );

  currentPiece = Tetromino.create(
    _bag.next(),
    boardCols: cols,
  );

  nextPiece = Tetromino.create(
    _bag.next(),
    boardCols: cols,
  );

  holdPiece = null;

  canHold = true;

  isGameOver = false;

  score = 0;

  // Não resetar o High Score.
  // Ele permanece salvo entre as partidas.
}

  //==========================================
  // LOOP DO JOGO
  //==========================================

  void tick() {
    if (isGameOver) return;

    if (!movePiece(0, 1)) {
      lockPiece();
      clearLines();
      spawnNextPiece();
    }
  }

  //==========================================
  // MOVIMENTO
  //==========================================

  bool movePiece(int dx, int dy) {
    if (_checkCollision(
      currentPiece.matrix,
      currentPiece.x + dx,
      currentPiece.y + dy,
    )) {
      return false;
    }

    currentPiece.x += dx;
    currentPiece.y += dy;

    return true;
  }

  //==========================================
  // ROTAÇÃO
  //==========================================

  bool rotatePiece({bool clockwise = true}) {
    List<List<int>> original =
        currentPiece.matrix
            .map((e) => List<int>.from(e))
            .toList();

    if (clockwise) {
      currentPiece.rotateClockwise();
    } else {
      currentPiece.rotateCounterClockwise();
    }

    if (_checkCollision(
      currentPiece.matrix,
      currentPiece.x,
      currentPiece.y,
    )) {
      currentPiece.matrix = original;
      return false;
    }

    return true;
  }

  //==========================================
  // COLISÃO
  //==========================================

  bool _checkCollision(
    List<List<int>> matrix,
    int px,
    int py,
  ) {
    for (int r = 0; r < matrix.length; r++) {
      for (int c = 0; c < matrix[r].length; c++) {
        if (matrix[r][c] == 0) continue;

        int boardX = px + c;
        int boardY = py + r;

        if (boardX < 0 || boardX >= cols) {
          return true;
        }

        if (boardY >= rows) {
          return true;
        }

        if (boardY >= 0 &&
            board[boardY][boardX] != 0) {
          return true;
        }
      }
    }

    return false;
  }

  //==========================================
  // FIXAR PEÇA
  //==========================================

  void lockPiece() {
    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] == 0) continue;

        int boardX = currentPiece.x + c;
        int boardY = currentPiece.y + r;

        if (boardY >= 0 &&
            boardY < rows &&
            boardX >= 0 &&
            boardX < cols) {
          board[boardY][boardX] =
              currentPiece.matrix[r][c];
        }
      }
    }
  }

  //==========================================
  // PRÓXIMA PEÇA
  //==========================================

  void spawnNextPiece() {
    currentPiece = nextPiece;

    currentPiece.x =
        (cols - currentPiece.matrix[0].length) ~/ 2;

    currentPiece.y = 0;

    nextPiece = Tetromino.create(
      _bag.next(),
      boardCols: cols,
    );

    canHold = true;

    if (_checkCollision(
      currentPiece.matrix,
      currentPiece.x,
      currentPiece.y,
    )) {
      isGameOver = true;
    }
  }

  //==========================================
  // HOLD
  //==========================================

  void holdCurrentPiece() {
    if (!canHold) return;

    if (holdPiece == null) {
      holdPiece = Tetromino.create(
        currentPiece.shape,
        boardCols: cols,
      );

      spawnNextPiece();
    } else {
      Tetromino temp = holdPiece!;

      holdPiece = Tetromino.create(
        currentPiece.shape,
        boardCols: cols,
      );

      currentPiece = Tetromino.create(
        temp.shape,
        boardCols: cols,
      );
    }

    canHold = false;
  }

  //==========================================
  // HARD DROP
  //==========================================

  void hardDrop() {
    while (movePiece(0, 1)) {}

    lockPiece();

    clearLines();

    spawnNextPiece();
  }
    //==========================================
  // LIMPAR LINHAS
  //==========================================

  void clearLines() {
    int cleared = 0;

    for (int r = rows - 1; r >= 0; r--) {
      if (!board[r].contains(0)) {
        board.removeAt(r);
        board.insert(0, List.filled(cols, 0));

        cleared++;
        r++;
      }
    }

    score += _calculateScore(cleared);
  }

  int _calculateScore(int lines) {
    switch (lines) {
      case 1:
        return 100;
      case 2:
        return 300;
      case 3:
        return 500;
      case 4:
        return 800;
      default:
        return 0;
    }
  }

  //==========================================
  // GHOST PIECE
  //==========================================

  int ghostY() {
    int y = currentPiece.y;

    while (!_checkCollision(
      currentPiece.matrix,
      currentPiece.x,
      y + 1,
    )) {
      y++;
    }

    return y;
  }

  //==========================================
  // TABULEIRO PARA DESENHO
  //==========================================

  List<List<int>> getDisplayBoard() {
    List<List<int>> display =
        List.generate(
      rows,
      (r) => List<int>.from(board[r]),
    );

    //------------- Ghost Piece -------------

    int ghost = ghostY();

    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] == 0) continue;

        int by = ghost + r;
        int bx = currentPiece.x + c;

        if (by >= 0 &&
            by < rows &&
            bx >= 0 &&
            bx < cols &&
            display[by][bx] == 0) {
          display[by][bx] = -1;
        }
      }
    }

    //------------- Peça Atual -------------

    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] == 0) continue;

        int by = currentPiece.y + r;
        int bx = currentPiece.x + c;

        if (by >= 0 &&
            by < rows &&
            bx >= 0 &&
            bx < cols) {
          display[by][bx] =
              currentPiece.matrix[r][c];
        }
      }
    }

    return display;
  }
}
