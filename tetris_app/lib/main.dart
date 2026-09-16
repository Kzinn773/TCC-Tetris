import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart'; // Importa o núcleo do Firebase
import 'firebase_options.dart'; // Importa o arquivo de chaves manuais que você criou no Passo 4
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'tetris.dart';

// ==========================================
// MODOS DE JOGO E SUBMODOS MEDIEVAIS
// ==========================================
enum GameMode { classic, medieval }
enum MedievalSubMode { campaign, horde }

// ==========================================
// PALETA DE CORES TEMA MEDIEVAL
// ==========================================
class MedievalColors {
  static const Color gold = Color(0xFFFFD700);
  static const Color darkGold = Color(0xFFB8860B);
  static const Color bronze = Color(0xFFCD7F32);
  static const Color woodDark = Color(0xFF1E140C);
  static const Color woodMedium = Color(0xFF3E2723);
  static const Color parchment = Color(0xFF2D241E);
  static const Color borderGold = Color(0xFFDAA520);
  static const Color crimson = Color(0xFF8B0000);
  static const Color emerald = Color(0xFF2E8B57);
}

// ==========================================
// EXTENSÃO DE COMPATIBILIDADE PARA TETROMINO
// ==========================================
extension TetrominoCompatExt on Tetromino {
  List<List<int>> get shape {
    dynamic self = this;
    try {
      var res = self.matrix;
      if (res != null) return List<List<int>>.from(res.map((row) => List<int>.from(row)));
    } catch (_) {}
    try {
      var res = self.tiles;
      if (res != null) return List<List<int>>.from(res.map((row) => List<int>.from(row)));
    } catch (_) {}
    try {
      var res = self.blocks;
      if (res != null) return List<List<int>>.from(res.map((row) => List<int>.from(row)));
    } catch (_) {}
    return [[1]];
  }

  int get colorIndex {
    dynamic self = this;
    try {
      var res = self.color;
      if (res != null) return res as int;
    } catch (_) {}
    try {
      var res = self.type;
      if (res != null) return res as int;
    } catch (_) {}
    try {
      var res = self.id;
      if (res != null) return res as int;
    } catch (_) {}
    return 1;
  }
}

// ==========================================
// INICIALIZAÇÃO DO APP COM FIREBASE
// ==========================================
void main() async {
  // 1. Garante que os bindings nativos do Flutter estejam prontos
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Inicializa o Firebase passando as configurações do arquivo firebase_options.dart
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. Carrega as configurações locais salvas do seu Tetris
  await GameSettings.load();
  
  // 4. Inicia o aplicativo
  runApp(const TetrisApp());
}

// ==========================================
// GERENCIADOR DE CONFIGURAÇÕES E CONTROLES
// ==========================================
class GameSettings {
  static double bgmVolume = 0.5;
  static double sfxVolume = 0.8;

  static LogicalKeyboardKey keyLeft = LogicalKeyboardKey.arrowLeft;
  static LogicalKeyboardKey keyRight = LogicalKeyboardKey.arrowRight;
  static LogicalKeyboardKey keyRotate = LogicalKeyboardKey.arrowUp;
  static LogicalKeyboardKey keySoftDrop = LogicalKeyboardKey.arrowDown;
  static LogicalKeyboardKey keyHardDrop = LogicalKeyboardKey.space;
  static LogicalKeyboardKey keyHold = LogicalKeyboardKey.keyC;
  static LogicalKeyboardKey keyPause = LogicalKeyboardKey.escape;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    bgmVolume = prefs.getDouble('bgmVolume') ?? 0.5;
    sfxVolume = prefs.getDouble('sfxVolume') ?? 0.8;

    keyLeft = _loadKey(prefs, 'keyLeft', LogicalKeyboardKey.arrowLeft);
    keyRight = _loadKey(prefs, 'keyRight', LogicalKeyboardKey.arrowRight);
    keyRotate = _loadKey(prefs, 'keyRotate', LogicalKeyboardKey.arrowUp);
    keySoftDrop = _loadKey(prefs, 'keySoftDrop', LogicalKeyboardKey.arrowDown);
    keyHardDrop = _loadKey(prefs, 'keyHardDrop', LogicalKeyboardKey.space);
    keyHold = _loadKey(prefs, 'keyHold', LogicalKeyboardKey.keyC);
    keyPause = _loadKey(prefs, 'keyPause', LogicalKeyboardKey.escape);
  }

  static LogicalKeyboardKey _loadKey(SharedPreferences prefs, String prefKey, LogicalKeyboardKey defaultKey) {
    int? keyId = prefs.getInt(prefKey);
    if (keyId == null) return defaultKey;
    return LogicalKeyboardKey(keyId);
  }

  static Future<void> saveVolume(String prefKey, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(prefKey, value);
  }

  static Future<void> resetToDefaults() async {
    bgmVolume = 0.5;
    sfxVolume = 0.8;
    keyLeft = LogicalKeyboardKey.arrowLeft;
    keyRight = LogicalKeyboardKey.arrowRight;
    keyRotate = LogicalKeyboardKey.arrowUp;
    keySoftDrop = LogicalKeyboardKey.arrowDown;
    keyHardDrop = LogicalKeyboardKey.space;
    keyHold = LogicalKeyboardKey.keyC;
    keyPause = LogicalKeyboardKey.escape;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bgmVolume', bgmVolume);
    await prefs.setDouble('sfxVolume', sfxVolume);
  }
}

// ==========================================
// IDENTIDADE DO JOGADOR (evita duplicar no ranking)
// ==========================================
class PlayerProfile {
  static String? _cachedId;

  // Gera (ou recupera) um ID único e fixo para este jogador/dispositivo
  static Future<String> getPlayerId() async {
    if (_cachedId != null) return _cachedId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('playerId');
    if (id == null) {
      id = _generateId();
      await prefs.setString('playerId', id);
    }
    _cachedId = id;
    return id;
  }

  static String _generateId() {
    final rand = Random();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(20, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static Future<String> getPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('playerName') ?? 'Cavaleiro Anônimo';
  }

  static Future<void> setPlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name.trim().isEmpty ? 'Cavaleiro Anônimo' : name.trim());
  }
}

class TetrisApp extends StatelessWidget {
  const TetrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tetris Medieval RPG',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0B08),
        dialogBackgroundColor: MedievalColors.woodDark,
      ),
      home: const HomeScreen(),
    );
  }
}

