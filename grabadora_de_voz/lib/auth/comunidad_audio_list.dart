import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../platform/comunidad_archivos_io.dart'
    if (dart.library.js_interop) '../platform/comunidad_archivos_web.dart' as archivos;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../theme/theme.dart';

const _azul = Color(0xFF215CF5);
const _gris = Color(0xFF9C9C9C);
const _fondo = Color(0xFFF0F0F0);
final _grabaciones = FirebaseFirestore.instance.collection('grabaciones');

String _mmss(int segundos) =>
    '${(segundos ~/ 60).toString().padLeft(2, '0')}:${(segundos % 60).toString().padLeft(2, '0')}';
String _fecha(dynamic valor) {
  if (valor is! Timestamp) return 'Recientemente';
  final fecha = valor.toDate().toLocal();
  final hoy = DateTime.now();
  final prefijo = fecha.year == hoy.year && fecha.month == hoy.month && fecha.day == hoy.day
      ? 'Hoy' : '${fecha.day}/${fecha.month}/${fecha.year}';
  final h = fecha.hour % 12 == 0 ? 12 : fecha.hour % 12;
  return '$prefijo, $h:${fecha.minute.toString().padLeft(2, '0')} ${fecha.hour >= 12 ? 'p.m.' : 'a.m.'}';
}

class ComunidadAudioList extends StatefulWidget {
  const ComunidadAudioList({super.key});
  @override
  State<ComunidadAudioList> createState() => _ComunidadAudioListState();
}

