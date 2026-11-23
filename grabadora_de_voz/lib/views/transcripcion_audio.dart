import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/theme.dart';

class TranscripcionAudioScreen extends StatefulWidget {
  const TranscripcionAudioScreen({
    super.key,
    required this.grabacionId,
    required this.titulo,
  });

  final String grabacionId;
  final String titulo;

  @override
  State<TranscripcionAudioScreen> createState() => _TranscripcionAudioScreenState();
}

class _TranscripcionAudioScreenState extends State<TranscripcionAudioScreen> {
  // Colores semánticos del sistema de diseño de la aplicación.
  static const azul = AppColors.primary500;
  static const colores = <Color>[
    AppColors.primary500,
    AppColors.secondary200,
    AppColors.primary800,
    AppColors.secondary700,
    AppColors.primary300,
    AppColors.gs800,
  ];
  static const fondosHablantes = <Color>[
    AppColors.primary50,
    AppColors.secondary50,
    AppColors.primary100,
    AppColors.secondary100,
    AppColors.primary50,
    AppColors.gsy200,
  ];

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlayerException>? _errorSub;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _clavesSegmentos = {};
  bool _seguirAudio = true;
  bool _reproduccionIniciada = false;
  int _ultimoSegmentoActivo = -1;
  Duration _posicion = Duration.zero;
  bool _cargandoAudio = false;
  bool _transcribiendo = false;
  bool _guardandoBandera = false;
  String? _error;
  String? _audioCargado;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('grabaciones').doc(widget.grabacionId);

  bool _iniciadoAutomaticamente = false;