// ==========================================
// PAISAGEM DE FUNDO: PLANÍCIE MEDIEVAL
// ==========================================
class MedievalPlainsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 1. Céu Crepúsculo / Pôr do Sol
    final skyGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF1A0B2E), // Roxo escuro
        Color(0xFF4A154B), // Púrpura
        Color(0xFF8C2D38), // Vermelho crepúsculo
        Color(0xFFD97724), // Laranja dourado
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, width, height));

    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..shader = skyGradient);

    // 2. Sol do Pôr do Sol
    final sunPaint = Paint()
      ..color = const Color(0xFFFFD166).withOpacity(0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(Offset(width * 0.7, height * 0.45), 45, sunPaint);

    // 3. Nuvens Distantes
    final cloudPaint = Paint()..color = const Color(0x334A154B);
    canvas.drawOval(Rect.fromLTWH(width * 0.1, height * 0.25, 180, 40), cloudPaint);
    canvas.drawOval(Rect.fromLTWH(width * 0.5, height * 0.2, 220, 50), cloudPaint);

    // 4. Montanhas Distantes (Silhueta Roxa)
    final mountainPaint = Paint()..color = const Color(0xFF2A1B3D);
    final mountainPath = Path();
    mountainPath.moveTo(0, height * 0.65);
    mountainPath.lineTo(width * 0.15, height * 0.52);
    mountainPath.lineTo(width * 0.3, height * 0.62);
    mountainPath.lineTo(width * 0.5, height * 0.48);
    mountainPath.lineTo(width * 0.7, height * 0.60);
    mountainPath.lineTo(width * 0.88, height * 0.50);
    mountainPath.lineTo(width, height * 0.62);
    mountainPath.lineTo(width, height);
    mountainPath.lineTo(0, height);
    mountainPath.close();
    canvas.drawPath(mountainPath, mountainPaint);

    // 5. Silhueta do Castelo Medieval na Montanha
    final castlePaint = Paint()..color = const Color(0xFF1D122B);
    double castleX = width * 0.46;
    double castleY = height * 0.48;

    canvas.drawRect(Rect.fromLTWH(castleX - 20, castleY - 25, 12, 30), castlePaint);
    canvas.drawRect(Rect.fromLTWH(castleX + 10, castleY - 25, 12, 30), castlePaint);
    canvas.drawRect(Rect.fromLTWH(castleX - 5, castleY - 35, 12, 40), castlePaint);
    canvas.drawRect(Rect.fromLTWH(castleX - 25, castleY - 10, 52, 18), castlePaint);

    final roofPath = Path();
    roofPath.moveTo(castleX - 22, castleY - 25);
    roofPath.lineTo(castleX - 14, castleY - 37);
    roofPath.lineTo(castleX - 6, castleY - 25);

    roofPath.moveTo(castleX + 8, castleY - 25);
    roofPath.lineTo(castleX + 16, castleY - 37);
    roofPath.lineTo(castleX + 24, castleY - 25);

    roofPath.moveTo(castleX - 7, castleY - 35);
    roofPath.lineTo(castleX + 1, castleY - 50);
    roofPath.lineTo(castleX + 9, castleY - 35);
    canvas.drawPath(roofPath, castlePaint);

    // 6. Colinas Intermediárias
    final midHillsPaint = Paint()..color = const Color(0xFF1E3A1E);
    final midHillsPath = Path();
    midHillsPath.moveTo(0, height * 0.68);
    midHillsPath.quadraticBezierTo(width * 0.25, height * 0.60, width * 0.5, height * 0.66);
    midHillsPath.quadraticBezierTo(width * 0.75, height * 0.72, width, height * 0.64);
    midHillsPath.lineTo(width, height);
    midHillsPath.lineTo(0, height);
    midHillsPath.close();
    canvas.drawPath(midHillsPath, midHillsPaint);

    // 7. Colinas de Primeiro Plano
    final foreHillsPaint = Paint()..color = const Color(0xFF132A13);
    final foreHillsPath = Path();
    foreHillsPath.moveTo(0, height * 0.75);
    foreHillsPath.quadraticBezierTo(width * 0.35, height * 0.82, width * 0.65, height * 0.74);
    foreHillsPath.quadraticBezierTo(width * 0.85, height * 0.70, width, height * 0.78);
    foreHillsPath.lineTo(width, height);
    foreHillsPath.lineTo(0, height);
    foreHillsPath.close();
    canvas.drawPath(foreHillsPath, foreHillsPaint);

    // 8. Árvores/Pinheiros
    final treePaint = Paint()..color = const Color(0xFF0A1B0A);
    void drawPineTree(double x, double y, double scale) {
      final treePath = Path();
      treePath.moveTo(x, y - (30 * scale));
      treePath.lineTo(x - (10 * scale), y - (10 * scale));
      treePath.lineTo(x - (5 * scale), y - (10 * scale));
      treePath.lineTo(x - (12 * scale), y);
      treePath.lineTo(x + (12 * scale), y);
      treePath.lineTo(x + (5 * scale), y - (10 * scale));
      treePath.lineTo(x + (10 * scale), y - (10 * scale));
      treePath.close();
      canvas.drawPath(treePath, treePaint);
      canvas.drawRect(Rect.fromLTWH(x - (2 * scale), y, 4 * scale, 6 * scale), treePaint);
    }

    drawPineTree(width * 0.08, height * 0.76, 1.2);
    drawPineTree(width * 0.12, height * 0.78, 0.9);
    drawPineTree(width * 0.82, height * 0.77, 1.3);
    drawPineTree(width * 0.88, height * 0.75, 1.0);
    drawPineTree(width * 0.92, height * 0.79, 1.1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// WIDGET: MOLDURA E BOTÕES MEDIEVAIS
// ==========================================
class MedievalFrame extends StatelessWidget {
  final Widget child;
  final double padding;
  final Color borderColor;

  const MedievalFrame({
    super.key,
    required this.child,
    this.padding = 16.0,
    this.borderColor = MedievalColors.borderGold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: MedievalColors.woodDark.withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 12, spreadRadius: 2),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(top: -8, left: -8, child: _buildCornerSign()),
          Positioned(top: -8, right: -8, child: _buildCornerSign()),
          Positioned(bottom: -8, left: -8, child: _buildCornerSign()),
          Positioned(bottom: -8, right: -8, child: _buildCornerSign()),
        ],
      ),
    );
  }

  Widget _buildCornerSign() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: MedievalColors.gold,
        border: Border.all(color: MedievalColors.woodDark, width: 2),
        shape: BoxShape.circle,
      ),
    );
  }
}

class MedievalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color primaryColor;
  final double width;

  const MedievalButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primaryColor = MedievalColors.borderGold,
    this.width = 280,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MedievalColors.woodMedium, MedievalColors.woodDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primaryColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 6,
            spreadRadius: 1,
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: primaryColor, size: 22),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.amber[100],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TELA INICIAL COM MENU ESTILIZADO
// ==========================================
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

  void _openSettings() {
    showDialog(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
  }

  void _openMedievalSubmenu() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MedievalSubmenuScreen()),
    );
  }

  void _startClassicGame() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const TetrisGameScreen(gameMode: GameMode.classic)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: MedievalPlainsPainter(),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MedievalFrame(
                    padding: 24,
                    borderColor: MedievalColors.gold,
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.shield, color: MedievalColors.gold, size: 32),
                            SizedBox(width: 10),
                            Text(
                              "TETRIS MEDIEVAL",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: MedievalColors.gold,
                                letterSpacing: 3,
                                fontFamily: 'Serif',
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 8, offset: Offset(2, 2)),
                                ],
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.shield, color: MedievalColors.gold, size: 32),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "CRÔNICAS DOS BLOCOS",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amberAccent,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: MedievalColors.gold.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events, color: MedievalColors.gold, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "GLÓRIA MÁXIMA: $highScore",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 35),

                  MedievalButton(
                    label: "MODO MEDIEVAL",
                    icon: Icons.fort,
                    primaryColor: MedievalColors.gold,
                    onPressed: _openMedievalSubmenu,
                  ),

                  MedievalButton(
                    label: "MODO CLÁSSICO",
                    icon: Icons.grid_on,
                    primaryColor: Colors.amber,
                    onPressed: _startClassicGame,
                  ),

                  MedievalButton(
                    label: "CONFIGURAÇÕES",
                    icon: Icons.settings,
                    primaryColor: Colors.grey,
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SUBMENU DEDICADO: TETRIS MEDIEVAL
// ==========================================
class MedievalSubmenuScreen extends StatelessWidget {
  const MedievalSubmenuScreen({super.key});

  void _startMedievalGame(BuildContext context, MedievalSubMode subMode) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TetrisGameScreen(
          gameMode: GameMode.medieval,
          subMode: subMode,
        ),
      ),
    );
  }

  void _showRulesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MedievalColors.woodDark,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MedievalColors.gold, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Row(
          children: [
            Icon(Icons.menu_book, color: MedievalColors.gold),
            SizedBox(width: 10),
            Text("MANUAL DO CAVALEIRO", style: TextStyle(color: MedievalColors.gold, fontSize: 18)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("• Complete linhas no Tetris para desferir ataques de espada no Monstro.", style: TextStyle(color: Colors.white70)),
              SizedBox(height: 8),
              Text("• Mais linhas completas simultaneamente causam DANO CRÍTICO!", style: TextStyle(color: Colors.amberAccent)),
              SizedBox(height: 8),
              Text("• Derrotar monstros aumenta o NÍVEL DO HERÓI e concede Dano Adicional.", style: TextStyle(color: Colors.white70)),
              SizedBox(height: 8),
              Text("• Cuidado! Os morcegos atacam periodicamente e reduzem seu HP.", style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ENTENDIDO", style: TextStyle(color: MedievalColors.gold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: MedievalPlainsPainter(),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: MedievalFrame(
                padding: 24,
                borderColor: MedievalColors.gold,
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: MedievalColors.gold),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Text(
                            "JORNADA MEDIEVAL",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: MedievalColors.gold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const Divider(color: MedievalColors.gold, thickness: 1),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: MedievalColors.borderGold.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: MedievalColors.woodMedium,
                                border: Border.all(color: MedievalColors.gold),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person, color: MedievalColors.gold, size: 30),
                            ),
                            const SizedBox(width: 15),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("CLASSE: GUERREIRO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                SizedBox(height: 4),
                                Text("HP INICIAL: 100  |  ATK: 10", style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),
                      MedievalButton(
                        width: double.infinity,
                        label: "CAMPANHA PRINCIPAL",
                        icon: Icons.sports_kabaddi,
                        primaryColor: MedievalColors.gold,
                        onPressed: () => _startMedievalGame(context, MedievalSubMode.campaign),
                      ),
                      MedievalButton(
                        width: double.infinity,
                        label: "MODO HORDA",
                        icon: Icons.groups,
                        primaryColor: Colors.purpleAccent,
                        onPressed: () => _startMedievalGame(context, MedievalSubMode.horde),
                      ),
                      MedievalButton(
                        width: double.infinity,
                        label: "GUIA DE COMBATE",
                        icon: Icons.menu_book,
                        primaryColor: Colors.lightBlueAccent,
                        onPressed: () => _showRulesDialog(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// DADOS INDIVIDUAIS DE CADA MORCEGO DA HORDA
// ==========================================
class HordeBat {
  final int id;
  final double baseX;
  final double baseY;
  final int intervalMs;
  late AnimationController controller;
  bool sweepLeftToRight = true;
  bool hasHitPlayer = false;
  Timer? timer;

  HordeBat({
    required this.id,
    required this.baseX,
    required this.baseY,
    required this.intervalMs,
  });
}

// ==========================================
// COMPONENTE: TELA DE PIXEL ART (COMBATE RPG)
// ==========================================
class PixelArtScreen extends StatefulWidget {
  final int level;
  final int score;
  final int lines;
  final int playerHp;
  final int playerMaxHp;
  final int playerDamage;
  final int monsterHp;
  final int monsterMaxHp;
  final bool isPaused;
  final bool isGameOver;
  final bool isHorde;
  final int batAttackTrigger;
  final int monsterDeathTrigger;
  final Function(int damage) onBatHitPlayer;

  const PixelArtScreen({
    super.key,
    required this.level,
    required this.score,
    required this.lines,
    required this.playerHp,
    required this.playerMaxHp,
    required this.playerDamage,
    required this.monsterHp,
    required this.monsterMaxHp,
    required this.isPaused,
    required this.isGameOver,
    required this.isHorde,
    required this.batAttackTrigger,
    required this.monsterDeathTrigger,
    required this.onBatHitPlayer,
  });

  @override
  State<PixelArtScreen> createState() => _PixelArtScreenState();
}

class _PixelArtScreenState extends State<PixelArtScreen> with TickerProviderStateMixin {
  late AnimationController _idleController;
  late AnimationController _batAttackController;
  late AnimationController _damageFlashController;
  late AnimationController _deathController;

  List<HordeBat> hordeBats = [];

  static const List<List<int>> warriorSprite16 = [
    [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
    [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
    [0,0,0,0,1,2,2,2,2,2,1,0,0,0,0,0],
    [0,0,0,0,1,2,1,1,1,2,1,0,0,0,0,0],
    [0,0,0,0,1,4,4,4,4,4,1,0,0,0,0,0],
    [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
    [0,0,0,1,1,2,5,5,2,2,1,1,0,0,0,0],
    [0,0,1,7,1,2,5,5,2,2,1,0,0,0,0,0],
    [0,0,1,7,1,2,2,2,2,2,1,0,0,0,0,0],
    [0,0,1,7,1,2,6,6,2,2,1,0,0,0,0,0],
    [0,0,1,6,1,2,2,2,2,2,1,0,0,0,0,0],
    [0,0,0,1,0,1,3,0,3,1,0,0,0,0,0,0],
    [0,0,0,0,0,1,3,0,3,1,0,0,0,0,0,0],
    [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
    [0,0,0,0,1,1,1,0,1,1,1,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
  ];

  static const List<List<int>> batSprite16 = [
    [0,0,1,1,0,0,0,0,0,0,0,0,1,1,0,0],
    [0,1,1,1,1,0,0,0,0,0,0,1,1,1,1,0],
    [1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1],
    [1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1],
    [1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1],
    [0,0,0,0,1,1,2,1,1,2,1,1,0,0,0,0],
    [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
    [0,0,0,0,0,1,3,3,3,3,1,0,0,0,0,0],
    [0,0,0,0,0,0,1,3,3,1,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0],
  ];

  static const List<List<int>> batSadSprite16 = [
    [0,0,1,1,0,0,0,0,0,0,0,0,1,1,0,0],
    [0,1,1,1,1,0,0,0,0,0,0,1,1,1,1,0],
    [1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1],
    [1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1],
    [1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1],
    [0,0,0,0,1,1,5,1,1,5,1,1,0,0,0,0],
    [0,0,0,0,1,1,4,1,1,4,1,1,0,0,0,0],
    [0,0,0,0,0,1,0,3,3,0,1,0,0,0,0,0],
    [0,0,0,0,0,0,1,3,3,1,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0],
  ];

  static const Map<int, Color> warriorColors = {
    1: Color(0xFF1A1A1A),
    2: Color(0xFF9E9E9E),
    3: Color(0xFF616161),
    4: Color(0xFFFFCC99),
    5: Color(0xFFE53935),
    6: Color(0xFFFFD54F),
    7: Color(0xFFE0E0E0),
  };

  static const Map<int, Color> batColors = {
    1: Color(0xFF3B1D5A),
    2: Color(0xFFFF0044),
    3: Color(0xFF7A43B6),
    4: Color(0xFF38BDF8),
    5: Color(0xFFFFFFFF),
  };

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _batAttackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _damageFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _deathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _initHordeBats();
  }

  void _initHordeBats() {
    _clearHordeBats();

    final intervals = [2000, 4000, 3000, 5000, 3500];
    final positionsX = [15.0, 50.0, 85.0, 120.0, 155.0];

    for (int i = 0; i < 5; i++) {
      final bat = HordeBat(
        id: i,
        baseX: positionsX[i],
        baseY: 40.0 + (i % 2 == 0 ? 0 : 12),
        intervalMs: intervals[i],
      );

      bat.controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );

      bat.controller.addListener(() {
        if (bat.controller.value >= 0.5 && !bat.hasHitPlayer) {
          bat.hasHitPlayer = true;
          widget.onBatHitPlayer(3);
        }
      });

      bat.controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          bat.controller.reset();
          bat.hasHitPlayer = false;
        }
      });

      bat.timer = Timer.periodic(Duration(milliseconds: bat.intervalMs), (_) {
        if (!mounted || widget.isGameOver || widget.isPaused || !widget.isHorde) return;
        if (!bat.controller.isAnimating) {
          bat.sweepLeftToRight = Random().nextBool();
          bat.hasHitPlayer = false;
          bat.controller.forward(from: 0.0);
        }
      });

      hordeBats.add(bat);
    }
  }

  void _clearHordeBats() {
    for (var bat in hordeBats) {
      bat.timer?.cancel();
      bat.controller.dispose();
    }
    hordeBats.clear();
  }

  @override
  void didUpdateWidget(PixelArtScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isHorde != oldWidget.isHorde) {
      if (widget.isHorde) {
        _initHordeBats();
      } else {
        _clearHordeBats();
      }
    }

    if (!widget.isHorde && widget.batAttackTrigger != oldWidget.batAttackTrigger && widget.batAttackTrigger > 0) {
      _batAttackController.forward(from: 0.0);
    }

    if (widget.monsterDeathTrigger != oldWidget.monsterDeathTrigger && widget.monsterDeathTrigger > 0) {
      _deathController.forward(from: 0.0);
    }

    if (widget.playerHp < oldWidget.playerHp) {
      _damageFlashController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _clearHordeBats();
    _idleController.dispose();
    _batAttackController.dispose();
    _damageFlashController.dispose();
    _deathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int displayMonsterHp = widget.monsterHp.clamp(0, widget.monsterMaxHp);
    double monsterHpProgress = (displayMonsterHp / widget.monsterMaxHp).clamp(0.0, 1.0);

    int displayPlayerHp = widget.playerHp.clamp(0, widget.playerMaxHp);
    double playerHpProgress = (displayPlayerHp / widget.playerMaxHp).clamp(0.0, 1.0);

    return Container(
      width: 220,
      height: 600,
      decoration: BoxDecoration(
        color: MedievalColors.woodDark,
        border: Border.all(color: widget.isHorde ? Colors.purpleAccent : MedievalColors.gold, width: 3),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: MedievalColors.woodMedium,
            child: Center(
              child: Text(
                widget.isHorde ? "HORDA DE MORCEGOS" : "HERÓI NÍVEL: ${widget.level}",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: widget.isHorde ? Colors.purpleAccent : MedievalColors.gold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: MedievalColors.gold),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PixelDungeonBackgroundPainter(),
                  ),
                ),
                Positioned(
                  top: 15,
                  left: 30,
                  right: 30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      border: Border.all(color: widget.isHorde ? Colors.purpleAccent : Colors.redAccent, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.isHorde ? "HORDA" : "MONSTRO",
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: widget.isHorde ? Colors.purpleAccent : Colors.redAccent),
                            ),
                            Text(
                              "$displayMonsterHp/${widget.monsterMaxHp}",
                              style: const TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: monsterHpProgress,
                            minHeight: 5,
                            backgroundColor: Colors.red.withOpacity(0.2),
                            color: widget.isHorde ? Colors.purpleAccent : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 30,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_idleController, _damageFlashController]),
                    builder: (context, child) {
                      double offsetY = widget.isGameOver ? 6.0 : _idleController.value * 4.0;
                      double flashValue = 0.0;
                      if (_damageFlashController.isAnimating) {
                        flashValue = (sin(_damageFlashController.value * pi * 4)).abs();
                      }

                      return Transform.translate(
                        offset: Offset(0, -offsetY),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.red.withOpacity(flashValue * 0.85),
                            BlendMode.srcATop,
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 128,
                      height: 128,
                      child: CustomPaint(
                        painter: PixelSpritePainter(
                          sprite: warriorSprite16,
                          colorPalette: warriorColors,
                          pixelSize: 8.0,
                        ),
                      ),
                    ),
                  ),
                ),

                if (widget.isHorde)
                  ...hordeBats.map((bat) {
                    return AnimatedBuilder(
                      animation: Listenable.merge([_idleController, bat.controller]),
                      builder: (context, child) {
                        double idleY = sin(_idleController.value * pi * 2 + bat.id) * 4;
                        double floatX = cos(_idleController.value * pi * 2 + bat.id) * 6;

                        double batLeft = bat.baseX + floatX;
                        double batTop = bat.baseY + idleY;

                        if (bat.controller.isAnimating) {
                          double t = bat.controller.value;
                          double u = 1 - t;
                          double tt = t * t;
                          double uu = u * u;

                          double startX = bat.sweepLeftToRight ? 170.0 : 10.0;
                          double startY = 30.0;

                          double warriorX = 35.0;
                          double warriorY = 210.0;

                          double endX = bat.baseX;
                          double endY = bat.baseY;

                          batLeft = uu * startX + 2 * u * t * warriorX + tt * endX;
                          batTop = uu * startY + 2 * u * t * warriorY + tt * endY;
                        }

                        return Positioned(
                          left: batLeft,
                          top: batTop,
                          child: SizedBox(
                            width: 50,
                            height: 35,
                            child: CustomPaint(
                              painter: PixelSpritePainter(
                                sprite: batSprite16,
                                colorPalette: batColors,
                                pixelSize: 3.2,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  })
                else
                  AnimatedBuilder(
                    animation: Listenable.merge([_idleController, _batAttackController, _deathController]),
                    builder: (context, child) {
                      double idleY = sin(_idleController.value * pi * 2) * 5;

                      double batLeft = 110;
                      double batTop = 50 + idleY;
                      double batOpacity = 1.0;
                      bool isSad = false;

                      if (_deathController.isAnimating) {
                        double t = _deathController.value;

                        if (t < 0.20) {
                          isSad = true;
                          double shakeProgress = t / 0.20;
                          batLeft = 110 + sin(shakeProgress * pi * 10) * 8;
                          batTop = 50;
                        } else if (t < 0.45) {
                          isSad = true;
                          double fallProgress = (t - 0.20) / 0.25;
                          batLeft = 110;
                          batTop = 50 + (fallProgress * 180);
                          batOpacity = (1.0 - fallProgress).clamp(0.0, 1.0);
                        } else {
                          isSad = false;
                          double enterProgress = (t - 0.45) / 0.55;
                          batLeft = -80 + (enterProgress * 190);
                          batTop = 50 + sin(enterProgress * pi * 4) * 8;
                          batOpacity = (enterProgress * 2.5).clamp(0.0, 1.0);
                        }
                      } else if (_batAttackController.isAnimating) {
                        double t = _batAttackController.value;
                        double u = 1 - t;
                        double tt = t * t;
                        double uu = u * u;
                        double uuu = uu * u;
                        double ttt = tt * t;

                        double p0x = 110, p0y = 50 + idleY;
                        double p1x = 130, p1y = 230;
                        double p2x = 20,  p2y = 230;
                        double p3x = 110, p3y = 50 + idleY;

                        batLeft = uuu * p0x + 3 * uu * t * p1x + 3 * u * tt * p2x + ttt * p3x;
                        batTop  = uuu * p0y + 3 * uu * t * p1y + 3 * u * tt * p2y + ttt * p3y;
                      }

                      return Positioned(
                        left: batLeft,
                        top: batTop,
                        child: Opacity(
                          opacity: batOpacity,
                          child: SizedBox(
                            width: 80,
                            height: 50,
                            child: CustomPaint(
                              painter: PixelSpritePainter(
                                sprite: isSad ? batSadSprite16 : batSprite16,
                                colorPalette: batColors,
                                pixelSize: 5.0,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: MedievalColors.gold),
          Container(
            padding: const EdgeInsets.all(10),
            color: MedievalColors.woodMedium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("VIDA (HP):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 11)),
                    Text(
                      "$displayPlayerHp / ${widget.playerMaxHp}",
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: playerHpProgress,
                    minHeight: 8,
                    backgroundColor: Colors.green.withOpacity(0.2),
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("DANO BASE:", style: TextStyle(fontSize: 11, color: Colors.white70)),
                    Text(
                      "${widget.playerDamage} ATK",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: MedievalColors.gold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PixelSpritePainter extends CustomPainter {
  final List<List<int>> sprite;
  final Map<int, Color> colorPalette;
  final double pixelSize;

  PixelSpritePainter({
    required this.sprite,
    required this.colorPalette,
    this.pixelSize = 4.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < sprite.length; r++) {
      for (int c = 0; c < sprite[r].length; c++) {
        int colorIndex = sprite[r][c];
        if (colorIndex != 0 && colorPalette.containsKey(colorIndex)) {
          paint.color = colorPalette[colorIndex]!;
          canvas.drawRect(
            Rect.fromLTWH(c * pixelSize, r * pixelSize, pixelSize, pixelSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelSpritePainter oldDelegate) => true;
}

class PixelDungeonBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()..color = const Color(0xFF1B1410);
    final brickLinePaint = Paint()
      ..color = const Color(0xFF2C1E17)
      ..strokeWidth = 2;
    final floorPaint = Paint()..color = const Color(0xFF3B291F);

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height - 60), wallPaint);

    for (double y = 20; y < size.height - 60; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), brickLinePaint);
    }

    canvas.drawRect(Rect.fromLTWH(0, size.height - 60, size.width, 60), floorPaint);
    canvas.drawLine(Offset(0, size.height - 60), Offset(size.width, size.height - 60), Paint()..color = MedievalColors.gold..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// TELA DO JOGO (TETRIS CLÁSSICO E RPG)
// ==========================================
class TetrisGameScreen extends StatefulWidget {
  final GameMode gameMode;
  final MedievalSubMode subMode;

  const TetrisGameScreen({
    super.key,
    this.gameMode = GameMode.medieval,
    this.subMode = MedievalSubMode.campaign,
  });

  @override
  State<TetrisGameScreen> createState() => _TetrisGameScreenState();
}

class _TetrisGameScreenState extends State<TetrisGameScreen> with SingleTickerProviderStateMixin {
  late TetrisGame game;
  Timer? gameTimer;
  Timer? monsterAttackTimer;

  bool isPaused = false;
  Timer? _leftTimer;
  Timer? _rightTimer;
  bool _isLeftPressed = false;
  bool _isRightPressed = false;

  final AudioPlayer _bgmPlayer = AudioPlayer();

  late AnimationController _shakeController;

  int currentScore = 0;
  int totalLinesCleared = 0;
  int dropInterval = 1000;
  int globalHighScore = 0;
  int sessionHighScore = 0;
  int finalScore = 0;
  bool _hasTriggeredGameOver = false;

  int batAttackTriggerCount = 0;
  int monsterDeathTriggerCount = 0;

  int playerLevel = 1;
  int playerHp = 100;
  int playerMaxHp = 100;
  int playerDamage = 10;

  int monsterHp = 20;
  int monsterMaxHp = 20;
  bool isHorde = false;

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

    if (widget.subMode == MedievalSubMode.horde) {
      isHorde = true;
      monsterMaxHp = 50;
      monsterHp = 50;
    }

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    game.onPieceDrop = () {
      _playSfx('audio/drop.mp3');
    };

    game.onLineClear = (lines) {
      int basePoints = 0;

      switch (lines) {
        case 1:
          basePoints = 100;
          _playSfx('audio/clear_1.mp3');
          break;
        case 2:
          basePoints = 300;
          _playSfx('audio/clear_2.mp3');
          break;
        case 3:
          basePoints = 500;
          _playSfx('audio/clear_3.mp3');
          break;
        case 4:
          basePoints = 800;
          _playSfx('audio/clear_4.mp3');
          break;
      }

      int levelMultiplier = (widget.gameMode == GameMode.medieval)
          ? playerLevel
          : ((totalLinesCleared ~/ 10) + 1);

      if (widget.gameMode == GameMode.medieval) {
        int damageDealt = lines * playerDamage;
        monsterHp -= damageDealt;

        bool killedMonster = false;

        if (monsterHp <= 0) {
          killedMonster = true;
          monsterDeathTriggerCount++;
          playerLevel++;
          playerDamage = max(playerDamage + 1, (playerDamage * 1.20).round());

          if (playerLevel % 5 == 0 && widget.subMode == MedievalSubMode.campaign) {
            isHorde = true;
            monsterMaxHp = max(monsterMaxHp + 1, (monsterMaxHp * 1.60).round());
          } else {
            if (widget.subMode == MedievalSubMode.campaign) isHorde = false;
            monsterMaxHp = max(monsterMaxHp + 1, (monsterMaxHp * 1.20).round());
          }

          monsterHp = monsterMaxHp;
          playerHp = playerMaxHp;
        }

        if (killedMonster) {
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted && !game.isGameOver && !isPaused) {
              _playSfx('audio/levelup.mp3');
            }
          });
        }
      }

      setState(() {
        totalLinesCleared += lines;
        currentScore += basePoints * levelMultiplier;
      });

      checkAndUpdateHighScore();
    };

    loadHighScore();
    _startBgm();
    startGameLoop();
    startMonsterAttackTimer();
  }

  void startMonsterAttackTimer() {
    if (widget.gameMode == GameMode.classic) return;

    monsterAttackTimer?.cancel();
    monsterAttackTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || game.isGameOver || isPaused || isHorde) return;

      setState(() {
        batAttackTriggerCount++;
        playerHp -= 5;
        if (playerHp <= 0) {
          playerHp = 0;
          game.isGameOver = true;
          _handleGameOver();
        }
      });
    });
  }

  void onBatHitPlayer(int damage) {
    if (!mounted || game.isGameOver || isPaused || widget.gameMode == GameMode.classic) return;

    setState(() {
      _playSfx('audio/drop.mp3');
      playerHp -= damage;
      if (playerHp <= 0) {
        playerHp = 0;
        game.isGameOver = true;
        _handleGameOver();
      }
    });
  }

  void updateSpeedByLevel() {
    int tetrisLevel = (totalLinesCleared ~/ 10) + 1;
    int baseInterval = 1000;
    int minInterval = 100;
    int newInterval = (baseInterval - ((tetrisLevel - 1) * 50)).clamp(minInterval, baseInterval);

    if (newInterval != dropInterval) {
      dropInterval = newInterval;
      startGameLoop();
    }
  }

  void _handleGameOver() async {
    if (_hasTriggeredGameOver) return;
    _hasTriggeredGameOver = true;

    _stopLeftMove();
    _stopRightMove();
    await checkAndUpdateHighScore();

    setState(() {
      finalScore = currentScore;
    });

    // 👑 Envia o resultado para o Firebase, separando por modo de jogo
    final nomeJogador = await PlayerProfile.getPlayerName();
    if (widget.gameMode == GameMode.medieval && widget.subMode == MedievalSubMode.campaign) {
      // Campanha: não usa pontuação, o recorde é o nível do herói alcançado
      salvarNivelHeroiNoFirebase(nomeJogador, playerLevel);
    } else {
      // Clássico (e Horda): mantém o ranking por pontuação
      salvarPontuacaoNoFirebase(nomeJogador, currentScore, totalLinesCleared, playerLevel);
    }

    _stopBgm();
    gameTimer?.cancel();
    monsterAttackTimer?.cancel();

    _shakeController.forward(from: 0.0);
    _playSfx('audio/gameover.mp3');
  }

  void togglePause() {
    if (game.isGameOver) return;

    setState(() {
      isPaused = !isPaused;
    });

    if (isPaused) {
      _stopLeftMove();
      _stopRightMove();
      gameTimer?.cancel();
      monsterAttackTimer?.cancel();
      _bgmPlayer.pause();
    } else {
      _bgmPlayer.setVolume(GameSettings.bgmVolume);
      _bgmPlayer.resume();
      startGameLoop();
      startMonsterAttackTimer();
    }
  }

  void _openSettingsModal() {
    if (!isPaused && !game.isGameOver) {
      togglePause();
    }
    showDialog(
      context: context,
      builder: (context) => const SettingsDialog(),
    ).then((_) {
      _bgmPlayer.setVolume(GameSettings.bgmVolume);
    });
  }

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

  void _startBgm() async {
    try {
      await _bgmPlayer.stop();
      await _bgmPlayer.setVolume(GameSettings.bgmVolume);
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.play(AssetSource('audio/tetris.mp3'));
    } catch (e) {
      debugPrint("Erro BGM: $e");
    }
  }

  void _stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (e) {
      debugPrint("Erro BGM: $e");
    }
  }

  void _playSfx(String assetPath) async {
    try {
      final sfxPlayer = AudioPlayer();
      await sfxPlayer.setVolume(GameSettings.sfxVolume);
      await sfxPlayer.play(AssetSource(assetPath));

      sfxPlayer.onPlayerComplete.listen((_) {
        sfxPlayer.dispose();
      });
    } catch (e) {
      debugPrint("Erro SFX: $e");
    }
  }

  Future<void> loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      globalHighScore = prefs.getInt('highScore') ?? 0;
    });
  }

  Future<void> checkAndUpdateHighScore() async {
    if (currentScore > sessionHighScore) {
      setState(() {
        sessionHighScore = currentScore;
      });
    }

    if (currentScore > globalHighScore) {
      setState(() {
        globalHighScore = currentScore;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('highScore', globalHighScore);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _stopLeftMove();
    _stopRightMove();
    _stopBgm();
    gameTimer?.cancel();
    monsterAttackTimer?.cancel();
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
          _handleGameOver();
        }
      },
    );
  }

  void restartGame() {
    _stopLeftMove();
    _stopRightMove();
    _isLeftPressed = false;
    _isRightPressed = false;
    _hasTriggeredGameOver = false;
    setState(() {
      isPaused = false;
      game.reset();
      currentScore = 0;
      totalLinesCleared = 0;
      finalScore = 0;
      dropInterval = 1000;
      batAttackTriggerCount = 0;
      monsterDeathTriggerCount = 0;
      isHorde = widget.subMode == MedievalSubMode.horde;

      playerLevel = 1;
      playerHp = 100;
      playerMaxHp = 100;
      playerDamage = 10;
      monsterMaxHp = isHorde ? 50 : 20;
      monsterHp = monsterMaxHp;
    });
    _startBgm();
    startGameLoop();
    startMonsterAttackTimer();
  }

  void goToHomeScreen() {
    _stopLeftMove();
    _stopRightMove();
    _stopBgm();
    monsterAttackTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void onKeyDown(LogicalKeyboardKey key) {
    if (key == GameSettings.keyPause) {
      togglePause();
      return;
    }

    if (key == LogicalKeyboardKey.backspace) {
      restartGame();
      return;
    }

    if (game.isGameOver && key == LogicalKeyboardKey.enter) {
      restartGame();
      return;
    }

    if (game.isGameOver || isPaused) return;

    if (key == GameSettings.keyLeft) {
      if (!_isLeftPressed) {
        _isLeftPressed = true;
        _startLeftMove();
      }
    } else if (key == GameSettings.keyRight) {
      if (!_isRightPressed) {
        _isRightPressed = true;
        _startRightMove();
      }
    } else if (key == GameSettings.keyRotate) {
      setState(() {
        game.rotatePiece(clockwise: rotateClockwise);
      });
    } else if (key == GameSettings.keySoftDrop) {
      if (!softDrop) {
        softDrop = true;
        startGameLoop();
      }
    } else if (key == GameSettings.keyHardDrop) {
      _playSfx('audio/hard_drop.mp3');
      setState(() {
        game.hardDrop();
      });
      checkAndUpdateHighScore();
      if (game.isGameOver) {
        _handleGameOver();
      }
    } else if (key == GameSettings.keyHold) {
      if (game.canHold) {
        _playSfx('audio/hold.mp3');
      }
      setState(() {
        game.holdCurrentPiece();
      });
    }
  }

  void onKeyUp(LogicalKeyboardKey key) {
    if (key == GameSettings.keyLeft) {
      _isLeftPressed = false;
      _stopLeftMove();
    } else if (key == GameSettings.keyRight) {
      _isRightPressed = false;
      _stopRightMove();
    } else if (key == GameSettings.keySoftDrop) {
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
    int displayScore = game.isGameOver ? finalScore : currentScore;
    String modeName = widget.gameMode == GameMode.medieval ? "Tetris Medieval" : "Tetris Clássico";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0B08),
      appBar: AppBar(
        backgroundColor: MedievalColors.woodDark,
        elevation: 4,
        centerTitle: true,
        title: Text(
          "$modeName | Pontuação: $displayScore | Recorde: $globalHighScore",
          style: const TextStyle(fontSize: 16, color: MedievalColors.gold, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: MedievalPlainsPainter(),
            ),
          ),

          KeyboardListener(
            autofocus: true,
            focusNode: focusNode,
            onKeyEvent: handleKeyboard,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.gameMode == GameMode.medieval) ...[
                          PixelArtScreen(
                            level: playerLevel,
                            score: displayScore,
                            lines: totalLinesCleared,
                            playerHp: playerHp,
                            playerMaxHp: playerMaxHp,
                            playerDamage: playerDamage,
                            monsterHp: monsterHp,
                            monsterMaxHp: monsterMaxHp,
                            isPaused: isPaused,
                            isGameOver: game.isGameOver,
                            isHorde: isHorde,
                            batAttackTrigger: batAttackTriggerCount,
                            monsterDeathTrigger: monsterDeathTriggerCount,
                            onBatHitPlayer: onBatHitPlayer,
                          ),
                          const SizedBox(width: 20),
                        ],

                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (context, child) {
                            double delta = sin(_shakeController.value * pi * 10) * 12 * (1 - _shakeController.value);
                            return Transform.translate(
                              offset: Offset(delta, 0),
                              child: child,
                            );
                          },
                          child: Stack(
                            children: [
                              Container(
                                width: 300,
                                height: 600,
                                decoration: BoxDecoration(
                                  color: MedievalColors.woodDark.withOpacity(0.9),
                                  border: Border.all(color: MedievalColors.gold, width: 3),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black87, blurRadius: 10),
                                  ],
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
                                          color: value != 0 ? Colors.black26 : Colors.black12,
                                        ),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              if (isPaused)
                                Container(
                                  width: 300,
                                  height: 600,
                                  color: Colors.black87,
                                  child: const Center(
                                    child: Text(
                                      "PAUSADO",
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: MedievalColors.gold,
                                        letterSpacing: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              if (game.isGameOver)
                                Container(
                                  width: 300,
                                  height: 600,
                                  color: Colors.black87,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        "DERROTA",
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(height: 15),
                                      Text(
                                        "Pontuação Final: $finalScore",
                                        style: const TextStyle(fontSize: 18, color: Colors.white),
                                      ),
                                      const SizedBox(height: 25),
                                      MedievalButton(
                                        width: 220,
                                        label: "REINICIAR",
                                        icon: Icons.refresh,
                                        primaryColor: MedievalColors.gold,
                                        onPressed: restartGame,
                                      ),
                                      const SizedBox(height: 10),
                                      MedievalButton(
                                        width: 220,
                                        label: "MENU",
                                        icon: Icons.home,
                                        primaryColor: Colors.grey,
                                        onPressed: goToHomeScreen,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),

                        SizedBox(
                          width: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPreviewBox("GUARDADA", game.holdPiece?.shape, game.holdPiece?.colorIndex),
                              const SizedBox(height: 12),
                              _buildPreviewBox("PRÓXIMA", game.nextPiece?.shape, game.nextPiece?.colorIndex),
                              const SizedBox(height: 15),

                              if (widget.gameMode == GameMode.medieval) ...[
                                _buildStatBox("HERÓI HP", "$playerHp/$playerMaxHp"),
                                const SizedBox(height: 6),
                                _buildStatBox("NÍVEL HERÓI", "$playerLevel"),
                                const SizedBox(height: 6),
                                _buildStatBox("DANO/LINHA", "$playerDamage"),
                                const SizedBox(height: 6),
                              ] else ...[
                                _buildStatBox("NÍVEL", "${(totalLinesCleared ~/ 10) + 1}"),
                                const SizedBox(height: 6),
                              ],

                              _buildStatBox("LINHAS", "$totalLinesCleared"),
                              const SizedBox(height: 15),

                              MedievalButton(
                                width: double.infinity,
                                label: isPaused ? "CONTINUAR" : "PAUSAR",
                                icon: isPaused ? Icons.play_arrow : Icons.pause,
                                primaryColor: isPaused ? Colors.green : Colors.orangeAccent,
                                onPressed: togglePause,
                              ),
                              MedievalButton(
                                width: double.infinity,
                                label: "CONFIGS",
                                icon: Icons.settings,
                                primaryColor: Colors.grey,
                                onPressed: _openSettingsModal,
                              ),
                              MedievalButton(
                                width: double.infinity,
                                label: "REINICIAR",
                                icon: Icons.refresh,
                                primaryColor: MedievalColors.gold,
                                onPressed: restartGame,
                              ),
                              MedievalButton(
                                width: double.infinity,
                                label: "MENU",
                                icon: Icons.home,
                                primaryColor: Colors.grey,
                                onPressed: goToHomeScreen,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: MedievalColors.woodDark,
        border: Border.all(color: MedievalColors.borderGold.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: MedievalColors.gold)),
        ],
      ),
    );
  }

  Widget _buildPreviewBox(String title, List<List<int>>? shape, int? colorIndex) {
    return Container(
      width: 180,
      height: 105,
      decoration: BoxDecoration(
        color: MedievalColors.woodDark,
        border: Border.all(color: MedievalColors.borderGold),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            width: double.infinity,
            color: MedievalColors.woodMedium,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: MedievalColors.gold),
            ),
          ),
          Expanded(
            child: Center(
              child: shape == null || colorIndex == null
                  ? const Text("-", style: TextStyle(color: Colors.grey))
                  : CustomPaint(
                      size: Size(shape[0].length * 18.0, shape.length * 18.0),
                      painter: PiecePreviewPainter(
                        shape: shape,
                        color: blockColors[colorIndex] ?? Colors.cyan,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// PINTOR DE PRÉ-VISUALIZAÇÃO DE PEÇAS
// ==========================================
class PiecePreviewPainter extends CustomPainter {
  final List<List<int>> shape;
  final Color color;

  PiecePreviewPainter({required this.shape, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    double cellSize = 18.0;

    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          Rect rect = Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize);
          canvas.drawRect(rect, paint);
          canvas.drawRect(rect, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PiecePreviewPainter oldDelegate) => true;
}

// ==========================================
// DIÁLOGO DE CONFIGURAÇÕES MEDIEVAL
// ==========================================
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  double bgm = GameSettings.bgmVolume;
  double sfx = GameSettings.sfxVolume;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MedievalColors.woodDark,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: MedievalColors.gold, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      title: const Text(
        "CONFIGURAÇÕES",
        style: TextStyle(color: MedievalColors.gold, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Música de Fundo (BGM)", style: TextStyle(fontSize: 14, color: Colors.white70)),
            Slider(
              value: bgm,
              activeColor: MedievalColors.gold,
              onChanged: (val) {
                setState(() => bgm = val);
                GameSettings.bgmVolume = val;
                GameSettings.saveVolume('bgmVolume', val);
              },
            ),
            const SizedBox(height: 10),
            const Text("Efeitos Sonoros (SFX)", style: TextStyle(fontSize: 14, color: Colors.white70)),
            Slider(
              value: sfx,
              activeColor: MedievalColors.gold,
              onChanged: (val) {
                setState(() => sfx = val);
                GameSettings.sfxVolume = val;
                GameSettings.saveVolume('sfxVolume', val);
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () async {
                  await GameSettings.resetToDefaults();
                  setState(() {
                    bgm = GameSettings.bgmVolume;
                    sfx = GameSettings.sfxVolume;
                  });
                },
                child: const Text("Restaurar Padrões"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("FECHAR", style: TextStyle(color: MedievalColors.gold)),
        ),
      ],
    );
  }
}

// Função para enviar os dados para o Firebase
Future<void> salvarPontuacaoNoFirebase(String nomeJogador, int pontos, int linhas, int nivel) async {
  try {
    final playerId = await PlayerProfile.getPlayerId();
    final docRef = FirebaseFirestore.instance.collection('ranking').doc(playerId);

    // Só sobrescreve se a nova pontuação for maior que a já salva
    final snapshot = await docRef.get();
    final melhorAtual = snapshot.exists ? ((snapshot.data()?['pontuacao'] ?? 0) as int) : 0;

    if (pontos > melhorAtual) {
      await docRef.set({
        'jogador': nomeJogador,
        'pontuacao': pontos,
        'linhas_detonadas': linhas,
        'nivel_heroi': nivel,
        'data': FieldValue.serverTimestamp(), // Salva o dia e hora exatos
      });
      print("🏆 Novo recorde salvo no Firebase!");
    } else {
      print("ℹ️ Pontuação não superou o recorde salvo, ranking mantido.");
    }
  } catch (erro) {
    print("❌ Falha ao enviar para o reino do Firebase: $erro");
  }
}

// Ranking exclusivo do modo Campanha: o que importa é o nível do herói, não pontos
Future<void> salvarNivelHeroiNoFirebase(String nomeJogador, int nivel) async {
  try {
    final playerId = await PlayerProfile.getPlayerId();
    final docRef = FirebaseFirestore.instance.collection('ranking_campanha').doc(playerId);

    // Só sobrescreve se o novo nível for maior que o já salvo
    final snapshot = await docRef.get();
    final melhorAtual = snapshot.exists ? ((snapshot.data()?['nivel_heroi'] ?? 0) as int) : 0;

    if (nivel > melhorAtual) {
      await docRef.set({
        'jogador': nomeJogador,
        'nivel_heroi': nivel,
        'data': FieldValue.serverTimestamp(),
      });
      print("👑 Novo recorde de nível salvo no Firebase!");
    } else {
      print("ℹ️ Nível não superou o recorde salvo, ranking mantido.");
    }
  } catch (erro) {
    print("❌ Falha ao enviar para o reino do Firebase: $erro");
  }
}