class _ComunidadAudioListState extends State<ComunidadAudioList> {
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _subs;
  String? _actual;
  String _busqueda = '';
  String _grupo = 'Todas';
  bool _cargando = false;
  @override
  void initState() {
    super.initState();
    _subs = _player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() {
    _subs?.cancel();
    _player.dispose();
    super.dispose();
  }
  void _mensaje(String texto) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _reproducir(Map<String, dynamic> datos) async {
    if (_cargando) return;
    final ruta = (datos['archivo'] as String?) ?? '';
    final url = (datos['url'] as String?) ?? '';
    final id = ruta.isNotEmpty ? ruta : url;
    if (id.isEmpty) { _mensaje('Esta publicación no contiene un audio.'); return; }
    try {
      if (_actual == id && _player.playing) { await _player.pause(); return; }
      if (_actual == id && _player.audioSource != null &&
          _player.processingState != ProcessingState.completed) {
        unawaited(_player.play()); return;
      }
      setState(() => _cargando = true);
      await _player.stop();
      final ref = ruta.isNotEmpty
          ? FirebaseStorage.instance.ref(ruta)
          : FirebaseStorage.instance.refFromURL(url);
      await _player.setVolume(1.0);
      await archivos.prepararAudioRemoto(_player, ref, id);
      if (!mounted) return;
      setState(() {
        _actual = id;
      });
      unawaited(_player.play().catchError((Object e) { _mensaje('Error al reproducir: $e'); }));
    } catch (e) {
      _mensaje('No se pudo reproducir: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _compartir(Map<String, dynamic> datos) async {
     final ruta = (datos['archivo'] as String?) ?? '';
     final url = (datos['url'] as String?) ?? '';
     if (ruta.isEmpty && url.isEmpty) {
       _mensaje('No existe un audio para compartir.');
       return;
     }
     try {
      final ref = ruta.isNotEmpty
           ? FirebaseStorage.instance.ref(ruta)
           : FirebaseStorage.instance.refFromURL(url);
       await archivos.compartirAudio(ref, '${datos['titulo'] ?? 'Audio'}');
     } catch (e) {
       _mensaje('No se pudo compartir: $e');
     }
   }

  Future<void> _quitarDeComunidad(String id) async {
    try {
      await _grabaciones.doc(id).update({'enComunidad': false});
      _mensaje('Publicación retirada de Comunidad');
    } catch (e) { _mensaje('No se pudo retirar: $e'); }
  }

  Future<void> _like(String id, Map<String, dynamic> datos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _mensaje('Inicia sesión para dar me gusta.'); return; }
    final likes = List<String>.from(datos['likesUsuarios'] is List ? datos['likesUsuarios'] : []);
    try {
      await _grabaciones.doc(id).update({
        'likesUsuarios': likes.contains(uid) ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      });
    } catch (e) { _mensaje('No se pudo guardar el Me gusta: $e'); }
  }

  // Misma tipografía, altura y línea de selección que Mis Grabaciones.
  Widget _filtro(String texto) {
    final seleccionado = _grupo == texto;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _grupo = texto),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.h6.copyWith(
                color: AppColors.gs900,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppGap.gaptight),
            Container(
              height: AppSpacing.spacingy200,
              decoration: BoxDecoration(
                color: seleccionado
                    ? AppColors.primary500
                    : AppColors.gs400,
                borderRadius: BorderRadius.circular(AppRadius.radiusfull),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(
            left: AppMargin.marginlg,
            right: AppMargin.marginlg,
            top: AppSpacing.spacing100,
            bottom: 150,
          ),
          children: [
            Text(
              'Comunidades',
              style: AppTypography.h5.copyWith(
                fontSize: 30,
                color: AppColors.gs900,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppGap.gapgroup),
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.gs300,
                borderRadius: BorderRadius.circular(AppRadius.radiuss),
              ),
              child: TextField(
                style: AppTypography.b2.copyWith(color: AppColors.gs900),
                onChanged: (texto) => setState(
                  () => _busqueda = texto.trim().toLowerCase(),
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar publicaciones...',
                  hintStyle: AppTypography.b2.copyWith(
                    color: AppColors.gs600,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.gs900,
                    size: 28,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppPadding.paddingmd,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppGap.gapsection),
            Row(
              children: [
                _filtro('Todas'),
                const SizedBox(width: AppGap.gapgroup / 2),
                _filtro('Estudio'),
                const SizedBox(width: AppGap.gapgroup / 2),
                _filtro('Trabajo'),
                const SizedBox(width: AppGap.gapgroup / 2),
                _filtro('Ideas'),
              ],
            ),
            const SizedBox(height: AppGap.gapsection),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _grabaciones.where('enComunidad', isEqualTo: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('No se pudieron cargar las publicaciones: ${snapshot.error}');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs.where((d) {
              final datos = d.data();
              final grupo = (datos['grupo'] as String?) ?? 'Estudio';
              final titulo = '${datos['titulo'] ?? ''}'.toLowerCase();
              return (_grupo == 'Todas' || grupo == _grupo) && titulo.contains(_busqueda);
            }).toList();
            docs.sort((a, b) {
              final x = a.data()['creadoEn']; final y = b.data()['creadoEn'];
              if (x is Timestamp && y is Timestamp) return y.compareTo(x);
              return 0;
            });
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: Text('No hay publicaciones en este grupo.')),
              );
            }
            return Column(children: docs.map((doc) => _tarjeta(doc)).toList());
          },
        ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: SizedBox(
          width: 86,
          height: 86,
          child: FloatingActionButton(
            heroTag: 'nueva_publicacion_comunidad',
            elevation: 0,
            backgroundColor: AppColors.primary500,
            foregroundColor: AppColors.gs50,
            shape: const CircleBorder(),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NuevaPublicacionScreen(),
                ),
              );
            },
            child: const Icon(Icons.add, size: 40),
          ),
        ),
      ),
    ]);
  }

  Widget _tarjeta(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final datos = doc.data();
    final titulo = (datos['titulo'] as String?) ?? 'Audio sin título';
    final segundos = (datos['duracionSegundos'] as num?)?.toInt() ?? 0;
    final idAudio = (datos['archivo'] as String?)?.isNotEmpty == true
        ? datos['archivo'] : datos['url'];
    final tocando = _actual == idAudio && _player.playing;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final propio = uid != null && datos['usuarioId'] == uid;
    final likes = List<String>.from(datos['likesUsuarios'] is List ? datos['likesUsuarios'] : []);
    final comentarios = (datos['comentarios'] is List) ? datos['comentarios'] as List : [];
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 9),
      decoration: BoxDecoration(color: AppColors.gs50, borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 9, offset: Offset(0, 5))]),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 26, backgroundColor: AppColors.primary500,
            child: IconButton(onPressed: _cargando ? null : () => _reproducir(datos),
              icon: Icon(tocando ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 30))),
          const SizedBox(width: 12),
          Expanded(child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => DetalleAudioScreen(id: doc.id))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTypography.s1.copyWith(color: AppColors.gs900, fontWeight: FontWeight.w500)),
              Text('${datos['autorNombre'] ?? 'Usuario'} | ${_fecha(datos['creadoEn'])}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
            ]),
          )),
          PopupMenuButton<String>(
            tooltip: 'Opciones de publicación',
            icon: const Icon(Icons.more_vert, color: _gris),
            color: AppColors.gs50,
            surfaceTintColor: Colors.transparent,
            elevation: 10,
            offset: const Offset(0, 8),
            constraints: const BoxConstraints(minWidth: 245, maxWidth: 290),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            onSelected: (accion) {
              if (accion == 'detalle') {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DetalleAudioScreen(id: doc.id),
                ));
              } else if (accion == 'compartir') {
                _compartir(datos);
              } else if (accion == 'retirar') {
                _quitarDeComunidad(doc.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'detalle',
                height: 58,
                child: Row(children: [
                  Icon(Icons.article_outlined, color: Color(0xFF252525), size: 25),
                  SizedBox(width: 15),
                  Text('Ver detalle', style: TextStyle(fontSize: 16, color: Color(0xFF252525))),
                ]),
              ),
              const PopupMenuItem<String>(
                value: 'compartir',
                height: 58,
                child: Row(children: [
                  Icon(Icons.ios_share, color: Color(0xFF252525), size: 25),
                  SizedBox(width: 15),
                  Text('Compartir', style: TextStyle(fontSize: 16, color: Color(0xFF252525))),
                ]),
              ),
              if (propio)
                const PopupMenuItem<String>(
                  value: 'retirar',
                  height: 58,
                  child: Row(children: [
                    Icon(Icons.remove_circle_outline, color: Color(0xFFFF3030), size: 25),
                    SizedBox(width: 15),
                    Expanded(child: Text('Retirar de Comunidad',
                      style: TextStyle(fontSize: 16, color: Color(0xFFFF3030)))),
                  ]),
                ),
            ],
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetalleAudioScreen(id: doc.id))),
            child: Row(children: [const Icon(Icons.chat_bubble_outline, size: 21),
              const SizedBox(width: 4), Text('${comentarios.length}')])),
          const SizedBox(width: 20),
          InkWell(onTap: () => _like(doc.id, datos), child: Row(children: [
            Icon(likes.contains(uid) ? Icons.favorite : Icons.favorite_border,
              color: likes.contains(uid) ? _azul : Colors.black, size: 22),
            const SizedBox(width: 4), Text('${likes.length}'),
          ])),
          const Spacer(),
          Text(_mmss(segundos), style: const TextStyle(color: _gris)),
          const SizedBox(width: 8),
        ]),
      ]),
    );
  }
}