  Future<void> _iniciarSiHaceFalta() async {
    if (_iniciadoAutomaticamente) return;
    _iniciadoAutomaticamente = true;
    try {
      final snap = await _doc.get();
      if (!mounted || !snap.exists) return;
      final datos = snap.data() ?? <String, dynamic>{};
      if (datos['usuarioId'] != FirebaseAuth.instance.currentUser?.uid) {
        if (mounted) setState(() => _error = 'Solo el propietario puede transcribir esta grabación.');
        return;
      }
      final segmentos = datos['segmentosTranscripcion'];
      if (segmentos is List && segmentos.isNotEmpty) return;
      await _transcribir();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo iniciar la transcripción: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Comienza automáticamente, sin solicitar otra pulsación después de Transcribir.
    Future<void>.microtask(_iniciarSiHaceFalta);
    _positionSub = _player.positionStream.listen((value) {
      if (mounted) setState(() => _posicion = value);
    });
    _stateSub = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _errorSub = _player.errorStream.listen((e) {
      if (mounted) _aviso('Error de reproducción: ${e.message}');
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _scrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  String _tiempo(double segundos) {
    final total = segundos.isFinite && segundos >= 0 ? segundos.floor() : 0;
    final horas = total ~/ 3600;
    final min = (total ~/ 60) % 60;
    final sec = total % 60;
    final mm = min.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return horas > 0 ? '$horas:$mm:$ss' : '$mm:$ss';
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // just_audio admite URL HTTPS en Android y Chrome. En Chrome no
  // utilizamos File ni rutas locales: el navegador reproduce la URL de
  // descarga de Firebase Storage. El servidor debe permitir CORS y el
  // navegador debe admitir el formato real del audio (M4A/WebM).
  Future<void> _cargarAudio(Map<String, dynamic> datos) async {
    if (_cargandoAudio) return;
    setState(() { _cargandoAudio = true; _error = null; });
    try {
      final path = (datos['archivo'] as String? ?? '').trim();
      final url = path.isNotEmpty
          ? await FirebaseStorage.instance.ref(path).getDownloadURL()
          : (datos['url'] as String? ?? '').trim();
      if (url.isEmpty) throw StateError('La grabación no tiene archivo de audio.');

      // setUrl es multiplataforma. Mantenerla evita volver a introducir
      // File / writeToFile, que no funcionan en Flutter Web.
      await _player.setUrl(url);
      if (!mounted) return;
      setState(() => _audioCargado = url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _audioCargado = null;
        _error = kIsWeb
            ? 'Chrome no pudo cargar el audio. Comprueba el formato del archivo, '
              'los permisos de Firebase Storage y CORS del bucket. Detalle: $e'
            : 'No se pudo abrir el audio: $e';
      });
    } finally {
      if (mounted) setState(() => _cargandoAudio = false);
    }
  }

  Future<void> _play(Map<String, dynamic> datos) async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_audioCargado == null) await _cargarAudio(datos);
    if (_audioCargado == null) return;
    if (mounted) setState(() => _reproduccionIniciada = true);
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    unawaited(_player.play().catchError((Object e) {
      if (mounted) _aviso('No se pudo reproducir: $e');
    }));
  }

  Future<void> _irA(double segundo, Map<String, dynamic> datos) async {
    if (_audioCargado == null) await _cargarAudio(datos);
    if (_audioCargado == null) return;
    if (mounted) setState(() => _reproduccionIniciada = true);
    await _player.seek(Duration(milliseconds: (segundo * 1000).round()));
  }

  // Lleva el fragmento activo a la vista sin cerrar las otras secciones.
  void _enfocarSegmento(int indice) {
    if (!_seguirAudio || !_reproduccionIniciada || !_player.playing) return;
    if (indice < 0 || indice == _ultimoSegmentoActivo) return;
    _ultimoSegmentoActivo = indice;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final contexto = _clavesSegmentos[indice]?.currentContext;
      if (contexto != null) {
        Scrollable.ensureVisible(
          contexto,
          alignment: 0.42,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // Cloud Functions Callable se utiliza igual desde Android y Chrome.
  // La función del servidor debe admitir el formato WebM si el audio vino de web.
  Future<void> _transcribir() async {
    if (_transcribiendo) return;
    setState(() { _transcribiendo = true; _error = null; });
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('transcribirGrabacion', options: HttpsCallableOptions(
            timeout: const Duration(seconds: 300),
          )).call(<String, dynamic>{'grabacionId': widget.grabacionId});
      _aviso('Transcripción lista.');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = 'No se pudo transcribir: ${e.message ?? e.code}');
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al transcribir: $e');
    } finally {
      if (mounted) setState(() => _transcribiendo = false);
    }
  }

  // Las correcciones son independientes de la transcripción original.
  // Clave: índice del segmento; valor: número de hablante (1, 2, 3...).
  int _numeroHablanteOriginal(String id, List<String> ids) {
    final index = ids.indexOf(id);
    return index >= 0 ? index + 1 : 1;
  }

  int _numeroHablante(
    Map<String, dynamic> segmento,
    int indice,
    List<String> ids,
    Map<String, dynamic> correcciones,
  ) {
    final original = _numeroHablanteOriginal('${segmento['hablante'] ?? 'desconocido'}', ids);
    final corregido = correcciones['$indice'];
    if (corregido is num && corregido >= 1 && corregido <= 6) {
      return corregido.toInt();
    }
    return original;
  }

  Future<void> _cambiarHablante(int indice, int numero) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _aviso('Inicia sesión para corregir los hablantes.'); return; }
    try {
      await _doc.update({
        'correccionesHablantes.$indice': numero,
      }).timeout(const Duration(seconds: 12));
    } on FirebaseException catch (e) {
      _aviso('No se pudo guardar el cambio (${e.code}). Revisa las reglas de Firestore.');
    } on TimeoutException {
      _aviso('Firebase no respondió. Comprueba si el cambio se guardó.');
    } catch (e) {
      _aviso('No se pudo corregir el hablante: $e');
    }
  }

  Future<void> _configurarHablantes(Map<String, dynamic> datos, int detectados) async {
    final actual = (datos['cantidadHablantes'] as num?)?.toInt() ?? (detectados < 2 ? 2 : detectados);
    var cantidad = actual.clamp(1, 6).toInt();
    final nombres = Map<String, dynamic>.from(
      datos['nombresHablantes'] is Map ? datos['nombresHablantes'] as Map : {},
    );
    final controladores = List.generate(6, (i) => TextEditingController(
      text: (nombres['${i + 1}'] as String? ?? '').trim(),
    ));
    try {
      final guardar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: Theme.of(dialogContext).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary500,
              onPrimary: AppColors.gs50,
              primaryContainer: AppColors.primary50,
              onPrimaryContainer: AppColors.primary800,
              secondary: AppColors.secondary200,
              onSecondary: AppColors.gs900,
              secondaryContainer: AppColors.secondary50,
              onSecondaryContainer: AppColors.secondary800,
              surface: AppColors.gs50,
              onSurface: AppColors.gs900,
              onSurfaceVariant: AppColors.gs800,
              outline: AppColors.gs500,
              error: AppFeedbackColors.error,
            ),
            textSelectionTheme: const TextSelectionThemeData(
              cursorColor: AppColors.primary500,
              selectionColor: AppColors.primary100,
              selectionHandleColor: AppColors.primary500,
            ),
          ),
          child: StatefulBuilder(
          builder: (dialogContext, cambiar) => AlertDialog(
            backgroundColor: AppColors.gs50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.radiusl)),
            title: Text('Configurar hablantes', style: AppTypography.h6.copyWith(
              color: AppColors.gs900, fontWeight: FontWeight.w700)),
            content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Personas que participaron', style: AppTypography.b2),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.gs300,
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: cantidad,
                      isExpanded: true,
                      dropdownColor: AppColors.gs50,
                      iconEnabledColor: AppColors.primary500,
                      borderRadius: BorderRadius.circular(AppRadius.radiusm),
                      style: AppTypography.b1.copyWith(color: AppColors.gs900),
                      items: List.generate(6, (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} personas',
                          style: AppTypography.b1.copyWith(color: AppColors.gs900)),
                      )),
                      onChanged: (v) {
                        if (v != null) cambiar(() => cantidad = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Nombres opcionales', style: AppTypography.b2),
                ...List.generate(cantidad, (i) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: controladores[i],
                    maxLength: 40,
                    cursorColor: AppColors.primary500,
                    style: AppTypography.b1.copyWith(color: AppColors.gs900),
                    decoration: InputDecoration(
                      labelText: 'Hablante ${i + 1}',
                      labelStyle: AppTypography.b2.copyWith(color: AppColors.gs700),
                      floatingLabelStyle: AppTypography.b2.copyWith(color: AppColors.primary500),
                      counterStyle: AppTypography.cptn.copyWith(color: AppColors.gs700),
                      filled: true,
                      fillColor: AppColors.gs300,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.radiusm),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.radiusm),
                        borderSide: const BorderSide(color: AppColors.primary500, width: 2),
                      ),
                    ),
                  ),
                )),
                const SizedBox(height: 8),
                Text('Indicar 3 personas no obliga a la IA a reconocerlas. Puedes corregir cada fragmento después.',
                  style: AppTypography.cptn.copyWith(color: AppColors.gs700)),
              ],
            ))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancelar', style: AppTypography.butt.copyWith(color: AppColors.gs800))),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary500,
                  foregroundColor: AppColors.gs50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusfull),
                  ),
                ),
                onPressed: () {
                  FocusScope.of(dialogContext).unfocus();
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
        ),
      );
      if (guardar != true || !mounted) return;
      final nuevosNombres = <String, String>{};
      for (var i = 0; i < 6; i++) {
        final nombre = controladores[i].text.trim();
        if (nombre.isNotEmpty) nuevosNombres['${i + 1}'] = nombre;
      }
      await _doc.update({
        'cantidadHablantes': cantidad,
        'nombresHablantes': nuevosNombres,
      }).timeout(const Duration(seconds: 12));
      _aviso('Hablantes configurados. Toca el lápiz en cada intervención para corregirla.');
    } on FirebaseException catch (e) {
      _aviso('No se pudieron guardar los hablantes (${e.code}).');
    } on TimeoutException {
      _aviso('Firebase no respondió al guardar los hablantes.');
    } catch (e) {
      _aviso('Error al configurar hablantes: $e');
    } finally {
      // Esperar a que finalice la animación de salida del diálogo.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controlador in controladores) {
        controlador.dispose();
      }
    }
  }

  Future<void> _agregarBandera() async {
    if (_guardandoBandera) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _aviso('Inicia sesión para guardar marcas.');
      return;
    }

    // Capturamos el segundo antes de abrir el diálogo; no cambia mientras
    // el usuario escribe, incluso si la reproducción continúa.
    final segundoMarcado = _posicion.inMilliseconds / 1000.0;
    // El formulario posee su propio TextEditingController y FocusNode.
    // No reconstruimos el TextField mientras se escribe ni desmontamos
    // el foco de la ruta en mitad de la pulsación de Guardar.
    final nota = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoBandera(segundo: segundoMarcado),
    );
    if (!mounted || nota == null || nota.isEmpty) return;

    setState(() => _guardandoBandera = true);
    try {
      // Un ID nuevo por marca. Evita guardar dos veces si se pulsa repetidamente.
      final marca = _doc.collection('banderas').doc();
      await marca.set({
        'usuarioId': uid,
        'segundo': segundoMarcado,
        'nota': nota,
        'creadoEn': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 12));
      _aviso('Bandera guardada correctamente');
    } on TimeoutException {
      _aviso('Firebase no respondió. Comprueba tu conexión y revisa si la bandera aparece antes de reintentar.');
    } on FirebaseException catch (e) {
      _aviso('No se pudo guardar (${e.code}). Revisa los permisos de Firestore.');
    } catch (e) {
      _aviso('No se pudo guardar la bandera: $e');
    } finally {
      if (mounted) setState(() => _guardandoBandera = false);
    }
  }

  Future<void> _borrarBandera(String id) async {
    try { await _doc.collection('banderas').doc(id).delete(); }
    catch (e) { _aviso('No se pudo borrar la marca: $e'); }
  }

  Widget _reproductor(Map<String, dynamic> datos) {
    final duracion = _player.duration?.inMilliseconds.toDouble() ??
        ((datos['duracionSegundos'] as num?)?.toDouble() ?? 0) * 1000;
    final max = duracion > 0 ? duracion : 1.0;
    final pos = _posicion.inMilliseconds.toDouble().clamp(0.0, max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.gsy200,
        borderRadius: BorderRadius.circular(AppRadius.radiusl)),
      child: Column(children: [
        Row(children: [
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: azul,
              minimumSize: const Size(50, 50)),
            onPressed: _cargandoAudio ? null : () => _play(datos),
            icon: _cargandoAudio
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: AppColors.gs50, strokeWidth: 2))
                : Icon(_player.playing ? Icons.pause : Icons.play_arrow, color: AppColors.gs50),
          ),
          const SizedBox(width: 10),
          Text('${_tiempo(pos / 1000)} / ${_tiempo(max / 1000)}'),
          const Spacer(),
          IconButton(tooltip: 'Retroceder 10 segundos', icon: const Icon(Icons.replay_10),
            onPressed: () => _irA(((pos / 1000) - 10).clamp(0, max / 1000).toDouble(), datos)),
          IconButton(tooltip: 'Avanzar 10 segundos', icon: const Icon(Icons.forward_10),
            onPressed: () => _irA(((pos / 1000) + 10).clamp(0, max / 1000).toDouble(), datos)),
        ]),
        Slider(value: pos, min: 0, max: max, activeColor: azul,
          onChanged: (v) => _irA(v / 1000, datos)),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _guardandoBandera ? null : _agregarBandera,
            icon: const Icon(Icons.outlined_flag, color: AppColors.primary500, size: 19),
            label: Text(
              _guardandoBandera ? 'Guardando bandera…' : 'Marcar momento importante',
              style: AppTypography.butt.copyWith(
                color: AppColors.primary500,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.gs50,
              side: const BorderSide(color: AppColors.gs500),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.radiusfull),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _marcas(Map<String, dynamic> datos) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _doc.collection('banderas').where('usuarioId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('No se pudieron leer las banderas.', style: AppTypography.b2.copyWith(color: AppFeedbackColors.error));
        }
        final marcas = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) => ((a.data()['segundo'] as num?)?.toDouble() ?? 0)
              .compareTo((b.data()['segundo'] as num?)?.toDouble() ?? 0));
        if (marcas.isEmpty) return Text('Todavía no tienes puntos marcados.', style: AppTypography.b2.copyWith(color: AppColors.gs800));
        return Column(children: marcas.map((marca) {
          final datosMarca = marca.data();
          final segundo = (datosMarca['segundo'] as num?)?.toDouble() ?? 0;
          return ListTile(
            leading: const Icon(Icons.flag, color: azul),
            title: Text(datosMarca['nota'] as String? ?? 'Punto importante'),
            subtitle: Text(_tiempo(segundo)),
            onTap: () => _irA(segundo, datos),
            trailing: IconButton(icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar bandera', onPressed: () => _borrarBandera(marca.id)),
          );
        }).toList());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gs50,
      appBar: AppBar(backgroundColor: AppColors.gs50, surfaceTintColor: AppColors.gs50,
        title: Text('Transcripción', style: AppTypography.h6.copyWith(
          fontWeight: FontWeight.w700, color: AppColors.gs900))),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _doc.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('No se pudieron cargar los datos.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text('La grabación ya no existe.'));
          final datos = snapshot.data!.data() ?? <String, dynamic>{};
          final esPropio = datos['usuarioId'] == FirebaseAuth.instance.currentUser?.uid;
          final segmentosRaw = datos['segmentosTranscripcion'];
          final segmentos = segmentosRaw is List
              ? segmentosRaw.whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList()
              : <Map<String, dynamic>>[];
          final hablantes = <String>[];
          for (final s in segmentos) {
            final nombre = '${s['hablante'] ?? 'desconocido'}';
            if (!hablantes.contains(nombre)) hablantes.add(nombre);
          }
          final correcciones = Map<String, dynamic>.from(
            datos['correccionesHablantes'] is Map ? datos['correccionesHablantes'] as Map : {},
          );
          final nombres = Map<String, dynamic>.from(
            datos['nombresHablantes'] is Map ? datos['nombresHablantes'] as Map : {},
          );
          final cantidadDefinida = (datos['cantidadHablantes'] as num?)?.toInt();
          final cantidadHablantes = (cantidadDefinida ?? hablantes.length).clamp(1, 6).toInt();
          final transcripcion = (datos['transcripcion'] as String? ?? '').trim();
          final titulo = (datos['titulo'] as String? ?? widget.titulo);
          // Muestra todos los fragmentos antes de tocar Play. Al reproducir,
          // revela la conversación según el tiempo real del reproductor.
          final modoProgresivo = _seguirAudio && _reproduccionIniciada;
          final ahora = _posicion.inMilliseconds / 1000.0;
          final indicesVisibles = <int>[];
          for (var i = 0; i < segmentos.length; i++) {
            final inicio = (segmentos[i]['inicio'] as num?)?.toDouble() ?? 0;
            if (!modoProgresivo || inicio <= ahora + 0.15) {
              indicesVisibles.add(i);
            }
          }
          final activo = indicesVisibles.isEmpty ? -1 : indicesVisibles.last;
          if (modoProgresivo && activo >= 0) _enfocarSegmento(activo);
          return ListView(controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 36), children: [
            Text(titulo, style: AppTypography.h5.copyWith(fontWeight: FontWeight.w700, color: AppColors.gs900)),
            const SizedBox(height: 18),
            _reproductor(datos),
            const SizedBox(height: 18),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 14),
              child: Text(_error!, style: AppTypography.b2.copyWith(color: AppFeedbackColors.error))),
            if (esPropio) SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: azul,
                padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _transcribiendo ? null : _transcribir,
              icon: _transcribiendo
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gs50))
                  : const Icon(Icons.auto_awesome),
              label: Text(_transcribiendo ? 'Generando transcripción…'
                  : segmentos.isEmpty ? 'Reintentar transcripción' : 'Volver a transcribir'),
            )),
            const SizedBox(height: 26),
            Row(children: [
              Expanded(child: Text('Transcripción por hablantes',
                style: AppTypography.h6.copyWith(fontWeight: FontWeight.w700, color: AppColors.gs900))),
              IconButton(tooltip: 'Copiar texto', icon: const Icon(Icons.copy),
                onPressed: transcripcion.isEmpty ? null : () async {
                  await Clipboard.setData(ClipboardData(text: transcripcion));
                  _aviso('Texto copiado');
                }),
            ]),
            if (segmentos.isNotEmpty) ...[
              const SizedBox(height: 4),
              if (esPropio) Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.groups_2_outlined, color: AppColors.primary500),
                  label: Text('Configurar hablantes ($cantidadHablantes)',
                    style: AppTypography.b2.copyWith(color: AppColors.primary500)),
                  onPressed: () => _configurarHablantes(datos, hablantes.length),
                ),
              ),
              Row(children: [
                const Icon(Icons.graphic_eq, size: 18,
                  color: AppColors.primary500),
                const SizedBox(width: 6),
                Expanded(child: Text('Seguir conversación al reproducir',
                  style: AppTypography.cptn.copyWith(color: AppColors.gs800))),
                Switch.adaptive(
                  value: _seguirAudio,
                  activeTrackColor: AppColors.primary500,
                  onChanged: (valor) => setState(() {
                    _seguirAudio = valor;
                    _ultimoSegmentoActivo = -1;
                  }),
                ),
              ]),
              if (modoProgresivo && indicesVisibles.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Escuchando… La conversación irá apareciendo mientras avanza el audio.',
                    style: AppTypography.b2.copyWith(color: AppColors.gs700))),
            ],
            const SizedBox(height: 8),
            if (segmentos.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(transcripcion.isEmpty
                    ? 'La transcripción comenzará automáticamente al abrir esta pantalla. Si falla, puedes volver a intentarlo con el botón superior.'
                    : transcripcion))
            else ...indicesVisibles.map((indiceSegmento) {
              final s = segmentos[indiceSegmento];
              final esActivo = modoProgresivo && indiceSegmento == activo;
              final numero = _numeroHablante(s, indiceSegmento, hablantes, correcciones);
              final colorIndex = (numero - 1) % colores.length;
              final nombrePersonalizado = (nombres['$numero'] as String? ?? '').trim();
              final nombreVisible = nombrePersonalizado.isEmpty
                  ? 'Hablante $numero'
                  : nombrePersonalizado;
              final color = colores[colorIndex];
              final fondo = fondosHablantes[colorIndex];
              // El secundario claro es perfecto para el fondo, pero en texto
              // necesitamos una variante más oscura para asegurar el contraste.
              final colorEtiqueta = colorIndex == 1
                  ? AppColors.secondary800
                  : color;
              final inicio = (s['inicio'] as num?)?.toDouble() ?? 0;
              final texto = (s['texto'] as String? ?? '').trim();
              return Padding(
                key: _clavesSegmentos.putIfAbsent(
                  indiceSegmento, () => GlobalKey()),
                padding: const EdgeInsets.only(top: 12), child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.radiusm),
                onTap: () => _irA(inicio, datos),
                child: Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: fondo,
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    border: Border(left: BorderSide(
                      color: color, width: esActivo ? 6 : 4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.person, size: 18, color: colorEtiqueta), const SizedBox(width: 6),
                      Expanded(child: Text(nombreVisible,
                        style: AppTypography.s1.copyWith(color: colorEtiqueta, fontWeight: FontWeight.w700))),
                      Text(_tiempo(inicio), style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
                      if (esPropio) PopupMenuButton<int>(
                        color: AppColors.gs50,
                        surfaceTintColor: AppColors.gs50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.radiusm),
                        ),
                        tooltip: 'Corregir hablante',
                        icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.gs800),
                        onSelected: (valor) => _cambiarHablante(indiceSegmento, valor),
                        itemBuilder: (_) => List.generate(cantidadHablantes, (i) {
                          final n = i + 1;
                          final nombre = (nombres['$n'] as String? ?? '').trim();
                          return PopupMenuItem<int>(
                            value: n,
                            child: Row(children: [
                              CircleAvatar(radius: 8, backgroundColor: colores[i % colores.length]),
                              const SizedBox(width: 10),
                              Text(nombre.isEmpty ? 'Hablante $n' : nombre,
                                style: AppTypography.b2.copyWith(color: AppColors.gs900)),
                            ]),
                          );
                        }),
                      ),
                    ]),
                    const SizedBox(height: 7),
                    Text(texto, style: AppTypography.b1.copyWith(color: AppColors.gs900, height: 1.45)),
                  ]),
                ),
              ));
            }),
            const SizedBox(height: 28),
            Text('Banderitas importantes', style: AppTypography.h6.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.gs900)),
            const SizedBox(height: 8),
            _marcas(datos),
          ]);
        },
      ),
    );
  }
}


