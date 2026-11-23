import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'platform/audio_archivos_io.dart'
    if (dart.library.js_interop) 'platform/audio_archivos_web.dart' as audioArchivos;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';

import 'firebase_options.dart';
import 'theme/theme.dart';
import 'auth/auth_gate.dart';
import 'auth/perfil.dart';
import 'auth/comunidad_audio_list.dart';
import 'views/transcripcion_audio.dart';

// Inicia Flutter, Firebase y Google Sign-In.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    await GoogleSignIn.instance.initialize();
  }

  runApp(const MainApp());
}

// Define la configuración general de la aplicación.
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grabadora de voz',
      debugShowCheckedModeBanner: false,
      theme: voz,
      home: const AuthGate(),
    );
  }
}

// Define los posibles estados del micrófono.
enum EstadoGrabacion {
  lista,
  grabando,
  pausada,
  finalizada,
}

// StatefulWidget permite actualizar la interfaz.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() =>
      _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {

  // Controla el micrófono del dispositivo.
  final AudioRecorder _recorder = AudioRecorder();

  // Reproduce los archivos guardados.
  final AudioPlayer _player = AudioPlayer();

  // Colección de grabaciones de Firebase.
  final _grabaciones = FirebaseFirestore.instance
      .collection('grabaciones');

  // Escucha en tiempo real la colección.
  late final Stream<
      QuerySnapshot<Map<String, dynamic>>>
      _ultimasGrabaciones = _grabaciones
          .orderBy('creadoEn', descending: true)
          .snapshots();

  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<Duration>? _posicionSubscription;
  Duration _posicionActual = Duration.zero;

  // Contador de la grabación.
  Timer? _timer;
  Timer? _ondasTimer;
  Timer? _verificacionTimer;
  bool _verificandoGrabador = false;
  bool _seDetectoVoz = false;
  bool _avisoSenalMostrado = false;
  final List<double> _ondas = List<double>.filled(49, 0.035, growable: true);
  bool _consultandoAmplitud = false;
  double _nivelSuavizado = 0;
  int _muestrasSilencio = 0;
  double _picoMicrofono = -160;
  int _lecturasAmplitud = 0;

  // Lee el nivel REAL que recibe el micrófono durante una grabación.
  // No inventa barras cuando la entrada es silenciosa.
  void _iniciarOndas() {
    _ondasTimer?.cancel();
    _ondasTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_consultandoAmplitud || _estado != EstadoGrabacion.grabando) return;
      _consultandoAmplitud = true;
      try {
        final amplitude = await _recorder.getAmplitude();
        if (!mounted || _estado != EstadoGrabacion.grabando) return;
        final db = amplitude.current;
        _lecturasAmplitud++;
        if (db > _picoMicrofono) _picoMicrofono = db;
        // La amplitud del micrófono se expresa en dBFS (normalmente negativa).
        // Con el umbral anterior (-50 dB), las voces suaves parecían silencio.
        // Esto modifica SOLO la visualización, no altera el audio grabado.
        final normalizado = ((db + 70) / 58).clamp(0.0, 1.0).toDouble();
        final nivel = normalizado * normalizado * (3 - 2 * normalizado);
        // Una lectura cada ~1 segundo facilita saber si Android capta voz.
        if (_lecturasAmplitud % 12 == 0) {
          debugPrint('DIAGNOSTICO MICROFONO: actual=${db.toStringAsFixed(1)} dBFS, '
              'pico=${_picoMicrofono.toStringAsFixed(1)} dBFS');
        }
        // Ataque rápido y caída suave: la imagen no parpadea.
        final coef = nivel > _nivelSuavizado ? 0.72 : 0.28;
        _nivelSuavizado += (nivel - _nivelSuavizado) * coef;
        // Un silencio prolongado DESPUÉS de detectar voz puede indicar que
        // Android dejó de entregar señal. No reiniciamos ni detenemos el
        // archivo: eso podría perder la grabación ya realizada.
        if (db > -35) _seDetectoVoz = true;
        if (db < -58) {
          _muestrasSilencio++;
        } else {
          _muestrasSilencio = 0;
        }
        if (_seDetectoVoz && _muestrasSilencio >= 20 && !_avisoSenalMostrado) {
          _avisoSenalMostrado = true;
          debugPrint('ALERTA AUDIO: amplitud inferior a -58 dBFS por ~5 s; '
              'comprobar entrada del emulador y micrófono del Mac.');
          _mensaje('La señal del micrófono está muy baja. Comprueba que las ondas reaccionen al hablar.');
        }
        setState(() {
          _ondas.removeAt(0);
          _ondas.add(_nivelSuavizado.clamp(0.0, 1.0));
        });
        // Diagnóstico útil cuando Android graba archivos silenciosos.
        if (_muestrasSilencio == 45) {
          debugPrint('MICROFONO: la amplitud sigue muy baja ($db dB). Revisar entrada de audio del emulador.');
        }
      } catch (e) {
        debugPrint('No se pudo leer la amplitud del micrófono: $e');
      } finally {
        _consultandoAmplitud = false;
      }
    });
  }

  // La existencia del Timer no demuestra que el micrófono siga activo.
  // Esta vigilancia comprueba periódicamente la sesión nativa de grabación.
  void _iniciarVerificacionGrabador() {
    _verificacionTimer?.cancel();
    _verificacionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_estado != EstadoGrabacion.grabando || _verificandoGrabador) return;
      _verificandoGrabador = true;
      try {
        final activo = await _recorder.isRecording();
        if (!mounted || _estado != EstadoGrabacion.grabando) return;
        if (!activo) {
          debugPrint('ALERTA AUDIO: isRecording() es false mientras el '
              'contador está activo. La sesión de grabación se interrumpió.');
          _timer?.cancel();
          _ondasTimer?.cancel();
          _verificacionTimer?.cancel();
          setState(() => _estado = EstadoGrabacion.pausada);
          _mensaje('Se interrumpió la captura del micrófono. Finaliza la grabación y revisa el audio.');
        }
      } catch (e) {
        debugPrint('DIAGNOSTICO: no se pudo verificar isRecording(): $e');
      } finally {
        _verificandoGrabador = false;
      }
    });
  }

  Widget _visualizadorOndas() {
    return SizedBox(
      height: 112,
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _ondas.map((valor) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 85),
              curve: Curves.easeOut,
              height: 4 + valor * 99,
              decoration: BoxDecoration(
                color: AppColors.primary500,
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  // Estado inicial del micrófono.
  EstadoGrabacion _estado = EstadoGrabacion.lista;

  // Duración del audio.
  Duration _duracion = Duration.zero;

  // Ubicación temporal del archivo.
  String? _archivoLocal;

  // Archivo que se está reproduciendo.
  String? _audioReproduciendo;

  // Fecha en que comenzó la grabación.
  DateTime? _fechaAudio;

  // Evita acciones simultáneas.
  bool _ocupado = false;
  bool _cargandoAudio = false;

  // Identifica posibles reintentos de guardado.
  String? _idSubidaPendiente;
  String? _urlSubidaPendiente;

  // Variables del buscador y favoritos.
  String _busqueda = '';
  bool _soloFavoritos = false;
  String? _grabacionExpandida;

  // 0 = Grabaciones, 1 = Comunidad, 2 = Perfil.
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    // Actualiza los iconos cuando cambia el reproductor.
    _posicionSubscription = _player.positionStream.listen((p) {
      if (mounted) setState(() => _posicionActual = p);
    });
    _playerSubscription =
        _player.playerStateStream.listen((estado) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // Convierte segundos en minutos y segundos.
  String _formatear(Duration duracion) {
    final minutos = duracion.inMinutes
        .toString()
        .padLeft(2, '0');

    final segundos = duracion.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return '$minutos:$segundos';
  }

  // Muestra un mensaje temporal.
  void _mensaje(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            texto,
            style: AppTypography.b2,
          ),
        ),
      );
  }

  // Actualiza el contador cada segundo.
  void _iniciarContador() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {
            _duracion += const Duration(seconds: 1);
          });
        }
      },
    );
  }

  // Inicia, pausa o continúa una grabación.
  Future<void> _controlarGrabacion() async {
    if (_ocupado) return;

    setState(() {
      _ocupado = true;
    });

    try {
      switch (_estado) {

        case EstadoGrabacion.lista:
          // Solicita el permiso oficial de Android.
          final permitido =
              await _recorder.hasPermission();

          if (!mounted) return;

          if (!permitido) {
            _mensaje(
              'Debes permitir el uso del micrófono.',
            );
            return;
          }

          // Detenemos cualquier audio que esté sonando.
          await _player.stop();

          final fecha = DateTime.now();
          final ruta = await audioArchivos.rutaNuevaGrabacion(fecha);
          // Android conserva AAC/M4A; Chrome graba Opus/WebM.
          await _recorder.start(
            kIsWeb
                ? const RecordConfig(encoder: AudioEncoder.opus, numChannels: 1)
                : const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
            path: ruta,
          );

          // Verifica que el grabador sí haya iniciado, no solo el contador.
          if (!await _recorder.isRecording()) {
            throw StateError('Android no inició el micrófono. Revisa permisos y entrada de audio.');
          }
          if (!mounted) return;

          setState(() {
            _archivoLocal = ruta;
            _fechaAudio = fecha;
            _duracion = Duration.zero;
            _nivelSuavizado = 0;
            _muestrasSilencio = 0;
            _picoMicrofono = -160;
            _lecturasAmplitud = 0;
            _seDetectoVoz = false;
            _avisoSenalMostrado = false;
            for (var i = 0; i < _ondas.length; i++) { _ondas[i] = 0.035; }
            _estado = EstadoGrabacion.grabando;
            _idSubidaPendiente = null;
            _urlSubidaPendiente = null;
          });

          _iniciarContador();
          _iniciarOndas();
          _iniciarVerificacionGrabador();
          break;

        case EstadoGrabacion.grabando:
          // Pausa el audio y el contador.
          await _recorder.pause();
          _timer?.cancel();
          _ondasTimer?.cancel();
          _verificacionTimer?.cancel();

          if (mounted) {
            setState(() {
              _estado = EstadoGrabacion.pausada;
            });
          }
          break;

        case EstadoGrabacion.pausada:
          // Continúa la grabación existente.
          await _recorder.resume();

          if (mounted) {
            setState(() {
              _estado = EstadoGrabacion.grabando;
            });
          }

          _iniciarContador();
          _iniciarOndas();
          _iniciarVerificacionGrabador();
          break;

        case EstadoGrabacion.finalizada:
          _mensaje(
            'Guarda o elimina la grabación.',
          );
          break;
      }
    } catch (e) {
      _mensaje('Error con el micrófono: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }
  }

  // Finaliza la grabación y abre el formulario.
  Future<void> _finalizarGrabacion() async {
    if (_ocupado || _estado == EstadoGrabacion.lista) {
      return;
    }

    if (_estado == EstadoGrabacion.finalizada) {
      await _abrirGuardar();
      return;
    }

    setState(() {
      _ocupado = true;
    });

    bool finalizo = false;

    try {
      final ruta = await _recorder.stop().timeout(
        const Duration(seconds: 20),
      );

      _timer?.cancel();
      _ondasTimer?.cancel();
      _verificacionTimer?.cancel();

      if (ruta == null) {
        throw Exception(
          'No se pudo generar el archivo.',
        );
      }

      final tamanioBytes = await audioArchivos.tamano(ruta);
      debugPrint('DIAGNOSTICO AUDIO FINAL: ${_duracion.inSeconds}s '
          'de contador; $tamanioBytes bytes en archivo; '
          'máximo micrófono ${_picoMicrofono.toStringAsFixed(1)} dBFS.');
      if (!mounted) return;

      setState(() {
        _archivoLocal = ruta;
        _estado = EstadoGrabacion.finalizada;
      });

      finalizo = true;
      if (_lecturasAmplitud > 4 && _picoMicrofono < -60) {
        _mensaje('El micrófono captó una señal muy baja. Reproduce el archivo antes de guardarlo; podría estar en silencio.');
      }
    } catch (e) {
      _mensaje('Error al finalizar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }

    if (finalizo && mounted) {
      await _abrirGuardar();
    }
  }

  // Elimina la grabación temporal.
  Future<void> _descartar() async {
    if (_ocupado) return;

    setState(() {
      _ocupado = true;
    });

    try {
      // Detenemos el micrófono antes de eliminar.
      if (_estado == EstadoGrabacion.grabando ||
          _estado == EstadoGrabacion.pausada) {
        await _recorder.stop().timeout(
          const Duration(seconds: 15),
        );
      }

      _timer?.cancel();
      _ondasTimer?.cancel();
      _verificacionTimer?.cancel();

      // Guardamos la ruta antes de limpiar el estado.
      final ruta = _archivoLocal;

      if (mounted) {
        setState(() {
          _archivoLocal = null;
          _audioReproduciendo = null;
          _duracion = Duration.zero;
          _fechaAudio = null;
          _estado = EstadoGrabacion.lista;
          _selectedIndex = 0;
          _idSubidaPendiente = null;
          _urlSubidaPendiente = null;
        });
      }

      // Eliminamos el archivo local.
      if (ruta != null) {
        try {
          await audioArchivos.borrar(ruta).timeout(
            const Duration(seconds: 5),
          );
        } catch (e) {
          debugPrint('Error al eliminar archivo: $e');
        }
      }
    } on TimeoutException {
      _mensaje(
        'El micrófono no respondió. Intenta nuevamente.',
      );
    } catch (e) {
      _mensaje('Error al descartar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }
  }

  // Pregunta antes de descartar una grabación.
  Future<void> _confirmarSalirGrabacion() async {
    if (_ocupado) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.gs50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppRadius.radiusl,
            ),
          ),
          title: Text(
            'Descartar grabación',
            style: AppTypography.h5.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            '¿Quieres eliminar esta grabación? '
            'No podrás recuperarla.',
            style: AppTypography.b2.copyWith(
              color: AppColors.gs800,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                'Cancelar',
                style: AppTypography.butt.copyWith(
                  color: AppColors.gs900,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                'Descartar',
                style: AppTypography.butt.copyWith(
                  color: AppFeedbackColors.error,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar == true && mounted) {
      await _descartar();
    }
  }

  // Descarga el audio en caché local antes de reproducirlo.
  // Esto evita depender de la reproducción directa de una URL HTTPS.
  Future<void> _reproducir(
    String ruta, {
    bool remoto = false,
    String? archivoStorage,
  }) async {
    if (_cargandoAudio) return;
    if (ruta.isEmpty && (archivoStorage == null || archivoStorage.isEmpty)) {
      _mensaje('No hay un archivo de audio asociado a esta grabación.');
      return;
    }
    final identificador = remoto && archivoStorage != null && archivoStorage.isNotEmpty
        ? archivoStorage : ruta;
    try {
      if (_audioReproduciendo == identificador && _player.playing) {
        await _player.pause();
        if (mounted) setState(() {});
        return;
      }
      if (_audioReproduciendo == identificador &&
          _player.audioSource != null &&
          _player.processingState != ProcessingState.completed) {
        await _player.setVolume(1.0);
        unawaited(_player.play().catchError((Object e) {
          debugPrint('ERROR PLAY: $e');
          _mensaje('Error al iniciar reproducción: $e');
        }));
        if (mounted) setState(() {});
        return;
      }
      if (mounted) setState(() => _cargandoAudio = true);
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.setSpeed(_velocidadReproduccion);
      final rutaLocal = remoto
          ? await audioArchivos.prepararAudioRemoto(
              archivoStorage != null && archivoStorage.isNotEmpty
                  ? FirebaseStorage.instance.ref(archivoStorage)
                  : FirebaseStorage.instance.refFromURL(ruta),
              identificador,
            )
          : ruta;
      final duracionReal = kIsWeb
          ? await _player.setUrl(rutaLocal)
          : await _player.setFilePath(rutaLocal);
      debugPrint('AUDIO ABIERTO: $rutaLocal; duración: $duracionReal');
      if (!mounted) return;
      setState(() => _audioReproduciendo = identificador);
      unawaited(_player.play().catchError((Object e) {
        debugPrint('ERROR PLAY: $e');
        _mensaje('No se pudo iniciar la reproducción: $e');
      }));
    } on FirebaseException catch (e) {
      debugPrint('ERROR STORAGE AUDIO: ${e.code} ${e.message}');
      _mensaje('Firebase Storage: ${e.code}. ${e.message ?? 'Revisa el acceso al audio.'}');
    } on PlayerException catch (e) {
      debugPrint('ERROR DECODIFICACIÓN: ${e.code} ${e.message}');
      _mensaje('No se pudo decodificar el audio (${e.code}). ${e.message}');
    } catch (e) {
      debugPrint('ERROR AUDIO: $e');
      _mensaje('Error de reproducción: $e');
    } finally {
      if (mounted) setState(() => _cargandoAudio = false);
    }
  }

  // Devuelve la fecha con el formato de la maqueta.
  String _formatearFechaGuardado(DateTime fecha) {
    const meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];

    final hora = fecha.hour % 12 == 0
        ? 12
        : fecha.hour % 12;

    final minuto =
        fecha.minute.toString().padLeft(2, '0');

    final periodo =
        fecha.hour >= 12 ? 'p.m.' : 'a.m.';

    return '${fecha.day} '
        '${meses[fecha.month - 1]}, '
        '${fecha.year}, $hora:$minuto $periodo';
  }

  // Abre el diseño inferior de Guardar grabación.
  Future<void> _abrirGuardar() async {
    if (_ocupado ||
        (_estado != EstadoGrabacion.pausada &&
            _estado != EstadoGrabacion.finalizada)) {
      return;
    }

    final tituloController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final fecha = _fechaAudio ?? DateTime.now();

    bool guardando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return PopScope(
              canPop: !guardando,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.gs50,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      AppRadius.radiusl,
                    ),
                    topRight: Radius.circular(
                      AppRadius.radiusl,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppPadding.paddinglg,
                      AppPadding.paddingmd,
                      AppPadding.paddinglg,
                      MediaQuery.viewInsetsOf(
                            sheetContext,
                          ).bottom +
                          AppPadding.paddinglg,
                    ),
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [

                            const SizedBox(
                              height: AppGap.gapgroup,
                            ),

                            Text(
                              'Guardar grabación',
                              style: AppTypography.h5.copyWith(
                                color: AppColors.gs900,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapgroup,
                            ),

                            Text(
                              'Nombre de archivo',
                              style: AppTypography.s2.copyWith(
                                color: AppColors.gs900,
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gaprelated,
                            ),

                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.gs50,
                                borderRadius:
                                    BorderRadius.circular(
                                  AppRadius.radiusm,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextFormField(
                                controller: tituloController,
                                maxLength: 50,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: AppTypography.b2.copyWith(
                                  color: AppColors.gs900,
                                ),
                                onChanged: (_) {
                                  setSheetState(() {});
                                },
                                decoration: InputDecoration(
                                  hintText: 'Nombre de archivo',
                                  hintStyle:
                                      AppTypography.b2.copyWith(
                                    color: AppColors.gs600,
                                  ),
                                  border: InputBorder.none,
                                  counterText: '',
                                  contentPadding:
                                      const EdgeInsets.all(
                                    AppPadding.paddingmd,
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.edit_outlined,
                                    color: AppColors.gs900,
                                  ),
                                ),
                                validator: (valor) {
                                  if (valor == null ||
                                      valor.trim().isEmpty) {
                                    return 'Ingresa un nombre';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gaptight,
                            ),

                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${tituloController.text.length}/50',
                                style: AppTypography.cptn.copyWith(
                                  color: AppColors.gs600,
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapcomponent,
                            ),

                            Text(
                              'Duración',
                              style: AppTypography.s1.copyWith(
                                color: AppColors.gs900,
                              ),
                            ),

                            Text(
                              _formatear(_duracion),
                              style: AppTypography.b2.copyWith(
                                color: AppColors.gs600,
                              ),
                            ),

                            // Verificar que el archivo local contiene voz ANTES de subirlo.
                            TextButton.icon(
                              onPressed: _archivoLocal == null ? null : () async {
                                if (_estado == EstadoGrabacion.pausada) {
                                  _mensaje('Finaliza la grabación antes de escucharla.');
                                  return;
                                }
                                await _reproducir(_archivoLocal!);
                              },
                              icon: const Icon(Icons.play_circle_outline),
                              label: const Text('Escuchar grabación antes de guardar'),
                            ),

                            const SizedBox(
                              height: AppGap.gapcomponent,
                            ),

                            Text(
                              'Fecha',
                              style: AppTypography.s1.copyWith(
                                color: AppColors.gs900,
                              ),
                            ),

                            Text(
                              _formatearFechaGuardado(fecha),
                              style: AppTypography.b2.copyWith(
                                color: AppColors.gs600,
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapcomponent,
                            ),

                            Text(
                              'Ubicación',
                              style: AppTypography.s1.copyWith(
                                color: AppColors.gs900,
                              ),
                            ),

                            Text(
                              'En la nube',
                              style: AppTypography.b2.copyWith(
                                color: AppColors.gs600,
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapsection,
                            ),

                            // Guarda en Firebase.
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      AppColors.primary500,
                                  foregroundColor:
                                      AppColors.gs50,
                                  padding: const EdgeInsets.all(
                                    AppPadding.paddingmd,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                      AppRadius.radiusfull,
                                    ),
                                  ),
                                ),
                                onPressed: guardando
                                    ? null
                                    : () async {
                                        if (!formKey
                                            .currentState!
                                            .validate()) {
                                          return;
                                        }

                                        setSheetState(() {
                                          guardando = true;
                                        });

                                        setState(() {
                                          _ocupado = true;
                                        });

                                        bool correcto = false;

                                        try {
                                          correcto =
                                              await _subirGrabacion(
                                            tituloController.text.trim(),
                                          );
                                        } catch (e) {
                                          _mensaje(
                                            'Error al guardar: $e',
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() {
                                              _ocupado = false;
                                            });
                                          }

                                          if (sheetContext.mounted) {
                                            setSheetState(() {
                                              guardando = false;
                                            });
                                          }
                                        }

                                        if (!sheetContext.mounted) {
                                          return;
                                        }

                                        if (correcto) {
                                          Navigator.of(sheetContext).pop();

                                          _mensaje(
                                            'Grabación guardada correctamente',
                                          );
                                        }
                                      },
                                child: guardando
                                    ? const SizedBox(
                                        width: AppSpacing.spacing500,
                                        height: AppSpacing.spacing500,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.gs50,
                                        ),
                                      )
                                    : Text(
                                        'Guardar',
                                        style: AppTypography.butt.copyWith(
                                          color: AppColors.gs50,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapgroup,
                            ),

                            // Volver no elimina el archivo.
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.gs50,
                                borderRadius:
                                    BorderRadius.circular(
                                  AppRadius.radiusfull,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextButton(
                                onPressed: guardando
                                    ? null
                                    : () {
                                        Navigator.of(sheetContext).pop();
                                      },
                                child: Text(
                                  'Volver',
                                  style: AppTypography.s1.copyWith(
                                    color: AppColors.gs900,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: AppGap.gapgroup,
                            ),

                            // Eliminar solicita confirmación.
                            Center(
                              child: TextButton(
                                onPressed: guardando
                                    ? null
                                    : () async {
                                        Navigator.of(sheetContext).pop();
                                        await _confirmarSalirGrabacion();
                                      },
                                child: Text(
                                  'Eliminar',
                                  style: AppTypography.s1.copyWith(
                                    color: AppFeedbackColors.error,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

    tituloController.dispose();
  }

  // Guarda el archivo en Storage y datos en Firestore.
  
Future<bool> _subirGrabacion(String titulo) async {
  // Comprobamos que exista una ruta de audio.
  if (_archivoLocal == null) {
    _mensaje('No hay una grabación para guardar.');
    return false;
  }

  UploadTask? tareaSubida;
  StreamSubscription<TaskSnapshot>? progresoSubida;

  String etapa = 'Preparando archivo';

  try {
    // Si el audio está pausado, lo finalizamos.
    if (_estado == EstadoGrabacion.pausada) {
      etapa = 'Finalizando grabación';

      final ruta = await _recorder.stop().timeout(
        const Duration(seconds: 15),
      );

      if (ruta == null) {
        throw Exception('No se generó el archivo.');
      }

      _timer?.cancel();
      _archivoLocal = ruta;

      if (mounted) {
        setState(() {
          _estado = EstadoGrabacion.finalizada;
        });
      }
    }

    // Comprobamos que el archivo realmente exista.
    etapa = 'Comprobando archivo';

    final tamano = await audioArchivos.tamano(_archivoLocal!);

    if (tamano == 0) {
      throw Exception('El archivo está vacío.');
    }

    debugPrint('ARCHIVO ENCONTRADO: $tamano bytes');

    // Identificador único para este audio.
    // Se reutiliza si el usuario vuelve a intentar.
    final id =
        _idSubidaPendiente ?? _grabaciones.doc().id;

    _idSubidaPendiente = id;

    // Ruta del audio en Firebase Storage.
    final referencia = FirebaseStorage.instance
        .ref('grabaciones/$id.${kIsWeb ? 'webm' : 'm4a'}');

    String url;

    if (_urlSubidaPendiente == null) {
      etapa = 'Subiendo audio a Firebase Storage';

      debugPrint('INICIANDO SUBIDA A STORAGE');

      final bytes = await audioArchivos.bytesParaSubir(_archivoLocal!);
      final subidaActual = audioArchivos.subir(
        referencia,
        _archivoLocal!,
        SettableMetadata(
          contentType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        ),
        bytes,
      );
      tareaSubida = subidaActual;

      // Escuchamos el progreso de la subida.
      progresoSubida =
          subidaActual.snapshotEvents.listen(
        (snapshot) {
          if (snapshot.totalBytes > 0) {
            final porcentaje =
                snapshot.bytesTransferred /
                snapshot.totalBytes *
                100;

            debugPrint(
              'SUBIDA: ${porcentaje.toStringAsFixed(0)}%',
            );
          }

          debugPrint(
            'ESTADO STORAGE: ${snapshot.state}',
          );
        },
        onError: (Object error) {
          debugPrint(
            'ERROR EN PROGRESO STORAGE: $error',
          );
        },
      );

      // No esperamos indefinidamente.
      await subidaActual.timeout(
        const Duration(seconds: 45),
      );

      debugPrint('AUDIO SUBIDO CORRECTAMENTE');

      etapa = 'Obteniendo URL';

      url = await referencia.getDownloadURL().timeout(
        const Duration(seconds: 15),
      );

      // Guardamos la URL para posibles reintentos.
      _urlSubidaPendiente = url;

      debugPrint('URL OBTENIDA');
    } else {
      url = _urlSubidaPendiente!;

      debugPrint('REUTILIZANDO AUDIO SUBIDO');
    }

    // Guardamos la información de la grabación.
    etapa = 'Guardando datos en Firestore';

    debugPrint('INICIANDO GUARDADO FIRESTORE');

    final usuario = FirebaseAuth.instance.currentUser;

    await _grabaciones.doc(id).set({
      'titulo': titulo,
      'archivo': referencia.fullPath,
      'url': url,
      'duracionSegundos': _duracion.inSeconds,
      'creadoEn': FieldValue.serverTimestamp(),
      'favorito': false,
      'enComunidad': false,
      'usuarioId': usuario?.uid,
    }).timeout(
      const Duration(seconds: 20),
    );

    debugPrint('FIRESTORE GUARDADO CORRECTAMENTE');

    // Guardar la ruta antes de limpiar el estado del widget.
    final archivoTemporalGuardado = _archivoLocal!;
    // Limpiamos el estado después de confirmar
    // que Firebase terminó de guardar.
    if (mounted) {
      setState(() {
        _archivoLocal = null;
        _fechaAudio = null;
        _duracion = Duration.zero;
        _estado = EstadoGrabacion.lista;
        _selectedIndex = 0;

        _idSubidaPendiente = null;
        _urlSubidaPendiente = null;
      });
    }

    // Borramos solamente el archivo temporal local.
    try {
      await audioArchivos.borrar(archivoTemporalGuardado);
    } catch (e) {
      debugPrint(
        'No se pudo limpiar archivo temporal: $e',
      );
    }

    return true;

  } on FirebaseException catch (e) {
    // FirebaseException indica errores de Firebase.
    debugPrint('ERROR FIREBASE EN: $etapa');
    debugPrint('CODIGO: ${e.code}');
    debugPrint('MENSAJE: ${e.message}');

    _mensaje(
      'Error de Firebase (${e.code}): '
      '${e.message ?? etapa}',
    );

    return false;

  } on TimeoutException {
    debugPrint('TIEMPO AGOTADO EN: $etapa');

    // Intentamos cancelar una subida pendiente.
    if (tareaSubida != null) {
      try {
        await tareaSubida.cancel().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint('Error al cancelar subida: $e');
      }
    }

    _mensaje(
      'Se agotó el tiempo en: $etapa',
    );

    return false;

  } catch (e) {
    debugPrint('ERROR EN $etapa: $e');

    _mensaje(
      'No se pudo guardar ($etapa): $e',
    );

    return false;

  } finally {
    // Dejamos de escuchar el progreso de subida.
    await progresoSubida?.cancel();
  }
}


  // Mueve una grabación guardada a la papelera. NO borra el audio de Storage.
  Future<void> _eliminarGrabacion(String id, String titulo, String url, String archivoStorage) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.gs50,
        title: const Text('Mover a borrados recientemente'),
        content: Text('¿Mover "$titulo" a la papelera? Podrás restaurarla desde el menú lateral.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Mover a papelera', style: TextStyle(color: AppFeedbackColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      final anterior = await _grabaciones.doc(id).get();
      final estabaPublicada = anterior.data()?['enComunidad'] == true;
      await _grabaciones.doc(id).update({
        'eliminado': true,
        'eliminadoEn': FieldValue.serverTimestamp(),
        'comunidadAntesDeEliminar': estabaPublicada,
        'enComunidad': false,
      });
      if (_grabacionExpandida == id) setState(() => _grabacionExpandida = null);
      if (_audioReproduciendo == archivoStorage || _audioReproduciendo == url) {
        await _player.stop();
        if (mounted) setState(() => _audioReproduciendo = null);
      }
      _mensaje('Grabación movida a Borrados recientemente');
    } catch (e) {
      _mensaje('No se pudo mover a la papelera: $e');
    }
  }

  Future<void> _restaurarGrabacion(String id) async {
    try {
      final documento = await _grabaciones.doc(id).get();
      final publicadaAntes = documento.data()?['comunidadAntesDeEliminar'] == true;
      await _grabaciones.doc(id).update({
        'eliminado': false,
        'eliminadoEn': FieldValue.delete(),
        'enComunidad': publicadaAntes,
        'comunidadAntesDeEliminar': FieldValue.delete(),
      });
      _mensaje('Grabación restaurada');
    } catch (e) {
      _mensaje('No se pudo restaurar: $e');
    }
  }

  // Solo esta acción elimina definitivamente Storage y Firestore.
  Future<void> _eliminarDefinitivamente(
    String id, String titulo, String url, String archivoStorage,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.gs50,
        title: const Text('Eliminar definitivamente'),
        content: Text('Se eliminará "$titulo" de forma permanente. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar', style: TextStyle(color: AppFeedbackColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      final referencia = archivoStorage.isNotEmpty
          ? FirebaseStorage.instance.ref(archivoStorage)
          : (url.isNotEmpty ? FirebaseStorage.instance.refFromURL(url) : null);
      if (referencia != null) {
        try {
          await referencia.delete();
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found') rethrow;
        }
      }
      await _grabaciones.doc(id).delete();
      _mensaje('Grabación eliminada definitivamente');
    } catch (e) {
      _mensaje('No se pudo eliminar definitivamente: $e');
    }
  }

  void _abrirBorradosRecientemente() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (pantallaContext) => Scaffold(
        backgroundColor: AppColors.gs50,
        appBar: AppBar(
          backgroundColor: AppColors.gs50,
          surfaceTintColor: AppColors.gs50,
          title: const Text('Borrados recientemente'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ultimasGrabaciones,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('No se pudo abrir la papelera.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary500));
            final borradas = snapshot.data!.docs.where((d) => d.data()['eliminado'] == true).toList();
            if (borradas.isEmpty) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No tienes grabaciones eliminadas.',
                  style: AppTypography.b2.copyWith(color: AppColors.gs600),
                  textAlign: TextAlign.center),
              ));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: borradas.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final d = borradas[i];
                final datos = d.data();
                final titulo = datos['titulo'] as String? ?? 'Sin título';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  leading: const Icon(Icons.audio_file_outlined, color: AppColors.primary500),
                  title: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Eliminada: ${_formatearFecha(datos['eliminadoEn'])}'),
                  trailing: PopupMenuButton<String>(
                    color: AppColors.gs50,
                    onSelected: (accion) async {
                      if (accion == 'restaurar') {
                        await _restaurarGrabacion(d.id);
                      } else {
                        await _eliminarDefinitivamente(
                          d.id, titulo,
                          datos['url'] as String? ?? '',
                          datos['archivo'] as String? ?? '',
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restaurar', child: Text('Restaurar')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar definitivamente')),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ));
  }

  double _velocidadReproduccion = 1.0;

  Future<void> _abrirConfiguracion() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, actualizarDialogo) => AlertDialog(
          backgroundColor: AppColors.gs50,
          title: const Text('Configuración'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Velocidad de reproducción'),
              const SizedBox(height: 10),
              DropdownButtonFormField<double>(
                key: ValueKey(_velocidadReproduccion),
                value: _velocidadReproduccion,
                dropdownColor: AppColors.gs50,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary500, width: 2),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 0.75, child: Text('0,75×')),
                  DropdownMenuItem(value: 1.0, child: Text('1× · Normal')),
                  DropdownMenuItem(value: 1.25, child: Text('1,25×')),
                  DropdownMenuItem(value: 1.5, child: Text('1,5×')),
                  DropdownMenuItem(value: 2.0, child: Text('2×')),
                ],
                onChanged: (valor) async {
                  if (valor == null) return;
                  actualizarDialogo(() => _velocidadReproduccion = valor);
                  await _player.setSpeed(valor);
                },
              ),
              const SizedBox(height: 12),
              Text('Esta preferencia se mantiene durante la sesión.',
                style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar', style: TextStyle(color: AppColors.primary500))),
          ],
        ),
      ),
    );
  }

  Future<Map<String, int>> _consultarAlmacenamiento() async {
    final documentos = await _grabaciones.get();
    var bytes = 0;
    var revisados = 0;
    var noDisponibles = 0;
    for (final doc in documentos.docs) {
      final datos = doc.data();
      final ruta = datos['archivo'] as String? ?? '';
      if (ruta.isEmpty) {
        noDisponibles++;
        continue;
      }
      try {
        final metadata = await FirebaseStorage.instance.ref(ruta).getMetadata();
        bytes += metadata.size ?? 0;
        revisados++;
      } catch (_) {
        noDisponibles++;
      }
    }
    return {'bytes': bytes, 'revisados': revisados,
      'noDisponibles': noDisponibles, 'total': documentos.docs.length};
  }

  String _formatearTamano(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _abrirAlmacenamiento() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.gs50,
        appBar: AppBar(
          backgroundColor: AppColors.gs50,
          surfaceTintColor: AppColors.gs50,
          title: const Text('Almacenamiento'),
        ),
        body: FutureBuilder<Map<String, int>>(
          future: _consultarAlmacenamiento(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('No se pudo consultar el almacenamiento.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary500));
            final datos = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Espacio de audio en la nube',
                  style: AppTypography.h5.copyWith(color: AppColors.gs900)),
                const SizedBox(height: 16),
                Text(_formatearTamano(datos['bytes']!),
                  style: AppTypography.h2.copyWith(color: AppColors.primary500)),
                const SizedBox(height: 12),
                Text('Grabaciones consultadas: ${datos['revisados']} de ${datos['total']}'),
                if (datos['noDisponibles']! > 0)
                  Text('No se pudo comprobar el tamaño de ${datos['noDisponibles']} archivo(s).'),
                const SizedBox(height: 14),
                Text('El tamaño mostrado corresponde a los archivos de audio cuya información está disponible en Firebase Storage. No incluye transcripciones ni almacenamiento local.',
                  style: AppTypography.b2.copyWith(color: AppColors.gs600)),
              ]),
            );
          },
        ),
      ),
    ));
  }

  Future<void> _mostrarInformacion(String titulo, String contenido) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.gs50,
        title: Text(titulo),
        content: SingleChildScrollView(child: Text(contenido,
          style: AppTypography.b2.copyWith(color: AppColors.gs900))),
        actions: [TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar', style: TextStyle(color: AppColors.primary500)),
        )],
      ),
    );
  }

  Widget _opcionMenuLateral(IconData icono, String titulo, VoidCallback accion) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icono, color: AppColors.gs900),
      title: Text(titulo, style: AppTypography.b2.copyWith(color: AppColors.gs900)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.gs600),
      onTap: () {
        Navigator.of(context).pop();
        accion();
      },
    );
  }

  // Comparte el archivo de audio mediante WhatsApp, correo u otras apps.
  Future<void> _compartirAudio(String titulo, String url) async {
    if (url.isEmpty) {
      _mensaje('Esta grabación no tiene un archivo disponible.');
      return;
    }
    try {
      await audioArchivos.compartir(titulo, url);
    } catch (e) {
      _mensaje('No se pudo compartir el audio: $e');
    }
  }

  // Cambia el campo favorito de Firestore.
  Future<void> _cambiarFavorito(
    String id,
    bool favorito,
  ) async {
    try {
      await _grabaciones.doc(id).update({
        'favorito': !favorito,
      });
    } catch (e) {
      _mensaje('Error al cambiar favorito: $e');
    }
  }

  // Da formato a la fecha de las tarjetas.
  String _formatearFecha(dynamic valor) {
    if (valor is! Timestamp) {
      return 'Guardada recientemente';
    }

    final fecha = valor.toDate().toLocal();
    final ahora = DateTime.now();

    final hora = fecha.hour % 12 == 0
        ? 12
        : fecha.hour % 12;

    final minuto =
        fecha.minute.toString().padLeft(2, '0');

    final periodo =
        fecha.hour >= 12 ? 'p.m.' : 'a.m.';

    if (fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day) {
      return 'Hoy, $hora:$minuto $periodo';
    }

    return '${fecha.day}/${fecha.month}/${fecha.year}, '
        '$hora:$minuto $periodo';
  }

  // Libera los recursos cuando se elimina el widget.
  @override
  void dispose() {
    _timer?.cancel();
    _ondasTimer?.cancel();
    _verificacionTimer?.cancel();
    _playerSubscription?.cancel();
    _posicionSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // Decide cuál pantalla debe mostrarse.
  @override
  Widget build(BuildContext context) {

    // Durante una grabación mostramos pantalla completa.
    if (_estado == EstadoGrabacion.grabando ||
        _estado == EstadoGrabacion.pausada ||
        _estado == EstadoGrabacion.finalizada) {
      return _pantallaGrabando();
    }

    // En estado lista mostramos la navegación normal.
    return Scaffold(
      backgroundColor: AppColors.gs50,

      // Perfil tiene su propia flecha superior.
      appBar: _selectedIndex == 2
          ? null
          : AppBar(
              backgroundColor: AppColors.gs50,
              surfaceTintColor: AppColors.gs50,
              elevation: 0,
              toolbarHeight: 68,
              leading: Builder(
                builder: (context) {
                  return IconButton(
                    icon: const Icon(
                      Icons.menu,
                      color: AppColors.gs900,
                      size: 30,
                    ),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  );
                },
              ),
            ),

      // Menú lateral: solo funciones complementarias.
      drawer: Drawer(
        backgroundColor: AppColors.gs50,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppPadding.paddingmd),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Menú', style: AppTypography.h5.copyWith(
                  color: AppColors.gs900, fontWeight: FontWeight.w700)),
              ),
              const Divider(color: AppColors.gs300),
              _opcionMenuLateral(Icons.restore_from_trash_outlined,
                'Borrados recientemente', _abrirBorradosRecientemente),
              _opcionMenuLateral(Icons.settings_outlined,
                'Configuración', () { _abrirConfiguracion(); }),
              _opcionMenuLateral(Icons.storage_outlined,
                'Almacenamiento', _abrirAlmacenamiento),
              _opcionMenuLateral(Icons.help_outline,
                'Ayuda', () {
                  _mostrarInformacion('Ayuda',
                    'Para grabar, pulsa el botón azul del micrófono. Puedes pausar y finalizar la grabación, escucharla antes de guardar y asignarle un nombre.\n\n'
                    'En Mis Grabaciones, toca una estrella para marcar un audio como favorito. Desde los tres puntos puedes compartir, renombrar, transcribir o mover a Borrados recientemente.\n\n'
                    'En Borrados recientemente puedes restaurar una grabación o eliminarla definitivamente.');
                }),
              _opcionMenuLateral(Icons.info_outline,
                'Acerca de la app', () {
                  _mostrarInformacion('Acerca de la app',
                    'Grabadora de voz\n\n'
                    'Aplicación para grabar, escuchar, organizar y transcribir audios.\n\n'
                    'Tus grabaciones se guardan en Firebase. La transcripción puede contener errores; revisa el audio original cuando necesites precisión.');
                }),
            ],
          ),
        ),
      ),

      // Cambia la pantalla utilizando _selectedIndex.
      body: _selectedIndex == 0
          ? _pantallaGrabaciones()
          : _selectedIndex == 1
              ? _comunidadConAudios()
              : PerfilScreen(
                  onVolver: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),

      // La grabadora muestra su FAB aquí. Comunidad tiene el suyo dentro
      // de ComunidadAudioList para que no desaparezca al cambiar de pestaña.
      floatingActionButton: _selectedIndex == 0
          ? SizedBox(
              width: 86,
              height: 86,
              child: FloatingActionButton(
                heroTag: 'grabar',
                elevation: 0,
                backgroundColor: AppColors.primary500,
                foregroundColor: AppColors.gs50,
                shape: const CircleBorder(),
                onPressed: _ocupado ? null : _controlarGrabacion,
                child: const Icon(Icons.mic, size: 40),
              ),
            )
          : null,

      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,

      // Barra inferior redondeada compartida.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: AppColors.gs50,
          height: 90,
          alignment: Alignment.center,
          child: Container(
            width: 250,
            height: 66,
            padding: const EdgeInsets.all(
              AppPadding.paddingxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.gs300,
              borderRadius: BorderRadius.circular(
                AppRadius.radiusfull,
              ),
            ),
            child: Row(
              children: [
                _iconoNavegacion(
                  Icons.home,
                  0,
                ),
                _iconoNavegacion(
                  Icons.groups_outlined,
                  1,
                ),
                _iconoNavegacion(
                  Icons.person_outline,
                  2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Pantalla completa mientras grabamos.
  Widget _pantallaGrabando() {
    final grabando =
        _estado == EstadoGrabacion.grabando;

    final finalizada =
        _estado == EstadoGrabacion.finalizada;

    return Scaffold(
      backgroundColor: AppColors.gs50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppPadding.paddinglg,
            vertical: AppPadding.paddingmd,
          ),
          child: Column(
            children: [

              // Flecha para salir con confirmación.
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _ocupado
                      ? null
                      : _confirmarSalirGrabacion,
                  icon: const Icon(
                    Icons.arrow_circle_left_outlined,
                    color: AppColors.gs900,
                    size: 30,
                  ),
                ),
              ),

              // Información central.
              Expanded(
                child: Column(
                  children: [
                    const Spacer(),

                    Text(
                      grabando
                          ? 'Grabando'
                          : finalizada
                              ? 'Grabación finalizada'
                              : 'En pausa',
                      style: AppTypography.h5.copyWith(
                        color: AppColors.gs900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(
                      height: AppGap.gapsection,
                    ),

                    // Contador grande.
                    Text(
                      _formatear(_duracion),
                      style: AppTypography.h2.copyWith(
                        color: AppColors.gs900,
                        fontWeight: FontWeight.w300,
                      ),
                    ),

                    const SizedBox(height: 28),
                    _visualizadorOndas(),
                    const Spacer(flex: 2),
                  ],
                ),
              ),

              // Línea horizontal inferior.
              Container(
                height: AppSpacing.spacingy200,
                decoration: BoxDecoration(
                  color: AppColors.gs600,
                  borderRadius: BorderRadius.circular(
                    AppRadius.radiusfull,
                  ),
                ),
              ),

              const SizedBox(
                height: AppGap.gaprelated,
              ),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '00:00',
                    style: AppTypography.cptn.copyWith(
                      color: AppColors.gs600,
                    ),
                  ),
                  Text(
                    _formatear(_duracion),
                    style: AppTypography.cptn.copyWith(
                      color: AppColors.gs600,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: AppGap.gapcomponent,
              ),

              // Controles: eliminar, pausa y finalizar.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  InkWell(
                    onTap: _ocupado
                        ? null
                        : _confirmarSalirGrabacion,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: AppSpacing.spacing900,
                      height: AppSpacing.spacing900,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppFeedbackColors.error,
                          width: AppSpacing.spacing50,
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppFeedbackColors.error,
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: AppGap.gapsection,
                  ),

                  FloatingActionButton.large(
                    heroTag: 'control_grabacion',
                    elevation: 2,
                    backgroundColor: AppColors.primary500,
                    foregroundColor: AppColors.gs50,
                    shape: const CircleBorder(),
                    onPressed: (_ocupado || finalizada)
                        ? null
                        : _controlarGrabacion,
                    child: Icon(
                      grabando
                          ? Icons.pause
                          : finalizada
                              ? Icons.check
                              : Icons.play_arrow,
                      size: AppSpacing.spacing800,
                    ),
                  ),

                  const SizedBox(
                    width: AppGap.gapsection,
                  ),

                  InkWell(
                    onTap: _ocupado
                        ? null
                        : _finalizarGrabacion,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: AppSpacing.spacing900,
                      height: AppSpacing.spacing900,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppFeedbackColors.warning,
                          width: AppSpacing.spacing50,
                        ),
                      ),
                      child: const Icon(
                        Icons.stop,
                        color: AppFeedbackColors.warning,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: AppGap.gapsection,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Pantalla principal de Mis Grabaciones.
  Widget _pantallaGrabaciones() {
    return ListView(
      padding: const EdgeInsets.only(
        left: AppMargin.marginlg,
        right: AppMargin.marginlg,
        top: AppSpacing.spacing100,
        bottom: 150,
      ),
      children: [

        Text(
          'Mis Grabaciones',
          style: AppTypography.h5.copyWith(
            fontSize: 30,
            color: AppColors.gs900,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(
          height: AppGap.gapgroup,
        ),

        // Buscador de grabaciones.
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.gs300,
            borderRadius: BorderRadius.circular(
              AppRadius.radiuss,
            ),
          ),
          child: TextField(
            style: AppTypography.b2.copyWith(
              color: AppColors.gs900,
            ),
            onChanged: (valor) {
              setState(() {
                _busqueda =
                    valor.trim().toLowerCase();
              });
            },
            decoration: InputDecoration(
              hintText: 'Buscar grabaciones...',
              hintStyle: AppTypography.b2.copyWith(
                color: AppColors.gs600,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.gs900,
                size: 28,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(
                vertical: AppPadding.paddingmd,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: AppGap.gapsection,
        ),

        // Categorías Todas y Favoritos.
        Row(
          children: [
            Expanded(
              child: _pestana(
                'Todas',
                !_soloFavoritos,
                () {
                  setState(() {
                    _soloFavoritos = false;
                  });
                },
              ),
            ),

            const SizedBox(
              width: AppGap.gapgroup,
            ),

            Expanded(
              child: _pestana(
                'Favoritos',
                _soloFavoritos,
                () {
                  setState(() {
                    _soloFavoritos = true;
                  });
                },
              ),
            ),
          ],
        ),

        const SizedBox(
          height: AppGap.gapsection,
        ),

        // Muestra las grabaciones guardadas en Firebase.
        StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: _ultimasGrabaciones,
          builder: (context, snapshot) {

            if (snapshot.hasError) {
              return Text(
                'No se pudieron cargar las grabaciones.',
                style: AppTypography.b2.copyWith(
                  color: AppColors.gs600,
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary500,
                ),
              );
            }

            final documentos =
                snapshot.data!.docs.where((documento) {
              final datos = documento.data();

              final titulo =
                  (datos['titulo'] as String? ?? '')
                      .toLowerCase();

              final favorito =
                  datos['favorito'] == true;

              return datos['eliminado'] != true &&
                  titulo.contains(_busqueda) &&
                  (!_soloFavoritos || favorito);
            }).toList();

            if (documentos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.spacing700,
                ),
                child: Center(
                  child: Text(
                    _soloFavoritos
                        ? 'Todavía no tienes favoritos.'
                        : _busqueda.isNotEmpty
                            ? 'No se encontraron grabaciones.'
                            : 'Todavía no hay grabaciones.',
                    style: AppTypography.b2.copyWith(
                      color: AppColors.gs600,
                    ),
                  ),
                ),
              );
            }

            // Una tarjeta por cada documento.
            return Column(
              children: documentos.map((documento) {
                final datos = documento.data();

                final titulo =
                    datos['titulo'] as String? ??
                        'Sin título';

                final url =
                    datos['url'] as String? ?? '';
                final archivoStorage = datos['archivo'] as String? ?? '';

                final segundos =
                    (datos['duracionSegundos'] as num?)
                            ?.toInt() ??
                        0;

                final favorito =
                    datos['favorito'] == true;
                final publicada =
                    datos['enComunidad'] == true;

                return _tarjetaGrabacion(
                  id: documento.id,
                  titulo: titulo,
                  fecha: _formatearFecha(
                    datos['creadoEn'],
                  ),
                  duracion: _formatear(
                    Duration(seconds: segundos),
                  ),
                  url: url,
                  archivoStorage: archivoStorage,
                  favorito: favorito,
                  publicada: publicada,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // Crea una categoría con línea azul o gris.
  Widget _pestana(
    String titulo,
    bool seleccionada,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: AppTypography.h6.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(
            height: AppGap.gaptight,
          ),

          Container(
            height: AppSpacing.spacingy200,
            decoration: BoxDecoration(
              color: seleccionada
                  ? AppColors.primary500
                  : AppColors.gs400,
              borderRadius: BorderRadius.circular(
                AppRadius.radiusfull,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renombrarGrabacion(String id, String titulo) async {
    final controlador = TextEditingController(text: titulo);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Renombrar grabación'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, controlador.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    controlador.dispose();
    if (nuevo == null || nuevo.isEmpty || nuevo == titulo) return;
    try {
      await _grabaciones.doc(id).update({'titulo': nuevo});
    } catch (e) {
      _mensaje('No se pudo renombrar: $e');
    }
  }

  Future<void> _saltarAudio(int segundos) async {
    if (_player.audioSource == null) return;
    final total = _player.duration ?? Duration.zero;
    final nuevo = (_player.position.inMilliseconds + segundos * 1000)
        .clamp(0, total.inMilliseconds);
    await _player.seek(Duration(milliseconds: nuevo));
  }

  // Card compacta o expandida, siguiendo las pantallas de referencia.
  Widget _tarjetaGrabacion({
    required String id,
    required String titulo,
    required String fecha,
    required String duracion,
    required String url,
    required String archivoStorage,
    required bool favorito,
    required bool publicada,
  }) {
    final identificador = archivoStorage.isNotEmpty ? archivoStorage : url;
    final reproduciendo = _audioReproduciendo == identificador &&
        _player.playing && _player.processingState != ProcessingState.completed;
    final expandida = _grabacionExpandida == id;
    final segundos = (int.tryParse(duracion.split(':').first) ?? 0) * 60 +
        (int.tryParse(duracion.split(':').last) ?? 0);
    final total = _audioReproduciendo == identificador && _player.duration != null
        ? _player.duration! : Duration(seconds: segundos);
    final posicion = _audioReproduciendo == identificador
        ? _posicionActual : Duration.zero;
    final maximo = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
    final actual = posicion.inMilliseconds.toDouble().clamp(0.0, maximo);
    final estilo = AppTypography.b2.copyWith(color: AppColors.gs900);

    final menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.gs700),
      color: AppColors.gs50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (accion) async {
        switch (accion) {
          case 'renombrar': await _renombrarGrabacion(id, titulo); break;
          case 'transcribir':
            if (!mounted) break;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TranscripcionAudioScreen(
                  grabacionId: id,
                  titulo: titulo,
                ),
              ),
            );
            break;
          case 'compartir': await _compartirAudio(titulo, url); break;
          case 'eliminar': await _eliminarGrabacion(id, titulo, url, archivoStorage); break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'compartir', child: Row(children: [Icon(Icons.ios_share), SizedBox(width: 12), Text('Compartir')])),
        const PopupMenuItem(value: 'renombrar', child: Row(children: [Icon(Icons.drive_file_rename_outline), SizedBox(width: 12), Text('Renombrar')])),
        const PopupMenuItem(value: 'transcribir', child: Row(children: [Icon(Icons.text_snippet_outlined), SizedBox(width: 12), Text('Transcribir')])),
        const PopupMenuItem(value: 'eliminar', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 12), Text('Eliminar', style: TextStyle(color: Colors.red))])),
      ],
    );

    // Estrella visible en ambas versiones de la tarjeta.
    // Firestore actualiza el estado automáticamente mediante el StreamBuilder.
    final estrella = IconButton(
      tooltip: favorito ? 'Quitar de favoritos' : 'Agregar a favoritos',
      constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
      icon: Icon(
        favorito ? Icons.star : Icons.star_border,
        color: favorito ? AppColors.primary500 : AppColors.gs600,
        size: 25,
      ),
      onPressed: () => _cambiarFavorito(id, favorito),
    );

    final play = IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: AppColors.primary500,
        foregroundColor: Colors.white,
        minimumSize: const Size(52, 52),
      ),
      onPressed: identificador.isEmpty || _cargandoAudio ? null : () async {
        if (!expandida) setState(() => _grabacionExpandida = id);
        await _reproducir(url, remoto: true, archivoStorage: archivoStorage);
      },
      icon: Icon(reproduciendo ? Icons.pause : Icons.play_arrow, size: 30),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: EdgeInsets.symmetric(horizontal: expandida ? 16 : 12, vertical: 12),
      decoration: BoxDecoration(
        color: expandida ? const Color(0xFFE8ECFF) : AppColors.gs50,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 9, offset: Offset(0, 5))],
      ),
      child: expandida
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: InkWell(
                  onTap: () => setState(() => _grabacionExpandida = null),
                  child: Text(titulo, style: AppTypography.s1.copyWith(color: AppColors.gs900, fontWeight: FontWeight.w600)),
                )),
                estrella,
                menu,
              ]),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
                child: Slider(value: actual, max: maximo,
                  activeColor: AppColors.primary500,
                  inactiveColor: AppColors.gs400,
                  onChanged: (_audioReproduciendo == identificador && _player.audioSource != null)
                      ? (value) => _player.seek(Duration(milliseconds: value.toInt())) : null),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_formatear(posicion), style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
                Text(duracion, style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
              ]),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(tooltip: 'Contraer', onPressed: () => setState(() => _grabacionExpandida = null), icon: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
                IconButton(tooltip: 'Retroceder 10 segundos', onPressed: () => _saltarAudio(-10), icon: const Icon(Icons.replay_10, color: Colors.grey)),
                play,
                IconButton(tooltip: 'Adelantar 10 segundos', onPressed: () => _saltarAudio(10), icon: const Icon(Icons.forward_10, color: Colors.grey)),
                IconButton(tooltip: 'Eliminar', onPressed: () => _eliminarGrabacion(id, titulo, url, archivoStorage), icon: const Icon(Icons.delete_outline, color: Colors.grey)),
              ]),
            ])
          : Row(children: [
              play,
              const SizedBox(width: 12),
              Expanded(child: InkWell(
                onTap: () => setState(() => _grabacionExpandida = id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
                  const SizedBox(height: 4),
                  Text(fecha, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTypography.cptn.copyWith(color: AppColors.gs500)),
                ]),
              )),
              Text(duracion, style: AppTypography.cptn.copyWith(color: AppColors.gs600)),
              estrella,
              menu,
            ]),
    );
  }

  // La vista de Comunidad ya contiene buscador, tarjetas y publicación.
  Widget _comunidadConAudios() => const ComunidadAudioList();

  // Construye cada botón de la navegación inferior.
  Widget _iconoNavegacion(
    IconData icono,
    int index,
  ) {
    final seleccionado =
        _selectedIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(
          AppRadius.radiusfull,
        ),
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: seleccionado
                ? AppColors.gs100
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              AppRadius.radiusfull,
            ),
          ),
          child: Icon(
            icono,
            color: AppColors.gs900,
            size: 30,
          ),
        ),
      ),
    );
  }
}