class NuevaPublicacionScreen extends StatefulWidget {
  const NuevaPublicacionScreen({super.key});
  @override
  State<NuevaPublicacionScreen> createState() => _NuevaPublicacionScreenState();
}
class _NuevaPublicacionScreenState extends State<NuevaPublicacionScreen> {
  final AudioRecorder _grabadorNuevo = AudioRecorder();
  String? _grabacionNueva;
  bool _grabandoNueva = false;
  bool _procesandoGrabacion = false;
  Duration _duracionNueva = Duration.zero;
  Timer? _contadorNuevo;
  Timer? _amplitudTimer;
  bool _leyendoAmplitud = false;
  double _maxNivelMicrofono = -160;
  int _lecturasMicrofono = 0;
  final _titulo = TextEditingController();
  final _descripcion = TextEditingController();
  String _grupo = 'Estudio';
  String? _audioId;
  bool _publicando = false;
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _previewId;
  bool _cargandoPreview = false;
  final List<double> _ondasEnVivo = List<double>.filled(38, 0.02, growable: true);
  @override
  void dispose() {
    _contadorNuevo?.cancel();
    _amplitudTimer?.cancel();
    _grabadorNuevo.dispose();
    _previewPlayer.dispose();
    _titulo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  // El audio se conserva local hasta presionar Publicar.
  // Así el usuario puede escucharlo antes de subirlo a Firebase.
  Future<void> _iniciarGrabacionNueva() async {
    if (_procesandoGrabacion || _grabandoNueva) return;
    setState(() => _procesandoGrabacion = true);
    try {
      if (!await _grabadorNuevo.hasPermission()) {
        throw Exception('Permite el acceso al micrófono en el dispositivo o navegador.');
      }
      await _previewPlayer.stop();
      final ruta = await archivos.nuevaRutaAudio();
      await _grabadorNuevo.start(
        kIsWeb
             ? const RecordConfig(encoder: AudioEncoder.opus, numChannels: 1)
             : const RecordConfig(
                 encoder: AudioEncoder.aacLc,
                 sampleRate: 44100,
                 numChannels: 1,
               ),
        path: ruta,
      );
      _contadorNuevo?.cancel();
      _amplitudTimer?.cancel();
      setState(() {
        _grabacionNueva = ruta;
        _audioId = null;
        _duracionNueva = Duration.zero;
        _maxNivelMicrofono = -160;
        _lecturasMicrofono = 0;
        _grabandoNueva = true;
        for (var i = 0; i < _ondasEnVivo.length; i++) { _ondasEnVivo[i] = 0.02; }
      });
      _contadorNuevo = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _grabandoNueva) {
          setState(() => _duracionNueva += const Duration(seconds: 1));
        }
      });
      _amplitudTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (!_grabandoNueva || _leyendoAmplitud) return;
        _leyendoAmplitud = true;
        try {
          final amp = await _grabadorNuevo.getAmplitude();
          final db = amp.current;
          if (db > _maxNivelMicrofono) {
            _maxNivelMicrofono = db;
          }
          _lecturasMicrofono++;
          if (mounted && _grabandoNueva) {
            final nivel = ((db + 70) / 58).clamp(0.0, 1.0).toDouble();
            setState(() {
              _ondasEnVivo.removeAt(0);
              _ondasEnVivo.add(nivel);
            });
          }
        } catch (e) { debugPrint('Amplitud micrófono: $e'); }
        finally { _leyendoAmplitud = false; }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar la grabación: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoGrabacion = false);
    }
  }

  Future<void> _detenerGrabacionNueva() async {
    if (!_grabandoNueva || _procesandoGrabacion) return;
    setState(() => _procesandoGrabacion = true);
    _contadorNuevo?.cancel();
    _amplitudTimer?.cancel();
    try {
      final ruta = await _grabadorNuevo.stop();
      if (ruta == null || await archivos.tamanoAudio(ruta) == 0) {
         throw Exception('El micrófono no generó un archivo válido.');
       }
      if (mounted) {
        setState(() { _grabacionNueva = ruta; _grabandoNueva = false; });
        if (_lecturasMicrofono > 3 && _maxNivelMicrofono < -48) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 6),
            content: Text('El micrófono captó una señal muy baja. Escucha el audio antes de publicarlo; podría estar en silencio.'),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al detener la grabación: $e')),
        );
      }
    } finally { if (mounted) setState(() => _procesandoGrabacion = false); }
  }

  Future<void> _escucharNueva() async {
    if (_grabacionNueva == null || _grabandoNueva) return;
    try {
      if (_previewId == _grabacionNueva && _previewPlayer.playing) {
        await _previewPlayer.pause();
      } else if (_previewId == _grabacionNueva &&
          _previewPlayer.processingState != ProcessingState.completed) {
        unawaited(_previewPlayer.play());
      } else {
        await _previewPlayer.stop();
        await archivos.prepararAudioLocal(_previewPlayer, _grabacionNueva!);
        await _previewPlayer.setVolume(1.0);
        _previewId = _grabacionNueva;
        unawaited(_previewPlayer.play());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reproducir esta grabación: $e')),
        );
      }
    }
  }

  Future<void> _descartarNueva() async {
    _contadorNuevo?.cancel(); _amplitudTimer?.cancel();
    if (_grabandoNueva) await _grabadorNuevo.stop();
    await _previewPlayer.stop();
    final ruta = _grabacionNueva;
         if (ruta != null) {
       await archivos.borrarAudio(ruta);
     }
    if (mounted) {
      setState(() {
        _grabandoNueva = false; _grabacionNueva = null;
        _duracionNueva = Duration.zero; _previewId = null;
        for (var i = 0; i < _ondasEnVivo.length; i++) { _ondasEnVivo[i] = 0.02; }
      });
    }
  }

  Future<void> _escucharAdjunto(Map<String, dynamic> datos, String id) async {
    if (_cargandoPreview) return;
    try {
      if (_previewId == id && _previewPlayer.playing) {
        await _previewPlayer.pause();
        if (mounted) setState(() {});
        return;
      }
      if (_previewId == id && _previewPlayer.audioSource != null &&
          _previewPlayer.processingState != ProcessingState.completed) {
        unawaited(_previewPlayer.play());
        if (mounted) setState(() {});
        return;
      }
      setState(() => _cargandoPreview = true);
      await _previewPlayer.stop();
      final ruta = (datos['archivo'] as String?) ?? '';
      final url = (datos['url'] as String?) ?? '';
      if (ruta.isEmpty && url.isEmpty) throw Exception('Sin archivo de audio.');
      final referencia = ruta.isNotEmpty
          ? FirebaseStorage.instance.ref(ruta)
          : FirebaseStorage.instance.refFromURL(url);
      await archivos.prepararAudioRemoto(_previewPlayer, referencia, id);
      await _previewPlayer.setVolume(1);
      if (mounted) setState(() => _previewId = id);
      unawaited(_previewPlayer.play());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo escuchar el adjunto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargandoPreview = false);
    }
  }


  Future<void> _publicar() async {
    if ((_audioId == null && _grabacionNueva == null) || _titulo.text.trim().isEmpty || _grabandoNueva) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Termina de grabar o selecciona un audio, y escribe un título.')));
      return;
    }
    setState(() => _publicando = true);
    try {
      final usuario = FirebaseAuth.instance.currentUser;
      if (usuario == null) throw Exception('Necesitas iniciar sesión.');
      if (_grabacionNueva != null) {
        if (await archivos.tamanoAudio(_grabacionNueva!) == 0) {
           throw Exception('La grabación nueva está vacía.');
         }
        final referenciaDoc = _grabaciones.doc();
        final storageRef = FirebaseStorage.instance.ref('grabaciones/${referenciaDoc.id}.${archivos.extensionAudio}');
        // Se sube únicamente al confirmar Publicar.
        await archivos.subirAudio(storageRef, _grabacionNueva!);
        final url = await storageRef.getDownloadURL();
        await referenciaDoc.set({
          'titulo': _titulo.text.trim(),
          'descripcion': _descripcion.text.trim(),
          'grupo': _grupo,
          'autorNombre': usuario.displayName ?? 'Usuario',
          'usuarioId': usuario.uid,
          'creadoEn': FieldValue.serverTimestamp(),
          'duracionSegundos': _duracionNueva.inSeconds,
          'archivo': storageRef.fullPath,
          'url': url,
          'favorito': false,
          'enComunidad': true,
          'likesUsuarios': <String>[],
          'comentarios': <Map<String, dynamic>>[],
        });
      } else {
        final doc = await _grabaciones.doc(_audioId).get();
        if (!doc.exists || doc.data()?['usuarioId'] != usuario.uid) {
          throw Exception('Solo puedes publicar tus propias grabaciones.');
        }
        await _grabaciones.doc(_audioId).update({
          'titulo': _titulo.text.trim(),
          'descripcion': _descripcion.text.trim(),
          'grupo': _grupo,
          'autorNombre': usuario.displayName ?? 'Usuario',
          'enComunidad': true,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo publicar: $e')));
    } finally { if (mounted) setState(() => _publicando = false); }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new), onPressed: () => Navigator.pop(context))),
      body: ListView(padding: const EdgeInsets.fromLTRB(26, 12, 26, 30), children: [
        const Text('Nueva publicación', style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        const Text('Audio adjunto', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF5F6FB),
              borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Grabar un audio nuevo', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(width: 54, height: 54, child: FloatingActionButton(
                heroTag: 'microfono_comunidad_nuevo',
                backgroundColor: _azul, foregroundColor: Colors.white,
                shape: const CircleBorder(),
                onPressed: _procesandoGrabacion ? null :
                    (_grabandoNueva ? _detenerGrabacionNueva : _iniciarGrabacionNueva),
                child: Icon(_grabandoNueva ? Icons.stop : Icons.mic, size: 29),
              )),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_grabandoNueva ? 'Grabando… ${_mmss(_duracionNueva.inSeconds)}'
                    : _grabacionNueva != null ? 'Audio nuevo · ${_mmss(_duracionNueva.inSeconds)}'
                    : 'Toca el micrófono para comenzar'),
                const SizedBox(height: 8),
                if (_grabandoNueva)
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: _ondasEnVivo.map((nivel) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: 4 + 40 * nivel,
                            decoration: BoxDecoration(
                              color: _azul,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                  )
                else
                  const SizedBox(height: 6),
              ])),
              if (_grabacionNueva != null && !_grabandoNueva) ...[
                IconButton(tooltip: 'Escuchar', onPressed: _escucharNueva,
                  icon: Icon(_previewId == _grabacionNueva && _previewPlayer.playing
                    ? Icons.pause_circle : Icons.play_circle, size: 32, color: _azul)),
                IconButton(tooltip: 'Descartar y volver a grabar', onPressed: _descartarNueva,
                  icon: const Icon(Icons.delete_outline)),
              ],
            ]),
            if (_grabacionNueva != null && !_grabandoNueva) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Escucha el audio antes de publicar. Para volver a grabar, elimínalo y toca el micrófono.',
                style: TextStyle(fontSize: 12, color: _gris)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_grabacionNueva == null) ...[
          const Text('O elige una grabación guardada', style: TextStyle(fontSize: 13, color: _gris)),
          const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _grabaciones.where('usuarioId', isEqualTo: uid ?? '').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Error al cargar audios: ${snapshot.error}');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final docs = snapshot.data!.docs;
            // El menú utiliza exclusivamente los colores de theme.dart.
            // Se mantiene la selección de audio y la vista previa originales.
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary500,
                  onPrimary: AppColors.gs50,
                  surface: AppColors.gs50,
                  onSurface: AppColors.gs900,
                  primaryContainer: AppColors.primary50,
                  onPrimaryContainer: AppColors.primary800,
                ),
                canvasColor: AppColors.gs50,
                splashColor: AppColors.primary50,
                highlightColor: AppColors.primary50,
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: AppColors.primary500,
                  selectionColor: AppColors.primary100,
                  selectionHandleColor: AppColors.primary500,
                ),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: docs.any((d) => d.id == _audioId)
                    ? _audioId
                    : null,
                isExpanded: true,
                menuMaxHeight: 390,
                dropdownColor: AppColors.gs50,
                borderRadius: BorderRadius.circular(AppRadius.radiusm),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.gs700,
                ),
                style: AppTypography.b1.copyWith(color: AppColors.gs900),
                decoration: InputDecoration(
                  labelText: 'Seleccionar grabación',
                  labelStyle: AppTypography.b2.copyWith(
                    color: AppColors.gs700,
                  ),
                  floatingLabelStyle: AppTypography.b2.copyWith(
                    color: AppColors.primary500,
                  ),
                  filled: true,
                  fillColor: AppColors.gs300,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    borderSide: const BorderSide(
                      color: AppColors.primary500,
                      width: 1.5,
                    ),
                  ),
                ),
                items: docs.map((d) {
                  final datos = d.data();
                  final titulo = '${datos['titulo'] ?? 'Sin título'}';
                  final duracion =
                      (datos['duracionSegundos'] as num?)?.toInt() ?? 0;
                  return DropdownMenuItem<String>(
                    value: d.id,
                    child: Text(
                      '$titulo · ${_mmss(duracion)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.b1.copyWith(
                        color: AppColors.gs900,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  _previewPlayer.stop();
                  setState(() {
                    _audioId = id;
                    _previewId = null;
                  });
                },
              ),
            );
          },
        ),
        ],
        const SizedBox(height: 12),
        if (_audioId != null && _grabacionNueva == null)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _grabaciones.doc(_audioId).snapshots(),
            builder: (context, snapshot) {
              final d = snapshot.data?.data();
              if (d == null) return const SizedBox.shrink();
              final duracion = (d['duracionSegundos'] as num?)?.toInt() ?? 0;
              final activo = _previewId == _audioId && _previewPlayer.playing;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x22000000),
                    blurRadius: 8, offset: Offset(0, 4))]),
                child: Row(children: [
                  CircleAvatar(radius: 26, backgroundColor: _azul,
                    child: IconButton(
                      onPressed: _cargandoPreview ? null : () => _escucharAdjunto(d, _audioId!),
                      icon: Icon(activo ? Icons.pause : Icons.play_arrow,
                        color: Colors.white))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d['titulo'] ?? 'Audio adjunto'}', maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text('Duración: ${_mmss(duracion)}',
                          style: const TextStyle(color: _gris, fontSize: 12)),
                    ])),
                  const SizedBox(width: 10),
                  Text(_mmss(duracion), style: const TextStyle(color: _gris)),
                ]),
              );
            },
          ),
        const SizedBox(height: 34),
        const Text('Título', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 10),
        TextField(controller: _titulo, maxLength: 50,
          decoration: InputDecoration(hintText: 'Escribe un título', filled: true, fillColor: _fondo,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
        const SizedBox(height: 20),
        const Text('Descripción', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 10),
        TextField(controller: _descripcion, maxLines: 5,
          decoration: InputDecoration(hintText: 'Agrega una descripción', filled: true, fillColor: _fondo,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
        const SizedBox(height: 26),
        const Text('Grupo', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: ['Estudio', 'Trabajo', 'Ideas'].map((g) => ChoiceChip(
          label: Text(g), selected: _grupo == g,
          selectedColor: _azul, labelStyle: TextStyle(color: _grupo == g ? Colors.white : Colors.black),
          onSelected: (_) => setState(() => _grupo = g),
        )).toList()),
        const SizedBox(height: 52),
        SizedBox(height: 54, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _azul),
          onPressed: _publicando ? null : _publicar,
          child: Text(_publicando ? 'Publicando...' : 'Publicar', style: const TextStyle(fontSize: 19)),
        )),
      ]),
    );
  }
}