/// Diálogo independiente: evita reconstruir el TextField en cada tecla.
/// Sus recursos viven hasta que Flutter desmonta realmente el diálogo.
class _DialogoBandera extends StatefulWidget {
  const _DialogoBandera({required this.segundo});

  final double segundo;

  @override
  State<_DialogoBandera> createState() => _DialogoBanderaState();
}

class _DialogoBanderaState extends State<_DialogoBandera> {
  final TextEditingController _texto = TextEditingController();
  final FocusNode _foco = FocusNode();
  bool _cerrando = false;

  @override
  void dispose() {
    _foco.dispose();
    _texto.dispose();
    super.dispose();
  }

  String _tiempo(double segundos) {
    final total = segundos.isFinite && segundos >= 0 ? segundos.floor() : 0;
    final mm = (total ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _cerrar([String? resultado]) async {
    if (_cerrando) return;
    _cerrando = true;
    _foco.unfocus();
    // Separa el desmontaje del teclado de la salida de la ruta.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (mounted) Navigator.of(context).pop(resultado);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.gs50,
      surfaceTintColor: AppColors.gs50,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppPadding.paddinglg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.radiusl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppPadding.paddinglg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Marcar punto importante',
                style: AppTypography.h6.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.gs900)),
              const SizedBox(height: AppSpacing.spacing500),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppPadding.paddingmd,
                  vertical: AppPadding.paddingsm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(AppRadius.radiusfull),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.outlined_flag, size: 18,
                    color: AppColors.primary500),
                  const SizedBox(width: AppGap.gaprelated),
                  Text('Minuto ${_tiempo(widget.segundo)}',
                    style: AppTypography.s2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary700)),
                ]),
              ),
              const SizedBox(height: AppSpacing.spacing500),
              TextField(
                controller: _texto,
                focusNode: _foco,
                autofocus: false,
                maxLength: 100,
                minLines: 1,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  final nota = _texto.text.trim();
                  if (nota.isNotEmpty) _cerrar(nota);
                },
                style: AppTypography.b1.copyWith(color: AppColors.gs900),
                cursorColor: AppColors.primary500,
                decoration: InputDecoration(
                  hintText: 'Ej.: idea principal, cambio de hablante...',
                  hintStyle: AppTypography.b2.copyWith(color: AppColors.gs600),
                  filled: true,
                  fillColor: AppColors.gs300,
                  counterStyle: AppTypography.cptn.copyWith(color: AppColors.gs700),
                  contentPadding: const EdgeInsets.all(AppPadding.paddingmd),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.radiusm),
                    borderSide: const BorderSide(
                      color: AppColors.primary500, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.spacing500),
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: _cerrando ? null : () => _cerrar(),
                  child: Text('Cancelar',
                    style: AppTypography.butt.copyWith(color: AppColors.gs800)),
                )),
                const SizedBox(width: AppSpacing.spacing100),
                Expanded(flex: 2, child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _texto,
                  builder: (context, value, _) => FilledButton(
                    onPressed: _cerrando || value.text.trim().isEmpty
                        ? null
                        : () => _cerrar(value.text.trim()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary500,
                      foregroundColor: AppColors.gs50,
                      disabledBackgroundColor: AppColors.primary200,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.radiusfull),
                      ),
                    ),
                    child: Text('Guardar bandera', textAlign: TextAlign.center,
                      style: AppTypography.butt.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.gs50,
                        letterSpacing: 0,
                      )),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
