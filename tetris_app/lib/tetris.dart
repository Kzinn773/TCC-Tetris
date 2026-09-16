import 'dart:math';

class Tetromino {
  List<List<int>> matrix;
  final int type; // 1 a 7

  Tetromino({required this.matrix, required this.type});

  // Clona a matriz da peça para rotações
  Tetromino clone() {
    return Tetromino(
      matrix: matrix.map((row) => List<int>.from(row)).toList(),
      type: type,
    );
  }

  // Rotação de Matriz (Horário / Anti-horário)
  void rotate({bool clockwise = true}) {
    int rows = matrix.length;
    int cols = matrix[0].length;
    List<List<int>> rotated = List.generate(
      cols,
      (r) => List.generate(rows, (c) => 0),
    );

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (clockwise) {
          rotated[c][rows - 1 - r] = matrix[r][c];
        } else {
          rotated[cols - 1 - c][r] = matrix[r][c];
        }
      }
    }
    matrix = rotated;
  }
}

class TetrisGame {
  final int rows = 20;
  final int cols = 10;

  late List<List<int>> board;
  late Tetromino currentPiece;
  late Tetromino nextPiece;
  Tetromino? holdPiece;

  bool canHold = true;
  int currentX = 3;
  int currentY = 0;

  int score = 0;
  bool isGameOver = false;

  // Sistema 7-Bag para controle de aleatoriedade
  final List<int> _bag = [];
  final Random _random = Random();

  Function()? onPieceDrop;
  Function(int lines)? onLineClear;

  TetrisGame() {
    reset();
  }

  // Definição das matrizes padrão dos 7 Tetrominós
  static Tetromino _createTetromino(int type) {
    switch (type) {
      case 1: // I
        return Tetromino(
          type: 1,
          matrix: [
            [1, 1, 1, 1]
          ],
        );
      case 2: // O
        return Tetromino(
          type: 2,
          matrix: [
            [2, 2],
            [2, 2]
          ],
        );
      case 3: // T
        return Tetromino(
          type: 3,
          matrix: [
            [0, 3, 0],
            [3, 3, 3]
          ],
        );
      case 4: // S
        return Tetromino(
          type: 4,
          matrix: [
            [0, 4, 4],
            [4, 4, 0]
          ],
        );
      case 5: // Z
        return Tetromino(
          type: 5,
          matrix: [
            [5, 5, 0],
            [0, 5, 5]
          ],
        );
      case 6: // J
        return Tetromino(
          type: 6,
          matrix: [
            [6, 0, 0],
            [6, 6, 6]
          ],
        );
      case 7: // L
        return Tetromino(
          type: 7,
          matrix: [
            [0, 0, 7],
            [7, 7, 7]
          ],
        );
      default:
        return Tetromino(type: 1, matrix: [[1]]);
    }
  }

  // Gera uma nova peça garantindo distribuição justa pelo 7-Bag
  Tetromino _generateNextPieceFromBag() {
    if (_bag.isEmpty) {
      _bag.addAll([1, 2, 3, 4, 5, 6, 7]);
      _bag.shuffle(_random);
    }
    int nextType = _bag.removeAt(0);
    return _createTetromino(nextType);
  }

  void reset() {
    board = List.generate(rows, (_) => List.generate(cols, (_) => 0));
    _bag.clear();
    isGameOver = false;
    score = 0;
    holdPiece = null;
    canHold = true;

    currentPiece = _generateNextPieceFromBag();
    nextPiece = _generateNextPieceFromBag();
    _spawnPiece();
  }

  void _spawnPiece() {
    currentX = (cols - currentPiece.matrix[0].length) ~/ 2;
    currentY = 0;

    if (_checkCollision(currentPiece, currentX, currentY)) {
      isGameOver = true;
    }
  }

