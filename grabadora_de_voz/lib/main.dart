

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'theme/theme.dart';
import 'auth/auth_gate.dart';
import 'auth/perfil.dart';
import 'auth/comunidad.dart';

// Inicia Flutter, Firebase y Google Sign-In.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await GoogleSignIn.instance.initialize();

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

  // Contador de la grabación.
  Timer? _timer;

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

  // Identifica posibles reintentos de guardado.
  String? _idSubidaPendiente;
  String? _urlSubidaPendiente;

  // Variables del buscador y favoritos.
  String _busqueda = '';
  bool _soloFavoritos = false;

  // 0 = Grabaciones, 1 = Comunidad, 2 = Perfil.
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    // Actualiza los iconos cuando cambia el reproductor.
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

          final carpeta =
              await getTemporaryDirectory();

          final fecha = DateTime.now();

          final ruta =
              '${carpeta.path}/audio_${fecha.millisecondsSinceEpoch}.m4a';

          // Comienza a grabar usando el formato AAC.
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.aacLc,
            ),
            path: ruta,
          );

          if (!mounted) return;

          setState(() {
            _archivoLocal = ruta;
            _fechaAudio = fecha;
            _duracion = Duration.zero;
            _estado = EstadoGrabacion.grabando;
            _idSubidaPendiente = null;
            _urlSubidaPendiente = null;
          });

          _iniciarContador();
          break;

        case EstadoGrabacion.grabando:
          // Pausa el audio y el contador.
          await _recorder.pause();
          _timer?.cancel();

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

      if (ruta == null) {
        throw Exception(
          'No se pudo generar el archivo.',
        );
      }

      if (!mounted) return;

      setState(() {
        _archivoLocal = ruta;
        _estado = EstadoGrabacion.finalizada;
      });

      finalizo = true;
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
          final archivo = File(ruta);

          if (await archivo.exists()) {
            await archivo.delete().timeout(
              const Duration(seconds: 5),
            );
          }
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

  // Reproduce un archivo local o una URL de Firebase.
  Future<void> _reproducir(
    String ruta, {
    bool remoto = false,
  }) async {
    if (ruta.isEmpty) return;

    try {
      if (_audioReproduciendo == ruta &&
          _player.playing) {
        await _player.pause();
        return;
      }

      if (_audioReproduciendo == ruta &&
          _player.processingState !=
              ProcessingState.completed) {
        unawaited(_player.play());
        return;
      }

      await _player.stop();

      if (remoto) {
        await _player.setUrl(ruta);
      } else {
        await _player.setFilePath(ruta);
      }

      if (!mounted) return;

      setState(() {
        _audioReproduciendo = ruta;
      });

      unawaited(_player.play());
    } catch (e) {
      _mensaje('No se pudo reproducir: $e');
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

                            // Línea azul de la maqueta.
                            Center(
                              child: Container(
                                width: AppSpacing.spacingy200,
                                height: AppSpacing.spacing800,
                                decoration: BoxDecoration(
                                  color: AppColors.primary500,
                                  borderRadius:
                                      BorderRadius.circular(
                                    AppRadius.radiusfull,
                                  ),
                                ),
                              ),
                            ),

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

    final archivo = File(_archivoLocal!);

    if (!await archivo.exists()) {
      throw Exception('El archivo no existe.');
    }

    final tamano = await archivo.length();

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
        .ref('grabaciones/$id.m4a');

    String url;

    if (_urlSubidaPendiente == null) {
      etapa = 'Subiendo audio a Firebase Storage';

      debugPrint('INICIANDO SUBIDA A STORAGE');

      tareaSubida = referencia.putFile(
        archivo,
        SettableMetadata(
          contentType: 'audio/mp4',
        ),
      );

      // Escuchamos el progreso de la subida.
      progresoSubida =
          tareaSubida.snapshotEvents.listen(
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
      await tareaSubida.timeout(
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
      'usuarioId': usuario?.uid,
    }).timeout(
      const Duration(seconds: 20),
    );

    debugPrint('FIRESTORE GUARDADO CORRECTAMENTE');

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
      await archivo.delete();
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
    _playerSubscription?.cancel();
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

      // Menú lateral.
      drawer: Drawer(
        backgroundColor: AppColors.gs50,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(
              AppPadding.paddingmd,
            ),
            children: [
              Text(
                'Menú',
                style: AppTypography.h5.copyWith(
                  color: AppColors.gs900,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(
                height: AppGap.gapgroup,
              ),

              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Mis Grabaciones'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 0);
                },
              ),

              ListTile(
                leading: const Icon(
                  Icons.groups_outlined,
                ),
                title: const Text('Comunidad'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 1);
                },
              ),

              ListTile(
                leading: const Icon(
                  Icons.person_outline,
                ),
                title: const Text('Perfil'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 2);
                },
              ),
            ],
          ),
        ),
      ),

      // Cambia la pantalla utilizando _selectedIndex.
      body: _selectedIndex == 0
          ? _pantallaGrabaciones()
          : _selectedIndex == 1
              ? const ComunidadScreen()
              : PerfilScreen(
                  onVolver: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),

      // Micrófono flotante solo en Mis Grabaciones.
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
                onPressed: _ocupado
                    ? null
                    : _controlarGrabacion,
                child: const Icon(
                  Icons.mic,
                  size: 40,
                ),
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

                    // No agregamos la línea azul vertical
                    // porque pediste eliminarla.
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

              return titulo.contains(_busqueda) &&
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

                final segundos =
                    (datos['duracionSegundos'] as num?)
                            ?.toInt() ??
                        0;

                final favorito =
                    datos['favorito'] == true;

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
                  favorito: favorito,
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

  // Crea una tarjeta individual de grabación.
  Widget _tarjetaGrabacion({
    required String id,
    required String titulo,
    required String fecha,
    required String duracion,
    required String url,
    required bool favorito,
  }) {
    final reproduciendo =
        _audioReproduciendo == url &&
        _player.playing &&
        _player.processingState !=
            ProcessingState.completed;

    return Container(
      margin: const EdgeInsets.only(
        bottom: AppGap.gapgroup,
      ),
      decoration: BoxDecoration(
        color: AppColors.gs50,
        borderRadius: BorderRadius.circular(
          AppRadius.radiusm,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppPadding.paddingsm,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: AppPadding.paddingmd,
            ),

            // Botón circular para reproducir.
            InkWell(
              onTap: url.isEmpty
                  ? null
                  : () {
                      _reproducir(
                        url,
                        remoto: true,
                      );
                    },
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: AppRadius.radiusl,
                backgroundColor: AppColors.primary500,
                child: Icon(
                  reproduciendo
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: AppColors.gs50,
                  size: 30,
                ),
              ),
            ),

            const SizedBox(
              width: AppGap.gapcomponent,
            ),

            // Título y fecha.
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.s1.copyWith(
                      color: AppColors.gs900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(
                    height: AppGap.gaptight,
                  ),

                  Text(
                    fecha,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cptn.copyWith(
                      color: AppColors.gs500,
                    ),
                  ),
                ],
              ),
            ),

            // Duración.
            Text(
              duracion,
              style: AppTypography.cptn.copyWith(
                color: AppColors.gs600,
              ),
            ),

            // Menú gris de tres puntos.
            PopupMenuButton<String>(
              color: AppColors.gs300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppRadius.radiusm,
                ),
              ),
              icon: const Icon(
                Icons.more_vert,
                color: AppColors.gs700,
              ),
              onSelected: (valor) {
                if (valor == 'favorito') {
                  _cambiarFavorito(id, favorito);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'favorito',
                  child: Row(
                    children: [
                      Icon(
                        favorito
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: AppColors.primary500,
                      ),

                      const SizedBox(
                        width: AppGap.gaprelated,
                      ),

                      Text(
                        favorito
                            ? 'Quitar favorito'
                            : 'Agregar favorito',
                        style: AppTypography.b2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
