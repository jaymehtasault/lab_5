import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ------------------------------------------------------------
/// DATA SOURCES
/// ------------------------------------------------------------
const String kDataUrl =
    'https://nawazchowdhury.github.io/pokemontcg/api.json';
const String kPtcgApiTwoRandom =
    'https://api.pokemontcg.io/v2/cards?pageSize=2&random=true';

const String? kPtcgApiKey = null; // optional API key

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pokémon TCG Battle',
        home: BattlePage(),
      );
}

/// ------------------------------------------------------------
/// MODEL
/// ------------------------------------------------------------
class PokemonBattleCard {
  final String name;
  final String? smallImage;
  final String? largeImage;
  final int hp;
  PokemonBattleCard({
    required this.name,
    required this.smallImage,
    required this.largeImage,
    required this.hp,
  });

  factory PokemonBattleCard.fromJson(Map<String, dynamic> json) {
    final img = json['images'] ?? {};
    final hpString = (json['hp'] ?? '0').toString();
    final hp = int.tryParse(hpString.replaceAll(RegExp('[^0-9]'), '')) ?? 0;
    return PokemonBattleCard(
      name: json['name'] ?? 'Unknown',
      smallImage: img['small'],
      largeImage: img['large'],
      hp: hp,
    );
  }
}

/// ------------------------------------------------------------
/// SERVICE
/// ------------------------------------------------------------
class PokemonApiService {
  static const _maxAttempts = 3;
  static Duration _backoff(int a) => Duration(milliseconds: 600 * (1 << a));

  static int _hpFromId(String id) {
    final sum = id.codeUnits.fold<int>(0, (a, b) => a + b);
    return 40 + (sum % 151);
  }

  static Future<({List<PokemonBattleCard> cards, bool fromFallback})>
      fetchTwoRandom() async {
    final headers = <String, String>{};
    if (kPtcgApiKey != null && kPtcgApiKey!.isNotEmpty) {
      headers['X-Api-Key'] = kPtcgApiKey!;
    }

    // ---- try official API ----
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final uri = Uri.parse(kPtcgApiTwoRandom);
        final resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final body = json.decode(resp.body) as Map<String, dynamic>;
          final data = (body['data'] as List).cast<Map<String, dynamic>>();
          if (data.length >= 2) {
            final cards = data.map((e) => PokemonBattleCard.fromJson(e)).toList();
            return (cards: cards, fromFallback: false);
          }
        }
      } catch (_) {
        if (attempt < _maxAttempts - 1) {
          await Future.delayed(_backoff(attempt));
          continue;
        }
      }
    }

    // ---- fallback: local JSON ----
    final local = await _fetchLocal();
    local.shuffle();
    final picked = local.take(2).toList();
    final fallbackCards = picked.map((c) {
      final hp = _hpFromId(c.name);
      return PokemonBattleCard(
        name: c.name,
        smallImage: c.smallImage,
        largeImage: c.largeImage,
        hp: hp,
      );
    }).toList();
    return (cards: fallbackCards, fromFallback: true);
  }

  static Future<List<PokemonBattleCard>> _fetchLocal() async {
    final uri = Uri.parse(kDataUrl);
    final resp = await http.get(uri);
    final parsed = json.decode(resp.body);
    final list = parsed is List ? parsed : parsed['data'];
    return (list as List)
        .map((e) => PokemonBattleCard.fromJson(e))
        .toList();
  }
}

/// ------------------------------------------------------------
/// BATTLE PAGE
/// ------------------------------------------------------------
class BattlePage extends StatefulWidget {
  const BattlePage({super.key});
  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  PokemonBattleCard? _left;
  PokemonBattleCard? _right;
  bool _loading = true;
  String? _error;
  bool _usedFallback = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PokemonApiService.fetchTwoRandom();
      setState(() {
        _left = result.cards[0];
        _right = result.cards[1];
        _usedFallback = result.fromFallback;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _winnerText() {
    if (_left == null || _right == null) return '';
    if (_left!.hp == _right!.hp) return 'It\'s a draw!';
    return _left!.hp > _right!.hp
        ? '${_left!.name} wins!'
        : '${_right!.name} wins!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pokémon TCG Battle'),
        backgroundColor: Colors.redAccent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 60),
                        const SizedBox(height: 10),
                        const Text('Something went wrong'),
                        Text(_error!,
                            style:
                                const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 20),
                        ElevatedButton(
                            onPressed: _loadCards, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              : _buildBattle(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadCards,
        label: const Text('Draw Again'),
        icon: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildBattle() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _pokeCard(_left),
                const Text('VS',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                _pokeCard(_right),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _winnerText(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (_usedFallback) ...[
              const SizedBox(height: 10),
              const Chip(label: Text('Offline fallback (API down)')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pokeCard(PokemonBattleCard? c) {
    if (c == null) return const SizedBox.shrink();
    return Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Image.network(
              c.smallImage ?? '',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported, size: 80),
            ),
          ),
          const SizedBox(height: 8),
          Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('HP: ${c.hp}'),
        ],
      ),
    );
  }
}