  bool _checkCollision(Tetromino piece, int x, int y) {
    for (int r = 0; r < piece.matrix.length; r++) {
      for (int c = 0; c < piece.matrix[r].length; c++) {
        if (piece.matrix[r][c] != 0) {
          int newX = x + c;
          int newY = y + r;

          if (newX < 0 || newX >= cols || newY >= rows) {
            return true;
          }

          if (newY >= 0 && board[newY][newX] != 0) {
            return true;
          }
        }
      }
    }
    return false;
  }

  void tick() {
    if (isGameOver) return;

    if (!_checkCollision(currentPiece, currentX, currentY + 1)) {
      currentY++;
    } else {
      _lockPiece();
    }
  }

  void movePiece(int dx, int dy) {
    if (isGameOver) return;
    if (!_checkCollision(currentPiece, currentX + dx, currentY + dy)) {
      currentX += dx;
      currentY += dy;
    }
  }

  void rotatePiece({bool clockwise = true}) {
    if (isGameOver) return;

    Tetromino rotated = currentPiece.clone();
    rotated.rotate(clockwise: clockwise);

    // Ajustes básicos de parede (Wall Kick Simples)
    List<int> offsets = [0, -1, 1, -2, 2];
    for (int offset in offsets) {
      if (!_checkCollision(rotated, currentX + offset, currentY)) {
        currentX += offset;
        currentPiece = rotated;
        return;
      }
    }
  }

  void hardDrop() {
    if (isGameOver) return;
    while (!_checkCollision(currentPiece, currentX, currentY + 1)) {
      currentY++;
    }
    _lockPiece();
  }

  void holdCurrentPiece() {
    if (isGameOver || !canHold) return;

    canHold = false;
    if (holdPiece == null) {
      holdPiece = _createTetromino(currentPiece.type);
      currentPiece = nextPiece;
      nextPiece = _generateNextPieceFromBag();
    } else {
      Tetromino temp = _createTetromino(currentPiece.type);
      currentPiece = _createTetromino(holdPiece!.type);
      holdPiece = temp;
    }
    _spawnPiece();
  }

  void _lockPiece() {
    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] != 0) {
          int boardY = currentY + r;
          int boardX = currentX + c;
          if (boardY >= 0 && boardY < rows && boardX >= 0 && boardX < cols) {
            board[boardY][boardX] = currentPiece.matrix[r][c];
          }
        }
      }
    }

    onPieceDrop?.call();
    _clearLines();

    currentPiece = nextPiece;
    nextPiece = _generateNextPieceFromBag();
    canHold = true;
    _spawnPiece();
  }

  void _clearLines() {
    int linesCleared = 0;

    for (int r = rows - 1; r >= 0; r--) {
      if (board[r].every((cell) => cell != 0)) {
        board.removeAt(r);
        board.insert(0, List.generate(cols, (_) => 0));
        linesCleared++;
        r++; 
      }
    }

    if (linesCleared > 0) {
      onLineClear?.call(linesCleared);
    }
  }

  // Gera o tabuleiro mesclado com a peça atual e a sombra (Ghost Piece)
  List<List<int>> getDisplayBoard() {
    List<List<int>> display = List.generate(
      rows,
      (r) => List.from(board[r]),
    );

    if (isGameOver) return display;

    // Projetar Sombra (Ghost Piece)
    int ghostY = currentY;
    while (!_checkCollision(currentPiece, currentX, ghostY + 1)) {
      ghostY++;
    }

    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] != 0) {
          // Desenha sombra
          int gY = ghostY + r;
          int gX = currentX + c;
          if (gY >= 0 && gY < rows && gX >= 0 && gX < cols && display[gY][gX] == 0) {
            display[gY][gX] = -1;
          }
        }
      }
    }

    // Desenha Peça Atual
    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] != 0) {
          int pY = currentY + r;
          int pX = currentX + c;
          if (pY >= 0 && pY < rows && pX >= 0 && pX < cols) {
            display[pY][pX] = currentPiece.matrix[r][c];
          }
        }
      }
    }

    return display;
  }
}