class DetalleAudioScreen extends StatefulWidget {
  final String id;
  const DetalleAudioScreen({super.key, required this.id});
  @override
  State<DetalleAudioScreen> createState() => _DetalleAudioScreenState();
}
class _DetalleAudioScreenState extends State<DetalleAudioScreen> {
  final _player = AudioPlayer();
  final _comentario = TextEditingController();
  @override
  void dispose() { _player.dispose(); _comentario.dispose(); super.dispose(); }

  Future<void> _play(Map<String, dynamic> datos) async {
    try {
      if (_player.playing) { await _player.pause(); setState(() {}); return; }
      if (_player.audioSource == null) {
        final ruta = (datos['archivo'] as String?) ?? '';
        final url = (datos['url'] as String?) ?? '';
       final ref = ruta.isNotEmpty
            ? FirebaseStorage.instance.ref(ruta) : FirebaseStorage.instance.refFromURL(url);
        await archivos.prepararAudioRemoto(_player, ref, widget.id);
      }
      unawaited(_player.play());
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo reproducir: $e')));
    }
  }

  Future<void> _enviarComentario() async {
    final texto = _comentario.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (texto.isEmpty || user == null) return;
    try {
      await _grabaciones.doc(widget.id).update({'comentarios': FieldValue.arrayUnion([
        {'usuarioId': user.uid, 'autor': user.displayName ?? 'Usuario',
          'texto': texto, 'fecha': Timestamp.now()},
      ])});
      _comentario.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo comentar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _grabaciones.doc(widget.id).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('No se pudo cargar el audio.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final datos = snapshot.data!.data();
          if (datos == null) return const Center(child: Text('La publicación ya no está disponible.'));
          final comentarios = datos['comentarios'] is List ? datos['comentarios'] as List : [];
          return ListView(padding: const EdgeInsets.fromLTRB(28, 20, 28, 40), children: [
            const Text('Detalle de audio', style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold)),
            const SizedBox(height: 35),
            Text('${datos['titulo'] ?? 'Sin título'}', style: const TextStyle(fontSize: 20)),
            Text('${datos['autorNombre'] ?? 'Usuario'} | ${_fecha(datos['creadoEn'])}',
              style: const TextStyle(color: _gris)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 5))]),
              child: Column(children: [
                StreamBuilder<Duration>(stream: _player.positionStream, builder: (context, posicion) {
                  final total = _player.duration?.inMilliseconds.toDouble() ??
                      (((datos['duracionSegundos'] as num?)?.toDouble() ?? 0) * 1000);
                  final valor = (posicion.data?.inMilliseconds.toDouble() ?? 0).clamp(0.0, total > 0 ? total : 1.0);
                  return Column(children: [
                    Slider(value: valor, max: total > 0 ? total : 1.0,
                      activeColor: _azul, onChanged: _player.audioSource == null
                          ? null : (v) => _player.seek(Duration(milliseconds: v.toInt()))),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_mmss((valor / 1000).floor()), style: const TextStyle(color: _gris)),
                      Text(_mmss((total / 1000).floor()), style: const TextStyle(color: _gris)),
                    ]),
                  ]);
                }),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: () {
                    final p = _player.position.inSeconds - 10;
                    _player.seek(Duration(seconds: p > 0 ? p : 0));
                  }, icon: const Icon(Icons.replay_10, color: _gris)),
                  const SizedBox(width: 12),
                  IconButton.filled(style: IconButton.styleFrom(backgroundColor: _azul,
                    minimumSize: const Size(55, 55)), onPressed: () => _play(datos),
                    icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow, size: 32)),
                  const SizedBox(width: 12),
                  IconButton(onPressed: () {
                    final total = _player.duration?.inSeconds ?? 0;
                    final p = _player.position.inSeconds + 10;
                    _player.seek(Duration(seconds: p < total ? p : total));
                  }, icon: const Icon(Icons.forward_10, color: _gris)),
                ]),
              ]),
            ),
            const SizedBox(height: 34),
            const Text('Descripción', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 9),
            Text('${datos['descripcion'] ?? 'Sin descripción.'}'),
            const SizedBox(height: 32),
            Text('Comentarios (${comentarios.length})', style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 15),
            for (final item in comentarios)
              if (item is Map) Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text('${item['autor'] ?? 'Usuario'}'),
                subtitle: Text('${item['texto'] ?? ''}'),
              )),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: TextField(controller: _comentario,
                decoration: const InputDecoration(hintText: 'Escribe un comentario...'))),
              IconButton(onPressed: _enviarComentario, icon: const Icon(Icons.send, color: _azul)),
            ]),
          ]);
        },
      ),
    );
  }
}
