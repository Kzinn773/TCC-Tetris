import 'dart:math';

enum TetrominoShape { I, O, T, S, Z, J, L }

class Tetromino {
  final TetrominoShape shape;
  List<List<int>> matrix;
  int x;
  int y;

  Tetromino(this.shape, this.matrix, {this.x = 3, this.y = 0});

  // Fábrica para criar peças com seus formatos padrão
  factory Tetromino.create(TetrominoShape shape) {
    switch (shape) {
      case TetrominoShape.I:
        return Tetromino(shape, [[1, 1, 1, 1]]);
      case TetrominoShape.O:
        return Tetromino(shape, [[1, 1], [1, 1]]);
      case TetrominoShape.T:
        return Tetromino(shape, [[0, 1, 0], [1, 1, 1]]);
      case TetrominoShape.S:
        return Tetromino(shape, [[0, 1, 1], [1, 1, 0]]);
      case TetrominoShape.Z:
        return Tetromino(shape, [[1, 1, 0], [0, 1, 1]]);
      case TetrominoShape.J:
        return Tetromino(shape, [[1, 0, 0], [1, 1, 1]]);
      case TetrominoShape.L:
        return Tetromino(shape, [[0, 0, 1], [1, 1, 1]]);
    }
  }

  factory Tetromino.random() {
    final shapes = TetrominoShape.values;
    return Tetromino.create(shapes[Random().nextInt(shapes.length)]);
  }

  // Rotaciona a matriz da peça em 90 graus no sentido horário
  void rotate() {
    int rows = matrix.length;
    int cols = matrix[0].length;
    List<List<int>> rotated = List.generate(cols, (_) => List.filled(rows, 0));

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        rotated[c][rows - 1 - r] = matrix[r][c];
      }
    }
    matrix = rotated;
  }
}
import 'tetromino.dart';

class TetrisGame {
  final int rows = 20;
  final int cols = 10;
  
  late List<List<int>> board;
  late Tetromino currentPiece;
  bool isGameOver = false;
  int score = 0;

  TetrisGame() {
    reset();
  }

  void reset() {
    board = List.generate(rows, (_) => List.filled(cols, 0));
    currentPiece = Tetromino.random();
    isGameOver = false;
    score = 0;
  }

  // Avança o jogo em um passo de tempo (queda livre)
  void tick() {
    if (isGameOver) return;

    if (!movePiece(0, 1)) {
      lockPiece();
      clearLines();
      spawnNextPiece();
    }
  }

  // Move ou rotaciona a peça validando os limites do tabuleiro
  bool movePiece(int dx, int dy) {
    if (_checkCollision(currentPiece.matrix, currentPiece.x + dx, currentPiece.y + dy)) {
      return false;
    }
    currentPiece.x += dx;
    currentPiece.y += dy;
    return true;
  }

  bool rotatePiece() {
    final originalMatrix = currentPiece.matrix;
    currentPiece.rotate();
    
    // Se colidir após rotacionar, desfaz a rotação
    if (_checkCollision(currentPiece.matrix, currentPiece.x, currentPiece.y)) {
      currentPiece.matrix = originalMatrix;
      return false;
    }
    return true;
  }

  // Verifica se a peça bateu nas paredes ou em blocos fixados
  bool _checkCollision(List<List<int>> matrix, int px, int py) {
    for (int r = 0; r < matrix.length; r++) {
      for (int c = 0; c < matrix[r].length; c++) {
        if (matrix[r][c] != 0) {
          int boardX = px + c;
          int boardY = py + r;

          if (boardX < 0 || boardX >= cols || boardY >= rows) return true;
          if (boardY >= 0 && board[boardY][boardX] != 0) return true;
        }
      }
    }
    return false;
  }

  // Fixa a peça no tabuleiro quando ela não pode mais descer
  void lockPiece() {
    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] != 0) {
          int boardY = currentPiece.y + r;
          if (boardY >= 0) {
            board[boardY][currentPiece.x + c] = 1; // 1 indica bloco ocupado
          }
        }
      }
    }
  }

  void spawnNextPiece() {
    currentPiece = Tetromino.random();
    // Se a peça nascer colidindo, é Fim de Jogo
    if (_checkCollision(currentPiece.matrix, currentPiece.x, currentPiece.y)) {
      isGameOver = true;
    }
  }

  // Remove linhas completas e atualiza a pontuação
  void clearLines() {
    int linesCleared = 0;
    
    for (int r = rows - 1; r >= 0; r--) {
      if (!board[r].contains(0)) {
        board.removeAt(r);
        board.insert(0, List.filled(cols, 0));
        linesCleared++;
        r++; // Reavalia a mesma linha atualizada
      }
    }

    if (linesCleared > 0) {
      score += _calculateScore(linesCleared);
    }
  }

  int _calculateScore(int lines) {
    const points =; // Pontuação clássica
    return points[lines];
  }

  // Retorna uma representação visual do tabuleiro com a peça atual inclusa
  List<List<int>> getDisplayBoard() {
    List<List<int>> display = List.generate(rows, (r) => List.from(board[r]));
    
    for (int r = 0; r < currentPiece.matrix.length; r++) {
      for (int c = 0; c < currentPiece.matrix[r].length; c++) {
        if (currentPiece.matrix[r][c] != 0) {
          int boardY = currentPiece.y + r;
          int boardX = currentPiece.x + c;
          if (boardY >= 0 && boardY < rows && boardX >= 0 && boardX < cols) {
            display[boardY][boardX] = 2; // 2 indica a peça ativa em movimento
          }
        }
      }
    }
    return display;
  }
}